// CineGL — 录像：H.264 视频（GPU 直接画进写入器的像素缓冲）+ AAC 音频 → MP4（对应安卓 record/VideoRecorder.kt）
//
// 编码缓冲永远是横的，竖拍时在轨道上写旋转（transform），播放器自己转回来。
// 时间戳：以第一帧视频为起点（startSession），比它早的声音直接丢掉；同一轨时间戳必须严格递增。
#pragma once

#import <CoreMedia/CoreMedia.h>

#import "CINRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINVideoRecorder : NSObject <CINRenderVideoSink>

/** 准备写入器。失败返回 nil 并给出原因（英文，进日志 / 拼进提示）。 */
- (nullable instancetype)initWithURL:(NSURL *)url
                               width:(int)width
                              height:(int)height
                                 fps:(int)fps
                             bitrate:(int)bitrate
                     orientationHint:(int)orientationHint
                               audio:(BOOL)audio
                          sampleRate:(double)sampleRate
                            channels:(int)channels
                               error:(NSString *_Nullable *_Nullable)error;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSURL *url;

- (BOOL)start;
/** 音频采集线程调用。 */
- (void)appendAudio:(CMSampleBufferRef)sampleBuffer;
/** 结束录制。调用前渲染器必须已经停止往里画、音频回调已经摘掉。completion 在任意线程，ok = 文件可用。 */
- (void)finishWithCompletion:(void (^)(BOOL ok))completion;

/** 码率：宽 × 高 × 帧率 × 0.25，限制在 4–100 Mbps（和安卓一致）。 */
+ (int)bitrateForWidth:(int)width height:(int)height fps:(int)fps;

@end

NS_ASSUME_NONNULL_END
