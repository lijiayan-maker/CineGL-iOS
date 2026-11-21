// 录像与保存：写出来的 MP4 尺寸、旋转元数据、时长对；照片 EXIF 带上拍摄参数。
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <XCTest/XCTest.h>

#import "CINAudioCapture.h"
#import "CINFrameGeometry.h"
#import "CINMediaSaver.h"
#import "CINVideoRecorder.h"

@interface CINRecordTests : XCTestCase
@end

@implementation CINRecordTests

- (void)testPortraitVideoIsLandscapeBufferWithRotation {
    // 竖拿录 1080x1920 的画面：缓冲做成横的 1920x1080，再写 270 度... 按 CINPlanVideoOutput 的结果来
    const CINOutputPlan plan = CINPlanVideoOutput(360, 640, 0);
    XCTAssertEqual(plan.width, 640);
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"cinegl-test.mp4"]];
    NSString *error = nil;
    CINVideoRecorder *rec = [[CINVideoRecorder alloc] initWithURL:url width:plan.width height:plan.height fps:30
                                                          bitrate:[CINVideoRecorder bitrateForWidth:plan.width height:plan.height fps:30]
                                                  orientationHint:plan.orientationHint audio:NO sampleRate:0 channels:0 error:&error];
    XCTAssertNotNil(rec, @"%@", error);
    XCTAssertTrue([rec start]);
    for (int i = 0; i < 30; ++i) {
        CVPixelBufferRef pb = [rec copyEmptyVideoBuffer];
        XCTAssertTrue(pb != NULL);
        CVPixelBufferLockBaseAddress(pb, 0);
        memset(CVPixelBufferGetBaseAddress(pb), i * 8, CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb));
        CVPixelBufferUnlockBaseAddress(pb, 0);
        [rec appendVideoBuffer:pb presentationTime:CMTimeMake(1000 + i, 30)];
        CVPixelBufferRelease(pb);
        [NSThread sleepForTimeInterval:0.005];
    }
    XCTestExpectation *done = [self expectationWithDescription:@"finish"];
    __block BOOL ok = NO;
    [rec finishWithCompletion:^(BOOL success) {
        ok = success;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10];
    XCTAssertTrue(ok);

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    XCTestExpectation *loaded = [self expectationWithDescription:@"tracks"];
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *e) {
        AVAssetTrack *track = tracks.firstObject;
        XCTAssertNotNil(track);
        XCTAssertEqual(track.naturalSize.width, 640);
        XCTAssertEqual(track.naturalSize.height, 360);
        // 播放器按旋转元数据转回竖的
        const CGSize shown = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
        XCTAssertEqualWithAccuracy(fabs(shown.width), 360, 0.5);
        XCTAssertEqualWithAccuracy(CMTimeGetSeconds(track.timeRange.duration), 1.0, 0.1);
        [loaded fulfill];
    }];
    [self waitForExpectations:@[loaded] timeout:5];
    XCTAssertNotNil([CINMediaSaver thumbnailForVideo:url]);
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
}

- (void)testBitrateClamped {
    XCTAssertEqual([CINVideoRecorder bitrateForWidth:640 height:360 fps:30], 4000000);
    XCTAssertEqual([CINVideoRecorder bitrateForWidth:1920 height:1080 fps:30], 15552000);
    XCTAssertEqual([CINVideoRecorder bitrateForWidth:3840 height:2160 fps:60], 100000000);
}

- (void)testPhotoExif {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, 64, 48, 8, 0, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGContextSetRGBFillColor(ctx, 1, 0.5, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 64, 48));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    NSData *jpeg = [CINMediaSaver jpegDataForImage:image meta:(CINPhotoMeta){400, 10000000, 6.0f, 1.8f} date:[NSDate date]];
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, NULL);
    NSDictionary *props = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    NSDictionary *exif = props[(NSString *)kCGImagePropertyExifDictionary];
    XCTAssertEqualObjects([exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] firstObject], @400);
    XCTAssertEqualWithAccuracy([exif[(NSString *)kCGImagePropertyExifExposureTime] doubleValue], 0.01, 1e-6);
    XCTAssertEqualObjects(props[(NSString *)kCGImagePropertyTIFFDictionary][(NSString *)kCGImagePropertyTIFFSoftware], @"CineGL");
    XCTAssertEqualObjects(props[(NSString *)kCGImagePropertyOrientation], @1);
    UIImage *thumb = [CINMediaSaver thumbnailForImage:image];
    XCTAssertEqual(thumb.size.width, 240);
    XCTAssertEqual(thumb.size.height, 180);
    CFRelease(src);
    CGImageRelease(image);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
}

- (void)testAudioLevelScale {
    XCTAssertEqual([CINAudioCapture levelForPeak:0.f], 0.f);
    XCTAssertEqualWithAccuracy([CINAudioCapture levelForPeak:1.f], 1.0, 1e-6);
    XCTAssertEqualWithAccuracy([CINAudioCapture levelForPeak:0.001f], 0.0, 1e-4);   // -60 dB
    XCTAssertEqualWithAccuracy([CINAudioCapture levelForPeak:0.0316f], 0.5, 1e-3);  // -30 dB
}

- (void)testFileNames {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 11; c.day = 21; c.hour = 20; c.minute = 15; c.second = 30;
    NSDate *date = [NSCalendar.currentCalendar dateFromComponents:c];
    XCTAssertEqualObjects([CINMediaSaver fileNameWithExtension:@"jpg" date:date], @"CineGL_20261121_201530_000.jpg");
}

@end
