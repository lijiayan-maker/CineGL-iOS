// 相机侧的纯逻辑（对应安卓 CameraMathTest.kt）：半自动曝光、一键重置、选流尺寸、变焦预设、朝向吸附、格式化、点击对焦坐标换算。
#import <XCTest/XCTest.h>

#import "CINCameraControls.h"
#import "CINMetering.h"

@interface CINCameraMathTests : XCTestCase
@end

static const int kIsoMin = 50, kIsoMax = 3200;
static const int64_t kExpMin = 100000, kExpMax = 1000000000;   // 1/10000s .. 1s

@implementation CINCameraMathTests

- (void)testManualIsoKeepsMeteredExposure {
    // 测光值：ISO 100 × 1/50s。手动把 ISO 提到 400 → 快门应该快 2 档到 1/200s
    CINCameraControls c = CINCameraControlsDefault();
    c.isoAuto = false;
    c.iso = 400;
    int iso;
    int64_t exp;
    CINResolveExposure(c, kIsoMin, kIsoMax, kExpMin, kExpMax, 100.0 * 20000000, 1.f / 3.f, &iso, &exp);
    XCTAssertEqual(iso, 400);
    XCTAssertEqual(exp, 5000000);
}

- (void)testManualShutterDerivesIsoAndAppliesEv {
    // 快门手动 1/100s，曝光补偿 +1 档（3 × 1/3）→ ISO = 100 × 2 × 2 = 400
    CINCameraControls c = CINCameraControlsDefault();
    c.shutterAuto = false;
    c.exposureNs = 10000000;
    c.evIndex = 3;
    int iso;
    int64_t exp;
    CINResolveExposure(c, kIsoMin, kIsoMax, kExpMin, kExpMax, 100.0 * 20000000, 1.f / 3.f, &iso, &exp);
    XCTAssertEqual(iso, 400);
    XCTAssertEqual(exp, 10000000);
}

- (void)testDerivedShutterIsCappedByFrameDuration {
    // 暗场景：推出来要 1/10s，但录像 30fps 时快门不能慢于 1/30s
    CINCameraControls c = CINCameraControlsDefault();
    c.isoAuto = false;
    c.iso = 100;
    int iso;
    int64_t exp;
    CINResolveExposure(c, kIsoMin, kIsoMax, kExpMin, 1000000000LL / 30, 100.0 * 100000000, 1.f / 3.f, &iso, &exp);
    XCTAssertEqual(exp, 33333333);
}

- (void)testFullyManualIgnoresMetering {
    CINCameraControls c = CINCameraControlsDefault();
    c.isoAuto = false;
    c.iso = 800;
    c.shutterAuto = false;
    c.exposureNs = 4000000;
    c.evIndex = 6;
    int iso;
    int64_t exp;
    CINResolveExposure(c, kIsoMin, kIsoMax, kExpMin, kExpMax, 1.0, 1.f / 3.f, &iso, &exp);
    XCTAssertEqual(iso, 800);
    XCTAssertEqual(exp, 4000000);
}

#pragma mark - 一键重置

- (void)testResetReturnsToAutoButKeepsFraming {
    CINCameraControls m = CINCameraControlsDefault();
    m.isoAuto = false; m.iso = 800; m.shutterAuto = false; m.exposureNs = 4000000; m.evIndex = -3;
    m.focusAuto = false; m.focusDiopters = 2.f; m.wbAuto = false; m.kelvin = 3200.f; m.tint = 0.4f;
    m.zoom = 2.f; m.torch = true; m.stabilization = true;
    XCTAssertTrue(CINCameraControlsHasManual(m));
    const CINCameraControls reset = CINCameraControlsResetToAuto(m);
    XCTAssertFalse(CINCameraControlsHasManual(reset));
    // 曝光、对焦、白平衡回到初始值；变焦、补光、防抖保留
    CINCameraControls expected = CINCameraControlsDefault();
    expected.zoom = 2.f;
    expected.torch = true;
    expected.stabilization = true;
    XCTAssertTrue(CINCameraControlsEqual(reset, expected));
}

- (void)testAnySingleManualControlEnablesReset {
    const CINCameraControls a = CINCameraControlsDefault();
    XCTAssertFalse(CINCameraControlsHasManual(a));
    CINCameraControls c = a; c.isoAuto = false; XCTAssertTrue(CINCameraControlsHasManual(c));
    c = a; c.shutterAuto = false; XCTAssertTrue(CINCameraControlsHasManual(c));
    c = a; c.evIndex = 1; XCTAssertTrue(CINCameraControlsHasManual(c));
    c = a; c.focusAuto = false; XCTAssertTrue(CINCameraControlsHasManual(c));
    c = a; c.wbAuto = false; XCTAssertTrue(CINCameraControlsHasManual(c));
    // 自动白平衡下残留的色温/色调、变焦和补光都不算手动参数
    c = a; c.kelvin = 3200.f; c.tint = 0.5f; c.zoom = 3.f; c.torch = true;
    XCTAssertFalse(CINCameraControlsHasManual(c));
}

#pragma mark - 尺寸

static const CINSize kSizes[] = {{4000, 3000}, {1920, 1080}, {1440, 1080}, {1280, 720}, {3840, 2160}, {640, 480}, {1080, 1080}};

- (void)testStreamSizePrefersExactShortSide {
    XCTAssertEqual(CINPickStreamSize(kSizes, 7, 16.f / 9.f, 1080), 1);
    XCTAssertEqual(CINPickStreamSize(kSizes, 7, 16.f / 9.f, 2160), 4);
    XCTAssertEqual(CINPickStreamSize(kSizes, 7, 4.f / 3.f, 1080), 2);
}

- (void)testStreamSizeFallsBackToLargestBelowTarget {
    const CINSize small[] = {{1280, 720}, {640, 360}};
    XCTAssertEqual(CINPickStreamSize(small, 2, 16.f / 9.f, 1080), 0);
    const CINSize none[] = {{0, 0}};
    XCTAssertEqual(CINPickStreamSize(none, 0, 16.f / 9.f, 1080), -1);
}

- (void)testPhotoSizeCapsAt13Megapixels {
    const CINSize photos[] = {{8000, 6000}, {4000, 3000}, {3264, 2448}, {1920, 1080}};
    XCTAssertEqual(CINPickPhotoSize(photos, 4), 1);
    const CINSize iphone[] = {{4032, 3024}, {8064, 6048}};
    XCTAssertEqual(CINPickPhotoSize(iphone, 2), 0);
}

- (void)testZoomPresetsStayInRange {
    XCTAssertEqualObjects(CINZoomPresets(0.6f, 10.f), (@[@0.6f, @1, @2, @3, @5]));
    XCTAssertEqualObjects(CINZoomPresets(1.f, 4.f), (@[@1, @2, @3]));
    XCTAssertEqualObjects(CINZoomPresets(1.f, 1.f), (@[@1]));
}

- (void)testOrientationSnapsWithHysteresis {
    XCTAssertEqual(CINSnapOrientation(30, 0), 0);      // 还在 0° 的回差区里
    XCTAssertEqual(CINSnapOrientation(80, 0), 90);
    XCTAssertEqual(CINSnapOrientation(130, 90), 90);   // 刚过 135° 之前不跳
    XCTAssertEqual(CINSnapOrientation(160, 90), 180);
    XCTAssertEqual(CINSnapOrientation(275, 0), 270);
    XCTAssertEqual(CINSnapOrientation(350, 270), 0);
    XCTAssertEqual(CINSnapOrientation(-1, 90), 90);    // 平放（朝向未知）保持不变
}

- (void)testFormatters {
    XCTAssertEqualObjects(CINFormatShutter(20000000), @"1/50");
    XCTAssertEqualObjects(CINFormatShutter(250000), @"1/4000");
    XCTAssertEqualObjects(CINFormatShutter(500000000), @"0.5\"");
    XCTAssertEqualObjects(CINFormatEv(0.01f), @"\u00b10");
    XCTAssertEqualObjects(CINFormatEv(2.f / 3.f), @"+0.7");
    XCTAssertEqualObjects(CINFormatEv(-1.f), @"-1.0");
    XCTAssertEqualObjects(CINFormatFocus(0.f), @"\u221e");
    XCTAssertEqualObjects(CINFormatFocus(2.f), @"0.50m");
}

#pragma mark - 点击对焦的坐标换算：必须和渲染时的旋转/镜像互为逆变换

static const CINFrameGeometry kFullFrame = {1080, 1440, 0.f, 0.f, 1.f, 1.f};

- (void)testMeteringUndoesSensorRotation {
    // 后置 90°：直立画面的左上角来自缓冲的左下角
    CGPoint p = CINFrameToBuffer(0.f, 0.f, kFullFrame, 90, NO);
    XCTAssertEqualWithAccuracy(p.x, 0.0, 1e-6);
    XCTAssertEqualWithAccuracy(p.y, 1.0, 1e-6);
    // 画面中心永远是缓冲中心
    p = CINFrameToBuffer(0.5f, 0.5f, kFullFrame, 90, NO);
    XCTAssertEqualWithAccuracy(p.x, 0.5, 1e-6);
    XCTAssertEqualWithAccuracy(p.y, 0.5, 1e-6);
}

- (void)testMeteringUndoesFrontMirror {
    // 前置 270° + 镜像：画面左上角 → 缓冲右下角（和 CINStillInputMatrix 的单测一致）
    const CGPoint p = CINFrameToBuffer(0.f, 0.f, kFullFrame, 270, YES);
    XCTAssertEqualWithAccuracy(p.x, 1.0, 1e-6);
    XCTAssertEqualWithAccuracy(p.y, 1.0, 1e-6);
}

- (void)testMeteringAccountsForAspectCrop {
    // 4:3 直立图像裁成 1:1：画面顶边对应直立图像的 1/8 处
    const CINFrameGeometry square = {1080, 1080, 0.f, 0.125f, 1.f, 0.75f};
    const CGPoint p = CINFrameToBuffer(0.5f, 0.f, square, 0, NO);
    XCTAssertEqualWithAccuracy(p.x, 0.5, 1e-6);
    XCTAssertEqualWithAccuracy(p.y, 0.125, 1e-6);
}

- (void)testMeteringMatchesStillInputMatrix {
    // 点击对焦的换算和渲染用的输入矩阵是同一套几何：画面上同一个点，两边算出同一个缓冲位置
    for (NSNumber *deg in @[@0, @90, @180, @270]) {
        for (NSNumber *front in @[@NO, @YES]) {
            const CINMat4 m = CINStillInputMatrix(deg.intValue, front.boolValue);
            float s, t;
            CINMat4Apply(m, 0.2f, 1.f - 0.3f, &s, &t);   // 画面 uv 是左下原点：图像坐标 (0.2, 0.3)
            const CGPoint p = CINFrameToBuffer(0.2f, 0.3f, kFullFrame, deg.intValue, front.boolValue);
            XCTAssertEqualWithAccuracy(p.x, s, 1e-6);
            XCTAssertEqualWithAccuracy(p.y, t, 1e-6);
        }
    }
}

@end
