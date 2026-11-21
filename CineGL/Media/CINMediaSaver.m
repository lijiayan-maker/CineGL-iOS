#import "CINMediaSaver.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/utsname.h>

#import "CINLocalization.h"

@implementation CINMediaSaver

+ (NSString *)fileNameWithExtension:(NSString *)ext date:(NSDate *)date {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyyMMdd_HHmmss_SSS";
    return [NSString stringWithFormat:@"CineGL_%@.%@", [f stringFromDate:date], ext];
}

+ (NSURL *)newVideoURL {
    NSString *name = [self fileNameWithExtension:@"mp4" date:[NSDate date]];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

/** 缓存目录里只留最近一次拍摄。 */
+ (NSURL *)lastCaptureDirectory {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [caches URLByAppendingPathComponent:@"LastCapture" isDirectory:YES];
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

/** 机型标识（如 iPhone17,3），写进 EXIF 的 Model。 */
static NSString *CINMachine(void) {
    NSString *sim = NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"];
    if (sim.length) return sim;
    struct utsname u;
    uname(&u);
    return [NSString stringWithUTF8String:u.machine] ?: @"iPhone";
}

+ (NSData *)jpegDataForImage:(CGImageRef)image meta:(CINPhotoMeta)meta date:(NSDate *)date {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy:MM:dd HH:mm:ss";
    NSString *now = [f stringFromDate:date];
    NSMutableDictionary *exif = [NSMutableDictionary dictionary];
    exif[(NSString *)kCGImagePropertyExifDateTimeOriginal] = now;
    exif[(NSString *)kCGImagePropertyExifDateTimeDigitized] = now;
    if (meta.iso > 0) exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] = @[@(meta.iso)];
    if (meta.exposureNs > 0) exif[(NSString *)kCGImagePropertyExifExposureTime] = @(meta.exposureNs / 1e9);
    if (meta.focalLength > 0) exif[(NSString *)kCGImagePropertyExifFocalLength] = @(meta.focalLength);
    if (meta.aperture > 0) exif[(NSString *)kCGImagePropertyExifFNumber] = @(meta.aperture);
    NSDictionary *properties = @{
        (NSString *)kCGImageDestinationLossyCompressionQuality: @0.95,
        (NSString *)kCGImagePropertyOrientation: @1,   // 像素已经转正，不靠 EXIF 方向
        (NSString *)kCGImagePropertyExifDictionary: exif,
        (NSString *)kCGImagePropertyTIFFDictionary: @{
            (NSString *)kCGImagePropertyTIFFMake: @"Apple",
            (NSString *)kCGImagePropertyTIFFModel: CINMachine(),
            (NSString *)kCGImagePropertyTIFFSoftware: @"CineGL",
            (NSString *)kCGImagePropertyTIFFDateTime: now,
        },
    };
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
                                                                  (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
    if (!dest) return nil;
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)properties);
    const bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    return ok ? data : nil;
}

/** 只要「添加到相册」权限。 */
+ (void)withAddPermission:(void (^)(BOOL granted))block {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        block(status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
    }];
}

static void CINOnMain(void (^completion)(NSURL *, NSString *), NSURL *url, NSString *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(url, error);
    });
}

+ (void)savePhoto:(CGImageRef)image meta:(CINPhotoMeta)meta completion:(void (^)(NSURL *, NSString *))completion {
    NSDate *date = [NSDate date];
    NSData *jpeg = [self jpegDataForImage:image meta:meta date:date];
    if (!jpeg) {
        CINOnMain(completion, nil, CINL(@"error_save"));
        return;
    }
    NSURL *file = [[self lastCaptureDirectory] URLByAppendingPathComponent:[self fileNameWithExtension:@"jpg" date:date]];
    if (![jpeg writeToURL:file atomically:YES]) {
        CINOnMain(completion, nil, CINL(@"error_save"));
        return;
    }
    [self withAddPermission:^(BOOL granted) {
        if (!granted) {
            CINOnMain(completion, file, CINL(@"error_photos_denied"));
            return;
        }
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto data:jpeg options:nil];
        } completionHandler:^(BOOL success, NSError *error) {
            CINOnMain(completion, file, success ? nil : CINL(@"error_save"));
        }];
    }];
}

+ (void)saveVideoAtURL:(NSURL *)url completion:(void (^)(NSURL *, NSString *))completion {
    NSURL *file = [[self lastCaptureDirectory] URLByAppendingPathComponent:url.lastPathComponent];
    if (![NSFileManager.defaultManager moveItemAtURL:url toURL:file error:nil]) {
        CINOnMain(completion, nil, CINL(@"error_record_save"));
        return;
    }
    [self withAddPermission:^(BOOL granted) {
        if (!granted) {
            CINOnMain(completion, file, CINL(@"error_photos_denied"));
            return;
        }
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:file];
        } completionHandler:^(BOOL success, NSError *error) {
            CINOnMain(completion, file, success ? nil : CINL(@"error_record_save"));
        }];
    }];
}

+ (UIImage *)thumbnailForImage:(CGImageRef)image {
    const CGFloat w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    const CGFloat scale = 240.0 / MAX(w, h);
    const CGSize size = CGSizeMake(round(w * scale), round(h * scale));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIImage imageWithCGImage:image] drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

+ (UIImage *)thumbnailForVideo:(NSURL *)url {
    AVAssetImageGenerator *g = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:url options:nil]];
    g.appliesPreferredTrackTransform = YES;   // 竖拍的视频按旋转元数据转正
    g.maximumSize = CGSizeMake(320, 320);
    __block UIImage *image = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [g generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef cg, CMTime actual, NSError *error) {
        if (cg) image = [UIImage imageWithCGImage:cg];
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    return image;
}

@end
