// CineGL — 着色器公共函数（只给 .metal 文件 include）
// 信号编码和 Core/CINColor.m 保持完全一致：0 = Rec.709 / sRGB 显示编码，1 = CineLog，2 = Apple Log（只做输入）
#pragma once

#include <metal_stdlib>
using namespace metal;

constant float CINELOG_K = 63.0;
constant float CINELOG_LOG2_RANGE = 7.982993575;   // log2(1 + 63 * 4)

// 采样器：线性插值、边缘夹紧
constexpr sampler kLinearClamp(coord::normalized, address::clamp_to_edge, filter::linear);

/** 全屏四边形的输出。uv：变换后的纹理坐标；frameUv：原始 0..1（左下原点，v 向上）。 */
struct QuadOut {
    float4 position [[position]];
    float2 uv;
    float2 frameUv;
};

/**
 * GL 习惯的 uv（左下原点）→ Metal 纹理坐标（左上原点）。
 * 管线自己画出来的纹理（signal、graded、光晕金字塔……）第 0 行是画面顶部，采样时统一过这一道。
 */
inline float2 tc(float2 uv) {
    return float2(uv.x, 1.0 - uv.y);
}

inline float3 srgbToLinear(float3 c) {
    c = clamp(c, 0.0, 1.0);
    float3 lo = c / 12.92;
    float3 hi = pow((c + 0.055) / 1.055, float3(2.4));
    return select(lo, hi, c >= float3(0.04045));
}

inline float3 linearToSrgb(float3 x) {
    x = max(x, float3(0.0));
    float3 lo = x * 12.92;
    float3 hi = 1.055 * pow(x, float3(1.0 / 2.4)) - 0.055;
    return select(lo, hi, x >= float3(0.0031308));
}

inline float3 cineLogEncode(float3 x) {
    return log2(1.0 + CINELOG_K * max(x, float3(0.0))) / CINELOG_LOG2_RANGE;
}

inline float3 cineLogDecode(float3 y) {
    return (exp2(y * CINELOG_LOG2_RANGE) - 1.0) / CINELOG_K;
}

/** Apple Log → 线性 Rec.2020 → 线性 Rec.709。 */
inline float3 appleLogDecode(float3 y) {
    const float R0 = -0.05641088, Rt = 0.01, C = 47.28711236;
    const float beta = 0.00964052, gamma = 0.08550479, delta = 0.69336945;
    const float pt = C * (Rt - R0) * (Rt - R0);
    float3 hi = exp2((y - delta) / gamma) - beta;
    float3 lo = sqrt(max(y, 0.0) / C) + R0;
    float3 lin2020 = select(lo, hi, y >= float3(pt));
    const float3x3 toRec709 = float3x3(float3(1.6604910, -0.1245505, -0.0181508),
                                       float3(-0.5876411, 1.1328999, -0.1005789),
                                       float3(-0.0728499, -0.0083494, 1.1187297));
    return toRec709 * lin2020;
}

inline float3 decodeSignal(float3 s, int encoding) {
    if (encoding == 1) return cineLogDecode(s);
    if (encoding == 2) return appleLogDecode(s);
    return srgbToLinear(s);
}

inline float3 encodeSignal(float3 x, int encoding) {
    return encoding == 1 ? cineLogEncode(x) : linearToSrgb(x);
}

inline float luma709(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}
