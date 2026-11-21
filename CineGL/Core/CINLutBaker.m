#import "CINLutBaker.h"

static const float kLogShoulderStart = 0.9f;

/** 信号 → 显示线性（[0,1]）。Log 信号可能超过 1，用肩部压回来；709 信号本来就 ≤ 1。 */
static CINVec3 CINSignalToDisplayLinear(CINEncoding signal, CINVec3 s) {
    CINVec3 lin = CINDecodeV(s, signal);
    if (signal == CINEncodingCineLog) {
        lin = CINVec3Make(CINHighlightRolloff(lin.x, kLogShoulderStart), CINHighlightRolloff(lin.y, kLogShoulderStart),
                          CINHighlightRolloff(lin.z, kLogShoulderStart));
    }
    return CINClamp01V(lin);
}

static float CINAngularDistance(float a, float b) {
    float d = fabsf(fmodf(a - b, 360.f));
    return d > 180.f ? 360.f - d : d;
}

static float CINOverlay(float base, float blend) {
    return base < 0.5f ? 2.f * base * blend : 1.f - 2.f * (1.f - base) * (1.f - blend);
}

float CINLutSCurve(float x, float contrast, float pivot) {
    x = CINClamp01(x);
    if (contrast == 1.f || x <= 0.f || x >= 1.f) return x;
    // 先用幂函数把支点挪到 0.5，在 0.5 处套对称的 S 曲线 x^c / (x^c + (1-x)^c)，再挪回去
    const float g = logf(0.5f) / logf(pivot);
    const float xp = powf(x, g);
    const float a = powf(xp, contrast);
    const float b = powf(1.f - xp, contrast);
    return powf(a / (a + b), 1.f / g);
}

static CINVec3 CINApplyRecipe(const CINLookRecipe *r, CINVec3 lin) {
    // —— 1. 线性空间：曝光、白平衡、串扰、饱和度 ——
    lin *= exp2f(r->exposure);
    if (r->temperature != 0.f || r->tint != 0.f) {
        lin *= CINVec3Make(exp2f(0.3f * r->temperature), exp2f(-0.2f * r->tint), exp2f(-0.3f * r->temperature));
    }
    if (r->crossTalk > 0.f) {
        const CINVec3 mixed = CINVec3Make(0.80f * lin.x + 0.15f * lin.y + 0.05f * lin.z,
                                          0.10f * lin.x + 0.80f * lin.y + 0.10f * lin.z,
                                          0.05f * lin.x + 0.15f * lin.y + 0.80f * lin.z);
        lin = CINMixV(lin, mixed, r->crossTalk);
    }
    if (r->mono) {
        const float m = simd_dot(r->monoWeights, lin);
        lin = (CINVec3)m;
    } else if (r->saturation != 1.f) {
        const float l = CINLuminance(lin);
        lin = CINMaxZero((CINVec3)l + (lin - (CINVec3)l) * r->saturation);
    }

    // —— 2. 转到显示编码空间 ——
    CINVec3 e = CINVec3Make(CINLinearToSrgb(fminf(lin.x, 1.f)), CINLinearToSrgb(fminf(lin.y, 1.f)),
                            CINLinearToSrgb(fminf(lin.z, 1.f)));

    // —— 3. 色相微调 ——
    if (r->hueCount > 0) {
        CINVec3 hsv = CINRgbToHsv(e);
        float hueShift = 0.f, satMul = 1.f;
        for (int i = 0; i < r->hueCount; ++i) {
            const CINHueAdjust h = r->hues[i];
            const float d = CINAngularDistance(hsv.x, h.centerDeg);
            if (d >= h.widthDeg) continue;
            float w = 1.f - d / h.widthDeg;
            w = w * w * (3.f - 2.f * w);
            hueShift += h.shiftDeg * w;
            satMul *= CINMix(1.f, h.saturation, w);
        }
        hsv.x += hueShift;
        hsv.y = CINClamp01(hsv.y * satMul);
        e = CINHsvToRgb(hsv);
    }

    // —— 4. S 曲线（逐通道，顺带带来胶片式的饱和度变化）——
    if (r->contrast != 1.f) {
        e = CINVec3Make(CINLutSCurve(e.x, r->contrast, r->pivot), CINLutSCurve(e.y, r->contrast, r->pivot),
                        CINLutSCurve(e.z, r->contrast, r->pivot));
    }

    // —— 5. 分离色调：暗部、亮部各加一点颜色（只改色度，不改亮度）——
    if (r->shadowTintAmount > 0.f || r->highlightTintAmount > 0.f) {
        const float l = CINLuminance(e);
        const float ws = 1.f - CINSmoothstep(0.f, 0.55f, l);
        const float wh = CINSmoothstep(0.45f, 1.f, l);
        const CINVec3 st = r->shadowTint - (CINVec3)CINLuminance(r->shadowTint);
        const CINVec3 ht = r->highlightTint - (CINVec3)CINLuminance(r->highlightTint);
        e += st * (r->shadowTintAmount * ws) + ht * (r->highlightTintAmount * wh);
    }

    // —— 6. 跳漂：和自身亮度做叠加混合，再去掉一部分饱和 ——
    if (r->bleach > 0.f) {
        const float l = CINLuminance(e);
        const CINVec3 desat = CINMixV(e, (CINVec3)l, 0.6f);
        const CINVec3 o = CINVec3Make(CINOverlay(desat.x, l), CINOverlay(desat.y, l), CINOverlay(desat.z, l));
        e = CINMixV(e, o, r->bleach);
    }

    // —— 7. 黑位 / 白位 ——
    if (r->fade != 0.f || r->whitePoint != 1.f) {
        e = (CINVec3)r->fade + CINClamp01V(e) * (r->whitePoint - r->fade);
    }
    return CINClamp01V(e);
}

CINVec3 CINLutEvaluateNeutral(CINEncoding signal, CINVec3 s) {
    const CINVec3 lin = CINSignalToDisplayLinear(signal, s);
    return CINClamp01V(CINEncodeV(lin, CINEncodingRec709));
}

CINVec3 CINLutEvaluate(CINLook *look, CINEncoding signal, CINVec3 s) {
    const CINVec3 lin = CINSignalToDisplayLinear(signal, s);
    if (look.isCube) {
        CINCubeLut *cube = look.cube;
        if (!cube) return CINClamp01V(CINEncodeV(lin, CINEncodingRec709));
        // 约定：导入的 .cube 吃 Rec.709 显示编码（网上绝大多数创意 LUT 都是 709 → 709）
        return CINClamp01V([cube sample:CINEncodeV(lin, CINEncodingRec709)]);
    }
    CINLookRecipe recipe = look.recipe;
    return CINApplyRecipe(&recipe, lin);
}

static NSData *CINBakeWith(int size, CINVec3 (^f)(CINVec3)) {
    NSMutableData *out = [NSMutableData dataWithLength:(size_t)size * size * size * 4 * sizeof(float)];
    float *p = out.mutableBytes;
    const float inv = 1.f / (float)(size - 1);
    size_t i = 0;
    for (int b = 0; b < size; ++b) {
        for (int g = 0; g < size; ++g) {
            for (int r = 0; r < size; ++r) {
                const CINVec3 c = f(CINVec3Make(r * inv, g * inv, b * inv));
                p[i++] = c.x;
                p[i++] = c.y;
                p[i++] = c.z;
                p[i++] = 1.f;
            }
        }
    }
    return out;
}

NSData *CINLutBake(CINLook *look, CINEncoding signal, int size) {
    if (look.isCube) {
        return CINBakeWith(size, ^CINVec3(CINVec3 s) { return CINLutEvaluate(look, signal, s); });
    }
    // 配方影调：先把配方拷出来，循环里不用每个格点都走一次 ObjC 消息
    CINLookRecipe recipe = look.recipe;
    CINLookRecipe *r = &recipe;
    return CINBakeWith(size, ^CINVec3(CINVec3 s) { return CINApplyRecipe(r, CINSignalToDisplayLinear(signal, s)); });
}

NSData *CINLutBakeNeutral(CINEncoding signal, int size) {
    return CINBakeWith(size, ^CINVec3(CINVec3 s) { return CINLutEvaluateNeutral(signal, s); });
}
