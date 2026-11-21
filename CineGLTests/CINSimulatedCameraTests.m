// 虚拟相机：在模拟器上出帧、曝光参数真的改变亮度、能拍照。
#import <XCTest/XCTest.h>

#import "CINSimulatedCamera.h"

@interface CINSimulatedCameraTests : XCTestCase <CINCameraSourceDelegate>
@property (nonatomic) XCTestExpectation *frameExpectation;
@property (nonatomic) int frames;
@property (nonatomic) double lastLuma;
@property (nonatomic) CINReadout readout;
@end

@implementation CINSimulatedCameraTests

- (void)cameraSource:(id<CINCameraSource>)source didOutputPixelBuffer:(CVPixelBufferRef)pb time:(CMTime)time {
    // 中心一行的平均亮度（BGRA）
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb);
    const uint8_t *row = (const uint8_t *)CVPixelBufferGetBaseAddress(pb) + bpr * (h / 2);
    double sum = 0;
    for (size_t x = 0; x < w; ++x) sum += row[x * 4 + 1];
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    self.lastLuma = sum / w;
    self.frames++;
    if (self.frames >= 3) {
        [self.frameExpectation fulfill];
        self.frameExpectation = nil;
    }
}

- (void)cameraSource:(id<CINCameraSource>)source didUpdateReadout:(CINReadout)readout {
    self.readout = readout;
}

- (void)cameraSource:(id<CINCameraSource>)source didFailWithMessage:(NSString *)message {
    XCTFail(@"%@", message);
}

- (double)lumaWithControls:(CINCameraControls)c camera:(CINSimulatedCamera *)cam {
    [cam updateControls:c];
    self.frames = 0;
    self.frameExpectation = [self expectationWithDescription:@"frames"];
    [self waitForExpectations:@[self.frameExpectation] timeout:3];
    return self.lastLuma;
}

- (void)testFramesExposureAndStill {
    CINSimulatedCamera *cam = [[CINSimulatedCamera alloc] init];
    cam.delegate = self;
    CINSessionConfig *config = [[CINSessionConfig alloc] init];
    config.video = NO;
    config.streamAspect = 4.f / 3.f;
    config.targetShort = 1440;
    config.fps = 30;
    config.controls = CINCameraControlsDefault();
    XCTestExpectation *started = [self expectationWithDescription:@"started"];
    __block CINSessionInfo *info = nil;
    [cam startWithConfig:config frameQueue:dispatch_queue_create("frames", DISPATCH_QUEUE_SERIAL)
              completion:^(CINSessionInfo *i, NSString *error) {
        info = i;
        [started fulfill];
    }];
    [self waitForExpectations:@[started] timeout:5];
    XCTAssertEqual(info.bufferWidth, 1920);
    XCTAssertEqual(info.bufferHeight, 1440);
    XCTAssertEqual(info.caps.sensorOrientation, 90);
    XCTAssertTrue(info.caps.manualFocus);

    const double normal = [self lumaWithControls:CINCameraControlsDefault() camera:cam];
    XCTAssertEqual(self.readout.iso, 200);   // 自动曝光的读数：ISO 200
    CINCameraControls dark = CINCameraControlsDefault();
    dark.isoAuto = false;
    dark.iso = 50;          // 半自动：ISO 降 2 档，快门按测光补回来 → 亮度不变
    const double semiAuto = [self lumaWithControls:dark camera:cam];
    XCTAssertEqualWithAccuracy(semiAuto, normal, 3.0);
    dark.shutterAuto = false;
    dark.exposureNs = 2500000;   // 全手动：再快 2 档 → 明显变暗
    const double manual = [self lumaWithControls:dark camera:cam];
    XCTAssertLessThan(manual, normal * 0.7);

    XCTestExpectation *shot = [self expectationWithDescription:@"still"];
    [cam captureWithCompletion:^(CINStillCapture *still, NSString *error) {
        XCTAssertNil(error);
        XCTAssertEqual(CVPixelBufferGetWidth(still.pixelBuffer), 4032u);
        XCTAssertEqual(still.iso, 50);
        [shot fulfill];
    }];
    [self waitForExpectations:@[shot] timeout:5];
    XCTestExpectation *stopped = [self expectationWithDescription:@"stopped"];
    [cam stopWithCompletion:^{
        [stopped fulfill];
    }];
    [self waitForExpectations:@[stopped] timeout:2];
}

@end
