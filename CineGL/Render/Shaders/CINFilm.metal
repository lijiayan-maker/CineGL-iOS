// ---- 第 2、3 站「胶片曝光 + 冲洗」：光晕/柔光叠加 → 3D LUT 调色 → 胶片颗粒 ----
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

// 3D LUT 采样：把 [0,1] 映射到「第一个格点中心 .. 最后一个格点中心」，
// 否则硬件插值会在边缘多出半个格子的偏差（经典坑）
static float3 sampleLut(texture3d<float> lut, float size, float3 s) {
    const float3 uvw = clamp(s, 0.0, 1.0) * ((size - 1.0) / size) + 0.5 / size;
    return lut.sample(kLinearClamp, uvw).rgb;
}

// PCG 风格的整数哈希：比 fract(sin(x) * 43758.5) 稳定，不同 GPU 上结果一致
static uint hash3(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v.x ^ v.y ^ v.z;
}

static float random(int2 cell, uint seed) {
    return float(hash3(uint3(uint2(cell + 65536), seed)) & 0xFFFFFFu) / 16777215.0;
}

// 值噪声：格点上放随机数，格子内平滑插值。比逐像素白噪声更像一团一团的银盐颗粒
static float valueNoise(float2 p, uint seed) {
    const float2 i = floor(p);
    const float2 f = fract(p);
    const float2 w = f * f * (3.0 - 2.0 * f);
    const int2 c = int2(i);
    const float a = random(c, seed);
    const float b = random(c + int2(1, 0), seed);
    const float d = random(c + int2(0, 1), seed);
    const float e = random(c + int2(1, 1), seed);
    return mix(mix(a, b, w.x), mix(d, e, w.x), w.y);
}

fragment float4 cin_film_fragment(QuadOut in [[stage_in]],
                                  texture2d<float> input [[texture(0)]],        // 工作信号
                                  texture2d<float> halationTex [[texture(1)]],  // 光晕模糊结果（线性）
                                  texture2d<float> mistTex [[texture(2)]],      // 柔光模糊结果（线性）
                                  texture3d<float> neutralLut [[texture(3)]],   // 中性渲染 LUT
                                  texture3d<float> lookLut [[texture(4)]],      // 影调 LUT
                                  constant CINFilmUniforms &u [[buffer(0)]]) {
    const float2 uv = tc(in.uv);
    float3 sig = input.sample(kLinearClamp, uv).rgb;

    if (u.halationAmount > 0.0 || u.mistAmount > 0.0) {
        // 光是「加」出来的，所以先解码到线性空间再叠加
        float3 lin = decodeSignal(sig, u.workingEncoding);
        if (u.mistAmount > 0.0) {
            // 柔光镜：亮部的光被散射到四周 → 高光外扩、暗部被轻微灌亮、反差下降
            const float3 m = mistTex.sample(kLinearClamp, uv).rgb;
            lin = lin * (1.0 - 0.25 * u.mistAmount) + m * (0.9 * u.mistAmount);
        }
        if (u.halationAmount > 0.0) {
            // 光晕：强光穿透乳剂、被片基反射回来，再次曝光最底下的红色感光层 → 高光边缘一圈红橙
            const float3 h = halationTex.sample(kLinearClamp, uv).rgb;
            const float energy = max(h.r, max(h.g, h.b));
            lin += float3(1.0, 0.28, 0.08) * energy * (2.2 * u.halationAmount);
        }
        sig = encodeSignal(lin, u.workingEncoding);
    }

    float3 color = sampleLut(neutralLut, u.neutralLutSize, sig);
    if (u.lookStrength > 0.0) {
        color = mix(color, sampleLut(lookLut, u.lookLutSize, sig), u.lookStrength);
    }

    if (u.grain > 0.0) {
        const float2 gp = in.uv * u.frameSize / u.grainSize;
        const uint seed = uint(u.seed);
        const float n = valueNoise(gp, seed) * 0.65 + valueNoise(gp * 2.17 + 13.7, seed + 101u) * 0.35 - 0.5;
        const float chroma = valueNoise(gp * 1.31 + 7.1, seed + 211u) - 0.5;
        // 颗粒在中间调最明显，纯黑纯白处几乎看不到（那里的银盐要么全没、要么全满）
        const float l = luma709(color);
        const float w = 0.25 + 3.0 * l * (1.0 - l);
        color += (float3(n) + float3(chroma, -chroma, chroma) * 0.15) * (u.grain * 0.22 * w);
    }

    return float4(clamp(color, 0.0, 1.0), 1.0);
}
