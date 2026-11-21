#import "CINAudioCapture.h"

#import <AVFoundation/AVFoundation.h>

@implementation CINAudioCapture {
    AVAudioEngine *_engine;
    CFTimeInterval _lastLevels;
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
    if (!_engine) return;
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
