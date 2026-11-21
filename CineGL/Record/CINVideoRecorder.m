#import "CINVideoRecorder.h"

#import <AVFoundation/AVFoundation.h>

@implementation CINVideoRecorder {
    AVAssetWriter *_writer;
    AVAssetWriterInput *_videoInput;
    AVAssetWriterInput *_audioInput;
    AVAssetWriterInputPixelBufferAdaptor *_adaptor;
    int _width, _height;
    BOOL _started;       // 第一帧视频到了，会话起点已定
    BOOL _finishing;
    CMTime _firstVideo;
    CMTime _lastVideo;
    CMTime _lastAudio;
}

+ (int)bitrateForWidth:(int)width height:(int)height fps:(int)fps {
    const long long b = (long long)((double)width * height * fps * 0.25);
    return (int)MIN(MAX(b, 4000000LL), 100000000LL);
}

- (instancetype)initWithURL:(NSURL *)url width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate
            orientationHint:(int)orientationHint audio:(BOOL)audio sampleRate:(double)sampleRate channels:(int)channels
                      error:(NSString **)error {
    if ((self = [super init])) {
        _url = url;
        _width = width;
        _height = height;
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        NSError *err = nil;
        _writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:&err];
        if (!_writer) {
            if (error) *error = err.localizedDescription ?: @"writer";
            return nil;
        }
        NSDictionary *video = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(width),
            AVVideoHeightKey: @(height),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(bitrate),
                AVVideoExpectedSourceFrameRateKey: @(fps),
                AVVideoMaxKeyFrameIntervalKey: @(fps),   // 1 秒一个关键帧
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            },
        };
        _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:video];
        _videoInput.expectsMediaDataInRealTime = YES;
        // 旋转元数据：播放器再顺时针转这么多度
        _videoInput.transform = CGAffineTransformMakeRotation((CGFloat)(orientationHint * M_PI / 180.0));
        _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoInput
            sourcePixelBufferAttributes:@{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                (id)kCVPixelBufferWidthKey: @(width),
                (id)kCVPixelBufferHeightKey: @(height),
                (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
                (id)kCVPixelBufferMetalCompatibilityKey: @YES,
            }];
        if (![_writer canAddInput:_videoInput]) {
            if (error) *error = @"video input";
            return nil;
        }
        [_writer addInput:_videoInput];

        if (audio && sampleRate > 0 && channels > 0) {
            NSDictionary *settings = @{
                AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                AVSampleRateKey: @(sampleRate),
                AVNumberOfChannelsKey: @(channels),
                AVEncoderBitRateKey: @(96000 * channels),
            };
            AVAssetWriterInput *a = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:settings];
            a.expectsMediaDataInRealTime = YES;
            if ([_writer canAddInput:a]) {
                [_writer addInput:a];
                _audioInput = a;
            }
        }
        _firstVideo = _lastVideo = _lastAudio = kCMTimeInvalid;
    }
    return self;
}

- (BOOL)start {
    return [_writer startWriting];
}

#pragma mark - CINRenderVideoSink

- (CVPixelBufferRef)copyEmptyVideoBuffer {
    CVPixelBufferPoolRef pool = _adaptor.pixelBufferPool;
    CVPixelBufferRef pb = NULL;
    if (pool) {
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb);
    } else {
        NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
        CVPixelBufferCreate(kCFAllocatorDefault, (size_t)_width, (size_t)_height, kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)attrs, &pb);
    }
    return pb;
}

- (void)appendVideoBuffer:(CVPixelBufferRef)buffer presentationTime:(CMTime)time {
    @synchronized (self) {
        if (_finishing || _writer.status != AVAssetWriterStatusWriting) return;
        if (!_started) {
            // 第一帧视频定起点：之前到的声音都丢掉
            [_writer startSessionAtSourceTime:time];
            _started = YES;
            _firstVideo = time;
        }
        if (CMTIME_IS_VALID(_lastVideo) && CMTimeCompare(time, _lastVideo) <= 0) return;   // 时间戳必须严格递增
        if (!_videoInput.readyForMoreMediaData) return;   // 编码器忙不过来就丢这一帧
        if ([_adaptor appendPixelBuffer:buffer withPresentationTime:time]) _lastVideo = time;
    }
}

- (void)appendAudio:(CMSampleBufferRef)sampleBuffer {
    @synchronized (self) {
        if (!_audioInput || !_started || _finishing || _writer.status != AVAssetWriterStatusWriting) return;
        const CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        if (CMTimeCompare(pts, _firstVideo) < 0) return;   // 第一帧视频之前的声音
        if (CMTIME_IS_VALID(_lastAudio) && CMTimeCompare(pts, _lastAudio) <= 0) return;
        if (!_audioInput.readyForMoreMediaData) return;
        if ([_audioInput appendSampleBuffer:sampleBuffer]) _lastAudio = pts;
    }
}

- (void)finishWithCompletion:(void (^)(BOOL))completion {
    BOOL started;
    @synchronized (self) {
        _finishing = YES;
        started = _started && CMTIME_IS_VALID(_lastVideo);
    }
    if (_writer.status != AVAssetWriterStatusWriting) {
        completion(NO);
        return;
    }
    if (!started) {
        // 一帧都没写进去：MP4 不完整，直接放弃
        [_writer cancelWriting];
        completion(NO);
        return;
    }
    [_videoInput markAsFinished];
    [_audioInput markAsFinished];
    AVAssetWriter *writer = _writer;
    [_writer finishWritingWithCompletionHandler:^{
        if (writer.status != AVAssetWriterStatusCompleted) NSLog(@"CineGL: video writer failed: %@", writer.error);
        completion(writer.status == AVAssetWriterStatusCompleted);
    }];
}

@end
