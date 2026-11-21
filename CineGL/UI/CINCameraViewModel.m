#import "CINCameraViewModel.h"

#import "CINCameraController.h"
#import "CINColor.h"
#import "CINLocalization.h"
#import "CINLooks.h"
#import "CINMediaSaver.h"
#import "CINMetering.h"
#import "CINRenderer.h"
#import "CINSettingsStore.h"
#import "CINSimulatedCamera.h"
#import "CINVideoRecorder.h"

@interface CINCameraViewModel () <CINRendererDelegate, CINCameraSourceDelegate>
@end

@implementation CINCameraViewModel {
    CINSettingsStore *_settings;
    CINRenderer *_renderer;
    id<CINCameraSource> _camera;
    CINAudioCapture *_audio;
    CINVideoRecorder *_recorder;
    NSUInteger _cameraGeneration;   // 相机切得快时，丢掉过期的「开好了」回调
    int _streamWidth, _streamHeight;
    int _sessionFps;
    BOOL _appleLogActive;
    BOOL _resumed;
    BOOL _cameraRunning;
    BOOL _notifyScheduled;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _settings = [[CINSettingsStore alloc] initWithDefaults:defaults ?: NSUserDefaults.standardUserDefaults];
        _state = [_settings load];
        _renderer = [[CINRenderer alloc] init];
        _renderer.delegate = self;
#if TARGET_OS_SIMULATOR
        // 模拟器没有摄像头：用虚拟相机把整条管线跑起来
        _camera = [[CINSimulatedCamera alloc] init];
#else
        _camera = [[CINCameraController alloc] init];
#endif
        _camera.delegate = self;
        _audio = [[CINAudioCapture alloc] init];
        __weak CINCameraViewModel *weakSelf = self;
        _audio.levelsHandler = ^(CINAudioLevels levels) {
            CINCameraViewModel *vm = weakSelf;
            [vm.delegate viewModel:vm audioLevelsDidChange:levels];
        };
        [self refreshLooks];
        [self loadImportedLuts];
        [self pushRenderParams];
    }
    return self;
}

#pragma mark - 状态通知

- (void)notify {
    if (_notifyScheduled) return;
    _notifyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_notifyScheduled = NO;
        [self.delegate viewModelDidChange:self];
    });
}

- (void)save {
    [_settings save:_state];
}

- (void)toast:(NSString *)message {
    _state.message = message;
    _state.messageId += 1;
    [self notify];
}

#pragma mark - 生命周期

- (void)onPermissionsCamera:(BOOL)camera microphone:(BOOL)microphone {
    _state.cameraPermission = camera;
    _state.micPermission = microphone;
    [self notify];
    [self maybeStartCamera];
}

- (void)onResume {
    _resumed = YES;
    [self maybeStartCamera];
}

- (void)onPause {
    _resumed = NO;
    if (_state.recording) [self stopRecording];
    [_audio stop];
    _cameraRunning = NO;
    _cameraGeneration++;
    [_camera stopWithCompletion:nil];
}

- (void)attachLayer:(CAMetalLayer *)layer {
    [_renderer attachLayer:layer];
}

- (void)detachLayer {
    [_renderer detachLayer];
}

- (void)setOverlayCornerRadius:(float)radiusPx topInset:(float)topInsetPx {
    _renderer.cornerRadiusPx = radiusPx;
    _renderer.overlayTopInsetPx = topInsetPx;
}

- (void)maybeStartCamera {
    if (_resumed && _state.cameraPermission && !_cameraRunning) [self restartCamera];
}

- (void)restartCamera {
    _cameraRunning = YES;
    const NSUInteger generation = ++_cameraGeneration;
    CINCameraState *s = _state;
    [_audio stop];
    const BOOL video = s.mode == CINCaptureModeVideo;
    // 拍照用 4:3 全幅流；录像按画幅选 16:9 或 4:3 的流，裁切交给 GPU
    const BOOL wide = video && (s.aspect == CINAspectRatio16x9 || s.aspect == CINAspectRatio239x1);
    CINSessionConfig *config = [[CINSessionConfig alloc] init];
    config.front = s.front;
    config.video = video;
    config.streamAspect = wide ? 16.f / 9.f : 4.f / 3.f;
    // 拍照模式的流选 1440 短边（iPhone 的 1920x1440，就是系统相机拍照取景用的那档）
    config.targetShort = video ? (s.resolution == CINResolutionUHD ? 2160 : 1080) : 1440;
    config.fps = s.fps;
    config.appleLog = s.logMode == CINLogModeIsp;
    config.controls = s.controls;
    __weak CINCameraViewModel *weakSelf = self;
    [_camera startWithConfig:config frameQueue:_renderer.queue completion:^(CINSessionInfo *info, NSString *error) {
        [weakSelf cameraStarted:info error:error generation:generation video:video];
    }];
}

- (void)cameraStarted:(CINSessionInfo *)info error:(NSString *)error generation:(NSUInteger)generation video:(BOOL)video {
    if (generation != _cameraGeneration) return;
    if (!info) {
        [self toast:error ?: CINL(@"error_camera_open")];
        _cameraRunning = NO;
        return;
    }
    CINCameraCaps *caps = info.caps;
    _streamWidth = info.bufferWidth;
    _streamHeight = info.bufferHeight;
    _sessionFps = info.fps;
    _appleLogActive = info.appleLogActive;
    [_renderer configureInput:(CINRenderInputConfig){info.bufferWidth, info.bufferHeight, caps.sensorOrientation, caps.front, _state.aspect}];
    if (video && _state.micPermission) [_audio start];
    _state.caps = caps;
    _state.fps = info.fps;
    _state.availableFps = info.availableFps;
    _state.uhdAvailable = info.uhdAvailable;
    _state.ispLogAvailable = info.appleLogAvailable;
    _state.zoomPresets = CINZoomPresets(caps.zoomMin, caps.zoomMax);
    [self notify];
    [self pushRenderParams];
}

#pragma mark - 渲染器回调

- (void)renderer:(CINRenderer *)renderer frameSizeDidChangeWidth:(int)width height:(int)height {
    _state.frameWidth = width;
    _state.frameHeight = height;
    [self notify];
}

- (void)renderer:(CINRenderer *)renderer didRenderThumbnails:(NSDictionary<NSNumber *, UIImage *> *)thumbnails {
    NSMutableDictionary *merged = [_state.lookThumbs mutableCopy];
    [merged addEntriesFromDictionary:thumbnails];
    _state.lookThumbs = merged;
    [self notify];
}

#pragma mark - 相机回调

- (void)cameraSource:(id<CINCameraSource>)source didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer time:(CMTime)time {
    [_renderer drawPixelBuffer:pixelBuffer presentationTime:time];
}

- (void)cameraSource:(id<CINCameraSource>)source didUpdateReadout:(CINReadout)readout {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_state.readout = readout;
        [self notify];
    });
}

- (void)cameraSource:(id<CINCameraSource>)source didFailWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self toast:message];
    });
}

#pragma mark - 拍摄设置

- (void)setMode:(CINCaptureMode)mode {
    if (_state.recording || _state.mode == mode) return;
    _state.mode = mode;
    _state.activeTool = CINToolNone;
    [self save];
    [self notify];
    [self restartCamera];
}

- (void)flipCamera {
    if (_state.recording) return;
    _state.front = !_state.front;
    CINCameraControls c = _state.controls;
    c.zoom = 1.f;
    c.focusAuto = true;
    _state.controls = c;
    [self notify];
    [self restartCamera];
}

static BOOL CINWide(CINAspectRatio a) { return a == CINAspectRatio16x9 || a == CINAspectRatio239x1; }

- (void)setAspect:(CINAspectRatio)aspect {
    if (_state.recording || _state.aspect == aspect) return;
    const CINAspectRatio old = _state.aspect;
    _state.aspect = aspect;
    [self save];
    [self notify];
    // 录像时 16:9 ↔ 4:3 要换相机流；同一类比例只需要换 GPU 裁切
    if (_state.mode == CINCaptureModeVideo && CINWide(old) != CINWide(aspect)) [self restartCamera];
    else [_renderer setAspect:aspect];
}

- (void)setResolution:(CINResolution)resolution {
    if (_state.recording) return;
    _state.resolution = resolution;
    [self save];
    [self notify];
    if (_state.mode == CINCaptureModeVideo) [self restartCamera];
}

- (void)setFps:(int)fps {
    if (_state.recording) return;
    _state.fps = fps;
    [self save];
    [self notify];
    [self restartCamera];
}

- (void)setLogMode:(CINLogMode)mode {
    if (_state.recording) return;
    const BOOL wasIsp = _state.logMode == CINLogModeIsp;
    _state.logMode = mode;
    [self save];
    [self notify];
    // Apple Log 要换相机格式和颜色空间（安卓的 ISP 曲线改个请求就行，这里得重开会话）
    if (wasIsp != (mode == CINLogModeIsp)) [self restartCamera];
    [self pushRenderParams];
}

- (void)setBurnIn:(BOOL)on {
    if (_state.recording) return;
    _state.burnIn = on;
    [self save];
    [self notify];
}

- (void)setShowSignal:(BOOL)on {
    _state.showSignal = on;
    [self notify];
    [self pushRenderParams];
}

- (void)setAssist:(CINAssist)assist {
    _state.assist = assist;
    [self save];
    [self notify];
    [self pushRenderParams];
}

- (void)onDeviceOrientation:(int)degrees {
    const int current = _state.deviceRotation;
    const int snapped = CINSnapOrientation(degrees, current);
    if (snapped != current && !_state.recording) {
        _state.deviceRotation = snapped;
        [self notify];
    }
}

#pragma mark - 影调 / 效果

- (void)selectLook:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_state.looks.count) return;
    _state.lookIndex = index;
    _state.lookId = _state.looks[(NSUInteger)index].lookId;
    [self save];
    [self notify];
    [_renderer selectLook:index];
}

- (void)setEffects:(CINEffects)effects {
    _state.effects = effects;
    [self save];
    [self notify];
    [self pushRenderParams];
}

- (void)resetEffects {
    [self setEffects:CINEffectsDefault()];
    [self toast:CINL(@"toast_effects_reset")];
}

/** 核心只给错误码和数字，这里按系统语言拼成文案。 */
static NSString *CINCubeFailureText(CINCubeParseError e) {
    switch (e.code) {
        case CINCubeErrorSizeOutOfRange: return CINL(@"cube_error_size_range");
        case CINCubeErrorUnsupported1D: return CINL(@"cube_error_1d");
        case CINCubeErrorBadDomain: return [NSString stringWithFormat:CINL(@"cube_error_domain"), e.line];
        case CINCubeErrorBadData: return [NSString stringWithFormat:CINL(@"cube_error_data"), e.line];
        case CINCubeErrorDataBeforeSize: return [NSString stringWithFormat:CINL(@"cube_error_data_before_size"), e.line];
        case CINCubeErrorCountMismatch: return [NSString stringWithFormat:CINL(@"cube_error_count"), e.count, e.expected];
        case CINCubeErrorDomainOrder: return CINL(@"cube_error_domain_order");
        case CINCubeErrorMissingSize: return CINL(@"cube_error_missing_size");
        case CINCubeErrorNone: break;
    }
    return CINL(@"cube_error_unknown");
}

/** 导入的 LUT 存在 Application Support/luts，下次启动自动加载。 */
static NSURL *CINLutDirectory(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [support URLByAppendingPathComponent:@"luts" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

/** 文件名里除了字母数字（含中文）、点、横线以外的字符都换成下划线。 */
static NSString *CINSafeName(NSString *name) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[^\\w.\\-]" options:0 error:nil];
    return [re stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0, name.length) withTemplate:@"_"];
}

- (void)importCubeFromURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const BOOL scoped = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (scoped) [url stopAccessingSecurityScopedResource];
        NSString *fileName = url.lastPathComponent.length ? url.lastPathComponent : @"imported.cube";
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self toast:CINL(@"toast_lut_read_failed")];
            });
            return;
        }
        NSString *safeName = CINSafeName(fileName);
        NSString *title = fileName.stringByDeletingPathExtension;
        CINCubeParseError err = {CINCubeErrorNone, 0, 0, 0};
        CINCubeLut *cube = [CINCubeLut parseData:data error:&err];
        if (!cube) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self toast:[NSString stringWithFormat:CINL(@"toast_lut_import_failed"), CINCubeFailureText(err)]];
            });
            return;
        }
        const NSInteger index = [CINLookLibrary.shared addCubeWithId:[@"cube:" stringByAppendingString:safeName] name:title cube:cube];
        // 拷一份到私有目录，下次启动自动加载
        [data writeToURL:[CINLutDirectory() URLByAppendingPathComponent:safeName] atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshLooks];
            [self->_renderer bakeLook:index];
            [self selectLook:index];
            [self toast:[NSString stringWithFormat:CINL(@"toast_lut_imported"), title]];
        });
    });
}

- (void)loadImportedLuts {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
        NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:CINLutDirectory() includingPropertiesForKeys:nil
                                                                                  options:0 error:nil];
        for (NSURL *f in [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
                 return [a.lastPathComponent compare:b.lastPathComponent];
             }]) {
            if ([f.pathExtension caseInsensitiveCompare:@"cube"] != NSOrderedSame) continue;
            NSData *data = [NSData dataWithContentsOfURL:f];
            CINCubeLut *cube = data ? [CINCubeLut parseData:data error:NULL] : nil;
            if (!cube) continue;
            [indices addObject:@([CINLookLibrary.shared addCubeWithId:[@"cube:" stringByAppendingString:f.lastPathComponent]
                                                                 name:f.lastPathComponent.stringByDeletingPathExtension
                                                                 cube:cube])];
        }
        if (indices.count == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshLooks];
            for (NSNumber *i in indices) [self->_renderer bakeLook:i.integerValue];
        });
    });
}

- (void)refreshLooks {
    NSArray<CINLookInfo *> *looks = [CINLookInfo allLooks];
    NSInteger index = -1;
    for (CINLookInfo *l in looks) {
        if ([l.lookId isEqualToString:_state.lookId]) index = l.index;
    }
    if (index < 0) index = MIN(MAX(_state.lookIndex, 0), (NSInteger)looks.count - 1);
    _state.looks = looks;
    _state.lookIndex = index;
    [self notify];
    [_renderer selectLook:index];
}

#pragma mark - 面板 / 工具

- (void)toggleTool:(CINTool)tool {
    _state.activeTool = _state.activeTool == tool ? CINToolNone : tool;
    _state.panel = CINPanelNone;
    [self notify];
}

- (void)togglePanel:(CINPanel)panel {
    const BOOL open = _state.panel != panel;
    _state.panel = open ? panel : CINPanelNone;
    _state.activeTool = CINToolNone;
    [self notify];
    [_renderer setThumbnailsEnabled:open && panel == CINPanelLooks];
}

- (void)closePanels {
    _state.panel = CINPanelNone;
    _state.activeTool = CINToolNone;
    [self notify];
    [_renderer setThumbnailsEnabled:NO];
}

#pragma mark - 手动参数

- (BOOL)wbOnIsp {
    return _camera.wbOnIsp;
}

- (void)updateControls:(CINCameraControls)c {
    _state.controls = c;
    [self notify];
    [_camera updateControls:c];
    [self pushRenderParams];
}

- (void)setAuto:(CINTool)tool auto:(BOOL)isAuto {
    const CINReadout r = _state.readout;
    CINCameraControls c = _state.controls;
    switch (tool) {
        case CINToolISO:
            c.isoAuto = isAuto;
            if (!isAuto && r.iso > 0) c.iso = r.iso;
            break;
        case CINToolShutter:
            c.shutterAuto = isAuto;
            if (!isAuto && r.exposureNs > 0) c.exposureNs = r.exposureNs;
            break;
        case CINToolFocus:
            c.focusAuto = isAuto;
            if (!isAuto) c.focusDiopters = r.focusDiopters;
            break;
        case CINToolWB:
            c.wbAuto = isAuto;
            // ISP 白平衡的色温是绝对值：从自动白平衡当前的色温起步，切过去画面不跳
            if (!isAuto && self.wbOnIsp && r.kelvin > 0) c.kelvin = fminf(10000.f, fmaxf(2000.f, roundf(r.kelvin / 100.f) * 100.f));
            break;
        case CINToolEV:
            c.evIndex = 0;
            break;
        case CINToolNone:
            break;
    }
    [self updateControls:c];
    if (tool == CINToolFocus && isAuto) [_camera resetFocus];
}

- (void)resetControls {
    [self updateControls:CINCameraControlsResetToAuto(_state.controls)];
    [_camera resetFocus];
    _state.hasFocusPoint = NO;
    [self toast:CINL(@"toast_controls_reset")];
}

- (void)tapToFocusFrameX:(float)x y:(float)y {
    CINCameraCaps *caps = _state.caps;
    if (!caps || _streamWidth <= 0) return;
    const CINFrameGeometry geo = CINComputeFrame(_streamWidth, _streamHeight, caps.sensorOrientation, _state.aspect, kCINFrameAlign);
    [_camera focusAtBufferPoint:CINFrameToBuffer(x, y, geo, caps.sensorOrientation, caps.front)];
    _state.hasFocusPoint = YES;
    _state.focusPoint = CGPointMake(x, y);
    _state.focusEventId += 1;
    [self notify];
}

- (void)resetFocus {
    [_camera resetFocus];
    _state.hasFocusPoint = NO;
    [self notify];
}

#pragma mark - 拍摄

- (void)onShutter {
    if (_state.mode == CINCaptureModePhoto) [self takePhoto];
    else if (_state.recording) [self stopRecording];
    else [self startRecording];
}

/** 录像 / 拍照写进文件的是调色后的成片，还是 Log 原片（LUT 只用来监看）。 */
- (CINPlane)recordPlane {
    return _state.burnIn || !_state.logOn ? CINPlaneGraded : CINPlaneSignal;
}

- (void)takePhoto {
    if (_state.busy) return;
    _state.busy = YES;
    [self notify];
    __weak CINCameraViewModel *weakSelf = self;
    [_camera captureWithCompletion:^(CINStillCapture *still, NSString *error) {
        [weakSelf processStill:still error:error];
    }];
}

- (void)processStill:(CINStillCapture *)still error:(NSString *)error {
    CINCameraCaps *caps = _state.caps;
    if (!still || !caps) {
        [self finishPhoto:nil thumb:nil error:error ?: (caps ? CINL(@"error_photo") : CINL(@"error_camera_not_ready"))];
        return;
    }
    CINStillRequest *req = [[CINStillRequest alloc] init];
    req.pixelBuffer = still.pixelBuffer;
    req.sensorOrientation = caps.sensorOrientation;
    req.front = caps.front;
    req.aspect = _state.aspect;
    req.deviceRotation = _state.deviceRotation;
    req.plane = [self recordPlane];
    CINRenderParams p = _renderer.params;
    p.showSignal = p.zebra = p.peaking = p.waveform = false;   // 监看辅助不进照片
    req.params = p;
    const CINPhotoMeta meta = {still.iso, still.exposureNs, still.focalLength, still.aperture};
    __weak CINCameraViewModel *weakSelf = self;
    [_renderer processStill:req completion:^(CGImageRef image) {
        if (!image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishPhoto:nil thumb:nil error:CINL(@"error_gpu")];
            });
            return;
        }
        UIImage *thumb = [CINMediaSaver thumbnailForImage:image];
        [CINMediaSaver savePhoto:image meta:meta completion:^(NSURL *lastCapture, NSString *saveError) {
            [weakSelf finishPhoto:lastCapture thumb:thumb error:saveError];
        }];
    }];
}

- (void)finishPhoto:(NSURL *)url thumb:(UIImage *)thumb error:(NSString *)error {
    _state.busy = NO;
    if (url) {
        _state.lastURL = url;
        _state.lastIsVideo = NO;
        _state.lastThumb = thumb;
    }
    if (error) [self toast:error];
    [self notify];
}

- (void)startRecording {
    CINCameraCaps *caps = _state.caps;
    if (!caps || _state.busy) return;
    const CINOutputPlan plan = CINPlanVideoOutput(_state.frameWidth, _state.frameHeight, _state.deviceRotation);
    const int fps = _sessionFps > 0 ? _sessionFps : _state.fps;
    const BOOL withAudio = _state.micPermission && _audio.isRunning;
    NSString *error = nil;
    CINVideoRecorder *rec = [[CINVideoRecorder alloc] initWithURL:[CINMediaSaver newVideoURL]
                                                            width:plan.width
                                                           height:plan.height
                                                              fps:fps
                                                          bitrate:[CINVideoRecorder bitrateForWidth:plan.width height:plan.height fps:fps]
                                                  orientationHint:plan.orientationHint
                                                            audio:withAudio
                                                       sampleRate:_audio.sampleRate
                                                         channels:_audio.channelCount
                                                            error:&error];
    if (!rec || ![rec start]) {
        [self toast:[NSString stringWithFormat:CINL(@"error_record_start"), error ?: CINL(@"error_video_file")]];
        return;
    }
    _recorder = rec;
    if (withAudio) {
        _audio.sink = ^(CMSampleBufferRef sb) {
            [rec appendAudio:sb];
        };
    }
    [_renderer startEncoder:rec width:plan.width height:plan.height matrix:CINOutputMatrix(plan.rotationCw, caps.front, false)
                      plane:[self recordPlane]];
    _state.recording = YES;
    _state.recordStart = CACurrentMediaTime();
    _state.activeTool = CINToolNone;
    _state.panel = CINPanelNone;
    [self notify];
    [_renderer setThumbnailsEnabled:NO];
}

- (void)stopRecording {
    CINVideoRecorder *rec = _recorder;
    if (!rec) return;
    _recorder = nil;
    _audio.sink = nil;
    _state.recording = NO;
    _state.busy = YES;
    [self notify];
    __weak CINCameraViewModel *weakSelf = self;
    [_renderer stopEncoder:^{
        [rec finishWithCompletion:^(BOOL ok) {
            if (!ok) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf finishVideo:nil thumb:nil error:CINL(@"error_record_save")];
                });
                return;
            }
            UIImage *thumb = [CINMediaSaver thumbnailForVideo:rec.url];
            [CINMediaSaver saveVideoAtURL:rec.url completion:^(NSURL *lastCapture, NSString *saveError) {
                [weakSelf finishVideo:lastCapture thumb:thumb error:saveError];
            }];
        }];
    }];
}

- (void)finishVideo:(NSURL *)url thumb:(UIImage *)thumb error:(NSString *)error {
    _state.busy = NO;
    if (url) {
        _state.lastURL = url;
        _state.lastIsVideo = YES;
        if (thumb) _state.lastThumb = thumb;
    }
    if (error) [self toast:error];
    [self notify];
}

#pragma mark - 渲染参数

- (void)pushRenderParams {
    CINCameraState *s = _state;
    const CINCameraControls c = s.controls;
    // 手动白平衡：ISP 能做就交给 ISP，否则在 GPU 的镜头 pass 里乘增益
    const simd_float3 wb = !c.wbAuto && !_camera.wbOnIsp ? CINWhiteBalanceGains(c.kelvin, c.tint) : simd_make_float3(1.f, 1.f, 1.f);
    const CINEffects fx = s.effects;
    CINRenderParams p = CINRenderParamsDefault();
    p.sourceEncoding = s.logMode == CINLogModeIsp && _appleLogActive ? CINEncodingAppleLog : CINEncodingRec709;
    p.workingEncoding = s.logOn ? CINEncodingCineLog : CINEncodingRec709;
    p.lookStrength = fx.lookStrength / 10.f;
    p.halation = fx.halation / 10.f;
    p.mist = fx.mist / 10.f;
    p.grain = fx.grain / 10.f;
    p.grainSize = fx.grainSize / 10.f;
    p.vignette = fx.vignette / 10.f;
    p.aberration = fx.aberration / 10.f;
    p.wbGains = wb;
    p.showSignal = s.showSignal && s.logOn;
    p.zebra = s.assist.zebra;
    p.peaking = s.assist.peaking;
    p.waveform = s.assist.waveform;
    _renderer.params = p;
}

@end
