// CineGL core — 画面几何：裁切、旋转、镜像、输出方向
//
// 坐标约定（全项目统一，踩坑重灾区，务必先读）：
//   * 「画面（frame）」= 竖持手机时看到的直立画面，长边竖直。预览、录像、拍照都从它出发。
//     前置摄像头的画面是镜像的（像照镜子），和系统相机预览一致。
//   * 画面 uv 用 GL 习惯：(0,0) 在左下角，v 向上。Metal 的纹理原点在左上角，
//     着色器里采样「管线自己画出来的纹理」时统一用 tc(uv) = (u, 1 - v) 翻过去。
//   * 「图像坐标」(x, y) 用图片习惯：(0,0) 在左上角，y 向下。相机缓冲、照片位图的纹理坐标就是它
//     （Metal 纹理第 0 行在 t = 0），所以 CINStillInputMatrix 的结果可以直接拿去采样相机纹理。
//   * 矩阵是 4x4 列主序（和 simd_float4x4、Metal 的 float4x4 一致），
//     作用在 (u, v, 0, 1) 上，只用到其中的二维仿射部分。
#pragma once

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    float m[16];
} CINMat4;

CINMat4 CINMat4Identity(void);
/** 由一个二维仿射映射构造：f(0,0)、f(1,0)、f(0,1) 三个点就能确定它。 */
CINMat4 CINMat4Affine(float ox, float oy, float ux, float uy, float vx, float vy);
/** a × b（先做 b，再做 a）。 */
CINMat4 CINMat4Multiply(CINMat4 a, CINMat4 b);
/** 变换一个点 (u, v)。 */
void CINMat4Apply(CINMat4 m, float u, float v, float *outU, float *outV);
simd_float4x4 CINMat4ToSimd(CINMat4 m);

/** 画幅：都按「长边 : 短边」描述。数值和设置里存的一致。 */
typedef NS_ENUM(int, CINAspectRatio) {
    CINAspectRatio16x9 = 0,
    CINAspectRatio4x3 = 1,
    CINAspectRatio1x1 = 2,
    CINAspectRatio239x1 = 3,
};

float CINAspectLongOverShort(CINAspectRatio a);

typedef struct {
    int frameWidth;    // 画面宽（像素，直立方向）
    int frameHeight;   // 画面高
    // 在直立图像（未裁切）里的裁切区域，归一化，图像坐标（左上原点）
    float cropX, cropY, cropW, cropH;
} CINFrameGeometry;

/** 被裁的那条边对齐到的像素数（编码器要求偶数，8 的倍数兼容性最好）。 */
static const int kCINFrameAlign = 8;

/**
 * 根据相机输出缓冲尺寸（传感器方向，通常是横的）、传感器安装角度和画幅，算出画面尺寸和裁切区域。
 * 被裁的那条边向下取整到 align 的倍数（取 16 的话 1:1 会把 1080 裁成 1072），没被裁的边保持原样。
 */
CINFrameGeometry CINComputeFrame(int bufferWidth, int bufferHeight, int sensorOrientation, CINAspectRatio aspect, int align);

/** 画面 uv → 直立图像 uv（GL 约定）。和输入矩阵相乘：texMatrix = inputMatrix × cropMatrix。 */
CINMat4 CINCropMatrix(CINFrameGeometry g);

/**
 * 输入用：直立画面 uv（前置时为镜像画面）→ 相机缓冲 / 照片位图的纹理坐标（左上原点）。
 * 缓冲是传感器方向（没转正、没镜像），「直立图像 = 缓冲顺时针转 sensorOrientation 度」。
 * 预览帧和拍照都用它（安卓预览靠 SurfaceTexture 的矩阵，iOS 没有这个东西，自己算）。
 */
CINMat4 CINStillInputMatrix(int sensorOrientation, bool frontFacing);

/**
 * 输出用：输出目标的 uv → 画面 uv。
 *   rotationCw —— 输出图像相对画面顺时针转了多少度（0/90/180/270）
 *   unmirror   —— 前置摄像头：把镜像翻回来（保存的照片/视频是「别人眼中的你」）
 *   flipY      —— 读回时如果是「底行在前」（OpenGL 的 glReadPixels），绘制时上下翻转；
 *                 Metal 的渲染目标本来就是顶行在前，传 false
 */
CINMat4 CINOutputMatrix(int rotationCw, bool unmirror, bool flipY);

typedef struct {
    int width;
    int height;
    int rotationCw;        // 画面 → 输出缓冲 的顺时针旋转
    int orientationHint;   // 写进视频文件的旋转元数据（播放器再顺时针转这么多）
} CINOutputPlan;

/**
 * 把设备朝向（顺时针转了多少度，吸附到 0/90/180/270，左侧朝上 = 90）换算成：
 * 「画面要顺时针转多少度，才能在真实世界里是正的」。
 */
int CINUprightRotation(int deviceOrientationDeg);

/** 录像：编码缓冲永远是横的（宽 ≥ 高，编码器兼容性最好），竖拍时靠旋转元数据让播放器转回来。 */
CINOutputPlan CINPlanVideoOutput(int frameWidth, int frameHeight, int deviceOrientationDeg);

/** 拍照：直接把像素转正，不依赖 EXIF 方向。 */
CINOutputPlan CINPlanPhotoOutput(int frameWidth, int frameHeight, int deviceOrientationDeg);

typedef struct {
    float x, y, w, h;
} CINRectF;

/** 等比缩放后居中放进盒子（左上角原点）。UI 叠加层和 GPU 上屏都用它，保证两边算出同一个框。 */
CINRectF CINFitCenter(float contentW, float contentH, float boxW, float boxH);

NS_ASSUME_NONNULL_END
