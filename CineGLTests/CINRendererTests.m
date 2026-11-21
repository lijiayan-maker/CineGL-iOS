// 渲染队列的单测：喂相机格式的缓冲，验证画面尺寸回调、缩略图回传、录像缓冲按顺序交付、拍照输出尺寸。
#import <XCTest/XCTest.h>

#import "CINRenderer.h"

static CVPixelBufferRef CINMakeBuffer(int w, int h, OSType format) CF_RETURNS_RETAINED {
    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    CVPixelBufferRef pb = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, (size_t)w, (size_t)h, format, (__bridge CFDictionaryRef)attrs, &pb);
    CVPixelBufferLockBaseAddress(pb, 0);
    if (CVPixelBufferIsPlanar(pb)) {
        for (size_t plane = 0; plane < CVPixelBufferGetPlaneCount(pb); ++plane) {
            memset(CVPixelBufferGetBaseAddressOfPlane(pb, plane), plane == 0 ? 180 : 128,
                   CVPixelBufferGetBytesPerRowOfPlane(pb, plane) * CVPixelBufferGetHeightOfPlane(pb, plane));
        }
    } else {
        memset(CVPixelBufferGetBaseAddress(pb), 150, CVPixelBufferGetBytesPerRow(pb) * (size_t)h);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

@interface CINFakeSink : NSObject <CINRenderVideoSink>
@property (nonatomic) NSMutableArray<NSNumber *> *times;
@end

@implementation CINFakeSink
- (instancetype)init {
    if ((self = [super init])) _times = [NSMutableArray array];
    return self;
}
- (CVPixelBufferRef)copyEmptyVideoBuffer {
    return CINMakeBuffer(320, 180, kCVPixelFormatType_32BGRA);
}
- (void)appendVideoBuffer:(CVPixelBufferRef)buffer presentationTime:(CMTime)time {
    @synchronized (self) {
        [self.times addObject:@(CMTimeGetSeconds(time))];
    }
}
@end

@interface CINRendererTests : XCTestCase <CINRendererDelegate>
@property (nonatomic) XCTestExpectation *sizeExpectation;
@property (nonatomic) XCTestExpectation *thumbExpectation;
@property (nonatomic) int frameWidth;
@property (nonatomic) NSDictionary *thumbs;
@end

@implementation CINRendererTests

- (void)renderer:(CINRenderer *)renderer frameSizeDidChangeWidth:(int)width height:(int)height {
    self.frameWidth = width;
    [self.sizeExpectation fulfill];
    self.sizeExpectation = nil;
}

- (void)renderer:(CINRenderer *)renderer didRenderThumbnails:(NSDictionary<NSNumber *, UIImage *> *)thumbnails {
    if (thumbnails.count < 2) return;
    self.thumbs = thumbnails;
    [self.thumbExpectation fulfill];
    self.thumbExpectation = nil;
}

- (void)testFramesThumbnailsAndRecording {
    CINRenderer *r = [[CINRenderer alloc] init];
    XCTAssertNotNil(r);
    r.delegate = self;
    self.sizeExpectation = [self expectationWithDescription:@"frame size"];
    [r configureInput:(CINRenderInputConfig){1920, 1080, 90, false, CINAspectRatio4x3}];
    [self waitForExpectations:@[self.sizeExpectation] timeout:2];
    XCTAssertEqual(self.frameWidth, 1080);

    // 等后台把 LUT 烘完，再打开缩略图
    [NSThread sleepForTimeInterval:1.0];
    [r setThumbnailsEnabled:YES];
    self.thumbExpectation = [self expectationWithDescription:@"thumbnails"];
    CINFakeSink *sink = [[CINFakeSink alloc] init];
    [r startEncoder:sink width:320 height:180 matrix:CINOutputMatrix(90, false, false) plane:CINPlaneGraded];

    CVPixelBufferRef frame = CINMakeBuffer(1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    for (int i = 0; i < 13; ++i) {
        dispatch_sync(r.queue, ^{
            [r drawPixelBuffer:frame presentationTime:CMTimeMake(i, 30)];
        });
        [NSThread sleepForTimeInterval:0.02];
    }
    CVPixelBufferRelease(frame);
    [self waitForExpectations:@[self.thumbExpectation] timeout:5];
    XCTAssertGreaterThanOrEqual(self.thumbs.count, 11u, @"all built-in looks (plus cubes other tests registered) get a thumbnail");
    UIImage *thumb = self.thumbs[@1];
    XCTAssertEqual(thumb.size.width, 132.0);
    XCTAssertEqual(thumb.size.height, 176.0);   // 132 × 1440 / 1080

    XCTestExpectation *stopped = [self expectationWithDescription:@"encoder stopped"];
    [r stopEncoder:^{
        [stopped fulfill];
    }];
    [self waitForExpectations:@[stopped] timeout:5];
    // 录像帧按相机时间戳的顺序交付（丢帧可以，乱序不行）
    XCTAssertGreaterThan(sink.times.count, 0u);
    for (NSUInteger i = 1; i < sink.times.count; ++i) XCTAssertGreaterThan(sink.times[i].doubleValue, sink.times[i - 1].doubleValue);
}

- (void)testStillOutputIsUpright {
    CINRenderer *r = [[CINRenderer alloc] init];
    CINStillRequest *req = [[CINStillRequest alloc] init];
    CVPixelBufferRef pb = CINMakeBuffer(800, 600, kCVPixelFormatType_32BGRA);
    req.pixelBuffer = pb;
    CVPixelBufferRelease(pb);
    req.sensorOrientation = 90;
    req.aspect = CINAspectRatio1x1;
    req.deviceRotation = 0;
    req.plane = CINPlaneGraded;
    req.params = CINRenderParamsDefault();
    XCTestExpectation *done = [self expectationWithDescription:@"still"];
    __block size_t w = 0, h = 0;
    [r processStill:req completion:^(CGImageRef image) {
        w = CGImageGetWidth(image);
        h = CGImageGetHeight(image);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqual(w, 600u);
    XCTAssertEqual(h, 600u);
}

@end
