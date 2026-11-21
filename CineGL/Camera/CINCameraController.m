#import "CINCameraController.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <os/lock.h>

#import "CINLocalization.h"

static const OSType kFormat8Bit = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;    // 420f
static const OSType kFormat10Bit = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;  // x420（Apple Log 用它）

static BOOL CINFormatSupportsFps(AVCaptureDeviceFormat *f, int fps) {
    for (AVFrameRateRange *r in f.videoSupportedFrameRateRanges) {
        if (r.maxFrameRate >= fps - 0.01 && r.minFrameRate <= fps + 0.01) return YES;
    }
    return NO;
}

static CMVideoDimensions CINDims(AVCaptureDeviceFormat *f) {
    return CMVideoFormatDescriptionGetDimensions(f.formatDescription);
}

static BOOL CINSupportsAppleLog(AVCaptureDeviceFormat *f) {
    return [f.supportedColorSpaces containsObject:@(AVCaptureColorSpace_AppleLog)];
}

/** 格式里能拍的照片尺寸里，挑一个不超过 1300 万像素的 4:3。 */
static CMVideoDimensions CINPhotoDims(AVCaptureDeviceFormat *f) {
    NSArray<NSValue *> *dims = f.supportedMaxPhotoDimensions;
    if (dims.count == 0) return (CMVideoDimensions){0, 0};
    CINSize sizes[dims.count];
    for (NSUInteger i = 0; i < dims.count; ++i) {
        CMVideoDimensions d = dims[i].CMVideoDimensionsValue;
        sizes[i] = (CINSize){d.width, d.height};
    }
    const NSInteger k = CINPickPhotoSize(sizes, (NSInteger)dims.count);
    return k >= 0 ? dims[(NSUInteger)k].CMVideoDimensionsValue : (CMVideoDimensions){0, 0};
}

/** 拍照的回调对象：一次拍摄一个，拍完自己从集合里移除。 */
@interface CINPhotoCaptureDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, copy) void (^completion)(CINStillCapture *_Nullable, NSString *_Nullable);
@property (nonatomic, copy) void (^finished)(CINPhotoCaptureDelegate *);
@property (nonatomic, strong, nullable) CINStillCapture *still;
@property (nonatomic, copy, nullable) NSString *error;
@end

@implementation CINPhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (error || !photo.pixelBuffer) {
        self.error = [NSString stringWithFormat:CINL(@"error_capture_code"), (int)error.code];
        return;
    }
    CINStillCapture *still = [[CINStillCapture alloc] init];
    still.pixelBuffer = photo.pixelBuffer;
    NSDictionary *exif = photo.metadata[(NSString *)kCGImagePropertyExifDictionary];
    NSArray *iso = exif[(NSString *)kCGImagePropertyExifISOSpeedRatings];
    still.iso = [iso.firstObject intValue];
    still.exposureNs = (int64_t)([exif[(NSString *)kCGImagePropertyExifExposureTime] doubleValue] * 1e9);
    still.focalLength = [exif[(NSString *)kCGImagePropertyExifFocalLength] floatValue];
    still.aperture = [exif[(NSString *)kCGImagePropertyExifFNumber] floatValue];
    self.still = still;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings
                error:(NSError *)error {
    CINStillCapture *still = self.still;
    NSString *message = still ? nil : (self.error ?: [NSString stringWithFormat:CINL(@"error_capture_code"), (int)error.code]);
    void (^completion)(CINStillCapture *, NSString *) = self.completion;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(still, message);
    });
    self.finished(self);
}

@end

@interface CINCameraController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation CINCameraController {
    dispatch_queue_t _sessionQueue;
    // ---- 只在相机队列上读写 ----
    AVCaptureSession *_session;
    AVCaptureDevice *_device;
    AVCaptureVideoDataOutput *_videoOutput;
    AVCapturePhotoOutput *_photoOutput;
    CINSessionConfig *_config;
    CINCameraCaps *_caps;
    float _zoomBase;
    CINCameraControls _applied;
    BOOL _hasApplied;
    NSMutableSet<CINPhotoCaptureDelegate *> *_photoDelegates;
    NSArray<id> *_observers;
    // ---- 帧回调线程也会读写，加锁 ----
    os_unfair_lock _lock;
    CINCameraControls _controls;
    /** 自动曝光时测到的「ISO × 曝光时间」（已扣除曝光补偿），半自动曝光靠它反推。 */
    double _meteredProduct;
    BOOL _tapFocus;
    CFTimeInterval _lastReadout;
    float _maxDiopters;
    float _evStep;
}

@synthesize delegate = _delegate;

+ (BOOL)hasCamera {
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] != nil;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sessionQueue = dispatch_queue_create("CineGL-Camera", DISPATCH_QUEUE_SERIAL);
        _photoDelegates = [NSMutableSet set];
        _lock = OS_UNFAIR_LOCK_INIT;
        _controls = CINCameraControlsDefault();
        _meteredProduct = 100.0 * 20000000.0;
        _zoomBase = 1.f;
        _evStep = 1.f / 3.f;
    }
    return self;
}

- (BOOL)wbOnIsp {
    return _caps.manualPostProcessing;
}

#pragma mark - 开相机

/**
 * 后置优先用多摄虚拟设备（能在广角/长焦之间切换），但前提是它支持自定义曝光和锁定镜头位置；
 * 不支持就退回单个广角镜头——这个 App 的核心是手动参数，宁可少几档变焦。
 */
- (AVCaptureDevice *)deviceForFront:(BOOL)front {
    if (front) {
        return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo
                                                   position:AVCaptureDevicePositionFront];
    }
    NSArray *types = @[AVCaptureDeviceTypeBuiltInTripleCamera, AVCaptureDeviceTypeBuiltInDualWideCamera, AVCaptureDeviceTypeBuiltInDualCamera];
    AVCaptureDeviceDiscoverySession *ds = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                                                                  mediaType:AVMediaTypeVideo
                                                                                                   position:AVCaptureDevicePositionBack];
    for (AVCaptureDevice *d in ds.devices) {
        if ([d isExposureModeSupported:AVCaptureExposureModeCustom] && d.isLockingFocusWithCustomLensPositionSupported) return d;
    }
    return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo
                                               position:AVCaptureDevicePositionBack];
}

/** 虚拟设备的 1x 是超广角；为了和「主摄 = 1x」的习惯一致，用第一个切换倍率做基准。 */
static float CINZoomBase(AVCaptureDevice *d) {
    if (!d.isVirtualDevice) return 1.f;
    for (AVCaptureDevice *c in d.constituentDevices) {
        if ([c.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInUltraWideCamera]) {
            NSNumber *first = d.virtualDeviceSwitchOverVideoZoomFactors.firstObject;
            return first ? first.floatValue : 1.f;
        }
    }
    return 1.f;
}

- (NSArray<AVCaptureDeviceFormat *> *)formatsOf:(AVCaptureDevice *)d subtype:(OSType)subtype aspect:(float)aspect fps:(int)fps
                                       appleLog:(BOOL)appleLog {
    NSMutableArray *out = [NSMutableArray array];
    for (AVCaptureDeviceFormat *f in d.formats) {
        if (CMFormatDescriptionGetMediaSubType(f.formatDescription) != subtype) continue;
        const CMVideoDimensions dim = CINDims(f);
        if (fabsf((float)dim.width / (float)dim.height - aspect) >= 0.02f) continue;
        if (fps > 0 && !CINFormatSupportsFps(f, fps)) continue;
        if (appleLog && !CINSupportsAppleLog(f)) continue;
        [out addObject:f];
    }
    return out;
}

- (void)startWithConfig:(CINSessionConfig *)config frameQueue:(dispatch_queue_t)frameQueue
             completion:(void (^)(CINSessionInfo *, NSString *))completion {
    dispatch_async(_sessionQueue, ^{
        NSString *error = nil;
        CINSessionInfo *info = [self openWithConfig:config frameQueue:frameQueue error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(info, error);
        });
    });
}

- (CINSessionInfo *)openWithConfig:(CINSessionConfig *)config frameQueue:(dispatch_queue_t)frameQueue error:(NSString **)error {
    [self teardown];
    AVCaptureDevice *device = [self deviceForFront:config.front];
    if (!device) {
        *error = CINL(@"error_no_camera");
        return nil;
    }

    // —— 挑格式：先按帧率筛，不支持就退回 30 ——
    int fps = config.fps;
    const BOOL wantLog = config.appleLog;
    NSArray *logFormats = [self formatsOf:device subtype:kFormat10Bit aspect:config.streamAspect fps:fps appleLog:YES];
    const BOOL useLog = wantLog && logFormats.count > 0;
    const OSType subtype = useLog ? kFormat10Bit : kFormat8Bit;
    NSArray<AVCaptureDeviceFormat *> *candidates = [self formatsOf:device subtype:subtype aspect:config.streamAspect fps:fps appleLog:useLog];
    if (candidates.count == 0) {
        fps = 30;
        candidates = [self formatsOf:device subtype:subtype aspect:config.streamAspect fps:fps appleLog:useLog];
    }
    if (candidates.count == 0) candidates = [self formatsOf:device subtype:subtype aspect:config.streamAspect fps:0 appleLog:NO];
    if (candidates.count == 0) {
        *error = CINL(@"error_no_preview_size");
        return nil;
    }
    CINSize sizes[candidates.count];
    for (NSUInteger i = 0; i < candidates.count; ++i) {
        const CMVideoDimensions d = CINDims(candidates[i]);
        sizes[i] = (CINSize){d.width, d.height};
    }
    const NSInteger pick = CINPickStreamSize(sizes, (NSInteger)candidates.count, config.streamAspect, config.targetShort);
    const CINSize chosen = sizes[pick];
    // 同一尺寸可能有好几个格式（有没有像素合并、HDR……）：拍照挑能拍最大照片的，录像优先不合并像素的
    AVCaptureDeviceFormat *format = nil;
    int64_t bestPhoto = -1;
    for (AVCaptureDeviceFormat *f in candidates) {
        const CMVideoDimensions d = CINDims(f);
        if (d.width != chosen.w || d.height != chosen.h) continue;
        if (config.video) {
            if (!format || (format.isVideoBinned && !f.isVideoBinned)) format = f;
        } else {
            const CMVideoDimensions p = CINPhotoDims(f);
            const int64_t area = (int64_t)p.width * p.height;
            if (area > bestPhoto) {
                bestPhoto = area;
                format = f;
            }
        }
    }

    NSError *err = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&err];
    if (!input) {
        *error = err.code == AVErrorDeviceAlreadyUsedByAnotherSession ? CINL(@"error_camera_in_use")
                                                                       : [NSString stringWithFormat:CINL(@"error_camera_open_code"), (int)err.code];
        return nil;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    // 颜色空间和音频会话都自己管：不让系统偷偷切到 P3 广色域，也不让它动 App 的音频设置
    session.automaticallyConfiguresCaptureDeviceForWideColor = NO;
    session.automaticallyConfiguresApplicationAudioSession = NO;
    [session beginConfiguration];
    session.sessionPreset = AVCaptureSessionPresetInputPriority;
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(subtype)};
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    [videoOutput setSampleBufferDelegate:self queue:frameQueue];
    AVCapturePhotoOutput *photoOutput = config.video ? nil : [[AVCapturePhotoOutput alloc] init];
    if (![session canAddInput:input] || ![session canAddOutput:videoOutput] || (photoOutput && ![session canAddOutput:photoOutput])) {
        [session commitConfiguration];
        *error = CINL(@"error_session_config");
        return nil;
    }
    [session addInput:input];
    [session addOutput:videoOutput];
    if (photoOutput) {
        [session addOutput:photoOutput];
        photoOutput.maxPhotoQualityPrioritization = AVCapturePhotoQualityPrioritizationBalanced;
    }

    if ([device lockForConfiguration:&err]) {
        device.activeFormat = format;
        device.activeColorSpace = useLog ? AVCaptureColorSpace_AppleLog : AVCaptureColorSpace_sRGB;
        // 录像要恒定帧率；拍照预览允许慢到 1/15s，暗处更亮
        const CMTime frame = CMTimeMake(1, fps);
        CMTime maxFrame = config.video ? frame : CMTimeMake(1, 15);
        CMTime formatMax = kCMTimeZero;
        for (AVFrameRateRange *r in format.videoSupportedFrameRateRanges) {
            if (CMTimeCompare(r.maxFrameDuration, formatMax) > 0) formatMax = r.maxFrameDuration;
        }
        if (CMTimeCompare(maxFrame, formatMax) > 0) maxFrame = formatMax;
        device.activeVideoMinFrameDuration = frame;
        device.activeVideoMaxFrameDuration = CMTimeCompare(maxFrame, frame) < 0 ? frame : maxFrame;
        [device unlockForConfiguration];
    }

    // 缓冲保持传感器方向、不镜像：转正和镜像都交给 GPU（省掉一次整帧旋转）
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoMirroringSupported) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = NO;
    }
    if ([connection isVideoRotationAngleSupported:0]) connection.videoRotationAngle = 0;
    AVCaptureConnection *photoConnection = [photoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (photoConnection.isVideoMirroringSupported) {
        photoConnection.automaticallyAdjustsVideoMirroring = NO;
        photoConnection.videoMirrored = NO;
    }
    if ([photoConnection isVideoRotationAngleSupported:0]) photoConnection.videoRotationAngle = 0;
    [session commitConfiguration];

    if (photoOutput) {
        const CMVideoDimensions p = CINPhotoDims(format);
        if (p.width > 0) photoOutput.maxPhotoDimensions = p;
    }

    _session = session;
    _device = device;
    _videoOutput = videoOutput;
    _photoOutput = photoOutput;
    _config = config;
    _zoomBase = CINZoomBase(device);
    _hasApplied = NO;

    // iOS 的「竖屏」是 90 度：缓冲在 0 度（传感器原生方向）时要顺时针转 90 度才正
    const int angle = (int)lround(connection.videoRotationAngle);
    CINCameraCaps *caps = [[CINCameraCaps alloc] init];
    caps.front = config.front;
    caps.sensorOrientation = ((90 - angle) % 360 + 360) % 360;
    caps.manualSensor = [device isExposureModeSupported:AVCaptureExposureModeCustom];
    caps.manualPostProcessing = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported;
    caps.focusLock = device.isLockingFocusWithCustomLensPositionSupported;
    caps.isoMin = (int)ceilf(format.minISO);
    caps.isoMax = (int)floorf(format.maxISO);
    caps.exposureMinNs = (int64_t)(CMTimeGetSeconds(format.minExposureDuration) * 1e9);
    caps.exposureMaxNs = (int64_t)(CMTimeGetSeconds(format.maxExposureDuration) * 1e9);
    caps.minFocusDiopters = device.minimumFocusDistance > 0 ? 1000.f / (float)device.minimumFocusDistance : 0.f;
    // 曝光补偿：iOS 是连续值（通常 ±8 EV），这里按 1/3 档、最多 ±3 档给刻度盘
    caps.evStep = 1.f / 3.f;
    caps.evMax = (int)floorf(fminf(3.f, device.maxExposureTargetBias) / caps.evStep + 1e-3f);
    caps.evMin = -(int)floorf(fminf(3.f, -device.minExposureTargetBias) / caps.evStep + 1e-3f);
    caps.zoomMin = (float)device.minAvailableVideoZoomFactor / _zoomBase;
    caps.zoomMax = fminf((float)device.maxAvailableVideoZoomFactor, _zoomBase * 10.f) / _zoomBase;
    caps.hasFlash = device.hasTorch && [device isTorchModeSupported:AVCaptureTorchModeOn];
    caps.previewStabilization = connection.isVideoStabilizationSupported;
    // 等效焦距：videoFieldOfView 是水平视角；按 4:3 传感器换算到对角线，再按 35mm 对角线 43.27mm 算
    const float tanH = tanf((float)format.videoFieldOfView * (float)M_PI / 360.f);
    caps.equivalentFocal = tanH > 0.f ? 21.635f / (tanH * 1.25f) * _zoomBase : 26.f;
    _caps = caps;

    os_unfair_lock_lock(&_lock);
    _maxDiopters = caps.minFocusDiopters;
    _evStep = caps.evStep;
    _tapFocus = NO;
    os_unfair_lock_unlock(&_lock);

    __weak CINCameraController *weakSelf = self;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    id runtime = [nc addObserverForName:AVCaptureSessionRuntimeErrorNotification object:session queue:nil
                             usingBlock:^(NSNotification *n) {
        NSError *e = n.userInfo[AVCaptureSessionErrorKey];
        [weakSelf fail:[NSString stringWithFormat:CINL(@"error_camera_code"), (int)e.code]];
    }];
    id interrupted = [nc addObserverForName:AVCaptureSessionWasInterruptedNotification object:session queue:nil
                                 usingBlock:^(NSNotification *n) {
        const NSInteger reason = [n.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
        if (reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) [weakSelf fail:CINL(@"error_camera_in_use")];
    }];
    _observers = @[runtime, interrupted];

    [session startRunning];
    [self applyControls:config.controls];

    CINSessionInfo *info = [[CINSessionInfo alloc] init];
    info.caps = caps;
    info.bufferWidth = chosen.w;
    info.bufferHeight = chosen.h;
    info.fps = fps;
    NSMutableArray *available = [NSMutableArray array];
    for (NSNumber *f in @[@24, @25, @30, @60]) {
        for (AVCaptureDeviceFormat *x in [self formatsOf:device subtype:subtype aspect:config.streamAspect fps:f.intValue appleLog:useLog]) {
            const CMVideoDimensions d = CINDims(x);
            if (d.width == chosen.w && d.height == chosen.h) {
                [available addObject:f];
                break;
            }
        }
    }
    info.availableFps = available.count > 0 ? available : @[@30];
    BOOL uhd = NO;
    for (AVCaptureDeviceFormat *f in [self formatsOf:device subtype:kFormat8Bit aspect:16.f / 9.f fps:0 appleLog:NO]) {
        if (MIN(CINDims(f).width, CINDims(f).height) == 2160) uhd = YES;
    }
    info.uhdAvailable = uhd;
    info.appleLogAvailable = logFormats.count > 0;
    info.appleLogActive = useLog;
    return info;
}

- (void)fail:(NSString *)message {
    [self.delegate cameraSource:self didFailWithMessage:message];
}

- (void)teardown {
    for (id o in _observers) [NSNotificationCenter.defaultCenter removeObserver:o];
    _observers = nil;
    if (_session.isRunning) [_session stopRunning];
    _session = nil;
    _device = nil;
    _videoOutput = nil;
    _photoOutput = nil;
    _config = nil;
    _caps = nil;
}

- (void)stopWithCompletion:(void (^)(void))completion {
    dispatch_async(_sessionQueue, ^{
        [self teardown];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

#pragma mark - 参数

- (void)updateControls:(CINCameraControls)controls {
    dispatch_async(_sessionQueue, ^{
        [self applyControls:controls];
    });
}

/** 白平衡：色温交给系统换算成增益（色调为 0），色调按本项目的约定单独乘在绿通道上，再把最小的增益归一到 1。 */
static AVCaptureWhiteBalanceGains CINDeviceGains(AVCaptureDevice *d, float kelvin, float tint) {
    AVCaptureWhiteBalanceTemperatureAndTintValues tt = {kelvin, 0.f};
    AVCaptureWhiteBalanceGains g = [d deviceWhiteBalanceGainsForTemperatureAndTintValues:tt];
    g.greenGain *= exp2f(-0.25f * tint);
    const float lo = fminf(g.redGain, fminf(g.greenGain, g.blueGain));
    const float maxGain = d.maxWhiteBalanceGain;
    g.redGain = fminf(maxGain, g.redGain / lo);
    g.greenGain = fminf(maxGain, g.greenGain / lo);
    g.blueGain = fminf(maxGain, g.blueGain / lo);
    return g;
}

- (void)applyControls:(CINCameraControls)c {
    os_unfair_lock_lock(&_lock);
    _controls = c;
    const double metered = _meteredProduct;
    const BOOL tapFocus = _tapFocus;
    os_unfair_lock_unlock(&_lock);

    AVCaptureDevice *d = _device;
    CINCameraCaps *caps = _caps;
    CINSessionConfig *cfg = _config;
    if (!d || !caps || !cfg) return;
    const CINCameraControls prev = _applied;
    const BOOL first = !_hasApplied;
    if (![d lockForConfiguration:nil]) return;

    // —— 变焦 ——
    const CGFloat zoom = MIN(MAX(c.zoom * _zoomBase, d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor);
    if (fabs(d.videoZoomFactor - zoom) > 1e-3) d.videoZoomFactor = zoom;

    // —— 曝光 ——
    if (CINCameraControlsExposureAuto(c) || !caps.manualSensor) {
        if (d.exposureMode != AVCaptureExposureModeContinuousAutoExposure &&
            [d isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            d.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        const float bias = fminf(fmaxf(c.evIndex * caps.evStep, d.minExposureTargetBias), d.maxExposureTargetBias);
        if (d.exposureTargetBias != bias) [d setExposureTargetBias:bias completionHandler:nil];
    } else {
        const int64_t frameNs = 1000000000LL / cfg.fps;
        // 录像时快门不能慢于一帧；拍照预览放宽到 1/15s
        const int64_t maxExposure = cfg.video ? frameNs : 66666666LL;
        int iso = 0;
        int64_t exposure = 0;
        CINResolveExposure(c, caps.isoMin, caps.isoMax, caps.exposureMinNs, MIN(caps.exposureMaxNs, maxExposure), metered,
                           caps.evStep, &iso, &exposure);
        [d setExposureModeCustomWithDuration:CMTimeMake(exposure, 1000000000) ISO:(float)iso completionHandler:nil];
    }

    // —— 补光 ——
    if (caps.hasFlash) {
        const AVCaptureTorchMode torch = c.torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
        if (d.torchMode != torch && [d isTorchModeSupported:torch]) d.torchMode = torch;
    }

    // —— 对焦 ——
    if (!c.focusAuto && caps.manualFocus) {
        // 镜头位置 0 = 最近、1 = 最远；屈光度近似线性（薄透镜：镜片移动量 ∝ 1 / 物距）
        const float lens = 1.f - fminf(fmaxf(c.focusDiopters / caps.minFocusDiopters, 0.f), 1.f);
        [d setFocusModeLockedWithLensPosition:lens completionHandler:nil];
    } else if (!tapFocus && (first || !prev.focusAuto || d.focusMode == AVCaptureFocusModeLocked)) {
        if ([d isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) d.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        if (d.isSmoothAutoFocusSupported) d.smoothAutoFocusEnabled = cfg.video;   // 录像时对焦慢一点，不「拉风箱」
    }

    // —— 白平衡 ——
    if (c.wbAuto) {
        if (d.whiteBalanceMode != AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance &&
            [d isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
            d.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
        }
    } else if (caps.manualPostProcessing) {
        // ISP 白平衡：色温是绝对值（系统帮忙换算），画面在 ISP 里就调好了
        [d setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:CINDeviceGains(d, c.kelvin, c.tint) completionHandler:nil];
    } else if (d.whiteBalanceMode != AVCaptureWhiteBalanceModeLocked) {
        // 不支持自定义增益：锁住当前的自动白平衡，色温交给 GPU（镜头 pass 里的 wbGains）
        [d setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:AVCaptureWhiteBalanceGainsCurrent completionHandler:nil];
    }
    [d unlockForConfiguration];

    // —— 防抖（预览优化模式：延迟低，适合取景）——
    if (caps.previewStabilization && (first || prev.stabilization != c.stabilization)) {
        AVCaptureConnection *conn = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        conn.preferredVideoStabilizationMode = c.stabilization ? AVCaptureVideoStabilizationModePreviewOptimized
                                                               : AVCaptureVideoStabilizationModeOff;
    }
    _applied = c;
    _hasApplied = YES;
}

- (void)focusAtBufferPoint:(CGPoint)point {
    dispatch_async(_sessionQueue, ^{
        AVCaptureDevice *d = self->_device;
        if (!d || ![d lockForConfiguration:nil]) return;
        os_unfair_lock_lock(&self->_lock);
        const CINCameraControls c = self->_controls;
        os_unfair_lock_unlock(&self->_lock);
        if (d.isExposurePointOfInterestSupported) {
            d.exposurePointOfInterest = point;
            // 重新设一次模式，新的测光点才会生效
            if (CINCameraControlsExposureAuto(c)) d.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        if (c.focusAuto && d.isFocusPointOfInterestSupported && [d isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            // 先对一次焦再锁住（相当于 Camera2 的 AF_MODE_AUTO + TRIGGER_START）
            d.focusPointOfInterest = point;
            d.focusMode = AVCaptureFocusModeAutoFocus;
            os_unfair_lock_lock(&self->_lock);
            self->_tapFocus = YES;
            os_unfair_lock_unlock(&self->_lock);
        }
        [d unlockForConfiguration];
    });
}

- (void)resetFocus {
    dispatch_async(_sessionQueue, ^{
        os_unfair_lock_lock(&self->_lock);
        self->_tapFocus = NO;
        const CINCameraControls c = self->_controls;
        os_unfair_lock_unlock(&self->_lock);
        AVCaptureDevice *d = self->_device;
        if (!d || ![d lockForConfiguration:nil]) return;
        const CGPoint center = CGPointMake(0.5, 0.5);
        if (d.isExposurePointOfInterestSupported) {
            d.exposurePointOfInterest = center;
            if (CINCameraControlsExposureAuto(c)) d.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        if (c.focusAuto) {
            if (d.isFocusPointOfInterestSupported) d.focusPointOfInterest = center;
            if ([d isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) d.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        [d unlockForConfiguration];
    });
}

#pragma mark - 拍照

- (void)captureWithCompletion:(void (^)(CINStillCapture *, NSString *))completion {
    dispatch_async(_sessionQueue, ^{
        AVCapturePhotoOutput *output = self->_photoOutput;
        if (!output || !self->_session.isRunning) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, CINL(@"error_photo_mode"));
            });
            return;
        }
        // 要未压缩的 BGRA：省掉一次 JPEG 编码 + 解码，直接进 GPU（安卓那边只能拿 JPEG 再解码）
        const BOOL bgra = [output.availablePhotoPixelFormatTypes containsObject:@(kCVPixelFormatType_32BGRA)];
        NSDictionary *format = @{(id)kCVPixelBufferPixelFormatTypeKey: @(bgra ? kCVPixelFormatType_32BGRA : kFormat8Bit)};
        AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettingsWithFormat:format];
        settings.maxPhotoDimensions = output.maxPhotoDimensions;
        settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationBalanced;
        if ([output.supportedFlashModes containsObject:@(AVCaptureFlashModeOff)]) settings.flashMode = AVCaptureFlashModeOff;
        CINPhotoCaptureDelegate *delegate = [[CINPhotoCaptureDelegate alloc] init];
        delegate.completion = completion;
        __weak CINCameraController *weakSelf = self;
        delegate.finished = ^(CINPhotoCaptureDelegate *d) {
            CINCameraController *strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf->_sessionQueue, ^{
                [strongSelf->_photoDelegates removeObject:d];
            });
        };
        [self->_photoDelegates addObject:delegate];
        [output capturePhotoWithSettings:settings delegate:delegate];
    });
}

#pragma mark - 帧

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pb) return;
    // 换到主机时钟：音频（AVAudioEngine）的时间戳也是主机时钟，两边对齐了音画才同步
    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMClockRef clock = connection.inputPorts.firstObject.clock;
    if (clock) time = CMSyncConvertTime(time, clock, CMClockGetHostTimeClock());
    [self.delegate cameraSource:self didOutputPixelBuffer:pb time:time];
    [self reportReadout];
}

- (void)reportReadout {
    AVCaptureDevice *d = _device;
    if (!d) return;
    const CFTimeInterval now = CACurrentMediaTime();
    os_unfair_lock_lock(&_lock);
    const BOOL due = now - _lastReadout >= 0.12;
    if (due) _lastReadout = now;
    const CINCameraControls c = _controls;
    const float maxD = _maxDiopters;
    const float evStep = _evStep;
    const BOOL tapFocus = _tapFocus;
    os_unfair_lock_unlock(&_lock);

    const float iso = d.ISO;
    const double exposureNs = CMTimeGetSeconds(d.exposureDuration) * 1e9;
    if (CINCameraControlsExposureAuto(c) && iso > 0 && exposureNs > 0) {
        // 记下「不含曝光补偿」的曝光量，半自动时再把补偿加回去
        const double product = iso * exposureNs / pow(2.0, (double)(c.evIndex * evStep));
        os_unfair_lock_lock(&_lock);
        _meteredProduct = product;
        os_unfair_lock_unlock(&_lock);
    }
    if (!due) return;
    CINReadout r;
    r.iso = (int)lroundf(iso);
    r.exposureNs = (int64_t)exposureNs;
    r.focusDiopters = maxD > 0.f ? (1.f - d.lensPosition) * maxD : 0.f;
    r.afLocked = tapFocus && !d.isAdjustingFocus;
    r.kelvin = 0.f;
    if (d.whiteBalanceMode == AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance) {
        r.kelvin = [d temperatureAndTintValuesForDeviceWhiteBalanceGains:d.deviceWhiteBalanceGains].temperature;
    }
    [self.delegate cameraSource:self didUpdateReadout:r];
}

@end
