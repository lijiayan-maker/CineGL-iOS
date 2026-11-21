// CineGL core — 色彩数学（纯 CPU，不依赖 UIKit / Metal，单测直接调）
//
// 整个项目里「信号」有两种编码：
//   Rec709  —— 相机平时直出的显示编码（近似 sRGB 曲线），中灰 18% ≈ 0.46
//   CineLog —— 本项目自定义的 Log 曲线：0 → 0，18% 中灰 → 0.454，100% → 0.752，400% → 1.0
// 另外 iOS 相机还能直接输出 Apple Log（iPhone 15 Pro 起），它只会作为「输入信号」出现，
// 镜头 pass 一进来就把它转成线性 Rec.709，再按管线的工作编码重新编码。
// Metal 着色器里有一份完全一致的实现（Render/Shaders/CINShaderCommon.h），两边必须同步修改。
#pragma once

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

typedef simd_float3 CINVec3;

/** 信号编码。数值和着色器里的 int 一一对应，不要改。 */
typedef NS_ENUM(int, CINEncoding) {
    CINEncodingRec709 = 0,
    CINEncodingCineLog = 1,
    CINEncodingAppleLog = 2,   // 只做输入：Apple Log 曲线 + Rec.2020 原色
};

static const float kCINCineLogK = 63.f;
static const float kCINCineLogMaxLinear = 4.f;   // CineLog 1.0 对应的线性值（比白高 2 档）

static inline float CINClamp01(float v) { return fminf(1.f, fmaxf(0.f, v)); }
static inline CINVec3 CINClamp01V(CINVec3 v) { return simd_clamp(v, (CINVec3)0.f, (CINVec3)1.f); }
static inline CINVec3 CINMaxZero(CINVec3 v) { return simd_max(v, (CINVec3)0.f); }
static inline float CINMix(float a, float b, float t) { return a + (b - a) * t; }
static inline CINVec3 CINMixV(CINVec3 a, CINVec3 b, float t) { return a + (b - a) * t; }
static inline float CINSmoothstep(float e0, float e1, float x) {
    float t = CINClamp01((x - e0) / (e1 - e0));
    return t * t * (3.f - 2.f * t);
}
static inline CINVec3 CINVec3Make(float r, float g, float b) { return simd_make_float3(r, g, b); }

float CINSrgbToLinear(float c);
float CINLinearToSrgb(float x);
float CINCineLogEncode(float x);
float CINCineLogDecode(float y);
/** Apple Log（Apple Log Profile 白皮书里的分段曲线）。 */
float CINAppleLogEncode(float x);
float CINAppleLogDecode(float y);

float CINDecode(float v, CINEncoding e);
float CINEncode(float x, CINEncoding e);
/** 解码到线性 Rec.709（Apple Log 还要从 Rec.2020 原色换到 Rec.709）。 */
CINVec3 CINDecodeV(CINVec3 v, CINEncoding e);
CINVec3 CINEncodeV(CINVec3 x, CINEncoding e);

/** 线性 Rec.2020 → 线性 Rec.709（原色换算，可能出现负值 = 709 色域外）。 */
CINVec3 CINRec2020ToRec709(CINVec3 c);

/** Rec.709 亮度权重（作用在线性值上才是「真亮度」，作用在编码值上是近似的 luma）。 */
static inline float CINLuminance(CINVec3 c) { return 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z; }

/**
 * 高光肩部：x <= start 时原样输出，之后平滑地逼近 1。
 * Log 信号能表示 1.0 以上的线性值（光晕会把高光推上去），显示前用它把超出的部分「压」回来，
 * 而不是一刀切掉——胶片的高光就是这样慢慢饱和的。
 */
float CINHighlightRolloff(float x, float start);

/** HSV（x = h 单位：度，0..360；y = s、z = v 0..1）。 */
CINVec3 CINRgbToHsv(CINVec3 rgb);
CINVec3 CINHsvToRgb(CINVec3 hsv);

/**
 * 白平衡相对增益（线性 RGB，作用在「已按 5500K 平衡过」的画面上）。
 * 用 mired（1e6 / K）差值建模：设成更低的色温 → 补蓝减红，画面变冷，和相机行为一致。
 * tint：-1 偏绿 .. +1 偏品。返回值按亮度归一，调色温不改变整体亮度。
 */
CINVec3 CINWhiteBalanceGains(float kelvin, float tint);

NS_ASSUME_NONNULL_END
