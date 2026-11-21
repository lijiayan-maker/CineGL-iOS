// CineGL core — 渲染 pass 的「规划」：每个 pass 画多大、参数怎么算。
//
// 这里只有纯数学，不碰任何 GPU API：CINEngine 只负责「绑定 + 绘制」，
// 「画多大、参数多少」都在这里算，好处是能在单测里直接验证。
#pragma once

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int w;
    int h;
} CINSize;

typedef NS_ENUM(int, CINGlowKind) {
    CINGlowKindHalation = 0,
    CINGlowKindMist = 1,
};

#define CIN_MAX_GLOW_LEVELS 6

/** 光晕 / 柔光的模糊金字塔。level 0 短边固定约 540 像素，所以模糊半径和画面分辨率无关。 */
typedef struct {
    int levelCount;
    CINSize levels[CIN_MAX_GLOW_LEVELS];
    float threshold;    // 线性亮度阈值
    float knee;
    float tapOffsetU;   // 预滤波 4 个采样点的偏移（源纹理 uv）
    float tapOffsetV;
} CINGlowPlan;

CINGlowPlan CINPlanGlow(int frameW, int frameH, CINGlowKind kind);

/** 颗粒尺寸：UI 上 0..1 → 像素，并按画面短边相对 1080 缩放（预览和千万像素照片里颗粒看起来一样大）。 */
float CINGrainSizePixels(float grainSize01, int frameW, int frameH);

/** 波形图：先把画面缩到这个尺寸再散点（点数 = w * h）。 */
CINSize CINWaveformSourceSize(int frameW, int frameH);
static const CINSize kCINWaveformTarget = {256, 128};

/** 波形图在预览视口里的位置（uv，左下原点）：x0, y0, x1, y1，放在右上角。 */
simd_float4 CINWaveformRect(float viewW, float viewH, float topInsetPx);

/** 缩略图图集：columns 列，行数向上取整。 */
CINSize CINThumbnailAtlasSize(int count, int thumbW, int thumbH, int columns);

NS_ASSUME_NONNULL_END
