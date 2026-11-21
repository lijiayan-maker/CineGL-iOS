// ---- 第 1 站「镜头」：取景裁切 + 色散 + 白平衡 + 暗角，输出工作信号 ----
// 相机给的是 YCbCr 双平面（亮度一张、色度一张），YCbCr → RGB 在采样时顺手做掉（安卓那边由驱动在
// samplerExternalOES 里偷偷做）；拍照和模拟器给的是一张普通的 BGRA 纹理。
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

static float3 sampleYCbCr(texture2d<float> luma, texture2d<float> chroma, float4x4 m, float2 uv) {
    const float y = luma.sample(kLinearClamp, uv).r;
    const float2 c = chroma.sample(kLinearClamp, uv).rg;
    return clamp((m * float4(y, c, 1.0)).rgb, 0.0, 1.0);
}

static float3 sampleInput(texture2d<float> luma, texture2d<float> chroma, bool ycbcr, constant CINInputUniforms &u,
                          float2 frameUv) {
    // 相机缓冲 / 照片位图的纹理坐标就是左上原点的图像坐标，不用 tc() 翻转
    const float2 uv = (u.texMatrix * float4(frameUv, 0.0, 1.0)).xy;
    return ycbcr ? sampleYCbCr(luma, chroma, u.ycbcrToRgb, uv) : luma.sample(kLinearClamp, uv).rgb;
}

static float4 lens(texture2d<float> luma, texture2d<float> chroma, bool ycbcr, constant CINInputUniforms &u,
                   float2 frameUv) {
    const float2 p = frameUv - 0.5;
    // 换算成「物理比例」：x 乘上宽高比，这样暗角是圆的，不会被画幅拉成椭圆
    const float2 q = p * float2(u.frameAspect, 1.0);
    const float r = length(q) / length(float2(0.5 * u.frameAspect, 0.5));   // 0 = 中心，1 = 四角

    float3 sig;
    if (u.aberration > 0.0) {
        // 横向色差：不同波长的放大率略有不同，R、B 两个通道沿径向往相反方向错开，越靠边越明显
        const float2 dir = p * r * (u.aberration * 0.012);
        sig.r = sampleInput(luma, chroma, ycbcr, u, frameUv - dir).r;
        sig.g = sampleInput(luma, chroma, ycbcr, u, frameUv).g;
        sig.b = sampleInput(luma, chroma, ycbcr, u, frameUv + dir).b;
    } else {
        sig = sampleInput(luma, chroma, ycbcr, u, frameUv);
    }

    // 白平衡、暗角都是「光量」的乘法，必须在线性空间做
    float3 lin = decodeSignal(sig, u.sourceEncoding) * u.wbGains;

    if (u.vignette > 0.0) {
        // 自然暗角的 cos⁴ 定律：tanθ = r·k，亮度 ∝ cos⁴θ = 1 / (1 + (r·k)²)²
        const float k = 1.4 * u.vignette;
        const float t = 1.0 / (1.0 + r * r * k * k);
        lin *= t * t;
    }
    return float4(encodeSignal(lin, u.workingEncoding), 1.0);
}

fragment float4 cin_input_ycbcr_fragment(QuadOut in [[stage_in]], texture2d<float> luma [[texture(0)]],
                                         texture2d<float> chroma [[texture(1)]],
                                         constant CINInputUniforms &u [[buffer(0)]]) {
    return lens(luma, chroma, true, u, in.frameUv);
}

fragment float4 cin_input_rgba_fragment(QuadOut in [[stage_in]], texture2d<float> rgba [[texture(0)]],
                                        constant CINInputUniforms &u [[buffer(0)]]) {
    return lens(rgba, rgba, false, u, in.frameUv);
}
