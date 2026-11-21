#import "CINColor.h"

// log2(1 + 63 * 4) = log2(253)
static float CINCineLogRange(void) {
    static float range = 0.f;
    if (range == 0.f) range = log2f(1.f + kCINCineLogK * kCINCineLogMaxLinear);
    return range;
}

// Apple Log 曲线参数（Apple Log Profile 白皮书）
static const float kALR0 = -0.05641088f;
static const float kALRt = 0.01f;
static const float kALC = 47.28711236f;
static const float kALBeta = 0.00964052f;
static const float kALGamma = 0.08550479f;
static const float kALDelta = 0.69336945f;

float CINSrgbToLinear(float c) {
    c = CINClamp01(c);
    return c <= 0.04045f ? c / 12.92f : powf((c + 0.055f) / 1.055f, 2.4f);
}

float CINLinearToSrgb(float x) {
    x = fmaxf(0.f, x);
    return x <= 0.0031308f ? x * 12.92f : 1.055f * powf(x, 1.f / 2.4f) - 0.055f;
}

float CINCineLogEncode(float x) {
    return log2f(1.f + kCINCineLogK * fmaxf(0.f, x)) / CINCineLogRange();
}

float CINCineLogDecode(float y) {
    return (exp2f(y * CINCineLogRange()) - 1.f) / kCINCineLogK;
}

float CINAppleLogEncode(float x) {
    if (x >= kALRt) return kALGamma * log2f(x + kALBeta) + kALDelta;
    if (x >= kALR0) return kALC * (x - kALR0) * (x - kALR0);
    return 0.f;
}

float CINAppleLogDecode(float y) {
    const float pt = kALC * (kALRt - kALR0) * (kALRt - kALR0);
    if (y >= pt) return exp2f((y - kALDelta) / kALGamma) - kALBeta;
    if (y >= 0.f) return sqrtf(y / kALC) + kALR0;
    return kALR0;
}

float CINDecode(float v, CINEncoding e) {
    switch (e) {
        case CINEncodingCineLog: return CINCineLogDecode(v);
        case CINEncodingAppleLog: return CINAppleLogDecode(v);
        default: return CINSrgbToLinear(v);
    }
}

float CINEncode(float x, CINEncoding e) {
    switch (e) {
        case CINEncodingCineLog: return CINCineLogEncode(x);
        case CINEncodingAppleLog: return CINAppleLogEncode(x);
        default: return CINLinearToSrgb(x);
    }
}

CINVec3 CINRec2020ToRec709(CINVec3 c) {
    return CINVec3Make(1.6604910f * c.x - 0.5876411f * c.y - 0.0728499f * c.z,
                       -0.1245505f * c.x + 1.1328999f * c.y - 0.0083494f * c.z,
                       -0.0181508f * c.x - 0.1005789f * c.y + 1.1187297f * c.z);
}

CINVec3 CINDecodeV(CINVec3 v, CINEncoding e) {
    CINVec3 lin = CINVec3Make(CINDecode(v.x, e), CINDecode(v.y, e), CINDecode(v.z, e));
    return e == CINEncodingAppleLog ? CINRec2020ToRec709(lin) : lin;
}

CINVec3 CINEncodeV(CINVec3 x, CINEncoding e) {
    return CINVec3Make(CINEncode(x.x, e), CINEncode(x.y, e), CINEncode(x.z, e));
}

float CINHighlightRolloff(float x, float start) {
    if (x <= start) return x;
    const float range = 1.f - start;
    // 在 start 处斜率为 1（和直线段平滑衔接），x → ∞ 时趋于 1
    return start + range * (1.f - expf(-(x - start) / range));
}

CINVec3 CINRgbToHsv(CINVec3 c) {
    const float mx = fmaxf(c.x, fmaxf(c.y, c.z));
    const float mn = fminf(c.x, fminf(c.y, c.z));
    const float d = mx - mn;
    float h = 0.f;
    if (d > 1e-6f) {
        if (mx == c.x) {
            h = 60.f * fmodf((c.y - c.z) / d, 6.f);
        } else if (mx == c.y) {
            h = 60.f * ((c.z - c.x) / d + 2.f);
        } else {
            h = 60.f * ((c.x - c.y) / d + 4.f);
        }
    }
    if (h < 0.f) h += 360.f;
    const float s = mx > 1e-6f ? d / mx : 0.f;
    return CINVec3Make(h, s, mx);
}

CINVec3 CINHsvToRgb(CINVec3 hsv) {
    float h = fmodf(hsv.x, 360.f);
    if (h < 0.f) h += 360.f;
    const float s = CINClamp01(hsv.y);
    const float v = hsv.z;
    const float c = v * s;
    const float x = c * (1.f - fabsf(fmodf(h / 60.f, 2.f) - 1.f));
    const float m = v - c;
    CINVec3 rgb;
    if (h < 60.f) rgb = CINVec3Make(c, x, 0.f);
    else if (h < 120.f) rgb = CINVec3Make(x, c, 0.f);
    else if (h < 180.f) rgb = CINVec3Make(0.f, c, x);
    else if (h < 240.f) rgb = CINVec3Make(0.f, x, c);
    else if (h < 300.f) rgb = CINVec3Make(x, 0.f, c);
    else rgb = CINVec3Make(c, 0.f, x);
    return rgb + m;
}

CINVec3 CINWhiteBalanceGains(float kelvin, float tint) {
    kelvin = fminf(15000.f, fmaxf(1500.f, kelvin));
    // 从 3200K 换到 5500K 大约是 +131 mired，相机里红增益约 ×0.65、蓝增益约 ×1.67，
    // 由此得到每 mired 的「档数」：蓝 0.0055，红 -0.0047。
    const float deltaMired = 1e6f / kelvin - 1e6f / 5500.f;
    CINVec3 g = CINVec3Make(exp2f(-0.0047f * deltaMired), exp2f(-0.25f * tint), exp2f(0.0055f * deltaMired));
    return g * (1.f / CINLuminance(g));
}
