// CineGL — 相机来源的统一接口
//
// 真机上是 AVFoundation（CINCameraController），模拟器没有摄像头，用一台「虚拟相机」
// （CINSimulatedCamera）按同样的接口出帧，让整条管线、手动参数、录像拍照都能在模拟器上跑通。
#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

#import "CINCameraControls.h"

NS_ASSUME_NONNULL_BEGIN

/** 当前相机的能力（只摘这个 App 关心的）。 */
@interface CINCameraCaps : NSObject
@property (nonatomic) BOOL front;
@property (nonatomic) int sensorOrientation;         // 缓冲顺时针转多少度才是直立画面
@property (nonatomic) BOOL manualSensor;             // 能自定义 ISO + 快门
@property (nonatomic) BOOL manualPostProcessing;     // 能自定义白平衡增益（白平衡在 ISP 里做）
@property (nonatomic) BOOL focusLock;                // 能锁定镜头位置（手动对焦）
@property (nonatomic) int isoMin;
@property (nonatomic) int isoMax;
@property (nonatomic) int64_t exposureMinNs;
@property (nonatomic) int64_t exposureMaxNs;
@property (nonatomic) float minFocusDiopters;        // 最近对焦距离的屈光度（1 / 米）
@property (nonatomic) int evMin;                     // 曝光补偿档位（× evStep）
@property (nonatomic) int evMax;
@property (nonatomic) float evStep;
@property (nonatomic) float zoomMin;                 // 相对主摄的变焦倍率
@property (nonatomic) float zoomMax;
@property (nonatomic) BOOL hasFlash;                 // 有补光灯（常亮手电）
@property (nonatomic) BOOL previewStabilization;
@property (nonatomic) float equivalentFocal;         // 变焦 1x 时的 35mm 等效焦距
@property (nonatomic, readonly) BOOL manualFocus;
@end

/** 开相机要的参数。 */
@interface CINSessionConfig : NSObject
@property (nonatomic) BOOL front;
@property (nonatomic) BOOL video;
@property (nonatomic) float streamAspect;    // 流的宽高比：16/9 或 4/3
@property (nonatomic) int targetShort;       // 流短边的目标：1080 / 1440 / 2160
@property (nonatomic) int fps;
@property (nonatomic) BOOL appleLog;         // 让相机直接输出 Apple Log
@property (nonatomic) CINCameraControls controls;
@end

/** 相机开好之后的实际情况。 */
@interface CINSessionInfo : NSObject
@property (nonatomic, strong) CINCameraCaps *caps;
@property (nonatomic) int bufferWidth;       // 流缓冲尺寸（传感器方向，通常是横的）
@property (nonatomic) int bufferHeight;
@property (nonatomic) int fps;
@property (nonatomic, copy) NSArray<NSNumber *> *availableFps;
@property (nonatomic) BOOL uhdAvailable;
@property (nonatomic) BOOL appleLogAvailable;
@property (nonatomic) BOOL appleLogActive;
@end

/** 一张照片：传感器方向的高分辨率缓冲 + 拍摄参数（拿不到的为 0）。 */
@interface CINStillCapture : NSObject
@property (nonatomic) CVPixelBufferRef pixelBuffer;   // 由对象持有
@property (nonatomic) int iso;
@property (nonatomic) int64_t exposureNs;
@property (nonatomic) float focalLength;
@property (nonatomic) float aperture;
@end

@protocol CINCameraSource;

@protocol CINCameraSourceDelegate <NSObject>
/** 一帧画面。在开相机时指定的 frameQueue（渲染队列）上回调；时间戳是主机时钟（和音频同一个时钟）。 */
- (void)cameraSource:(id<CINCameraSource>)source didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer time:(CMTime)time;
/** 相机实际在用的参数，约每 120ms 一次。任意线程。 */
- (void)cameraSource:(id<CINCameraSource>)source didUpdateReadout:(CINReadout)readout;
/** 运行中出错（被别的 App 占用等）。任意线程。 */
- (void)cameraSource:(id<CINCameraSource>)source didFailWithMessage:(NSString *)message;
@end

@protocol CINCameraSource <NSObject>

@property (nonatomic, weak, nullable) id<CINCameraSourceDelegate> delegate;
/** 手动白平衡能不能交给 ISP（否则锁住自动白平衡，色温在 GPU 里调）。 */
@property (nonatomic, readonly) BOOL wbOnIsp;

/** 开相机并开始出帧。completion 在主线程，失败时给出文案。 */
- (void)startWithConfig:(CINSessionConfig *)config
             frameQueue:(dispatch_queue_t)frameQueue
             completion:(void (^)(CINSessionInfo *_Nullable info, NSString *_Nullable error))completion;
/** 参数变了就重新下发。 */
- (void)updateControls:(CINCameraControls)controls;
/** 点击对焦/测光。point：传感器方向缓冲里的归一化坐标。手动对焦时只改测光点。 */
- (void)focusAtBufferPoint:(CGPoint)point;
/** 回到连续自动对焦、中央测光。 */
- (void)resetFocus;
/** 拍一张。completion 在主线程。 */
- (void)captureWithCompletion:(void (^)(CINStillCapture *_Nullable still, NSString *_Nullable error))completion;
/** 关相机。completion（可选）在主线程。 */
- (void)stopWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
