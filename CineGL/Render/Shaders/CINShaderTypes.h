// CineGL — 着色器和 OC 共用的参数结构体（Metal 和 C 都能编这个头文件）
//
// 字段顺序、类型两边必须一致：OC 侧填好整个结构体，用 setFragmentBytes 一次传过去。
#pragma once

#include <simd/simd.h>

/** 全屏四边形顶点着色器：画面 uv → 纹理坐标（裁切、旋转、镜像全塞在这一个矩阵里）。 */
typedef struct {
    simd_float4x4 texMatrix;
} CINQuadUniforms;

/** 第 1 站「镜头」。 */
typedef struct {
    simd_float4x4 texMatrix;     // 画面 uv → 输入纹理坐标（左上原点）
    simd_float4x4 ycbcrToRgb;    // (Y, Cb, Cr, 1) → RGB；RGBA 输入时不用
    simd_float3 wbGains;         // GPU 白平衡增益（线性空间）
    int sourceEncoding;          // 输入信号编码：相机直出 = 0，Apple Log = 2
    int workingEncoding;         // 管线内部信号编码：开 Log = 1
    float vignette;              // 暗角 0..1
    float aberration;            // 色散 0..1
    float frameAspect;           // 画面宽 / 高
} CINInputUniforms;

/** 光晕/柔光第 1 步：提取高光 + 降采样。 */
typedef struct {
    simd_float2 tapOffset;       // 4 个采样点相对中心的偏移（输入纹理 uv 单位）
    int workingEncoding;
    float threshold;             // 线性亮度阈值
    float knee;                  // 软膝宽度
} CINPrefilterUniforms;

/** Dual Kawase 降 / 升采样。 */
typedef struct {
    simd_float2 halfTexel;       // 0.5 / 输入尺寸
    float offset;
} CINKawaseUniforms;

/** 第 2、3 站「胶片曝光 + 冲洗」。 */
typedef struct {
    simd_float2 frameSize;       // 画面尺寸（像素）
    float neutralLutSize;
    float lookLutSize;
    float lookStrength;          // 影调强度 0..1
    int workingEncoding;
    float halationAmount;        // 光晕强度 0..1
    float mistAmount;            // 柔光强度 0..1
    float grain;                 // 0..1
    float grainSize;             // 颗粒尺寸（像素）
    float seed;                  // 每帧变化的随机种子，让颗粒「活」起来
} CINFilmUniforms;

/** 上屏：监看辅助 + 圆角。 */
typedef struct {
    simd_float4 waveformRect;    // 波形图在视口里的位置（uv，左下原点）：x0, y0, x1, y1；x1 <= x0 表示关闭
    simd_float2 texel;           // 1 / 输入纹理尺寸
    simd_float2 viewport;        // 视口像素尺寸
    float cornerRadius;          // 圆角半径（像素）
    int zebra;
    float zebraThreshold;
    int peaking;
    float time;
} CINPresentUniforms;

/** 波形图散点。 */
typedef struct {
    simd_float3 color;           // 每个点贡献的亮度（很小，靠叠加变亮）
    simd_int2 sourceSize;
} CINWaveformUniforms;

/** 模拟器的虚拟相机：画一张「传感器方向」的场景（只在模拟器上用）。 */
typedef struct {
    simd_float4 monitorRect;     // 后置场景里显示器屏幕的位置（直立场景坐标，左上原点）：x0, y0, x1, y1
    float time;                  // 秒，用来让画面动起来
    float gain;                  // 曝光增益（线性）：ISO × 快门相对「ISO 200、1/100s」的倍数
    float zoom;                  // 数码变焦
    float blur;                  // 失焦程度（采样的 mip 级别）
    float torch;                 // 补光 0 / 1
    float uprightAspect;         // 直立画面宽 / 高
    float sceneAspect;           // 场景图宽 / 高
    int front;                   // 1 = 前置的彩色场景
} CINSimSceneUniforms;
