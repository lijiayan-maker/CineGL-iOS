// CineGL — 写入系统相册（对应安卓 media/MediaSaver.kt）
//
// 只申请「添加到相册」权限（最小权限）：没法建 CineGL 相册，照片和视频出现在「最近项目」里。
// 另外在 App 的缓存目录留一份「最近一次拍摄」，左下角的相册按钮用系统预览（QuickLook）直接打开它。
#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int iso;             // 0 = 不知道
    int64_t exposureNs;
    float focalLength;
    float aperture;
} CINPhotoMeta;

@interface CINMediaSaver : NSObject

/** 文件名：CineGL_20261121_201530_123.jpg。 */
+ (NSString *)fileNameWithExtension:(NSString *)ext date:(NSDate *)date;
/** 录像先写到临时目录，写完再存进相册。 */
+ (NSURL *)newVideoURL;

/** JPEG + EXIF，存进相册。completion 在主线程：成功给出缓存里「最近一次拍摄」的文件。 */
+ (void)savePhoto:(CGImageRef)image meta:(CINPhotoMeta)meta
       completion:(void (^)(NSURL *_Nullable lastCapture, NSString *_Nullable error))completion;
/** 把录好的视频存进相册（临时文件会被移进缓存当「最近一次拍摄」）。completion 在主线程。 */
+ (void)saveVideoAtURL:(NSURL *)url completion:(void (^)(NSURL *_Nullable lastCapture, NSString *_Nullable error))completion;

/** JPEG 数据（带 EXIF），单测也用它。 */
+ (nullable NSData *)jpegDataForImage:(CGImageRef)image meta:(CINPhotoMeta)meta date:(NSDate *)date;

/** 缩略图：长边 240（照片）/ 320（视频，同步等待解码，别在主线程调）。 */
+ (UIImage *)thumbnailForImage:(CGImageRef)image;
+ (nullable UIImage *)thumbnailForVideo:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
