// Metal 引擎的单测：在模拟器的 GPU 上真跑一遍管线，验证着色器能编、坐标方向对、和 CPU 的色彩数学一致。
// 安卓版靠 validate_shaders.sh 离线编 GLSL；这里 .metal 在编译期就编好了，单测再验证「跑出来对不对」。
#import <XCTest/XCTest.h>

#import "CINEngine.h"
#import "CINLooks.h"
#import "CINLutBaker.h"
#import "CINPassPlan.h"

@interface CINEngineTests : XCTestCase
@property (nonatomic, strong) CINEngine *engine;
@end

typedef struct {
    uint8_t b, g, r, a;
} CINBGRA;

@implementation CINEngineTests

- (void)setUp {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        XCTSkip(@"no Metal device");
    }
    self.engine = [[CINEngine alloc] initWithDevice:device];
    XCTAssertNotNil(self.engine, @"all pipelines should compile");
}

/** 左上红、右上绿、左下蓝、右下白的四象限图。 */
- (id<MTLTexture>)quadrantTextureWidth:(int)w height:(int)h {
    id<MTLTexture> t = [self.engine makeReadableTextureWidth:w height:h];
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)(w * h) * 4];
    CINBGRA *px = data.mutableBytes;
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const BOOL left = x < w / 2, top = y < h / 2;
            CINBGRA c = {0, 0, 0, 255};
            if (left && top) c.r = 255;
            else if (!left && top) c.g = 255;
            else if (left && !top) c.b = 255;
            else c.r = c.g = c.b = 255;
            px[y * w + x] = c;
        }
    }
    [t replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)w, (NSUInteger)h) mipmapLevel:0 withBytes:data.bytes bytesPerRow:(NSUInteger)w * 4];
    return t;
}

- (CINBGRA)pixel:(id<MTLTexture>)t x:(int)x y:(int)y {
    CINBGRA c;
    [t getBytes:&c bytesPerRow:4 fromRegion:MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, 1, 1) mipmapLevel:0];
    return c;
}

- (CINRenderParams)plainParams {
    CINRenderParams p = CINRenderParamsDefault();
    p.lookStrength = 0.f;
    return p;
}

- (void)testYCbCrMatrices {
    // 全范围 8 bit BT.709：Y = 1、色度居中 → 白；Cr 拉满 → 偏红
    simd_float4x4 m = CINYCbCrToRgbMatrix(CINYCbCrMatrix709, YES, 8);
    simd_float4 white = simd_mul(m, simd_make_float4(1.f, 128.f / 255.f, 128.f / 255.f, 1.f));
    XCTAssertEqualWithAccuracy(white.x, 1.0, 1e-3);
    XCTAssertEqualWithAccuracy(white.y, 1.0, 1e-3);
    XCTAssertEqualWithAccuracy(white.z, 1.0, 1e-3);
    simd_float4 red = simd_mul(m, simd_make_float4(0.5f, 128.f / 255.f, 1.f, 1.f));
    XCTAssertTrue(red.x > red.y && red.x > red.z);
    // 视频范围 10 bit（x420，Apple Log 用它）：码值 64 是黑、940 是白
    m = CINYCbCrToRgbMatrix(CINYCbCrMatrix2020, NO, 10);
    simd_float4 black = simd_mul(m, simd_make_float4(64.f * 64.f / 65535.f, 512.f * 64.f / 65535.f, 512.f * 64.f / 65535.f, 1.f));
    XCTAssertEqualWithAccuracy(black.x, 0.0, 2e-3);
    white = simd_mul(m, simd_make_float4(940.f * 64.f / 65535.f, 512.f * 64.f / 65535.f, 512.f * 64.f / 65535.f, 1.f));
    XCTAssertEqualWithAccuracy(white.y, 1.0, 2e-3);
}

/** 传感器缓冲（横的，顺时针转 90 度才正）→ 竖直画面：缓冲左上角应该跑到画面右上角。 */
- (void)testStillRotatesSensorBufferUpright {
    const int bw = 64, bh = 48;
    CINInputFrame *in = [[CINInputFrame alloc] init];
    in.rgba = [self quadrantTextureWidth:bw height:bh];
    const CINFrameGeometry g = CINComputeFrame(bw, bh, 90, CINAspectRatio4x3, kCINFrameAlign);
    XCTAssertTrue(g.frameWidth == 48 && g.frameHeight == 64);
    in.texMatrix = CINMat4Multiply(CINStillInputMatrix(90, false), CINCropMatrix(g));
    const CINOutputPlan plan = CINPlanPhotoOutput(g.frameWidth, g.frameHeight, 0);
    id<MTLTexture> out = [self.engine makeReadableTextureWidth:plan.width height:plan.height];
    XCTAssertTrue([self.engine processStill:in frameWidth:g.frameWidth frameHeight:g.frameHeight params:[self plainParams]
                                      plane:CINPlaneGraded outMatrix:CINOutputMatrix(plan.rotationCw, false, false) output:out]);
    const CINBGRA topRight = [self pixel:out x:44 y:4];
    XCTAssertTrue(topRight.r > 240 && topRight.g < 15 && topRight.b < 15, @"buffer top-left (red) → upright top-right");
    const CINBGRA topLeft = [self pixel:out x:4 y:4];
    XCTAssertTrue(topLeft.b > 240 && topLeft.r < 15, @"buffer bottom-left (blue) → upright top-left");
    const CINBGRA bottomRight = [self pixel:out x:44 y:60];
    XCTAssertTrue(bottomRight.g > 240 && bottomRight.r < 15, @"buffer top-right (green) → upright bottom-right");
}

/** 前置：画面是镜像的，保存时再去镜像，成片和「不镜像的直立图」一致。 */
- (void)testFrontCameraUnmirrorsOutput {
    const int bw = 64, bh = 48;
    CINInputFrame *in = [[CINInputFrame alloc] init];
    in.rgba = [self quadrantTextureWidth:bw height:bh];
    const CINFrameGeometry g = CINComputeFrame(bw, bh, 90, CINAspectRatio4x3, kCINFrameAlign);
    in.texMatrix = CINMat4Multiply(CINStillInputMatrix(90, true), CINCropMatrix(g));
    id<MTLTexture> out = [self.engine makeReadableTextureWidth:g.frameWidth height:g.frameHeight];
    XCTAssertTrue([self.engine processStill:in frameWidth:g.frameWidth frameHeight:g.frameHeight params:[self plainParams]
                                      plane:CINPlaneGraded outMatrix:CINOutputMatrix(0, true, false) output:out]);
    const CINBGRA topRight = [self pixel:out x:44 y:4];
    XCTAssertTrue(topRight.r > 240 && topRight.g < 15, @"mirror + unmirror cancels out");
}

/** 开 Log：镜头 pass 编码成 CineLog，中性 LUT 再还原，整条管线（无效果）应该近似恒等。 */
- (void)testCineLogRoundTripMatchesCpu {
    [self.engine uploadNeutralLut:CINLutBakeNeutral(CINEncodingCineLog, kCINLutDefaultSize) size:kCINLutDefaultSize];
    const int w = 32, h = 32;
    id<MTLTexture> src = [self.engine makeReadableTextureWidth:w height:h];
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)(w * h) * 4];
    CINBGRA *px = data.mutableBytes;
    for (int i = 0; i < w * h; ++i) px[i] = (CINBGRA){(uint8_t)(i % 200), (uint8_t)(i / 8 % 255), 118, 255};
    [src replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)w, (NSUInteger)h) mipmapLevel:0 withBytes:data.bytes bytesPerRow:(NSUInteger)w * 4];
    CINInputFrame *in = [[CINInputFrame alloc] init];
    in.rgba = src;
    in.texMatrix = CINStillInputMatrix(0, false);
    CINRenderParams p = [self plainParams];
    p.workingEncoding = CINEncodingCineLog;
    id<MTLTexture> out = [self.engine makeReadableTextureWidth:w height:h];
    XCTAssertTrue([self.engine processStill:in frameWidth:w frameHeight:h params:p plane:CINPlaneGraded
                                  outMatrix:CINOutputMatrix(0, false, false) output:out]);
    NSMutableData *result = [NSMutableData dataWithLength:data.length];
    [out getBytes:result.mutableBytes bytesPerRow:(NSUInteger)w * 4 fromRegion:MTLRegionMake2D(0, 0, (NSUInteger)w, (NSUInteger)h) mipmapLevel:0];
    const CINBGRA *a = data.bytes, *b = result.bytes;
    int maxDiff = 0;
    for (int i = 0; i < w * h; ++i) {
        maxDiff = MAX(maxDiff, abs((int)a[i].r - (int)b[i].r));
        maxDiff = MAX(maxDiff, abs((int)a[i].g - (int)b[i].g));
        maxDiff = MAX(maxDiff, abs((int)a[i].b - (int)b[i].b));
    }
    // 8 bit 中间纹理 + 33³ LUT 插值，暗部差几个码值是正常的
    XCTAssertLessThanOrEqual(maxDiff, 6);
}

/** 预览一帧：效果全开、监看全开、缩略图，跑通不出错。 */
- (void)testPreviewFrameWithEverythingOn {
    CINLook *teal = [CINLookLibrary.shared lookAtIndex:1];
    [self.engine uploadNeutralLut:CINLutBakeNeutral(CINEncodingRec709, kCINLutDefaultSize) size:kCINLutDefaultSize];
    [self.engine uploadLookLut:CINLutBake(teal, CINEncodingRec709, kCINLutDefaultSize) size:kCINLutDefaultSize index:1];
    [self.engine selectLook:1];
    CINInputFrame *in = [[CINInputFrame alloc] init];
    in.rgba = [self quadrantTextureWidth:160 height:120];
    const CINFrameGeometry g = CINComputeFrame(160, 120, 90, CINAspectRatio16x9, kCINFrameAlign);
    in.texMatrix = CINMat4Multiply(CINStillInputMatrix(90, false), CINCropMatrix(g));
    CINRenderParams p = CINRenderParamsDefault();
    p.halation = 0.5f;
    p.mist = 0.5f;
    p.grain = 0.4f;
    p.vignette = 0.3f;
    p.aberration = 0.5f;
    p.zebra = p.peaking = p.waveform = true;
    id<MTLCommandBuffer> cb = [self.engine.queue commandBuffer];
    XCTAssertTrue([self.engine renderFrame:in frameWidth:g.frameWidth frameHeight:g.frameHeight params:p frameIndex:3 commandBuffer:cb]);
    id<MTLTexture> screen = [self.engine makeReadableTextureWidth:200 height:300];
    CINPresentParams pp = {CINFitCenter(g.frameWidth, g.frameHeight, 200, 300), 16.f, 40.f};
    [self.engine presentTo:screen present:pp params:p time:0.5f commandBuffer:cb];
    id<MTLTexture> atlas = [self.engine renderThumbnails:@[@0, @1] thumbWidth:40 thumbHeight:60 columns:4 commandBuffer:cb];
    [cb commit];
    [cb waitUntilCompleted];
    XCTAssertEqual(cb.status, MTLCommandBufferStatusCompleted);
    XCTAssertEqual(atlas.width, 160u);
    XCTAssertEqual(atlas.height, 60u);
    XCTAssertEqual(self.engine.frameWidth, g.frameWidth);
    // 圆角外是黑的
    const CINBGRA corner = [self pixel:screen x:0 y:0];
    XCTAssertTrue(corner.r == 0 && corner.g == 0 && corner.b == 0);
}

@end
