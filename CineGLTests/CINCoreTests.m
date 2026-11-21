// 渲染核心（纯 CPU 部分）的单测：和安卓版 core/tests/CoreTests.cpp 一条条对应。
#import <XCTest/XCTest.h>

#import "CINColor.h"
#import "CINCubeLut.h"
#import "CINFrameGeometry.h"
#import "CINLooks.h"
#import "CINLutBaker.h"
#import "CINPassPlan.h"

@interface CINCoreTests : XCTestCase
@end

static NSString *CINIdentityCube(int n) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"TITLE \"identity\"\n# comment\nLUT_3D_SIZE %d\n", n];
    for (int b = 0; b < n; ++b)
        for (int g = 0; g < n; ++g)
            for (int r = 0; r < n; ++r)
                [s appendFormat:@"%.6f %.6f %.6f\n", r / (float)(n - 1), g / (float)(n - 1), b / (float)(n - 1)];
    return s;
}

@implementation CINCoreTests

#pragma mark - 色彩

- (void)testCineLogKeyPoints {
    XCTAssertEqualWithAccuracy(CINCineLogEncode(0.f), 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(CINCineLogEncode(0.18f), 0.4541, 1e-3);   // 中灰
    XCTAssertEqualWithAccuracy(CINCineLogEncode(1.f), 0.7516, 1e-3);     // 100% 白
    XCTAssertEqualWithAccuracy(CINCineLogEncode(4.f), 1.0, 1e-5);        // 2 档余量的顶
    for (NSNumber *n in @[@0, @0.001, @0.05, @0.18, @0.9, @2.5, @4]) {
        const float x = n.floatValue;
        XCTAssertEqualWithAccuracy(CINCineLogDecode(CINCineLogEncode(x)), x, 1e-4 + x * 1e-5);
    }
}

- (void)testAppleLogKeyPoints {
    // Apple Log：18% 中灰约 0.488，曲线在拼接点两侧连续，编码/解码互逆
    XCTAssertEqualWithAccuracy(CINAppleLogEncode(0.18f), 0.4884, 2e-3);
    XCTAssertEqualWithAccuracy(CINAppleLogEncode(0.0099999f), CINAppleLogEncode(0.0100001f), 1e-4);
    for (NSNumber *n in @[@0, @0.005, @0.05, @0.18, @1, @6]) {
        const float x = n.floatValue;
        XCTAssertEqualWithAccuracy(CINAppleLogDecode(CINAppleLogEncode(x)), x, 1e-4 + x * 1e-4);
    }
    // Rec.2020 → Rec.709：白还是白
    const CINVec3 white = CINRec2020ToRec709(CINVec3Make(1.f, 1.f, 1.f));
    XCTAssertEqualWithAccuracy(white.x, 1.0, 1e-3);
    XCTAssertEqualWithAccuracy(white.y, 1.0, 1e-3);
    XCTAssertEqualWithAccuracy(white.z, 1.0, 1e-3);
}

- (void)testSrgbRoundTrip {
    for (float c = 0.f; c <= 1.f; c += 0.05f) {
        XCTAssertEqualWithAccuracy(CINLinearToSrgb(CINSrgbToLinear(c)), c, 1e-5);
    }
    XCTAssertEqualWithAccuracy(CINLinearToSrgb(0.18f), 0.4614, 1e-3);
}

- (void)testHsvRoundTrip {
    const CINVec3 samples[] = {{0.9f, 0.2f, 0.1f}, {0.1f, 0.8f, 0.3f}, {0.2f, 0.3f, 0.9f}, {0.5f, 0.5f, 0.5f}};
    for (int i = 0; i < 4; ++i) {
        const CINVec3 c = samples[i];
        const CINVec3 back = CINHsvToRgb(CINRgbToHsv(c));
        XCTAssertEqualWithAccuracy(back.x, c.x, 1e-5);
        XCTAssertEqualWithAccuracy(back.y, c.y, 1e-5);
        XCTAssertEqualWithAccuracy(back.z, c.z, 1e-5);
    }
}

- (void)testWhiteBalanceGains {
    const CINVec3 neutral = CINWhiteBalanceGains(5500.f, 0.f);
    XCTAssertEqualWithAccuracy(neutral.x, 1.0, 1e-5);
    XCTAssertEqualWithAccuracy(neutral.y, 1.0, 1e-5);
    XCTAssertEqualWithAccuracy(neutral.z, 1.0, 1e-5);
    const CINVec3 tungsten = CINWhiteBalanceGains(3200.f, 0.f);   // 设成钨丝灯 → 画面变冷
    XCTAssertTrue(tungsten.z > tungsten.y && tungsten.y > tungsten.x);
    XCTAssertEqualWithAccuracy(CINLuminance(tungsten), 1.0, 1e-5);
    const CINVec3 shade = CINWhiteBalanceGains(8000.f, 0.f);       // 设成阴天 → 画面变暖
    XCTAssertTrue(shade.x > shade.z);
    const CINVec3 magenta = CINWhiteBalanceGains(5500.f, 1.f);
    XCTAssertTrue(magenta.y < magenta.x);
}

- (void)testHighlightRolloff {
    XCTAssertEqualWithAccuracy(CINHighlightRolloff(0.5f, 0.9f), 0.5, 1e-6);
    XCTAssertTrue(CINHighlightRolloff(1.f, 0.9f) < 1.f);
    XCTAssertTrue(CINHighlightRolloff(4.f, 0.9f) <= 1.f);
    XCTAssertTrue(CINHighlightRolloff(2.f, 0.9f) > CINHighlightRolloff(1.f, 0.9f));
}

#pragma mark - LUT

- (void)testSCurveFixesEndpointsAndPivot {
    XCTAssertEqualWithAccuracy(CINLutSCurve(0.f, 1.3f, 0.43f), 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(CINLutSCurve(1.f, 1.3f, 0.43f), 1.0, 1e-6);
    XCTAssertEqualWithAccuracy(CINLutSCurve(0.43f, 1.3f, 0.43f), 0.43, 1e-4);
    XCTAssertTrue(CINLutSCurve(0.2f, 1.3f, 0.43f) < 0.2f);   // 暗部更暗
    XCTAssertTrue(CINLutSCurve(0.8f, 1.3f, 0.43f) > 0.8f);   // 亮部更亮
    XCTAssertEqualWithAccuracy(CINLutSCurve(0.3f, 1.f, 0.43f), 0.3, 1e-6);
}

- (void)testNeutralRec709IsIdentity {
    const int n = 9;
    NSData *data = CINLutBakeNeutral(CINEncodingRec709, n);
    XCTAssertEqual(data.length, (NSUInteger)(n * n * n * 4) * sizeof(float));
    const float *d = data.bytes;
    double maxErr = 0.0;
    for (int b = 0; b < n; ++b)
        for (int g = 0; g < n; ++g)
            for (int r = 0; r < n; ++r) {
                const size_t i = (size_t)(((b * n + g) * n + r) * 4);
                maxErr = fmax(maxErr, fabs(d[i] - r / (float)(n - 1)));
                maxErr = fmax(maxErr, fabs(d[i + 1] - g / (float)(n - 1)));
                maxErr = fmax(maxErr, fabs(d[i + 2] - b / (float)(n - 1)));
            }
    XCTAssertLessThan(maxErr, 1e-4);
}

- (void)testNeutralLogDecodesToDisplay {
    // Log 信号里的中灰，经中性 LUT 应该还原成 sRGB 的中灰
    const float grey = CINCineLogEncode(0.18f);
    const CINVec3 out = CINLutEvaluateNeutral(CINEncodingCineLog, (CINVec3)grey);
    XCTAssertEqualWithAccuracy(out.x, CINLinearToSrgb(0.18f), 1e-3);
    // Log 的 100% 白被肩部压到略低于 1
    const CINVec3 white = CINLutEvaluateNeutral(CINEncodingCineLog, (CINVec3)CINCineLogEncode(1.f));
    XCTAssertTrue(white.x > 0.97f && white.x < 1.f);
}

- (void)testNaturalLookEqualsNeutral {
    CINLookLibrary *lib = CINLookLibrary.shared;
    CINLook *natural = [lib lookAtIndex:[lib indexOfId:@"natural"]];
    XCTAssertNotNil(natural);
    for (NSNumber *n in @[@0, @0.1, @0.35, @0.6, @0.95]) {
        const float v = n.floatValue;
        const CINVec3 s = CINVec3Make(v, 1.f - v, v * 0.5f);
        for (int e = CINEncodingRec709; e <= CINEncodingCineLog; ++e) {
            const CINVec3 a = CINLutEvaluate(natural, (CINEncoding)e, s);
            const CINVec3 b = CINLutEvaluateNeutral((CINEncoding)e, s);
            XCTAssertEqualWithAccuracy(a.x, b.x, 1e-5);
            XCTAssertEqualWithAccuracy(a.y, b.y, 1e-5);
            XCTAssertEqualWithAccuracy(a.z, b.z, 1e-5);
        }
    }
}

- (void)testAllBuiltInLooksBakeCleanly {
    CINLookLibrary *lib = CINLookLibrary.shared;
    XCTAssertGreaterThanOrEqual(lib.count, 10);
    for (NSInteger i = 0; i < lib.count; ++i) {
        CINLook *look = [lib lookAtIndex:i];
        XCTAssertNotNil(look);
        for (int e = CINEncodingRec709; e <= CINEncodingCineLog; ++e) {
            NSData *data = CINLutBake(look, (CINEncoding)e, 9);
            const float *d = data.bytes;
            BOOL clean = YES;
            for (NSUInteger k = 0; k < data.length / sizeof(float); ++k) clean = clean && isfinite(d[k]) && d[k] >= 0.f && d[k] <= 1.f;
            XCTAssertTrue(clean, @"look %@ produced out-of-range values", look.lookId);
        }
    }
}

- (void)testBuiltInLooksMatchAndroid {
    // 和安卓版同一套内置影调：11 个，顺序、id、名字一致
    NSArray *ids = @[@"natural", @"teal_orange", @"warm_film", @"nordic", @"matte", @"silver", @"neon", @"forest",
                     @"golden_hour", @"bleach", @"chrome"];
    CINLookLibrary *lib = CINLookLibrary.shared;
    for (NSUInteger i = 0; i < ids.count; ++i) {
        XCTAssertEqualObjects([lib lookAtIndex:(NSInteger)i].lookId, ids[i]);
    }
    XCTAssertEqualObjects([lib lookAtIndex:1].nameEn, @"Teal & Orange");
    XCTAssertEqualObjects([lib lookAtIndex:1].name, @"青橙");
}

- (void)testSilverLookIsMonochrome {
    CINLookLibrary *lib = CINLookLibrary.shared;
    CINLook *silver = [lib lookAtIndex:[lib indexOfId:@"silver"]];
    const CINVec3 out = CINLutEvaluate(silver, CINEncodingRec709, CINVec3Make(0.8f, 0.3f, 0.1f));
    XCTAssertEqualWithAccuracy(out.x, out.y, 1e-4);
    XCTAssertEqualWithAccuracy(out.y, out.z, 1e-4);
}

#pragma mark - .cube

- (void)testCubeParseAndSample {
    CINCubeParseError err;
    CINCubeLut *cube = [CINCubeLut parseText:CINIdentityCube(5) error:&err];
    XCTAssertNotNil(cube);
    XCTAssertEqual(err.code, CINCubeErrorNone);
    XCTAssertEqual(cube.size, 5);
    XCTAssertEqualObjects(cube.title, @"identity");
    const CINVec3 s = [cube sample:CINVec3Make(0.3f, 0.62f, 0.91f)];
    XCTAssertEqualWithAccuracy(s.x, 0.3, 1e-5);
    XCTAssertEqualWithAccuracy(s.y, 0.62, 1e-5);
    XCTAssertEqualWithAccuracy(s.z, 0.91, 1e-5);
}

- (void)testCubeHandlesCrlfAndTrailingText {
    NSString *text = @"LUT_3D_SIZE 2\r\n0 0 0\r\n1 0 0\r\n0 1 0\r\n1 1 0\r\n0 0 1\r\n1 0 1\r\n0 1 1\r\n1 1 1";
    CINCubeParseError err;
    XCTAssertNotNil([CINCubeLut parseText:text error:&err]);
    XCTAssertEqual(err.code, CINCubeErrorNone);
}

- (void)testCubeLookWithoutTitleLeavesEnglishNameEmpty {
    NSString *text = CINIdentityCube(2);
    text = [text substringFromIndex:[text rangeOfString:@"\n"].location + 1];   // 去掉 TITLE 行
    CINCubeParseError err;
    CINCubeLut *cube = [CINCubeLut parseText:text error:&err];
    XCTAssertNotNil(cube);
    const NSInteger index = [CINLookLibrary.shared addCubeWithId:@"test_untitled" name:@"untitled" cube:cube];
    CINLook *look = [CINLookLibrary.shared lookAtIndex:index];
    XCTAssertEqual(look.nameEn.length, 0u);   // 由界面按系统语言显示「导入的 LUT / Imported LUT」
}

// 失败时给出错误码和定位数字（界面按系统语言把它们拼成文案）
- (void)testCubeRejectsBadInput {
    CINCubeParseError err;
    XCTAssertNil([CINCubeLut parseText:@"LUT_1D_SIZE 16\n" error:&err]);
    XCTAssertEqual(err.code, CINCubeErrorUnsupported1D);
    XCTAssertNil([CINCubeLut parseText:@"LUT_3D_SIZE 300\n" error:&err]);
    XCTAssertEqual(err.code, CINCubeErrorSizeOutOfRange);
    XCTAssertNil([CINCubeLut parseText:@"LUT_3D_SIZE 2\n0 0 0\n1 1 1\n" error:&err]);   // 数量不够
    XCTAssertTrue(err.code == CINCubeErrorCountMismatch && err.count == 2 && err.expected == 8);
    XCTAssertNil([CINCubeLut parseText:@"0 0 0\n" error:&err]);                          // 数据在尺寸之前
    XCTAssertTrue(err.code == CINCubeErrorDataBeforeSize && err.line == 1);
    XCTAssertNil([CINCubeLut parseText:@"TITLE \"x\"\n# only comments\n" error:&err]);   // 整个文件没有尺寸
    XCTAssertEqual(err.code, CINCubeErrorMissingSize);
    XCTAssertNil([CINCubeLut parseText:@"LUT_3D_SIZE 2\n0 0 zero\n" error:&err]);
    XCTAssertTrue(err.code == CINCubeErrorBadData && err.line == 2);
    XCTAssertEqualObjects(CINCubeParseErrorDescribe(err), @"line 2: expected 3 numbers");
    XCTAssertNil([CINCubeLut parseText:@"DOMAIN_MIN 0 0\nLUT_3D_SIZE 2\n" error:&err]);
    XCTAssertTrue(err.code == CINCubeErrorBadDomain && err.line == 1);
    NSString *reversed = [@"DOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n" stringByAppendingString:CINIdentityCube(2)];
    XCTAssertNil([CINCubeLut parseText:reversed error:&err]);
    XCTAssertEqual(err.code, CINCubeErrorDomainOrder);
}

- (void)testCubeLookBakeOrderAndLogInput {
    CINCubeParseError err;
    CINCubeLut *cube = [CINCubeLut parseText:CINIdentityCube(3) error:&err];
    const NSInteger index = [CINLookLibrary.shared addCubeWithId:@"test_identity" name:@"test" cube:cube];
    CINLook *look = [CINLookLibrary.shared lookAtIndex:index];
    XCTAssertTrue(look.isCube);
    XCTAssertEqualObjects(look.nameEn, @"identity");   // 英文名取 .cube 里的 TITLE
    // 709 信号 + 单位 .cube = 单位 LUT，顺带验证内存顺序（R 最快）
    const int n = 5;
    NSData *data = CINLutBake(look, CINEncodingRec709, n);
    const float *d = data.bytes;
    const size_t i = (size_t)(((3 * n + 1) * n + 2) * 4);   // r=2, g=1, b=3
    XCTAssertEqualWithAccuracy(d[i], 0.5, 1e-4);
    XCTAssertEqualWithAccuracy(d[i + 1], 0.25, 1e-4);
    XCTAssertEqualWithAccuracy(d[i + 2], 0.75, 1e-4);
    // Log 信号会先被转成 709 再喂给 .cube
    const CINVec3 out = CINLutEvaluate(look, CINEncodingCineLog, (CINVec3)CINCineLogEncode(0.18f));
    XCTAssertEqualWithAccuracy(out.y, CINLinearToSrgb(0.18f), 2e-3);
}

#pragma mark - 几何

- (void)testComputeFrameCrops {
    // 1920x1080 的传感器流，装成 90 度 → 直立 1080x1920
    CINFrameGeometry g = CINComputeFrame(1920, 1080, 90, CINAspectRatio16x9, kCINFrameAlign);
    XCTAssertTrue(g.frameWidth == 1080 && g.frameHeight == 1920);
    XCTAssertEqualWithAccuracy(g.cropW, 1.0, 1e-6);
    g = CINComputeFrame(1920, 1080, 90, CINAspectRatio4x3, kCINFrameAlign);
    XCTAssertTrue(g.frameWidth == 1080 && g.frameHeight == 1440);
    XCTAssertEqualWithAccuracy(g.cropH, 0.75, 1e-6);
    XCTAssertEqualWithAccuracy(g.cropY, 0.125, 1e-6);
    g = CINComputeFrame(1920, 1080, 90, CINAspectRatio239x1, kCINFrameAlign);
    XCTAssertTrue(g.frameWidth == 800 && g.frameHeight == 1920);
    g = CINComputeFrame(1440, 1080, 270, CINAspectRatio1x1, kCINFrameAlign);
    XCTAssertTrue(g.frameWidth == 1080 && g.frameHeight == 1080);
    g = CINComputeFrame(1440, 1080, 90, CINAspectRatio4x3, kCINFrameAlign);   // 4:3 流 + 4:3 画幅 = 全幅
    XCTAssertTrue(g.frameWidth == 1080 && g.frameHeight == 1440);
}

- (void)testCropMatrixMapsCorners {
    const CINFrameGeometry g = CINComputeFrame(1920, 1080, 90, CINAspectRatio4x3, kCINFrameAlign);
    const CINMat4 m = CINCropMatrix(g);
    float u, v;
    CINMat4Apply(m, 0.f, 0.f, &u, &v);
    XCTAssertEqualWithAccuracy(u, 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(v, 0.125, 1e-6);
    CINMat4Apply(m, 1.f, 1.f, &u, &v);
    XCTAssertEqualWithAccuracy(u, 1.0, 1e-6);
    XCTAssertEqualWithAccuracy(v, 0.875, 1e-6);
}

- (void)testMatrixMultiplyComposes {
    const CINMat4 a = CINMat4Affine(0.1f, 0.2f, 0.6f, 0.2f, 0.1f, 0.9f);
    const CINMat4 b = CINMat4Affine(0.f, 1.f, 1.f, 1.f, 0.f, 0.f);
    const CINMat4 ab = CINMat4Multiply(a, b);
    float u1, v1, u2, v2;
    CINMat4Apply(b, 0.3f, 0.7f, &u1, &v1);
    CINMat4Apply(a, u1, v1, &u1, &v1);
    CINMat4Apply(ab, 0.3f, 0.7f, &u2, &v2);
    XCTAssertEqualWithAccuracy(u1, u2, 1e-6);
    XCTAssertEqualWithAccuracy(v1, v2, 1e-6);
    // simd 版本和 CINMat4 的列主序一致
    const simd_float4 p = simd_mul(CINMat4ToSimd(ab), simd_make_float4(0.3f, 0.7f, 0.f, 1.f));
    XCTAssertEqualWithAccuracy(p.x, u2, 1e-6);
    XCTAssertEqualWithAccuracy(p.y, v2, 1e-6);
}

- (void)testStillInputMatrixRotates {
    // 后置 90 度：直立画面的左上角，来自传感器缓冲的左下角（s=0, t=1）
    const CINMat4 m = CINStillInputMatrix(90, false);
    float s, t;
    CINMat4Apply(m, 0.f, 1.f, &s, &t);
    XCTAssertEqualWithAccuracy(s, 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(t, 1.0, 1e-6);
    // 直立画面右上角 → 缓冲左上角
    CINMat4Apply(m, 1.f, 1.f, &s, &t);
    XCTAssertEqualWithAccuracy(s, 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(t, 0.0, 1e-6);
    // 前置 270 度 + 镜像：直立（镜像）画面左上角 → 缓冲右下角
    const CINMat4 f = CINStillInputMatrix(270, true);
    CINMat4Apply(f, 0.f, 1.f, &s, &t);
    XCTAssertEqualWithAccuracy(s, 1.0, 1e-6);
    XCTAssertEqualWithAccuracy(t, 1.0, 1e-6);
}

- (void)testOutputMatrixRotation {
    // 输出 = 画面顺时针转 90：输出左下角显示的是画面右下角（uv = (1, 0)）
    const CINMat4 m = CINOutputMatrix(90, false, false);
    float u, v;
    CINMat4Apply(m, 0.f, 0.f, &u, &v);
    XCTAssertEqualWithAccuracy(u, 1.0, 1e-6);
    XCTAssertEqualWithAccuracy(v, 0.0, 1e-6);
    // 不转 + flipY：输出第 0 行放画面顶行
    const CINMat4 f = CINOutputMatrix(0, false, true);
    CINMat4Apply(f, 0.3f, 0.f, &u, &v);
    XCTAssertEqualWithAccuracy(u, 0.3, 1e-6);
    XCTAssertEqualWithAccuracy(v, 1.0, 1e-6);
    // 去镜像：左右互换
    const CINMat4 mm = CINOutputMatrix(0, true, false);
    CINMat4Apply(mm, 0.2f, 0.4f, &u, &v);
    XCTAssertEqualWithAccuracy(u, 0.8, 1e-6);
    XCTAssertEqualWithAccuracy(v, 0.4, 1e-6);
}

- (void)testVideoAndPhotoPlans {
    CINOutputPlan p = CINPlanVideoOutput(1080, 1920, 0);   // 竖拿
    XCTAssertTrue(p.width == 1920 && p.height == 1080);
    XCTAssertTrue(p.rotationCw == 90 && p.orientationHint == 270);
    p = CINPlanVideoOutput(1080, 1920, 270);               // 右侧朝上（逆时针横拿）
    XCTAssertTrue(p.rotationCw == 90 && p.orientationHint == 0);
    p = CINPlanVideoOutput(1080, 1920, 90);                // 左侧朝上
    XCTAssertTrue(p.rotationCw == 270 && p.orientationHint == 0);
    p = CINPlanVideoOutput(1080, 1920, 180);               // 倒拿
    XCTAssertTrue(p.rotationCw == 90 && p.orientationHint == 90);
    p = CINPlanPhotoOutput(1080, 1440, 0);
    XCTAssertTrue(p.rotationCw == 0 && p.width == 1080 && p.height == 1440);
    p = CINPlanPhotoOutput(1080, 1440, 90);
    XCTAssertTrue(p.rotationCw == 270 && p.width == 1440 && p.height == 1080);
    XCTAssertEqual(CINUprightRotation(359), 0);
    XCTAssertEqual(CINUprightRotation(80), 270);
}

- (void)testFitCenterLetterboxes {
    const CINRectF r = CINFitCenter(1080.f, 1920.f, 1000.f, 1000.f);
    XCTAssertEqualWithAccuracy(r.h, 1000.0, 1e-3);
    XCTAssertEqualWithAccuracy(r.w, 562.5, 1e-3);
    XCTAssertEqualWithAccuracy(r.x, 218.75, 1e-3);
    XCTAssertEqualWithAccuracy(r.y, 0.0, 1e-3);
}

#pragma mark - pass 规划

- (void)testGlowPlanIsResolutionIndependent {
    const CINGlowPlan preview = CINPlanGlow(1080, 1920, CINGlowKindHalation);
    const CINGlowPlan still = CINPlanGlow(3000, 4000, CINGlowKindHalation);
    XCTAssertTrue(preview.levelCount == 4 && still.levelCount == 4);
    XCTAssertTrue(preview.levels[0].w == 540 && preview.levels[0].h == 960);
    XCTAssertTrue(still.levels[0].w == 540 && still.levels[0].h == 720);
    const CINGlowPlan mist = CINPlanGlow(1080, 1920, CINGlowKindMist);
    XCTAssertEqual(mist.levelCount, 6);
    XCTAssertEqual(mist.levels[mist.levelCount - 1].w, 16);
    XCTAssertEqualWithAccuracy(CINGrainSizePixels(0.f, 3000, 4000) / CINGrainSizePixels(0.f, 1080, 1920), 3000.0 / 1080.0, 1e-4);
}

- (void)testWaveformAndThumbnailPlans {
    const CINSize s = CINWaveformSourceSize(1080, 1920);
    XCTAssertTrue(s.w == 192 && s.h == 256);
    const simd_float4 r = CINWaveformRect(1000.f, 1800.f, 0.f);
    XCTAssertTrue(r.z > r.x && r.w > r.y && r.z <= 1.f && r.w <= 1.f);
    const simd_float4 inset = CINWaveformRect(1000.f, 1800.f, 120.f);   // 给角标留 120px
    XCTAssertEqualWithAccuracy(r.w - inset.w, 120.0 / 1800.0, 1e-6);
    XCTAssertEqualWithAccuracy(inset.w - inset.y, r.w - r.y, 1e-6);
    const CINSize atlas = CINThumbnailAtlasSize(11, 120, 160, 4);
    XCTAssertTrue(atlas.w == 480 && atlas.h == 480);
}

@end
