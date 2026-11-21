// CineGL — Metal 渲染引擎
//
// 一帧的旅程：
//   相机纹理 ─[镜头 input]→ signal ─[光晕/柔光 glow]→ ─[胶片 film: LUT + 颗粒]→ graded
//   graded（或 signal）再分别画到：屏幕（present，带监看辅助）、录像编码、拍照输出。
// 安卓版用 OpenGL ES 3.0（core/src/pipeline/Engine.cpp），这里 pass 划分、参数、数学一一对应，
// 只把 GL 换成了 iOS 上性能最好的 Metal。
//
// 所有方法都在渲染队列上调用（CINRenderer 负责），引擎本身不加锁。
#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

#import "CINColor.h"
#import "CINFrameGeometry.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    CINEncoding sourceEncoding;    // 相机给的信号（Apple Log 时为 CINEncodingAppleLog）
    CINEncoding workingEncoding;   // 管线内部的信号（开 Log 时为 CineLog）
    float lookStrength;            // 影调强度 0..1
    float halation;                // 光晕 0..1
    float mist;                    // 柔光 0..1
    float grain;                   // 颗粒 0..1
    float grainSize;               // 颗粒大小 0..1
    float vignette;                // 暗角 0..1
    float aberration;              // 色散 0..1
    simd_float3 wbGains;

    // —— 监看辅助（只影响屏幕）——
    bool showSignal;               // 直接看工作信号（开 Log 时就是「灰片」）
    bool zebra;
    float zebraThreshold;
    bool peaking;
    bool waveform;
} CINRenderParams;

CINRenderParams CINRenderParamsDefault(void);

typedef struct {
    CINRectF frameRect;            // 画面在目标纹理里的位置（左上原点，像素）
    float cornerRadius;            // 圆角半径（像素）
    float overlayTopInset;         // 画面顶部留给 UI 角标的高度（像素），波形图放在它下面
} CINPresentParams;

typedef NS_ENUM(int, CINPlane) {
    CINPlaneSignal = 0,
    CINPlaneGraded = 1,
};

/** YCbCr 转换矩阵的种类（来自 CVPixelBuffer 的附件）。 */
typedef NS_ENUM(int, CINYCbCrMatrix) {
    CINYCbCrMatrix709 = 0,
    CINYCbCrMatrix601 = 1,
    CINYCbCrMatrix2020 = 2,
};

/**
 * (Y, Cb, Cr, 1) → RGB 的 4x4 矩阵（列主序）。
 * bitDepth 10 指 10 bit 数据放在 16 bit 容器的高位（x420 格式），采样得到的是 v16 / 65535。
 */
simd_float4x4 CINYCbCrToRgbMatrix(CINYCbCrMatrix kind, BOOL fullRange, int bitDepth);

/** 一帧输入：相机的 YCbCr 双平面，或者一张 RGBA 纹理（拍照、模拟器）。 */
@interface CINInputFrame : NSObject
@property (nonatomic, strong, nullable) id<MTLTexture> luma;     // YCbCr：亮度平面
@property (nonatomic, strong, nullable) id<MTLTexture> chroma;   // YCbCr：色度平面
@property (nonatomic, strong, nullable) id<MTLTexture> rgba;     // RGBA 输入
@property (nonatomic) simd_float4x4 ycbcrToRgb;
@property (nonatomic) CINMat4 texMatrix;                        // 画面 uv → 输入纹理坐标（已含裁切、旋转、镜像）
@end

@interface CINEngine : NSObject

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> queue;
@property (nonatomic, readonly) int frameWidth;
@property (nonatomic, readonly) int frameHeight;

/** 编译着色器、建管线。失败返回 nil（看日志）。 */
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;
- (instancetype)init NS_UNAVAILABLE;

// —— LUT ——
/** rgba：size³ × 4 个 float（CINLutBake 的输出）。 */
- (void)uploadNeutralLut:(NSData *)rgba size:(int)size;
- (void)uploadLookLut:(NSData *)rgba size:(int)size index:(NSInteger)lookIndex;
- (void)clearLookLuts;
- (BOOL)hasLookLut:(NSInteger)lookIndex;
- (void)selectLook:(NSInteger)lookIndex;

// —— 每帧（只往 commandBuffer 里编码，提交由调用方负责）——
/** 输入 → signal → graded，结果留在引擎内部的纹理里。 */
- (BOOL)renderFrame:(CINInputFrame *)input
         frameWidth:(int)frameW
        frameHeight:(int)frameH
             params:(CINRenderParams)p
         frameIndex:(uint32_t)frameIndex
      commandBuffer:(id<MTLCommandBuffer>)cb;

/** 画到屏幕（drawable），带圆角和监看辅助；画面以外的部分清成黑色。 */
- (void)presentTo:(id<MTLTexture>)target
          present:(CINPresentParams)pp
           params:(CINRenderParams)p
             time:(float)timeSeconds
    commandBuffer:(id<MTLCommandBuffer>)cb;

/** 把 signal / graded 按矩阵画满目标纹理（录像编码用）。 */
- (void)drawPlane:(CINPlane)plane matrix:(CINMat4)uvMatrix to:(id<MTLTexture>)target commandBuffer:(id<MTLCommandBuffer>)cb;

/**
 * 用最近一帧的 signal 给多个影调各渲染一张缩略图，拼成图集（BGRA，可被 CPU 读取）。
 * 图集尺寸 = CINThumbnailAtlasSize(...)；GPU 跑完之后才能读。
 */
- (nullable id<MTLTexture>)renderThumbnails:(NSArray<NSNumber *> *)lookIndices
                                 thumbWidth:(int)thumbW
                                thumbHeight:(int)thumbH
                                    columns:(int)columns
                              commandBuffer:(id<MTLCommandBuffer>)cb;

// —— 离线 ——
/**
 * 处理一张静态图（拍照）：用独立的一套全分辨率纹理跑完整管线，结果按 outMatrix 画到 output。
 * 同步执行（内部等 GPU 跑完）。
 */
- (BOOL)processStill:(CINInputFrame *)input
          frameWidth:(int)frameW
         frameHeight:(int)frameH
              params:(CINRenderParams)p
               plane:(CINPlane)plane
           outMatrix:(CINMat4)outMatrix
              output:(id<MTLTexture>)output;

/** 新建一张 GPU 能画、CPU 能读的 BGRA 纹理。 */
- (nullable id<MTLTexture>)makeReadableTextureWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
