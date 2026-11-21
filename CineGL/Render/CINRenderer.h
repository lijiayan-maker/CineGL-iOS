// CineGL — 渲染队列：整个渲染管线的「司机」（对应安卓的 RenderEngine.kt）
//
// 平台相关的事（Metal 设备、相机缓冲转纹理、屏幕和录像的目标）在这里做，
// 真正的绘制交给 CINEngine。一帧的顺序：
//
//   相机出帧（直接投递到渲染队列）→ CVPixelBuffer 零拷贝转成 Metal 纹理
//     → renderFrame（镜头 → 光晕/柔光 → LUT + 颗粒）
//     → 正在录像？再画一遍到录像缓冲（带旋转），GPU 跑完后按相机时间戳交给写入器
//     → 画到屏幕（带圆角和监看辅助）
//     → 影调面板开着？每隔几帧渲染一次缩略图
#pragma once

#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#import "CINEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class CINRenderer;

@protocol CINRendererDelegate <NSObject>
/** 画面尺寸变化（切画幅、切分辨率、换镜头）。主线程回调。 */
- (void)renderer:(CINRenderer *)renderer frameSizeDidChangeWidth:(int)width height:(int)height;
/** 影调缩略图（索引 → 图片）。主线程回调。 */
- (void)renderer:(CINRenderer *)renderer didRenderThumbnails:(NSDictionary<NSNumber *, UIImage *> *)thumbnails;
@end

/** 录像的画面接收方（CINVideoRecorder 实现）。两个方法都在渲染相关的线程上调用。 */
@protocol CINRenderVideoSink <NSObject>
/** 取一个空的 BGRA 缓冲给 GPU 画；忙不过来时返回 NULL（这一帧丢掉）。返回值归调用方释放。 */
- (nullable CVPixelBufferRef)copyEmptyVideoBuffer CF_RETURNS_RETAINED;
/** GPU 画完了，按相机时间戳写进文件。 */
- (void)appendVideoBuffer:(CVPixelBufferRef)buffer presentationTime:(CMTime)time;
@end

/** 相机输出给渲染器的缓冲描述。 */
typedef struct {
    int bufferWidth;
    int bufferHeight;
    int sensorOrientation;   // 缓冲顺时针转多少度才是直立画面
    bool front;
    CINAspectRatio aspect;
} CINRenderInputConfig;

/** 拍照请求：一张传感器方向的高分辨率缓冲，走同一条管线。 */
@interface CINStillRequest : NSObject
@property (nonatomic) CVPixelBufferRef pixelBuffer;   // 由请求持有
@property (nonatomic) int sensorOrientation;
@property (nonatomic) BOOL front;
@property (nonatomic) CINAspectRatio aspect;
@property (nonatomic) int deviceRotation;
@property (nonatomic) CINPlane plane;
@property (nonatomic) CINRenderParams params;
@end

@interface CINRenderer : NSObject

/** 渲染队列。相机把帧直接投递到这里（AVCaptureVideoDataOutput 的回调队列就是它）。 */
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, weak) id<CINRendererDelegate> delegate;
/** 可在任意线程读写。 */
@property (atomic) CINRenderParams params;
@property (atomic) float cornerRadiusPx;
/** 画面顶部被 UI 角标占用的高度（像素），波形图要让开。 */
@property (atomic) float overlayTopInsetPx;

/** Metal 不可用时返回 nil。 */
- (nullable instancetype)init;

/** 配置相机输入。必须在相机开始出帧之前调用（同步）。 */
- (void)configureInput:(CINRenderInputConfig)config;
/** 只换画幅，不换相机流。 */
- (void)setAspect:(CINAspectRatio)aspect;
- (void)selectLook:(NSInteger)index;
/** 新注册的影调（导入的 .cube）需要烘一张表。 */
- (void)bakeLook:(NSInteger)index;
- (void)setThumbnailsEnabled:(BOOL)enabled;

// —— 屏幕 ——
- (void)attachLayer:(CAMetalLayer *)layer;
/** 视图要消失时调用：等渲染队列真正放开图层后才返回，不会再往已移除的图层里画。 */
- (void)detachLayer;

// —— 相机帧（渲染队列上调用）——
- (void)drawPixelBuffer:(CVPixelBufferRef)pixelBuffer presentationTime:(CMTime)time;

// —— 录像 ——
/** 开始往录像缓冲画：matrix 决定旋转/去镜像，plane 决定录调色后的还是 Log 原片。 */
- (void)startEncoder:(id<CINRenderVideoSink>)sink width:(int)width height:(int)height matrix:(CINMat4)matrix plane:(CINPlane)plane;
/** 停止往录像缓冲画；已经提交给 GPU 的帧全部写完之后才回调（渲染队列）。 */
- (void)stopEncoder:(void (^)(void))onStopped;

// —— 拍照 ——
/** 在渲染队列上用同一套管线处理一张高分辨率照片。回调在渲染队列，失败给 NULL。 */
- (void)processStill:(CINStillRequest *)request completion:(void (^)(CGImageRef _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
