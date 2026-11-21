// ---- 光晕 / 柔光：提取高光 → Dual Kawase 降采样 → 升采样 ----
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

// 第 1 步：从全分辨率工作信号缩小到「短边约 540 像素」的 level 0，同时只保留比阈值亮的部分
fragment float4 cin_glow_prefilter_fragment(QuadOut in [[stage_in]], texture2d<float> input [[texture(0)]],
                                            constant CINPrefilterUniforms &u [[buffer(0)]]) {
    const float2 uv = tc(in.uv);
    const float2 o = u.tapOffset;
    // 4 个双线性采样 ≈ 一个 4x4 的盒式滤波，缩小时不容易闪烁
    float3 c = decodeSignal(input.sample(kLinearClamp, uv + float2(-o.x, -o.y)).rgb, u.workingEncoding)
             + decodeSignal(input.sample(kLinearClamp, uv + float2( o.x, -o.y)).rgb, u.workingEncoding)
             + decodeSignal(input.sample(kLinearClamp, uv + float2(-o.x,  o.y)).rgb, u.workingEncoding)
             + decodeSignal(input.sample(kLinearClamp, uv + float2( o.x,  o.y)).rgb, u.workingEncoding);
    c *= 0.25;

    const float brightness = max(c.r, max(c.g, c.b));
    float soft = clamp(brightness - u.threshold + u.knee, 0.0, 2.0 * u.knee);
    soft = soft * soft / (4.0 * u.knee + 1e-4);
    const float contribution = max(soft, brightness - u.threshold) / max(brightness, 1e-4);
    return float4(c * contribution, 1.0);
}

// Dual Kawase 降采样：每一级尺寸减半，中心权重 4，四个对角各 1。
// 每一级的像素数只有上一级的 1/4，总开销收敛——这就是它在手机上比高斯模糊省得多的原因。
fragment float4 cin_kawase_down_fragment(QuadOut in [[stage_in]], texture2d<float> input [[texture(0)]],
                                         constant CINKawaseUniforms &u [[buffer(0)]]) {
    const float2 uv = tc(in.uv);
    const float2 o = u.halfTexel * u.offset;
    float4 sum = input.sample(kLinearClamp, uv) * 4.0;
    sum += input.sample(kLinearClamp, uv - o);
    sum += input.sample(kLinearClamp, uv + o);
    sum += input.sample(kLinearClamp, uv + float2(o.x, -o.y));
    sum += input.sample(kLinearClamp, uv - float2(o.x, -o.y));
    return sum / 8.0;
}

// Dual Kawase 升采样：8 个采样排成菱形（4 个轴向权重 1，4 个对角权重 2），一级级放大回去
fragment float4 cin_kawase_up_fragment(QuadOut in [[stage_in]], texture2d<float> input [[texture(0)]],
                                       constant CINKawaseUniforms &u [[buffer(0)]]) {
    const float2 uv = tc(in.uv);
    const float2 o = u.halfTexel * u.offset;
    float4 sum = input.sample(kLinearClamp, uv + float2(-o.x * 2.0, 0.0));
    sum += input.sample(kLinearClamp, uv + float2(-o.x, o.y)) * 2.0;
    sum += input.sample(kLinearClamp, uv + float2(0.0, o.y * 2.0));
    sum += input.sample(kLinearClamp, uv + float2(o.x, o.y)) * 2.0;
    sum += input.sample(kLinearClamp, uv + float2(o.x * 2.0, 0.0));
    sum += input.sample(kLinearClamp, uv + float2(o.x, -o.y)) * 2.0;
    sum += input.sample(kLinearClamp, uv + float2(0.0, -o.y * 2.0));
    sum += input.sample(kLinearClamp, uv + float2(-o.x, -o.y)) * 2.0;
    return sum / 12.0;
}
