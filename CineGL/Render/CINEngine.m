#import "CINEngine.h"

#import "CINPassPlan.h"
#import "CINShaderTypes.h"

// 管线内部的 8 bit 纹理统一用 BGRA：屏幕、录像缓冲本来就是 BGRA，一种格式到底，管线状态也只要一份
static const MTLPixelFormat kColorFormat = MTLPixelFormatBGRA8Unorm;
// 光晕金字塔存的是线性光，高光会超过 1.0，用半精度浮点（Metal 上总是能当渲染目标，不需要像 GL 那样兜底）
static const MTLPixelFormat kGlowFormat = MTLPixelFormatRGBA16Float;

CINRenderParams CINRenderParamsDefault(void) {
    CINRenderParams p;
    memset(&p, 0, sizeof(p));
    p.sourceEncoding = CINEncodingRec709;
    p.workingEncoding = CINEncodingRec709;
    p.lookStrength = 1.f;
    p.grainSize = 0.3f;
    p.wbGains = simd_make_float3(1.f, 1.f, 1.f);
    p.zebraThreshold = 0.95f;
    return p;
}

simd_float4x4 CINYCbCrToRgbMatrix(CINYCbCrMatrix kind, BOOL fullRange, int bitDepth) {
    float kr = 0.2126f, kb = 0.0722f;
    if (kind == CINYCbCrMatrix601) {
        kr = 0.299f;
        kb = 0.114f;
    } else if (kind == CINYCbCrMatrix2020) {
        kr = 0.2627f;
        kb = 0.0593f;
    }
    const float kg = 1.f - kr - kb;
    const int n = bitDepth >= 10 ? 10 : 8;
    // 采样值 → 码值：8 bit 直接 ×255；10 bit 放在 16 bit 高位，采样值 = v16 / 65535 = v10 × 64 / 65535
    const float k = n == 10 ? 65535.f / 64.f : 255.f;
    const float maxCode = (float)((1 << n) - 1);
    float ay, by, ac, bc;
    if (fullRange) {
        ay = k / maxCode;
        by = 0.f;
        ac = k / maxCode;
        bc = -(float)(1 << (n - 1)) / maxCode;
    } else {
        const float s = (float)(1 << (n - 8));
        ay = k / (219.f * s);
        by = -16.f / 219.f;
        ac = k / (224.f * s);
        bc = -128.f / 224.f;
    }
    const float crR = 2.f * (1.f - kr);
    const float cbG = -2.f * kb * (1.f - kb) / kg;
    const float crG = -2.f * kr * (1.f - kr) / kg;
    const float cbB = 2.f * (1.f - kb);
    return (simd_float4x4){{
        {ay, ay, ay, 0.f},
        {0.f, cbG * ac, cbB * ac, 0.f},
        {crR * ac, crG * ac, 0.f, 0.f},
        {by + crR * bc, by + (cbG + crG) * bc, by + cbB * bc, 1.f},
    }};
}

@implementation CINInputFrame
- (instancetype)init {
    if ((self = [super init])) {
        _ycbcrToRgb = matrix_identity_float4x4;
        _texMatrix = CINMat4Identity();
    }
    return self;
}
@end

#pragma mark - 帧缓冲

/** 一条模糊金字塔（光晕或柔光各一条）。 */
@interface CINGlowChain : NSObject
@property (nonatomic, strong) NSArray<id<MTLTexture>> *levels;
@end
@implementation CINGlowChain
@end

/** 一套完整的帧缓冲：预览用一套常驻的，拍照时临时建一套大的。 */
@interface CINFrameTargets : NSObject
@property (nonatomic, strong) id<MTLTexture> signal;   // 镜头之后的工作信号
@property (nonatomic, strong) id<MTLTexture> graded;   // 调色之后的成片
@property (nonatomic, strong) CINGlowChain *halation;
@property (nonatomic, strong) CINGlowChain *mist;
@end
@implementation CINFrameTargets
@end

@implementation CINEngine {
    id<MTLRenderPipelineState> _inputYCbCr, _inputRgba, _prefilter, _kawaseDown, _kawaseUp, _film, _present, _blit, _waveform;
    id<MTLTexture> _neutral;
    int _neutralSize;
    NSMutableDictionary<NSNumber *, id<MTLTexture>> *_looks;
    NSInteger _selectedLook;
    CINFrameTargets *_preview;
    CINRenderParams _lastParams;
    id<MTLTexture> _waveformSource, _waveformTarget, _thumbSource;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        _queue = [device newCommandQueue];
        _queue.label = @"CineGL";
        _looks = [NSMutableDictionary dictionary];
        _selectedLook = -1;
        _lastParams = CINRenderParamsDefault();
        if (![self buildPipelines]) return nil;
        // 先放一张 2³ 的单位 LUT 兜底，真正的中性 LUT 烘好之前也能出图
        const float identity[] = {0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1,
                                  0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1};
        [self uploadNeutralLut:[NSData dataWithBytes:identity length:sizeof(identity)] size:2];
    }
    return self;
}

- (BOOL)buildPipelines {
    NSError *error = nil;
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:&error];
    if (!library) {
        NSLog(@"CineGL: Metal library unavailable: %@", error);
        return NO;
    }
    id<MTLFunction> quad = [library newFunctionWithName:@"cin_quad_vertex"];
    _inputYCbCr = [self pipeline:library vertex:quad fragment:@"cin_input_ycbcr_fragment" format:kColorFormat additive:NO];
    _inputRgba = [self pipeline:library vertex:quad fragment:@"cin_input_rgba_fragment" format:kColorFormat additive:NO];
    _prefilter = [self pipeline:library vertex:quad fragment:@"cin_glow_prefilter_fragment" format:kGlowFormat additive:NO];
    _kawaseDown = [self pipeline:library vertex:quad fragment:@"cin_kawase_down_fragment" format:kGlowFormat additive:NO];
    _kawaseUp = [self pipeline:library vertex:quad fragment:@"cin_kawase_up_fragment" format:kGlowFormat additive:NO];
    _film = [self pipeline:library vertex:quad fragment:@"cin_film_fragment" format:kColorFormat additive:NO];
    _present = [self pipeline:library vertex:quad fragment:@"cin_present_fragment" format:kColorFormat additive:NO];
    _blit = [self pipeline:library vertex:quad fragment:@"cin_blit_fragment" format:kColorFormat additive:NO];
    _waveform = [self pipeline:library vertex:[library newFunctionWithName:@"cin_waveform_vertex"]
                      fragment:@"cin_waveform_fragment" format:kColorFormat additive:YES];
    const BOOL ok = _inputYCbCr && _inputRgba && _prefilter && _kawaseDown && _kawaseUp && _film && _present && _blit && _waveform;
    if (!ok) NSLog(@"CineGL: engine initialize failed");
    return ok;
}

- (id<MTLRenderPipelineState>)pipeline:(id<MTLLibrary>)library
                                vertex:(id<MTLFunction>)vertex
                              fragment:(NSString *)fragmentName
                                format:(MTLPixelFormat)format
                              additive:(BOOL)additive {
    id<MTLFunction> fragment = [library newFunctionWithName:fragmentName];
    if (!vertex || !fragment) {
        NSLog(@"CineGL: missing shader function %@", fragmentName);
        return nil;
    }
    MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
    d.label = fragmentName;
    d.vertexFunction = vertex;
    d.fragmentFunction = fragment;
    d.colorAttachments[0].pixelFormat = format;
    if (additive) {
        // 波形图：同一位置落的点越多越亮
        d.colorAttachments[0].blendingEnabled = YES;
        d.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        d.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        d.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        d.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    }
    NSError *error = nil;
    id<MTLRenderPipelineState> state = [_device newRenderPipelineStateWithDescriptor:d error:&error];
    if (!state) NSLog(@"CineGL: pipeline %@ failed: %@", fragmentName, error);
    return state;
}

#pragma mark - 纹理

- (id<MTLTexture>)makeTarget:(int)w height:(int)h format:(MTLPixelFormat)format {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                 width:(NSUInteger)MAX(1, w)
                                                                                height:(NSUInteger)MAX(1, h)
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:d];
}

- (id<MTLTexture>)makeReadableTextureWidth:(int)width height:(int)height {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:kColorFormat
                                                                                 width:(NSUInteger)MAX(1, width)
                                                                                height:(NSUInteger)MAX(1, height)
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModeShared;
    return [_device newTextureWithDescriptor:d];
}

static BOOL CINSameSize(id<MTLTexture> t, int w, int h) {
    return t && (int)t.width == w && (int)t.height == h;
}

- (CINFrameTargets *)ensureTargets:(CINFrameTargets *)t width:(int)w height:(int)h {
    if (t && CINSameSize(t.signal, w, h)) return t;
    CINFrameTargets *n = [[CINFrameTargets alloc] init];
    n.signal = [self makeTarget:w height:h format:kColorFormat];
    n.graded = [self makeTarget:w height:h format:kColorFormat];
    return n.signal && n.graded ? n : nil;
}

- (CINGlowChain *)ensureChain:(CINGlowChain *)chain plan:(CINGlowPlan)plan {
    BOOL same = chain && (int)chain.levels.count == plan.levelCount;
    for (int i = 0; same && i < plan.levelCount; ++i) same = CINSameSize(chain.levels[(NSUInteger)i], plan.levels[i].w, plan.levels[i].h);
    if (same) return chain;
    NSMutableArray *levels = [NSMutableArray array];
    for (int i = 0; i < plan.levelCount; ++i) {
        id<MTLTexture> t = [self makeTarget:plan.levels[i].w height:plan.levels[i].h format:kGlowFormat];
        if (!t) return nil;
        [levels addObject:t];
    }
    CINGlowChain *c = [[CINGlowChain alloc] init];
    c.levels = levels;
    return c;
}

- (id<MTLTexture>)upload3D:(NSData *)rgba size:(int)size {
    // float → half：33³ × 4 个数，一两毫秒
    const NSUInteger count = (NSUInteger)size * size * size * 4;
    if (rgba.length < count * sizeof(float)) return nil;
    const float *src = rgba.bytes;
    NSMutableData *half = [NSMutableData dataWithLength:count * sizeof(__fp16)];
    __fp16 *dst = half.mutableBytes;
    for (NSUInteger i = 0; i < count; ++i) dst[i] = (__fp16)src[i];

    MTLTextureDescriptor *d = [[MTLTextureDescriptor alloc] init];
    d.textureType = MTLTextureType3D;
    d.pixelFormat = MTLPixelFormatRGBA16Float;
    d.width = d.height = d.depth = (NSUInteger)size;
    d.usage = MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModeShared;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    [t replaceRegion:MTLRegionMake3D(0, 0, 0, (NSUInteger)size, (NSUInteger)size, (NSUInteger)size)
         mipmapLevel:0
               slice:0
           withBytes:half.bytes
         bytesPerRow:(NSUInteger)size * 8
       bytesPerImage:(NSUInteger)size * size * 8];
    return t;
}

#pragma mark - LUT

- (void)uploadNeutralLut:(NSData *)rgba size:(int)size {
    id<MTLTexture> t = [self upload3D:rgba size:size];
    if (!t) return;
    _neutral = t;   // 换一个新纹理对象：还在 GPU 上排队的命令缓冲拿着旧的，互不干扰
    _neutralSize = size;
}

- (void)uploadLookLut:(NSData *)rgba size:(int)size index:(NSInteger)lookIndex {
    id<MTLTexture> t = [self upload3D:rgba size:size];
    if (t) _looks[@(lookIndex)] = t;
}

- (void)clearLookLuts {
    [_looks removeAllObjects];
}

- (BOOL)hasLookLut:(NSInteger)lookIndex {
    return _looks[@(lookIndex)] != nil;
}

- (void)selectLook:(NSInteger)lookIndex {
    _selectedLook = lookIndex;
}

- (int)frameWidth {
    return _preview ? (int)_preview.signal.width : 0;
}

- (int)frameHeight {
    return _preview ? (int)_preview.signal.height : 0;
}

#pragma mark - pass

- (id<MTLRenderCommandEncoder>)beginPass:(id<MTLTexture>)target clear:(BOOL)clear commandBuffer:(id<MTLCommandBuffer>)cb {
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = clear ? MTLLoadActionClear : MTLLoadActionDontCare;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    return [cb renderCommandEncoderWithDescriptor:rp];
}

static void CINDrawQuad(id<MTLRenderCommandEncoder> enc, CINMat4 m) {
    CINQuadUniforms q = {CINMat4ToSimd(m)};
    [enc setVertexBytes:&q length:sizeof(q) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

/** 第 1 站：镜头。 */
- (BOOL)runInput:(CINInputFrame *)in width:(int)fw height:(int)fh params:(CINRenderParams)p
         targets:(CINFrameTargets *)t commandBuffer:(id<MTLCommandBuffer>)cb {
    const BOOL ycbcr = in.luma != nil && in.chroma != nil;
    if (!ycbcr && !in.rgba) return NO;
    id<MTLRenderCommandEncoder> enc = [self beginPass:t.signal clear:NO commandBuffer:cb];
    enc.label = @"input";
    [enc setRenderPipelineState:ycbcr ? _inputYCbCr : _inputRgba];
    CINInputUniforms u;
    u.texMatrix = CINMat4ToSimd(in.texMatrix);
    u.ycbcrToRgb = in.ycbcrToRgb;
    u.wbGains = p.wbGains;
    u.sourceEncoding = p.sourceEncoding;
    u.workingEncoding = p.workingEncoding;
    u.vignette = p.vignette;
    u.aberration = p.aberration;
    u.frameAspect = (float)fw / (float)fh;
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    if (ycbcr) {
        [enc setFragmentTexture:in.luma atIndex:0];
        [enc setFragmentTexture:in.chroma atIndex:1];
    } else {
        [enc setFragmentTexture:in.rgba atIndex:0];
    }
    CINDrawQuad(enc, CINMat4Identity());
    [enc endEncoding];
    return YES;
}

/** 光晕/柔光：提取高光 → Dual Kawase 降采样 → 升采样，返回 level 0 的纹理。 */
- (id<MTLTexture>)runGlow:(CINGlowChain *)chain source:(id<MTLTexture>)src encoding:(CINEncoding)encoding
                     kind:(CINGlowKind)kind commandBuffer:(id<MTLCommandBuffer>)cb {
    const CINGlowPlan gp = CINPlanGlow((int)src.width, (int)src.height, kind);
    const NSUInteger n = chain.levels.count;
    const CINMat4 identity = CINMat4Identity();

    id<MTLRenderCommandEncoder> enc = [self beginPass:chain.levels[0] clear:NO commandBuffer:cb];
    enc.label = @"glow prefilter";
    [enc setRenderPipelineState:_prefilter];
    CINPrefilterUniforms pu = {simd_make_float2(gp.tapOffsetU, gp.tapOffsetV), encoding, gp.threshold, gp.knee};
    [enc setFragmentBytes:&pu length:sizeof(pu) atIndex:0];
    [enc setFragmentTexture:src atIndex:0];
    CINDrawQuad(enc, identity);
    [enc endEncoding];

    for (NSUInteger i = 1; i < n; ++i) {
        id<MTLTexture> from = chain.levels[i - 1];
        enc = [self beginPass:chain.levels[i] clear:NO commandBuffer:cb];
        enc.label = @"kawase down";
        [enc setRenderPipelineState:_kawaseDown];
        CINKawaseUniforms ku = {simd_make_float2(0.5f / from.width, 0.5f / from.height), 1.f};
        [enc setFragmentBytes:&ku length:sizeof(ku) atIndex:0];
        [enc setFragmentTexture:from atIndex:0];
        CINDrawQuad(enc, identity);
        [enc endEncoding];
    }
    // 升采样直接写回上一级：那一级的降采样结果已经用完了，省一套显存
    for (NSUInteger i = n - 1; i-- > 0;) {
        id<MTLTexture> from = chain.levels[i + 1];
        enc = [self beginPass:chain.levels[i] clear:NO commandBuffer:cb];
        enc.label = @"kawase up";
        [enc setRenderPipelineState:_kawaseUp];
        CINKawaseUniforms ku = {simd_make_float2(0.5f / from.width, 0.5f / from.height), 1.f};
        [enc setFragmentBytes:&ku length:sizeof(ku) atIndex:0];
        [enc setFragmentTexture:from atIndex:0];
        CINDrawQuad(enc, identity);
        [enc endEncoding];
    }
    return chain.levels[0];
}

/** 第 2、3 站：胶片曝光 + 冲洗，往 enc 当前的渲染目标里画。 */
- (void)encodeFilm:(id<MTLRenderCommandEncoder>)enc
            signal:(id<MTLTexture>)signalTex
          halation:(nullable id<MTLTexture>)halationTex
              mist:(nullable id<MTLTexture>)mistTex
             width:(int)fw
            height:(int)fh
            params:(CINRenderParams)p
              seed:(uint32_t)seed
              look:(nullable id<MTLTexture>)look
          strength:(float)lookStrength
          uvMatrix:(CINMat4)uvMatrix
           effects:(BOOL)effects {
    [enc setRenderPipelineState:_film];
    [enc setFragmentTexture:signalTex atIndex:0];
    [enc setFragmentTexture:halationTex ?: signalTex atIndex:1];
    [enc setFragmentTexture:mistTex ?: signalTex atIndex:2];
    [enc setFragmentTexture:_neutral atIndex:3];
    id<MTLTexture> lut = look ?: _neutral;
    [enc setFragmentTexture:lut atIndex:4];
    CINFilmUniforms u;
    u.frameSize = simd_make_float2((float)fw, (float)fh);
    u.neutralLutSize = (float)_neutralSize;
    u.lookLutSize = (float)lut.width;
    u.lookStrength = look ? lookStrength : 0.f;
    u.workingEncoding = p.workingEncoding;
    u.halationAmount = effects && halationTex ? p.halation : 0.f;
    u.mistAmount = effects && mistTex ? p.mist : 0.f;
    u.grain = effects ? p.grain : 0.f;
    u.grainSize = CINGrainSizePixels(p.grainSize, fw, fh);
    u.seed = (float)(seed % 65536u);
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    CINDrawQuad(enc, uvMatrix);
}

- (BOOL)runPipeline:(CINInputFrame *)in width:(int)fw height:(int)fh params:(CINRenderParams)p seed:(uint32_t)seed
            targets:(CINFrameTargets *)t commandBuffer:(id<MTLCommandBuffer>)cb {
    if (![self runInput:in width:fw height:fh params:p targets:t commandBuffer:cb]) return NO;

    id<MTLTexture> halationTex = nil, mistTex = nil;
    if (p.halation > 0.f) {
        t.halation = [self ensureChain:t.halation plan:CINPlanGlow(fw, fh, CINGlowKindHalation)];
        if (t.halation) halationTex = [self runGlow:t.halation source:t.signal encoding:p.workingEncoding kind:CINGlowKindHalation commandBuffer:cb];
    }
    if (p.mist > 0.f) {
        t.mist = [self ensureChain:t.mist plan:CINPlanGlow(fw, fh, CINGlowKindMist)];
        if (t.mist) mistTex = [self runGlow:t.mist source:t.signal encoding:p.workingEncoding kind:CINGlowKindMist commandBuffer:cb];
    }

    id<MTLRenderCommandEncoder> enc = [self beginPass:t.graded clear:NO commandBuffer:cb];
    enc.label = @"film";
    [self encodeFilm:enc signal:t.signal halation:halationTex mist:mistTex width:fw height:fh params:p seed:seed
                look:_looks[@(_selectedLook)] strength:p.lookStrength uvMatrix:CINMat4Identity() effects:YES];
    [enc endEncoding];
    return YES;
}

- (void)blit:(id<MTLTexture>)src into:(id<MTLTexture>)target matrix:(CINMat4)m commandBuffer:(id<MTLCommandBuffer>)cb {
    id<MTLRenderCommandEncoder> enc = [self beginPass:target clear:NO commandBuffer:cb];
    enc.label = @"blit";
    [enc setRenderPipelineState:_blit];
    [enc setFragmentTexture:src atIndex:0];
    CINDrawQuad(enc, m);
    [enc endEncoding];
}

/** 波形图：缩小画面 → 每个像素一个点，加法混合累加。 */
- (id<MTLTexture>)updateWaveform:(id<MTLTexture>)src commandBuffer:(id<MTLCommandBuffer>)cb {
    const CINSize s = CINWaveformSourceSize((int)src.width, (int)src.height);
    if (!CINSameSize(_waveformSource, s.w, s.h)) _waveformSource = [self makeTarget:s.w height:s.h format:kColorFormat];
    if (!_waveformTarget) _waveformTarget = [self makeTarget:kCINWaveformTarget.w height:kCINWaveformTarget.h format:kColorFormat];
    if (!_waveformSource || !_waveformTarget) return nil;
    [self blit:src into:_waveformSource matrix:CINMat4Identity() commandBuffer:cb];

    id<MTLRenderCommandEncoder> enc = [self beginPass:_waveformTarget clear:YES commandBuffer:cb];
    enc.label = @"waveform";
    [enc setRenderPipelineState:_waveform];
    // 每列有 s.h 个点落在 128 行里，单点贡献要小，靠叠加变亮
    CINWaveformUniforms u = {simd_make_float3(0.035f, 0.07f, 0.045f), simd_make_int2(s.w, s.h)};
    [enc setVertexBytes:&u length:sizeof(u) atIndex:0];
    [enc setVertexTexture:_waveformSource atIndex:0];
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:(NSUInteger)(s.w * s.h)];
    [enc endEncoding];
    return _waveformTarget;
}

#pragma mark - 每帧

- (BOOL)renderFrame:(CINInputFrame *)input frameWidth:(int)frameW frameHeight:(int)frameH params:(CINRenderParams)p
         frameIndex:(uint32_t)frameIndex commandBuffer:(id<MTLCommandBuffer>)cb {
    if (frameW <= 0 || frameH <= 0) return NO;
    CINFrameTargets *t = [self ensureTargets:_preview width:frameW height:frameH];
    if (!t) return NO;
    _preview = t;
    _lastParams = p;
    return [self runPipeline:input width:frameW height:frameH params:p seed:frameIndex targets:t commandBuffer:cb];
}

- (void)presentTo:(id<MTLTexture>)target present:(CINPresentParams)pp params:(CINRenderParams)p time:(float)timeSeconds
    commandBuffer:(id<MTLCommandBuffer>)cb {
    if (!_preview) {
        [[self beginPass:target clear:YES commandBuffer:cb] endEncoding];
        return;
    }
    id<MTLTexture> src = p.showSignal ? _preview.signal : _preview.graded;
    id<MTLTexture> wave = p.waveform ? [self updateWaveform:src commandBuffer:cb] : nil;

    // 视口：UI 给的是左上原点，Metal 的视口也是左上原点，四舍五入到整像素
    const double x = floor(pp.frameRect.x + 0.5), y = floor(pp.frameRect.y + 0.5);
    const double w = fmin(floor(pp.frameRect.w + 0.5), (double)target.width - x);
    const double h = fmin(floor(pp.frameRect.h + 0.5), (double)target.height - y);
    id<MTLRenderCommandEncoder> enc = [self beginPass:target clear:YES commandBuffer:cb];
    enc.label = @"present";
    if (w > 0 && h > 0) {
        [enc setViewport:(MTLViewport){x, y, w, h, 0.0, 1.0}];
        [enc setRenderPipelineState:_present];
        [enc setFragmentTexture:src atIndex:0];
        [enc setFragmentTexture:wave ?: src atIndex:1];
        CINPresentUniforms u;
        u.waveformRect = wave ? CINWaveformRect((float)w, (float)h, pp.overlayTopInset) : simd_make_float4(0.f, 0.f, 0.f, 0.f);
        u.texel = simd_make_float2(1.f / src.width, 1.f / src.height);
        u.viewport = simd_make_float2((float)w, (float)h);
        u.cornerRadius = pp.cornerRadius;
        u.zebra = p.zebra ? 1 : 0;
        u.zebraThreshold = p.zebraThreshold;
        u.peaking = p.peaking ? 1 : 0;
        u.time = timeSeconds;
        [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
        CINDrawQuad(enc, CINMat4Identity());
    }
    [enc endEncoding];
}

- (void)drawPlane:(CINPlane)plane matrix:(CINMat4)uvMatrix to:(id<MTLTexture>)target commandBuffer:(id<MTLCommandBuffer>)cb {
    if (!_preview) return;
    [self blit:plane == CINPlaneSignal ? _preview.signal : _preview.graded into:target matrix:uvMatrix commandBuffer:cb];
}

- (id<MTLTexture>)renderThumbnails:(NSArray<NSNumber *> *)lookIndices thumbWidth:(int)thumbW thumbHeight:(int)thumbH
                           columns:(int)columns commandBuffer:(id<MTLCommandBuffer>)cb {
    if (!_preview || lookIndices.count == 0) return nil;
    const CINSize atlasSize = CINThumbnailAtlasSize((int)lookIndices.count, thumbW, thumbH, columns);
    if (!CINSameSize(_thumbSource, thumbW, thumbH)) _thumbSource = [self makeTarget:thumbW height:thumbH format:kColorFormat];
    // 图集每次新建：上一张可能还在等 CPU 读，别把它覆盖了
    id<MTLTexture> atlas = [self makeReadableTextureWidth:atlasSize.w height:atlasSize.h];
    if (!_thumbSource || !atlas) return nil;

    [self blit:_preview.signal into:_thumbSource matrix:CINMat4Identity() commandBuffer:cb];
    id<MTLRenderCommandEncoder> enc = [self beginPass:atlas clear:YES commandBuffer:cb];
    enc.label = @"thumbnails";
    const CINRenderParams p = _lastParams;
    for (NSUInteger i = 0; i < lookIndices.count; ++i) {
        const int col = (int)i % columns;
        const int row = (int)i / columns;
        [enc setViewport:(MTLViewport){(double)(col * thumbW), (double)(row * thumbH), (double)thumbW, (double)thumbH, 0.0, 1.0}];
        // Metal 的视口和读回都是顶行在前，不需要安卓那样的 kFlipV
        [self encodeFilm:enc signal:_thumbSource halation:nil mist:nil width:thumbW height:thumbH params:p seed:0
                    look:_looks[lookIndices[i]] strength:1.f uvMatrix:CINMat4Identity() effects:NO];
    }
    [enc endEncoding];
    return atlas;
}

#pragma mark - 离线

- (BOOL)processStill:(CINInputFrame *)input frameWidth:(int)frameW frameHeight:(int)frameH params:(CINRenderParams)p
               plane:(CINPlane)plane outMatrix:(CINMat4)outMatrix output:(id<MTLTexture>)output {
    const int maxSize = 16384;
    if (frameW > maxSize || frameH > maxSize || (int)output.width > maxSize || (int)output.height > maxSize) {
        NSLog(@"CineGL: still %dx%d exceeds max texture size %d", frameW, frameH, maxSize);
        return NO;
    }
    CINFrameTargets *t = [self ensureTargets:nil width:frameW height:frameH];
    if (!t) return NO;
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    cb.label = @"still";
    if (![self runPipeline:input width:frameW height:frameH params:p seed:7u targets:t commandBuffer:cb]) return NO;
    [self blit:plane == CINPlaneSignal ? t.signal : t.graded into:output matrix:outMatrix commandBuffer:cb];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.status != MTLCommandBufferStatusCompleted) NSLog(@"CineGL: still processing failed: %@", cb.error);
    return cb.status == MTLCommandBufferStatusCompleted;
}

@end
