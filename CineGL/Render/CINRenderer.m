#import "CINRenderer.h"

#import "CINLutBank.h"
#import "CINPassPlan.h"

static const int kThumbnailInterval = 6;        // 影调面板开着：每 6 帧刷新所有缩略图
static const int kIdleThumbnailInterval = 45;   // 面板关着：只给底部的影调按钮低频刷新当前这一个
static const int kThumbWidth = 132;
static const int kThumbColumns = 4;
static const long kMaxFramesInFlight = 3;

@implementation CINStillRequest
- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == _pixelBuffer) return;
    CVPixelBufferRetain(pixelBuffer);
    CVPixelBufferRelease(_pixelBuffer);
    _pixelBuffer = pixelBuffer;
}
- (void)dealloc {
    CVPixelBufferRelease(_pixelBuffer);
}
@end

/** 正在往里画的录像目标。 */
@interface CINEncoderTarget : NSObject
@property (nonatomic, strong) id<CINRenderVideoSink> sink;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) CINMat4 matrix;
@property (nonatomic) CINPlane plane;
@end
@implementation CINEncoderTarget
@end

@implementation CINRenderer {
    // ---- 只在渲染队列访问 ----
    CINEngine *_engine;
    CINLutBank *_lutBank;
    CVMetalTextureCacheRef _textureCache;
    CAMetalLayer *_layer;
    BOOL _hasInput;
    CINRenderInputConfig _input;
    CINFrameGeometry _geometry;
    CINEncoderTarget *_encoder;
    uint32_t _frameIndex;
    NSInteger _selectedLook;
    BOOL _thumbnailsEnabled;
    // ----
    dispatch_queue_t _writerQueue;   // 录像缓冲按提交顺序等 GPU 跑完再交给写入器
    dispatch_semaphore_t _inFlight;
    CFTimeInterval _startTime;
}

- (instancetype)init {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return nil;
    CINEngine *engine = [[CINEngine alloc] initWithDevice:device];
    // 只会出现在日志里，给开发者看，所以用英文（和其他日志一致）
    if (!engine) {
        NSLog(@"CineGL: Metal engine init failed, see the CineGL errors above");
        return nil;
    }
    if ((self = [super init])) {
        _engine = engine;
        _queue = dispatch_queue_create("CineGL-Render", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _writerQueue = dispatch_queue_create("CineGL-VideoBuffers", DISPATCH_QUEUE_SERIAL);
        _inFlight = dispatch_semaphore_create(kMaxFramesInFlight);
        _lutBank = [[CINLutBank alloc] initWithEngine:engine renderQueue:_queue];
        _params = CINRenderParamsDefault();
        _startTime = CACurrentMediaTime();
        CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, device, NULL, &_textureCache);
        dispatch_async(_queue, ^{
            [self->_lutBank ensureEncoding:self.params.workingEncoding priority:self->_selectedLook];
        });
    }
    return self;
}

- (void)dealloc {
    if (_textureCache) CFRelease(_textureCache);
}

#pragma mark - 配置

- (void)configureInput:(CINRenderInputConfig)config {
    dispatch_sync(_queue, ^{
        self->_input = config;
        self->_hasInput = YES;
        [self updateGeometry];
    });
}

- (void)setAspect:(CINAspectRatio)aspect {
    dispatch_async(_queue, ^{
        if (!self->_hasInput) return;
        self->_input.aspect = aspect;
        [self updateGeometry];
    });
}

- (void)updateGeometry {
    const CINRenderInputConfig c = _input;
    _geometry = CINComputeFrame(c.bufferWidth, c.bufferHeight, c.sensorOrientation, c.aspect, kCINFrameAlign);
    const int w = _geometry.frameWidth, h = _geometry.frameHeight;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate renderer:self frameSizeDidChangeWidth:w height:h];
    });
}

- (void)selectLook:(NSInteger)index {
    dispatch_async(_queue, ^{
        self->_selectedLook = index;
        [self->_engine selectLook:index];
    });
}

- (void)bakeLook:(NSInteger)index {
    dispatch_async(_queue, ^{
        [self->_lutBank bake:index];
    });
}

- (void)setThumbnailsEnabled:(BOOL)enabled {
    dispatch_async(_queue, ^{
        self->_thumbnailsEnabled = enabled;
    });
}

#pragma mark - 屏幕

- (void)attachLayer:(CAMetalLayer *)layer {
    layer.device = _engine.device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    dispatch_async(_queue, ^{
        self->_layer = layer;
    });
}

- (void)detachLayer {
    dispatch_sync(_queue, ^{
        self->_layer = nil;
    });
}

#pragma mark - 录像

- (void)startEncoder:(id<CINRenderVideoSink>)sink width:(int)width height:(int)height matrix:(CINMat4)matrix plane:(CINPlane)plane {
    CINEncoderTarget *t = [[CINEncoderTarget alloc] init];
    t.sink = sink;
    t.width = width;
    t.height = height;
    t.matrix = matrix;
    t.plane = plane;
    dispatch_async(_queue, ^{
        self->_encoder = t;
    });
}

- (void)stopEncoder:(void (^)(void))onStopped {
    dispatch_async(_queue, ^{
        self->_encoder = nil;
        // 排在所有已提交的录像帧后面：它们都交给写入器之后才算停稳
        dispatch_async(self->_writerQueue, onStopped);
    });
}

#pragma mark - 纹理

static id<MTLTexture> CINTextureFromBuffer(CVMetalTextureCacheRef cache, CVPixelBufferRef pb, size_t plane,
                                           MTLPixelFormat format, NSMutableArray *keepAlive) {
    const BOOL planar = CVPixelBufferIsPlanar(pb);
    const size_t w = planar ? CVPixelBufferGetWidthOfPlane(pb, plane) : CVPixelBufferGetWidth(pb);
    const size_t h = planar ? CVPixelBufferGetHeightOfPlane(pb, plane) : CVPixelBufferGetHeight(pb);
    CVMetalTextureRef ref = NULL;
    const CVReturn r = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pb, NULL, format, w, h, plane, &ref);
    if (r != kCVReturnSuccess || !ref) return nil;
    // CVMetalTexture 要活到 GPU 用完为止，否则底下的 IOSurface 可能被相机拿去复用
    [keepAlive addObject:(__bridge_transfer id)ref];
    return CVMetalTextureGetTexture(ref);
}

static CINYCbCrMatrix CINMatrixKind(CVPixelBufferRef pb) {
    CFTypeRef m = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, NULL);
    CINYCbCrMatrix kind = CINYCbCrMatrix709;
    if (m) {
        if (CFEqual(m, kCVImageBufferYCbCrMatrix_ITU_R_601_4)) kind = CINYCbCrMatrix601;
        else if (CFEqual(m, kCVImageBufferYCbCrMatrix_ITU_R_2020)) kind = CINYCbCrMatrix2020;
        CFRelease(m);
    }
    return kind;
}

/** 相机缓冲 → 引擎输入。支持 8 / 10 bit 的 YCbCr 双平面和 BGRA。 */
- (CINInputFrame *)inputFrom:(CVPixelBufferRef)pb keepAlive:(NSMutableArray *)keepAlive {
    CINInputFrame *in = [[CINInputFrame alloc] init];
    const OSType format = CVPixelBufferGetPixelFormatType(pb);
    switch (format) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: {
            in.luma = CINTextureFromBuffer(_textureCache, pb, 0, MTLPixelFormatR8Unorm, keepAlive);
            in.chroma = CINTextureFromBuffer(_textureCache, pb, 1, MTLPixelFormatRG8Unorm, keepAlive);
            in.ycbcrToRgb = CINYCbCrToRgbMatrix(CINMatrixKind(pb), format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, 8);
            break;
        }
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: {
            in.luma = CINTextureFromBuffer(_textureCache, pb, 0, MTLPixelFormatR16Unorm, keepAlive);
            in.chroma = CINTextureFromBuffer(_textureCache, pb, 1, MTLPixelFormatRG16Unorm, keepAlive);
            in.ycbcrToRgb = CINYCbCrToRgbMatrix(CINMatrixKind(pb), format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange, 10);
            break;
        }
        case kCVPixelFormatType_32BGRA:
            in.rgba = CINTextureFromBuffer(_textureCache, pb, 0, MTLPixelFormatBGRA8Unorm, keepAlive);
            break;
        default:
            NSLog(@"CineGL: unsupported pixel format %u", (unsigned)format);
            return nil;
    }
    if (!in.rgba && (!in.luma || !in.chroma)) return nil;
    return in;
}

#pragma mark - 每帧

- (void)drawPixelBuffer:(CVPixelBufferRef)pixelBuffer presentationTime:(CMTime)time {
    if (!_hasInput) return;
    // GPU 落后太多就丢帧，别让相机缓冲越积越多
    if (dispatch_semaphore_wait(_inFlight, DISPATCH_TIME_NOW) != 0) return;

    NSMutableArray *keepAlive = [NSMutableArray array];
    CINInputFrame *input = [self inputFrom:pixelBuffer keepAlive:keepAlive];
    if (!input) {
        dispatch_semaphore_signal(_inFlight);
        return;
    }
    const CINFrameGeometry geo = _geometry;
    const CINRenderParams p = self.params;
    [_lutBank ensureEncoding:p.workingEncoding priority:_selectedLook];

    // 相机缓冲是传感器方向：输入矩阵负责转正（和镜像），再乘上画幅裁切，就是镜头 pass 用的 texMatrix
    input.texMatrix = CINMat4Multiply(CINStillInputMatrix(_input.sensorOrientation, _input.front), CINCropMatrix(geo));

    id<MTLCommandBuffer> cb = [_engine.queue commandBuffer];
    cb.label = @"frame";
    [_engine renderFrame:input frameWidth:geo.frameWidth frameHeight:geo.frameHeight params:p frameIndex:_frameIndex commandBuffer:cb];

    CINEncoderTarget *enc = _encoder;
    if (enc) {
        CVPixelBufferRef out = [enc.sink copyEmptyVideoBuffer];
        id<MTLTexture> target = out ? CINTextureFromBuffer(_textureCache, out, 0, MTLPixelFormatBGRA8Unorm, keepAlive) : nil;
        if (target) {
            [_engine drawPlane:enc.plane matrix:enc.matrix to:target commandBuffer:cb];
            // 用相机的时间戳，音画同步全靠它（音频用同一个时钟）
            id<CINRenderVideoSink> sink = enc.sink;
            dispatch_async(_writerQueue, ^{
                [cb waitUntilCompleted];
                if (cb.status == MTLCommandBufferStatusCompleted) [sink appendVideoBuffer:out presentationTime:time];
                CVPixelBufferRelease(out);
            });
        } else if (out) {
            CVPixelBufferRelease(out);
        }
    }

    CAMetalLayer *layer = _layer;
    id<CAMetalDrawable> drawable = layer ? [layer nextDrawable] : nil;
    if (drawable) {
        id<MTLTexture> screen = drawable.texture;
        CINPresentParams pp;
        pp.frameRect = CINFitCenter(geo.frameWidth, geo.frameHeight, screen.width, screen.height);
        pp.cornerRadius = self.cornerRadiusPx;
        pp.overlayTopInset = self.overlayTopInsetPx;
        [_engine presentTo:screen present:pp params:p time:(float)(CACurrentMediaTime() - _startTime) commandBuffer:cb];
        [cb presentDrawable:drawable];
    }

    // 影调面板开着：所有影调高频刷新；关着：只给底部的影调按钮低频刷新当前这一个
    NSArray<NSNumber *> *ready = _lutBank.readyLooks;
    NSArray<NSNumber *> *thumbLooks = nil;
    if (_thumbnailsEnabled && _frameIndex % kThumbnailInterval == 0) {
        thumbLooks = ready;
    } else if (!_thumbnailsEnabled && _frameIndex % kIdleThumbnailInterval == 0 && [ready containsObject:@(_selectedLook)]) {
        thumbLooks = @[@(_selectedLook)];
    }
    if (thumbLooks.count > 0) [self renderThumbnails:thumbLooks geometry:geo commandBuffer:cb];

    dispatch_semaphore_t inFlight = _inFlight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        (void)keepAlive;   // 纹理和相机缓冲留到这里才放手
        dispatch_semaphore_signal(inFlight);
    }];
    [cb commit];
    _frameIndex++;
}

- (void)renderThumbnails:(NSArray<NSNumber *> *)looks geometry:(CINFrameGeometry)geo commandBuffer:(id<MTLCommandBuffer>)cb {
    const int tw = kThumbWidth;
    const int th = MIN(MAX(tw * geo.frameHeight / MAX(1, geo.frameWidth), tw / 2), tw * 2);
    const int cols = kThumbColumns;
    id<MTLTexture> atlas = [_engine renderThumbnails:looks thumbWidth:tw thumbHeight:th columns:cols commandBuffer:cb];
    if (!atlas) return;
    __weak CINRenderer *weakSelf = self;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        if (buffer.status != MTLCommandBufferStatusCompleted) return;
        NSDictionary *result = CINSliceAtlas(atlas, looks, tw, th, cols);
        dispatch_async(dispatch_get_main_queue(), ^{
            CINRenderer *r = weakSelf;
            if (r) [r.delegate renderer:r didRenderThumbnails:result];
        });
    }];
}

/** 读回 BGRA 纹理，做成 CGImage（sRGB，顶行在前）。 */
static CGImageRef CINCopyImage(id<MTLTexture> texture) CF_RETURNS_RETAINED {
    const size_t w = texture.width, h = texture.height, bpr = w * 4;
    NSMutableData *bytes = [NSMutableData dataWithLength:bpr * h];
    [texture getBytes:bytes.mutableBytes bytesPerRow:bpr fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)bytes);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(w, h, 8, 32, bpr, space, kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

static NSDictionary<NSNumber *, UIImage *> *CINSliceAtlas(id<MTLTexture> atlas, NSArray<NSNumber *> *looks, int tw, int th, int cols) {
    CGImageRef image = CINCopyImage(atlas);
    if (!image) return @{};
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:looks.count];
    for (NSUInteger i = 0; i < looks.count; ++i) {
        const CGRect cell = CGRectMake((CGFloat)((int)i % cols * tw), (CGFloat)((int)i / cols * th), tw, th);
        CGImageRef sub = CGImageCreateWithImageInRect(image, cell);
        if (!sub) continue;
        result[looks[i]] = [UIImage imageWithCGImage:sub];
        CGImageRelease(sub);
    }
    CGImageRelease(image);
    return result;
}

#pragma mark - 拍照

- (void)processStill:(CINStillRequest *)req completion:(void (^)(CGImageRef))completion {
    dispatch_async(_queue, ^{
        CVPixelBufferRef pb = req.pixelBuffer;
        NSMutableArray *keepAlive = [NSMutableArray array];
        CINInputFrame *input = pb ? [self inputFrom:pb keepAlive:keepAlive] : nil;
        if (!input) {
            completion(NULL);
            return;
        }
        const int bw = (int)CVPixelBufferGetWidth(pb);
        const int bh = (int)CVPixelBufferGetHeight(pb);
        // 正常情况下照片缓冲是传感器方向（横的）；万一给的已经是竖图，就当它已经转正了
        const int orientation = req.sensorOrientation % 180 == 90 && bh > bw ? 0 : req.sensorOrientation;
        const CINFrameGeometry geo = CINComputeFrame(bw, bh, orientation, req.aspect, kCINFrameAlign);
        input.texMatrix = CINMat4Multiply(CINStillInputMatrix(orientation, req.front), CINCropMatrix(geo));
        const CINOutputPlan plan = CINPlanPhotoOutput(geo.frameWidth, geo.frameHeight, req.deviceRotation);
        // Metal 的渲染目标本来就是顶行在前，不需要安卓 glReadPixels 那样的 flipY
        const CINMat4 outMatrix = CINOutputMatrix(plan.rotationCw, req.front, false);
        id<MTLTexture> output = [self->_engine makeReadableTextureWidth:plan.width height:plan.height];
        const BOOL ok = output && [self->_engine processStill:input frameWidth:geo.frameWidth frameHeight:geo.frameHeight
                                                       params:req.params plane:req.plane outMatrix:outMatrix output:output];
        CGImageRef image = ok ? CINCopyImage(output) : NULL;
        completion(image);
        if (image) CGImageRelease(image);
    });
}

@end
