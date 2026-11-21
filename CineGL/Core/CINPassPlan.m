#import "CINPassPlan.h"

CINGlowPlan CINPlanGlow(int frameW, int frameH, CINGlowKind kind) {
    CINGlowPlan p;
    memset(&p, 0, sizeof(p));
    const int shortSide = MAX(1, MIN(frameW, frameH));
    const float baseShort = fminf(540.f, shortSide * 0.5f);
    const float scale = baseShort / (float)shortSide;

    // 光晕紧贴高光（4 级），柔光要铺得很开（6 级）
    p.levelCount = kind == CINGlowKindHalation ? 4 : 6;
    p.threshold = kind == CINGlowKindHalation ? 0.8f : 0.4f;
    p.knee = kind == CINGlowKindHalation ? 0.2f : 0.3f;

    CINSize s = {MAX(1, (int)lroundf(frameW * scale)), MAX(1, (int)lroundf(frameH * scale))};
    for (int i = 0; i < p.levelCount; ++i) {
        p.levels[i] = s;
        s = (CINSize){MAX(1, s.w / 2), MAX(1, s.h / 2)};
    }
    // 采样点放在 level 0 一个像素的 ±1/4 处：2 倍缩小时正好覆盖 2x2 个源像素
    p.tapOffsetU = 0.25f / (float)p.levels[0].w;
    p.tapOffsetV = 0.25f / (float)p.levels[0].h;
    return p;
}

float CINGrainSizePixels(float grainSize01, int frameW, int frameH) {
    const float shortSide = (float)MAX(1, MIN(frameW, frameH));
    return (1.f + 2.5f * fminf(1.f, fmaxf(0.f, grainSize01))) * shortSide / 1080.f;
}

CINSize CINWaveformSourceSize(int frameW, int frameH) {
    const int w = MAX(1, MIN(192, frameW / 4));
    const int h = MAX(1, MIN(256, (int)lroundf(w * (float)frameH / (float)frameW)));
    return (CINSize){w, h};
}

simd_float4 CINWaveformRect(float viewW, float viewH, float topInsetPx) {
    if (viewW <= 0.f || viewH <= 0.f) return simd_make_float4(0.f, 0.f, 0.f, 0.f);
    const float margin = 0.03f * viewW;
    const float w = 0.42f * viewW;
    const float h = w * 0.5f;
    const float x1 = 1.f - margin / viewW;
    // 顶部留出 UI 角标那一行（LOG / LUT 烧录 / 影调名）的高度，别压在一起
    const float y1 = 1.f - (margin + topInsetPx) / viewH;
    return simd_make_float4(x1 - w / viewW, y1 - h / viewH, x1, y1);
}

CINSize CINThumbnailAtlasSize(int count, int thumbW, int thumbH, int columns) {
    columns = MAX(1, columns);
    const int rows = MAX(1, (count + columns - 1) / columns);
    return (CINSize){columns * thumbW, rows * thumbH};
}
