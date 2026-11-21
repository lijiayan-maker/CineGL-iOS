// CineGL — 麦克风采集（对应安卓 record/AudioCapture.kt）
//
// 视频模式下常驻运行：一边给顶栏的 L/R 电平表供数，一边在录像时把 PCM 交给写入器。
// 时间戳用主机时钟（AVAudioTime.hostTime），和相机帧换算后的时钟是同一个，音画才对得上。
#pragma once

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    float left;    // 0..1：-60 dBFS → 0，0 dBFS → 1
    float right;
} CINAudioLevels;

@interface CINAudioCapture : NSObject

@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) int channelCount;
@property (nonatomic, readonly) BOOL isRunning;
/** 电平回调（主线程）。 */
@property (nonatomic, copy, nullable) void (^levelsHandler)(CINAudioLevels levels);
/** 录像时挂上：每一小段 PCM（带主机时钟时间戳）交给它。采集线程上回调。 */
@property (atomic, copy, nullable) void (^sink)(CMSampleBufferRef sampleBuffer);

/** 开始采集（优先立体声，不行就单声道）。没有麦克风或没权限时返回 NO。 */
- (BOOL)start;
- (void)stop;

/** 峰值 → 电平：dBFS 线性映射到 0..1（-60 dB 以下为 0）。 */
+ (float)levelForPeak:(float)peak;

@end

NS_ASSUME_NONNULL_END
