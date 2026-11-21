#import "CINSimulatedCamera.h"

#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>

#import "CINFrameGeometry.h"
#import "CINLocalization.h"
#import "CINShaderTypes.h"

static const int kSceneW = 1536;
static const int kSceneH = 2048;
// 「测光」认为的标准曝光：ISO 200、1/100s
static const double kBaseProduct = 200.0 * 10000000.0;
static const float kSceneFocus = 0.5f;   // 场景整体在 2 米处（0.5 屈光度）

#pragma mark - 场景图

typedef struct {
    CGContextRef albedo;
    CGContextRef emission;
} CINSceneCanvas;

static void CINFill(CINSceneCanvas c, float x0, float y0, float x1, float y1, float r, float g, float b, float em) {
    const CGRect rect = CGRectMake(x0 * kSceneW, y0 * kSceneH, (x1 - x0) * kSceneW, (y1 - y0) * kSceneH);
    CGContextSetRGBFillColor(c.albedo, r, g, b, 1);
    CGContextFillRect(c.albedo, rect);
    CGContextSetGrayFillColor(c.emission, em, 1);
    CGContextFillRect(c.emission, rect);
}

static void CINFillEllipse(CINSceneCanvas c, float cx, float cy, float rx, float ry, float r, float g, float b, float em) {
    const CGRect rect = CGRectMake((cx - rx) * kSceneW, (cy - ry) * kSceneH, 2 * rx * kSceneW, 2 * ry * kSceneH);
    CGContextSetRGBFillColor(c.albedo, r, g, b, 1);
    CGContextFillEllipseInRect(c.albedo, rect);
    CGContextSetGrayFillColor(c.emission, em, 1);
    CGContextFillEllipseInRect(c.emission, rect);
}

static void CINFillPolygon(CINSceneCanvas c, const float *xy, int n, float r, float g, float b, float em) {
    for (int k = 0; k < 2; ++k) {
        CGContextRef ctx = k == 0 ? c.albedo : c.emission;
        CGContextBeginPath(ctx);
        for (int i = 0; i < n; ++i) {
            const CGFloat x = xy[2 * i] * kSceneW, y = xy[2 * i + 1] * kSceneH;
            if (i == 0) CGContextMoveToPoint(ctx, x, y);
            else CGContextAddLineToPoint(ctx, x, y);
        }
        CGContextClosePath(ctx);
        if (k == 0) CGContextSetRGBFillColor(ctx, r, g, b, 1);
        else CGContextSetGrayFillColor(ctx, em, 1);
        CGContextFillPath(ctx);
    }
}

/** 色卡的 24 个色块（常见的标准色卡 sRGB 参考值）。 */
static const uint8_t kChart[24][3] = {
    {115, 82, 68},   {194, 150, 130}, {98, 122, 157},  {87, 108, 67},   {133, 128, 177}, {103, 189, 170},
    {214, 126, 44},  {80, 91, 166},   {193, 90, 99},   {94, 60, 108},   {157, 188, 64},  {224, 163, 46},
    {56, 61, 150},   {70, 148, 73},   {175, 54, 60},   {231, 199, 31},  {187, 86, 149},  {8, 133, 161},
    {243, 243, 242}, {200, 200, 200}, {160, 160, 160}, {122, 122, 121}, {85, 85, 85},    {52, 52, 52},
};

/** 显示器屏幕在场景里的位置（左上原点，归一化）。着色器在这里画一个会动的方块。 */
static const float kMonitor[4] = {0.535f, 0.405f, 0.885f, 0.535f};

static void CINDrawScene(CINSceneCanvas c) {
    // 墙：上亮下暗的暖色木板墙，竖向板缝给峰值对焦一些细节
    for (int i = 0; i < 64; ++i) {
        const float y0 = i / 64.f * 0.64f, y1 = (i + 1) / 64.f * 0.64f;
        const float t = i / 63.f;
        CINFill(c, 0, y0, 1, y1 + 0.001f, 0.80f - 0.14f * t, 0.72f - 0.14f * t, 0.60f - 0.13f * t, 0);
    }
    for (int i = 1; i < 13; ++i) CINFill(c, i / 13.f - 0.0015f, 0, i / 13.f + 0.0015f, 0.64f, 0.52f, 0.45f, 0.36f, 0);
    // 地板：深色木地板 + 横向地板缝
    CINFill(c, 0, 0.64f, 1, 1, 0.42f, 0.30f, 0.21f, 0);
    for (int i = 0; i < 9; ++i) {
        const float y = 0.66f + 0.34f * (i / 9.f) * (i / 9.f + 0.4f);
        CINFill(c, 0, y, 1, y + 0.002f, 0.30f, 0.21f, 0.15f, 0);
    }
    CINFill(c, 0, 0.635f, 1, 0.645f, 0.36f, 0.27f, 0.19f, 0);   // 踢脚线
    // 地毯：深灰格纹
    const float rug[] = {0.18f, 0.78f, 0.90f, 0.78f, 1.0f, 0.97f, 0.05f, 0.97f};
    CINFillPolygon(c, rug, 4, 0.22f, 0.22f, 0.24f, 0);
    for (int i = 0; i < 6; ++i) {
        const float y = 0.80f + i * 0.03f;
        CINFill(c, 0.12f, y, 0.95f, y + 0.004f, 0.32f, 0.32f, 0.34f, 0);
    }
    // 窗户：天空亮得远超白，过曝、光晕、斑马纹都靠它
    CINFill(c, 0.04f, 0.10f, 0.34f, 0.52f, 0.30f, 0.22f, 0.16f, 0);   // 窗框
    for (int i = 0; i < 40; ++i) {
        const float y0 = 0.115f + i / 40.f * 0.39f, y1 = 0.115f + (i + 1) / 40.f * 0.39f;
        const float t = i / 39.f;
        CINFill(c, 0.055f, y0, 0.325f, y1 + 0.001f, 0.72f + 0.2f * t, 0.84f + 0.1f * t, 0.98f, 1.0f - 0.3f * t);
    }
    CINFill(c, 0.186f, 0.115f, 0.194f, 0.505f, 0.30f, 0.22f, 0.16f, 0);   // 中梃
    CINFill(c, 0.055f, 0.300f, 0.325f, 0.308f, 0.30f, 0.22f, 0.16f, 0);
    // 窗外照进来的光斑
    const float sun[] = {0.06f, 0.70f, 0.30f, 0.70f, 0.46f, 0.90f, 0.14f, 0.90f};
    CINFillPolygon(c, sun, 4, 0.62f, 0.47f, 0.33f, 0.18f);
    // 色卡：6 x 4
    CINFill(c, 0.50f, 0.12f, 0.93f, 0.33f, 0.08f, 0.08f, 0.08f, 0);
    for (int i = 0; i < 24; ++i) {
        const int col = i % 6, row = i / 6;
        const float x0 = 0.512f + col * 0.0695f, y0 = 0.132f + row * 0.049f;
        CINFill(c, x0, y0, x0 + 0.06f, y0 + 0.042f, kChart[i][0] / 255.f, kChart[i][1] / 255.f, kChart[i][2] / 255.f, 0);
    }
    // 电视柜 + 显示器（棋盘格屏幕，方块由着色器画）
    CINFill(c, 0.46f, 0.57f, 0.96f, 0.69f, 0.74f, 0.62f, 0.46f, 0);
    CINFill(c, 0.46f, 0.625f, 0.96f, 0.628f, 0.55f, 0.45f, 0.33f, 0);
    CINFill(c, 0.71f, 0.57f, 0.713f, 0.69f, 0.55f, 0.45f, 0.33f, 0);
    CINFill(c, 0.48f, 0.69f, 0.49f, 0.73f, 0.55f, 0.45f, 0.33f, 0);
    CINFill(c, 0.93f, 0.69f, 0.94f, 0.73f, 0.55f, 0.45f, 0.33f, 0);
    CINFill(c, 0.69f, 0.545f, 0.73f, 0.57f, 0.08f, 0.08f, 0.09f, 0);   // 支架
    CINFill(c, 0.52f, 0.39f, 0.90f, 0.55f, 0.05f, 0.05f, 0.06f, 0);    // 边框
    for (int row = 0; row < 8; ++row) {
        for (int col = 0; col < 16; ++col) {
            const float w = (kMonitor[2] - kMonitor[0]) / 16.f, h = (kMonitor[3] - kMonitor[1]) / 8.f;
            const BOOL white = (row + col) % 2 == 0;
            CINFill(c, kMonitor[0] + col * w, kMonitor[1] + row * h, kMonitor[0] + (col + 1) * w, kMonitor[1] + (row + 1) * h,
                    white ? 0.85f : 0.04f, white ? 0.85f : 0.04f, white ? 0.86f : 0.05f, white ? 0.08f : 0.f);
        }
    }
    // 绿植：陶盆 + 几片叶子（青橙、森屿这些影调会推绿色）
    CINFill(c, 0.08f, 0.80f, 0.24f, 0.93f, 0.70f, 0.37f, 0.24f, 0);
    CINFill(c, 0.07f, 0.79f, 0.25f, 0.815f, 0.62f, 0.32f, 0.21f, 0);
    const float leaves[][4] = {{0.16f, 0.70f, 0.07f, 0.05f}, {0.11f, 0.74f, 0.05f, 0.04f}, {0.21f, 0.74f, 0.05f, 0.04f},
                               {0.13f, 0.65f, 0.04f, 0.05f}, {0.19f, 0.64f, 0.04f, 0.05f}, {0.16f, 0.60f, 0.03f, 0.04f}};
    for (int i = 0; i < 6; ++i) {
        const float g = i % 2 ? 0.50f : 0.42f;
        CINFillEllipse(c, leaves[i][0], leaves[i][1], leaves[i][2], leaves[i][3], 0.18f, g, 0.17f, 0);
    }
    // 橙色花瓶（肤色附近的颜色，看影调对暖色的处理）
    CINFillEllipse(c, 0.62f, 0.53f, 0.025f, 0.035f, 0.88f, 0.58f, 0.42f, 0);
    // 落地灯：灯罩 + 发光的灯泡
    CINFill(c, 0.947f, 0.22f, 0.953f, 0.64f, 0.12f, 0.11f, 0.10f, 0);
    const float shade[] = {0.91f, 0.14f, 0.99f, 0.14f, 1.0f, 0.21f, 0.90f, 0.21f};
    CINFillPolygon(c, shade, 4, 0.95f, 0.86f, 0.70f, 0.35f);
    CINFillEllipse(c, 0.95f, 0.215f, 0.018f, 0.012f, 1.0f, 0.85f, 0.60f, 1.0f);
}

#pragma mark - 虚拟相机

@implementation CINSimulatedCamera {
    dispatch_queue_t _queue;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLTexture> _albedo;
    id<MTLTexture> _emission;
    CVMetalTextureCacheRef _textureCache;
    CVPixelBufferPoolRef _pool;
    dispatch_source_t _timer;
    dispatch_queue_t _frameQueue;
    CINSessionConfig *_config;
    CINCameraCaps *_caps;
    int _bufferW, _bufferH;
    BOOL _rendering;
    CFTimeInterval _start;
    CFTimeInterval _lastReadout;
    os_unfair_lock _lock;
    CINCameraControls _controls;
    CFTimeInterval _focusStart;   // 点击对焦开始的时间（0 = 没在点击对焦）
}

@synthesize delegate = _delegate;

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("CineGL-SimCamera", DISPATCH_QUEUE_SERIAL);
        _lock = OS_UNFAIR_LOCK_INIT;
        _controls = CINCameraControlsDefault();
        _start = CACurrentMediaTime();
    }
    return self;
}

- (void)dealloc {
    if (_timer) dispatch_source_cancel(_timer);
    if (_pool) CVPixelBufferPoolRelease(_pool);
    if (_textureCache) CFRelease(_textureCache);
}

- (BOOL)wbOnIsp {
    return NO;
}

- (BOOL)prepareGpu {
    if (_pipeline) return YES;
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return NO;
    _commandQueue = [_device newCommandQueue];
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:nil];
    MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
    d.vertexFunction = [library newFunctionWithName:@"cin_quad_vertex"];
    d.fragmentFunction = [library newFunctionWithName:@"cin_sim_scene_fragment"];
    d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipeline = [_device newRenderPipelineStateWithDescriptor:d error:nil];
    CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_textureCache);
    [self buildScene];
    return _pipeline != nil && _albedo != nil;
}

/** 用 Core Graphics 画一次场景：颜色一张、「自发光」一张，上传成带 mipmap 的纹理（失焦时采样更高的 mip 级别）。 */
- (void)buildScene {
    CGColorSpaceRef rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CINSceneCanvas c;
    c.albedo = CGBitmapContextCreate(NULL, kSceneW, kSceneH, 8, kSceneW * 4, rgb, kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    c.emission = CGBitmapContextCreate(NULL, kSceneW, kSceneH, 8, kSceneW, gray, (CGBitmapInfo)kCGImageAlphaNone);
    for (int k = 0; k < 2; ++k) {
        CGContextRef ctx = k == 0 ? c.albedo : c.emission;
        // 翻成左上原点，和纹理坐标一致
        CGContextTranslateCTM(ctx, 0, kSceneH);
        CGContextScaleCTM(ctx, 1, -1);
    }
    CINDrawScene(c);
    _albedo = [self mipTexture:CGBitmapContextGetData(c.albedo) format:MTLPixelFormatRGBA8Unorm bytesPerRow:kSceneW * 4];
    _emission = [self mipTexture:CGBitmapContextGetData(c.emission) format:MTLPixelFormatR8Unorm bytesPerRow:kSceneW];
    CGContextRelease(c.albedo);
    CGContextRelease(c.emission);
    CGColorSpaceRelease(rgb);
    CGColorSpaceRelease(gray);
}

- (id<MTLTexture>)mipTexture:(const void *)bytes format:(MTLPixelFormat)format bytesPerRow:(NSUInteger)bpr {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:kSceneW height:kSceneH mipmapped:YES];
    d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    [t replaceRegion:MTLRegionMake2D(0, 0, kSceneW, kSceneH) mipmapLevel:0 withBytes:bytes bytesPerRow:bpr];
    id<MTLCommandBuffer> cb = [_commandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:t];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    return t;
}

#pragma mark - 开相机

static const CINSize kSimSizes[] = {{1280, 720}, {1920, 1080}, {3840, 2160}, {640, 480}, {1440, 1080}, {1920, 1440}};

- (void)startWithConfig:(CINSessionConfig *)config frameQueue:(dispatch_queue_t)frameQueue
             completion:(void (^)(CINSessionInfo *, NSString *))completion {
    dispatch_async(_queue, ^{
        [self stopTimer];
        if (![self prepareGpu]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, CINL(@"error_camera_open"));
            });
            return;
        }
        const NSInteger k = CINPickStreamSize(kSimSizes, 6, config.streamAspect, config.targetShort);
        self->_bufferW = kSimSizes[k].w;
        self->_bufferH = kSimSizes[k].h;
        self->_config = config;
        self->_frameQueue = frameQueue;
        [self makePool];

        CINCameraCaps *caps = [[CINCameraCaps alloc] init];
        caps.front = config.front;
        caps.sensorOrientation = 90;
        caps.manualSensor = YES;
        caps.manualPostProcessing = NO;
        caps.focusLock = YES;
        caps.isoMin = 50;
        caps.isoMax = 3200;
        caps.exposureMinNs = 125000;          // 1/8000s
        caps.exposureMaxNs = 1000000000;      // 1s
        caps.minFocusDiopters = 10.f;         // 最近 10cm
        caps.evStep = 1.f / 3.f;
        caps.evMin = -9;
        caps.evMax = 9;
        caps.zoomMin = 1.f;
        caps.zoomMax = 10.f;
        caps.hasFlash = !config.front;
        caps.previewStabilization = NO;
        caps.equivalentFocal = config.front ? 23.f : 26.f;
        self->_caps = caps;

        os_unfair_lock_lock(&self->_lock);
        self->_controls = config.controls;
        self->_focusStart = 0;
        os_unfair_lock_unlock(&self->_lock);
        [self startTimer:config.fps];

        CINSessionInfo *info = [[CINSessionInfo alloc] init];
        info.caps = caps;
        info.bufferWidth = self->_bufferW;
        info.bufferHeight = self->_bufferH;
        info.fps = config.fps;
        info.availableFps = @[@24, @25, @30, @60];
        info.uhdAvailable = YES;
        info.appleLogAvailable = NO;
        info.appleLogActive = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(info, nil);
        });
    });
}

- (void)makePool {
    if (_pool) CVPixelBufferPoolRelease(_pool);
    _pool = NULL;
    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(_bufferW),
        (id)kCVPixelBufferHeightKey: @(_bufferH),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attrs, &_pool);
}

- (void)startTimer:(int)fps {
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    const uint64_t interval = NSEC_PER_SEC / (uint64_t)MAX(1, fps);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval / 10);
    __weak CINSimulatedCamera *weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        [weakSelf tick];
    });
    dispatch_resume(_timer);
}

- (void)stopTimer {
    if (_timer) dispatch_source_cancel(_timer);
    _timer = nil;
}

- (void)stopWithCompletion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self stopTimer];
        self->_config = nil;
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

#pragma mark - 曝光 / 对焦模型

/** 当前参数下的 ISO、快门：自动时以「ISO 200、1/100s」为准（叠加曝光补偿），半自动按测光乘积反推。 */
- (void)exposureFor:(CINCameraControls)c iso:(int *)iso exposure:(int64_t *)exposure {
    CINCameraCaps *caps = _caps;
    const int64_t frameNs = 1000000000LL / MAX(1, _config.fps);
    const int64_t maxExposure = MIN(caps.exposureMaxNs, _config.video ? frameNs : 66666666LL);
    if (CINCameraControlsExposureAuto(c)) {
        const double product = kBaseProduct * pow(2.0, c.evIndex * caps.evStep);
        *iso = (int)MIN(MAX(lround(200.0 * pow(2.0, c.evIndex * caps.evStep)), caps.isoMin), caps.isoMax);
        *exposure = MIN(MAX(llround(product / *iso), caps.exposureMinNs), maxExposure);
    } else {
        CINResolveExposure(c, caps.isoMin, caps.isoMax, caps.exposureMinNs, maxExposure, kBaseProduct, caps.evStep, iso, exposure);
    }
}

- (CINSimSceneUniforms)uniformsAt:(CFTimeInterval)now controls:(CINCameraControls)c focusStart:(CFTimeInterval)focusStart
                         bufferW:(int)bw bufferH:(int)bh {
    int iso = 0;
    int64_t exposure = 0;
    [self exposureFor:c iso:&iso exposure:&exposure];
    CINSimSceneUniforms u;
    u.monitorRect = simd_make_float4(kMonitor[0], kMonitor[1], kMonitor[2], kMonitor[3]);
    u.time = (float)(now - _start);
    u.gain = (float)((double)iso * (double)exposure / kBaseProduct);
    u.zoom = fminf(fmaxf(c.zoom, 1.f), 10.f);
    u.blur = 0.f;
    if (!c.focusAuto) {
        u.blur = fminf(5.f, fabsf(c.focusDiopters - kSceneFocus) * 2.5f);
    } else if (focusStart > 0 && now - focusStart < 0.35) {
        u.blur = 1.5f * (float)(1.0 - (now - focusStart) / 0.35);   // 点击对焦时「拉一下风箱」
    }
    u.torch = c.torch && _caps.hasFlash ? 1.f : 0.f;
    u.uprightAspect = (float)bh / (float)bw;
    u.sceneAspect = (float)kSceneW / (float)kSceneH;
    u.front = _config.front ? 1 : 0;
    return u;
}

- (BOOL)render:(CVPixelBufferRef)pb uniforms:(CINSimSceneUniforms)u commandBuffer:(id<MTLCommandBuffer>)cb
     keepAlive:(CVMetalTextureRef *)outRef {
    CVMetalTextureRef ref = NULL;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pb, NULL, MTLPixelFormatBGRA8Unorm,
                                              CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &ref);
    if (!ref) return NO;
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = CVMetalTextureGetTexture(ref);
    rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:_pipeline];
    const CINMat4 identity = CINMat4Identity();
    const simd_float4x4 m = CINMat4ToSimd(identity);
    [enc setVertexBytes:&m length:sizeof(m) atIndex:0];
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    [enc setFragmentTexture:_albedo atIndex:0];
    [enc setFragmentTexture:_emission atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
    *outRef = ref;
    return YES;
}

- (void)tick {
    if (!_config || !_pool || _rendering) return;
    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &pb) != kCVReturnSuccess || !pb) return;
    const CFTimeInterval now = CACurrentMediaTime();
    os_unfair_lock_lock(&_lock);
    const CINCameraControls c = _controls;
    const CFTimeInterval focusStart = _focusStart;
    os_unfair_lock_unlock(&_lock);
    const CINSimSceneUniforms u = [self uniformsAt:now controls:c focusStart:focusStart bufferW:_bufferW bufferH:_bufferH];
    const CMTime time = CMClockGetTime(CMClockGetHostTimeClock());

    id<MTLCommandBuffer> cb = [_commandQueue commandBuffer];
    CVMetalTextureRef ref = NULL;
    if (![self render:pb uniforms:u commandBuffer:cb keepAlive:&ref]) {
        CVPixelBufferRelease(pb);
        return;
    }
    _rendering = YES;
    dispatch_queue_t frameQueue = _frameQueue;
    dispatch_queue_t queue = _queue;
    __weak CINSimulatedCamera *weakSelf = self;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        CFRelease(ref);
        dispatch_async(frameQueue, ^{
            CINSimulatedCamera *cam = weakSelf;
            if (cam) [cam.delegate cameraSource:cam didOutputPixelBuffer:pb time:time];
            CVPixelBufferRelease(pb);
        });
        dispatch_async(queue, ^{
            CINSimulatedCamera *cam = weakSelf;
            if (cam) cam->_rendering = NO;
        });
    }];
    [cb commit];
    [self reportReadout:c now:now focusStart:focusStart];
}

- (void)reportReadout:(CINCameraControls)c now:(CFTimeInterval)now focusStart:(CFTimeInterval)focusStart {
    if (now - _lastReadout < 0.12) return;
    _lastReadout = now;
    int iso = 0;
    int64_t exposure = 0;
    [self exposureFor:c iso:&iso exposure:&exposure];
    CINReadout r;
    r.iso = iso;
    r.exposureNs = exposure;
    r.focusDiopters = c.focusAuto ? kSceneFocus : c.focusDiopters;
    r.afLocked = focusStart > 0 && now - focusStart >= 0.35;
    r.kelvin = 0.f;
    [self.delegate cameraSource:self didUpdateReadout:r];
}

#pragma mark - 参数 / 对焦 / 拍照

- (void)updateControls:(CINCameraControls)controls {
    os_unfair_lock_lock(&_lock);
    _controls = controls;
    os_unfair_lock_unlock(&_lock);
}

- (void)focusAtBufferPoint:(CGPoint)point {
    os_unfair_lock_lock(&_lock);
    if (_controls.focusAuto) _focusStart = CACurrentMediaTime();
    os_unfair_lock_unlock(&_lock);
}

- (void)resetFocus {
    os_unfair_lock_lock(&_lock);
    _focusStart = 0;
    os_unfair_lock_unlock(&_lock);
}

- (void)captureWithCompletion:(void (^)(CINStillCapture *, NSString *))completion {
    dispatch_async(_queue, ^{
        if (!self->_config || self->_config.video) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, CINL(@"error_photo_mode"));
            });
            return;
        }
        // 照片：4032x3024，和真机 1200 万像素一样
        const int w = 4032, h = 3024;
        NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
        CVPixelBufferRef pb = NULL;
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &pb);
        os_unfair_lock_lock(&self->_lock);
        const CINCameraControls c = self->_controls;
        const CFTimeInterval focusStart = self->_focusStart;
        os_unfair_lock_unlock(&self->_lock);
        const CFTimeInterval now = CACurrentMediaTime();
        const CINSimSceneUniforms u = [self uniformsAt:now controls:c focusStart:focusStart bufferW:w bufferH:h];
        id<MTLCommandBuffer> cb = [self->_commandQueue commandBuffer];
        CVMetalTextureRef ref = NULL;
        const BOOL ok = pb && [self render:pb uniforms:u commandBuffer:cb keepAlive:&ref];
        CINStillCapture *still = nil;
        if (ok) {
            [cb commit];
            [cb waitUntilCompleted];
            CFRelease(ref);
            int iso = 0;
            int64_t exposure = 0;
            [self exposureFor:c iso:&iso exposure:&exposure];
            still = [[CINStillCapture alloc] init];
            still.pixelBuffer = pb;
            still.iso = iso;
            still.exposureNs = exposure;
            still.focalLength = 6.0f;
            still.aperture = 1.8f;
        }
        CVPixelBufferRelease(pb);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(still, still ? nil : [NSString stringWithFormat:CINL(@"error_capture_code"), -1]);
        });
    });
}

@end
