// ---- 上屏：监看辅助（峰值对焦、斑马纹、波形图）+ 圆角 ----
// 这些只画在屏幕上，不会进入录像和照片。
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

static float lumaAt(texture2d<float> t, float2 uv) {
    return luma709(t.sample(kLinearClamp, tc(uv)).rgb);
}

fragment float4 cin_present_fragment(QuadOut in [[stage_in]], texture2d<float> input [[texture(0)]],
                                     texture2d<float> waveform [[texture(1)]],
                                     constant CINPresentUniforms &u [[buffer(0)]]) {
    const float2 vUv = in.uv;
    float3 c = input.sample(kLinearClamp, tc(vUv)).rgb;
    const float l = luma709(c);

    if (u.peaking == 1) {
        // 峰值对焦：亮度梯度大 = 边缘锐利 = 合焦，叠一层红色
        const float gx = lumaAt(input, vUv + float2(u.texel.x, 0.0)) - lumaAt(input, vUv - float2(u.texel.x, 0.0));
        const float gy = lumaAt(input, vUv + float2(0.0, u.texel.y)) - lumaAt(input, vUv - float2(0.0, u.texel.y));
        const float edge = length(float2(gx, gy));
        c = mix(c, float3(1.0, 0.18, 0.12), smoothstep(0.16, 0.32, edge));
    }

    if (u.zebra == 1 && l >= u.zebraThreshold) {
        // 斑马纹：过曝区域画会移动的斜条纹。Metal 的像素坐标 y 向下，用 x + y 得到和 GL 版 x - y 一样的「/」方向
        const float stripe = step(0.5, fract((in.position.x + in.position.y + u.time * 40.0) / 14.0));
        c = mix(c, float3(stripe), 0.65);
    }

    const float4 wr = u.waveformRect;
    if (wr.z > wr.x) {
        const float2 w = (vUv - wr.xy) / (wr.zw - wr.xy);
        if (w.x >= 0.0 && w.x <= 1.0 && w.y >= 0.0 && w.y <= 1.0) {
            const float3 trace = waveform.sample(kLinearClamp, tc(w)).rgb;
            // 10% / 50% / 90% 三条参考线
            const float px = 1.0 / (wr.w - wr.y) / u.viewport.y;
            float grid = 0.0;
            grid += 1.0 - smoothstep(0.0, px * 1.5, abs(w.y - 0.1));
            grid += 1.0 - smoothstep(0.0, px * 1.5, abs(w.y - 0.5));
            grid += 1.0 - smoothstep(0.0, px * 1.5, abs(w.y - 0.9));
            c = c * 0.3 + trace + float3(grid * 0.18);
        }
    }

    // 圆角：用圆角矩形的有向距离场（SDF），边缘 1 像素做抗锯齿
    const float2 p = vUv * u.viewport;
    const float2 hs = 0.5 * u.viewport;
    const float2 q = abs(p - hs) - (hs - float2(u.cornerRadius));
    const float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.cornerRadius;
    const float alpha = clamp(0.5 - d, 0.0, 1.0);
    return float4(c * alpha, 1.0);
}
