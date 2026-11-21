#import "CINAudioCapture.h"

#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>

@implementation CINAudioCapture {
    AVAudioEngine *_engine;
    CFTimeInterval _lastLevels;
    dispatch_source_t _simTimer;     // 模拟器的虚拟麦克风
    AVAudioFormat *_simFormat;
    uint32_t _simSeed;
    double _simPhase;
}

+ (float)levelForPeak:(float)peak {
    if (peak <= 0.f) return 0.f;
    return fminf(1.f, fmaxf(0.f, (20.f * log10f(peak) + 60.f) / 60.f));
}

/** 内置麦克风能录立体声（iPhone XS 起的多麦克风）就用立体声，像安卓的 CHANNEL_IN_STEREO。 */
static void CINPreferStereo(AVAudioSession *session) {
    for (AVAudioSessionPortDescription *port in session.availableInputs) {
        if (![port.portType isEqualToString:AVAudioSessionPortBuiltInMic]) continue;
        for (AVAudioSessionDataSourceDescription *source in port.dataSources) {
            if (![source.supportedPolarPatterns containsObject:AVAudioSessionPolarPatternStereo]) continue;
            [source setPreferredPolarPattern:AVAudioSessionPolarPatternStereo error:nil];
            [port setPreferredDataSource:source error:nil];
            [session setPreferredInput:port error:nil];
            [session setPreferredInputOrientation:AVAudioStereoOrientationPortrait error:nil];
            return;
        }
    }
}

- (BOOL)start {
    if (_isRunning) return YES;
#if TARGET_OS_SIMULATOR
    // 模拟器里 AVAudioEngine 的输入要经 coreaudiod 转到 Mac 的麦克风，经常超时，系统会直接把进程 abort 掉。
    // 和虚拟相机一个思路：造一路很轻的底噪，电平表、录像的音轨照样能跑
    return [self startSimulated];
#endif
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeVideoRecording
                 options:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker
                   error:&error];
    [session setPreferredSampleRate:48000 error:nil];
    [session setActive:YES error:&error];
    CINPreferStereo(session);

    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *input = engine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate <= 0 || format.channelCount == 0) return NO;   // 没有麦克风
    _sampleRate = format.sampleRate;
    _channelCount = (int)MIN(format.channelCount, 2u);

    __weak CINAudioCapture *weakSelf = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [weakSelf handleBuffer:buffer time:when];
    }];
    [engine prepare];
    if (![engine startAndReturnError:&error]) {
        [input removeTapOnBus:0];
        NSLog(@"CineGL: audio engine failed: %@", error);
        return NO;
    }
    _engine = engine;
    _isRunning = YES;
    return YES;
}

- (void)stop {
    if (!_engine && !_simTimer) return;
    if (_simTimer) dispatch_source_cancel(_simTimer);
    _simTimer = nil;
    [_engine.inputNode removeTapOnBus:0];
    [_engine stop];
    _engine = nil;
    _isRunning = NO;
    self.sink = nil;
    void (^handler)(CINAudioLevels) = self.levelsHandler;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (handler) handler((CINAudioLevels){0.f, 0.f});
    });
}

#pragma mark - 模拟器的虚拟麦克风

- (BOOL)startSimulated {
    _sampleRate = 48000;
    _channelCount = 2;
    _simFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:48000 channels:2 interleaved:NO];
    _simSeed = 12345;
    dispatch_queue_t queue = dispatch_queue_create("CineGL-SimMic", DISPATCH_QUEUE_SERIAL);
    _simTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    const uint64_t interval = (uint64_t)(1024.0 / 48000.0 * NSEC_PER_SEC);
    dispatch_source_set_timer(_simTimer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval / 10);
    __weak CINAudioCapture *weakSelf = self;
    dispatch_source_set_event_handler(_simTimer, ^{
        [weakSelf simulatedTick];
    });
    dispatch_resume(_simTimer);
    _isRunning = YES;
    return YES;
}

/** 1024 帧的底噪：约 -45 dBFS、缓慢起伏，左右声道略有不同。 */
- (void)simulatedTick {
    const AVAudioFrameCount frames = 1024;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_simFormat frameCapacity:frames];
    buffer.frameLength = frames;
    _simPhase += frames / 48000.0;
    const float amp = 0.006f * (1.f + 0.6f * (float)sin(_simPhase * 1.7));
    for (int ch = 0; ch < 2; ++ch) {
        float *data = buffer.floatChannelData[ch];
        for (AVAudioFrameCount i = 0; i < frames; ++i) {
            _simSeed = _simSeed * 1664525u + 1013904223u;
            data[i] = amp * (ch == 0 ? 1.f : 0.8f) * ((float)(_simSeed >> 8) / 8388608.f - 1.f);
        }
    }
    const uint64_t now = mach_absolute_time();
    const double ticks = (double)frames / 48000.0 * 1e9;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    const uint64_t start = now - (uint64_t)(ticks * tb.denom / tb.numer);
    [self handleBuffer:buffer time:[AVAudioTime timeWithHostTime:start]];
}

#pragma mark - 采集回调

- (void)handleBuffer:(AVAudioPCMBuffer *)buffer time:(AVAudioTime *)when {
    const AVAudioFrameCount frames = buffer.frameLength;
    if (frames == 0) return;
    [self updateLevels:buffer];

    void (^sink)(CMSampleBufferRef) = self.sink;
    if (!sink) return;
    // 这批数据第一帧的采集时刻：AVAudioTime 给的是主机时钟
    CMTime pts = when.hostTimeValid ? CMClockMakeHostTimeFromSystemUnits(when.hostTime)
                                    : CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), CMTimeMake(frames, (int32_t)_sampleRate));
    CMAudioFormatDescriptionRef fmt = NULL;
    if (CMAudioFormatDescriptionCreate(kCFAllocatorDefault, buffer.format.streamDescription, 0, NULL, 0, NULL, NULL, &fmt) != noErr) return;
    CMSampleTimingInfo timing = {CMTimeMake(1, (int32_t)_sampleRate), pts, kCMTimeInvalid};
    CMSampleBufferRef sb = NULL;
    OSStatus status = CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, fmt, frames, 1, &timing, 0, NULL, &sb);
    CFRelease(fmt);
    if (status != noErr || !sb) return;
    // 拷一份数据进 CMSampleBuffer：tap 的缓冲下一次回调会被复用
    status = CMSampleBufferSetDataBufferFromAudioBufferList(sb, kCFAllocatorDefault, kCFAllocatorDefault, 0, buffer.audioBufferList);
    if (status == noErr) sink(sb);
    CFRelease(sb);
}

- (void)updateLevels:(AVAudioPCMBuffer *)buffer {
    const CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastLevels < 0.05) return;   // 电平表 20 Hz 足够
    _lastLevels = now;
    float peaks[2] = {0.f, 0.f};
    const AVAudioFrameCount frames = buffer.frameLength;
    const AVAudioChannelCount channels = MIN(buffer.format.channelCount, 2u);
    if (buffer.floatChannelData) {
        for (AVAudioChannelCount ch = 0; ch < channels; ++ch) {
            const float *data = buffer.floatChannelData[ch];
            const NSUInteger stride = (NSUInteger)buffer.stride;
            float peak = 0.f;
            for (AVAudioFrameCount i = 0; i < frames; ++i) peak = fmaxf(peak, fabsf(data[i * stride]));
            peaks[ch] = peak;
        }
    } else if (buffer.int16ChannelData) {
        for (AVAudioChannelCount ch = 0; ch < channels; ++ch) {
            const int16_t *data = buffer.int16ChannelData[ch];
            const NSUInteger stride = (NSUInteger)buffer.stride;
            int peak = 0;
            for (AVAudioFrameCount i = 0; i < frames; ++i) peak = MAX(peak, abs((int)data[i * stride]));
            peaks[ch] = peak / 32768.f;
        }
    }
    if (channels == 1) peaks[1] = peaks[0];
    const CINAudioLevels levels = {[CINAudioCapture levelForPeak:peaks[0]], [CINAudioCapture levelForPeak:peaks[1]]};
    void (^handler)(CINAudioLevels) = self.levelsHandler;
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{
        handler(levels);
    });
}

@end
