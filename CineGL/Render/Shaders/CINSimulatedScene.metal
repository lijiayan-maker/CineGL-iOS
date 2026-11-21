// ---- 模拟器的虚拟相机：按真机相机的样子输出「传感器方向」的画面 ----
// 模拟器没有摄像头。为了让整条管线（以及手动参数、录像拍照）能在模拟器上跑，
// 这里画一个会动的场景，输出成和真机一样「横着放、要顺时针转 90 度才正」的缓冲。
// 曝光按 ISO × 快门 线性缩放、超过 1.0 的高光被截掉，和真相机一样会过曝。
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

constexpr sampler kMipSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

static float3 hsv2rgb(float3 c) {
    const float3 k = float3(1.0, 2.0 / 3.0, 1.0 / 3.0);
    const float3 p = abs(fract(c.xxx + k) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

/** 前置：色轮 + 肤色圆 + 色条 + 一个来回跑的方块，全是程序生成的（线性光）。 */
static float3 frontScene(float2 s, float t) {
    float3 c = mix(float3(0.10, 0.07, 0.18), float3(0.05, 0.22, 0.24), s.y);
    const float2 center = float2(0.5, 0.40);
    const float2 d = (s - center) * float2(1.0, 4.0 / 3.0);
    const float r = length(d);
    if (r < 0.30) {
        const float hue = fract(atan2(d.y, d.x) / (2.0 * M_PI_F) + t * 0.03);
        c = srgbToLinear(hsv2rgb(float3(hue, smoothstep(0.0, 0.30, r), 0.95)));
    }
    if (length((s - float2(0.5, 0.40)) * float2(1.0, 4.0 / 3.0)) < 0.09) c = srgbToLinear(float3(0.86, 0.64, 0.52));
    if (s.y > 0.80) {
        const int bar = clamp(int(s.x * 7.0), 0, 6);
        const float3 bars[7] = {float3(0.9), float3(0.9, 0.9, 0.1), float3(0.1, 0.9, 0.9), float3(0.1, 0.9, 0.1),
                                float3(0.9, 0.1, 0.9), float3(0.9, 0.1, 0.1), float3(0.1, 0.1, 0.9)};
        c = srgbToLinear(bars[bar] * (s.y > 0.92 ? 0.35 : 1.0));
    }
    const float2 sq = float2(0.2 + 0.6 * (0.5 + 0.5 * sin(t * 0.9)), 0.70);
    if (all(abs(s - sq) < float2(0.05, 0.0375))) c = float3(1.6);   // 比白还亮：用来看斑马纹和光晕
    return c;
}

fragment float4 cin_sim_scene_fragment(QuadOut in [[stage_in]], texture2d<float> albedo [[texture(0)]],
                                       texture2d<float> emission [[texture(1)]],
                                       constant CINSimSceneUniforms &u [[buffer(0)]]) {
    // 缓冲图像坐标（左上原点）→ 直立画面坐标：直立 = 缓冲顺时针转 90 度，所以 up = (1 - by, bx)
    const float bx = in.frameUv.x, by = 1.0 - in.frameUv.y;
    float2 up = float2(1.0 - by, bx);
    up = 0.5 + (up - 0.5) / u.zoom;
    // 直立画面比场景窄（16:9 的流）时裁掉场景左右两边
    float2 s = up;
    if (u.uprightAspect < u.sceneAspect) s.x = 0.5 + (up.x - 0.5) * u.uprightAspect / u.sceneAspect;
    else s.y = 0.5 + (up.y - 0.5) * u.sceneAspect / u.uprightAspect;

    float3 lin;
    float3 alb;
    if (u.front == 1) {
        lin = frontScene(s, u.time);
        alb = lin;
    } else {
        alb = srgbToLinear(albedo.sample(kMipSampler, s, level(u.blur)).rgb);
        const float em = emission.sample(kMipSampler, s, level(u.blur)).r;
        lin = alb * (0.85 + 6.0 * em);   // 窗户、灯泡这些「自己发光」的地方远远亮过白
        // 显示器里一个来回跑的方块，颜色在红绿之间换
        const float4 m = u.monitorRect;
        const float2 local = (s - m.xy) / (m.zw - m.xy);
        const float2 pos = float2(0.15 + 0.7 * (0.5 + 0.5 * sin(u.time * 0.7)), 0.55 + 0.2 * sin(u.time * 1.3));
        if (all(local > 0.0) && all(local < 1.0) && all(abs(local - pos) < float2(0.09, 0.14))) {
            lin = fract(u.time * 0.1) < 0.5 ? float3(0.9, 0.02, 0.02) : float3(0.02, 0.6, 0.35);
        }
    }
    lin = lin * u.gain + alb * (0.6 * u.torch * u.gain);
    return float4(linearToSrgb(min(lin, 1.0)), 1.0);
}
