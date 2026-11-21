#import "CINCameraControls.h"

CINCameraControls CINCameraControlsDefault(void) {
    CINCameraControls c;
    memset(&c, 0, sizeof(c));
    c.isoAuto = true;
    c.iso = 100;
    c.shutterAuto = true;
    c.exposureNs = 1000000000LL / 50;
    c.focusAuto = true;
    c.wbAuto = true;
    c.kelvin = 5500.f;
    c.zoom = 1.f;
    return c;
}

BOOL CINCameraControlsEqual(CINCameraControls a, CINCameraControls b) {
    return a.isoAuto == b.isoAuto && a.iso == b.iso && a.shutterAuto == b.shutterAuto && a.exposureNs == b.exposureNs &&
           a.evIndex == b.evIndex && a.focusAuto == b.focusAuto && a.focusDiopters == b.focusDiopters && a.wbAuto == b.wbAuto &&
           a.kelvin == b.kelvin && a.tint == b.tint && a.zoom == b.zoom && a.torch == b.torch && a.stabilization == b.stabilization;
}

BOOL CINCameraControlsHasManual(CINCameraControls c) {
    return !c.isoAuto || !c.shutterAuto || c.evIndex != 0 || !c.focusAuto || !c.wbAuto;
}

CINCameraControls CINCameraControlsResetToAuto(CINCameraControls c) {
    CINCameraControls r = CINCameraControlsDefault();
    r.zoom = c.zoom;
    r.torch = c.torch;
    r.stabilization = c.stabilization;
    return r;
}

void CINResolveExposure(CINCameraControls c, int isoMin, int isoMax, int64_t exposureMinNs, int64_t exposureMaxNs,
                        double meteredProduct, float evStep, int *outIso, int64_t *outExposureNs) {
    const double target = meteredProduct * pow(2.0, (double)(c.evIndex * evStep));
    int iso = MIN(MAX(c.iso, isoMin), isoMax);
    int64_t exp = MIN(MAX(c.exposureNs, exposureMinNs), exposureMaxNs);
    if (c.isoAuto && !c.shutterAuto) {
        iso = (int)MIN(MAX(lround(target / (double)exp), (long)isoMin), (long)isoMax);
    } else if (!c.isoAuto && c.shutterAuto) {
        exp = MIN(MAX(llround(target / iso), exposureMinNs), exposureMaxNs);
    }
    *outIso = iso;
    *outExposureNs = exp;
}

static int64_t CINArea(CINSize s) { return (int64_t)s.w * s.h; }

NSInteger CINPickStreamSize(const CINSize *sizes, NSInteger count, float aspect, int targetShort) {
    if (count <= 0) return -1;
    NSMutableArray<NSNumber *> *pool = [NSMutableArray array];
    for (NSInteger i = 0; i < count; ++i) {
        if (fabsf((float)sizes[i].w / (float)sizes[i].h - aspect) < 0.02f) [pool addObject:@(i)];
    }
    if (pool.count == 0) {
        for (NSInteger i = 0; i < count; ++i) [pool addObject:@(i)];
    }
    for (NSNumber *n in pool) {
        const CINSize s = sizes[n.integerValue];
        if (MIN(s.w, s.h) == targetShort) return n.integerValue;
    }
    NSInteger best = -1;
    for (NSNumber *n in pool) {
        const CINSize s = sizes[n.integerValue];
        if (MIN(s.w, s.h) <= targetShort && (best < 0 || CINArea(s) > CINArea(sizes[best]))) best = n.integerValue;
    }
    if (best >= 0) return best;
    for (NSNumber *n in pool) {
        if (best < 0 || CINArea(sizes[n.integerValue]) < CINArea(sizes[best])) best = n.integerValue;
    }
    return best;
}

NSInteger CINPickPhotoSize(const CINSize *sizes, NSInteger count) {
    NSInteger best = -1;
    for (NSInteger i = 0; i < count; ++i) {
        const CINSize s = sizes[i];
        const BOOL fit = fabsf((float)s.w / (float)s.h - 4.f / 3.f) < 0.02f && CINArea(s) <= 13000000LL && MAX(s.w, s.h) <= 4096;
        if (fit && (best < 0 || CINArea(s) > CINArea(sizes[best]))) best = i;
    }
    if (best >= 0) return best;
    for (NSInteger i = 0; i < count; ++i) {
        if (best < 0 || llabs(CINArea(sizes[i]) - 12000000LL) < llabs(CINArea(sizes[best]) - 12000000LL)) best = i;
    }
    return best;
}

NSArray<NSNumber *> *CINZoomPresets(float lower, float upper) {
    const float candidates[] = {lower, 1.f, 2.f, 3.f, 5.f};
    NSMutableOrderedSet<NSNumber *> *set = [NSMutableOrderedSet orderedSet];
    for (int i = 0; i < 5; ++i) {
        const float z = candidates[i];
        if (z >= lower - 1e-3f && z <= upper + 1e-3f) [set addObject:@(roundf(z * 10.f) / 10.f)];
    }
    return [set.array sortedArrayUsingSelector:@selector(compare:)];
}

NSString *CINFormatShutter(int64_t ns) {
    if (ns <= 0) return @"--";
    const double seconds = (double)ns / 1e9;
    if (seconds >= 0.5) return [NSString stringWithFormat:@"%.1f\"", seconds];
    return [NSString stringWithFormat:@"1/%ld", lround(1.0 / seconds)];
}

NSString *CINFormatEv(float ev) {
    if (fabsf(ev) < 0.05f) return @"±0";
    if (ev > 0) return [NSString stringWithFormat:@"+%.1f", ev];
    return [NSString stringWithFormat:@"%.1f", ev];
}

NSString *CINFormatFocus(float diopters) {
    if (diopters < 0.01f) return @"∞";
    return [NSString stringWithFormat:@"%.2fm", 1.f / diopters];
}

int CINSnapOrientation(int degrees, int current) {
    if (degrees < 0) return current;
    const int diff = abs(((degrees - current + 540) % 360) - 180);
    if (diff < 55) return current;
    return ((degrees + 45) / 90 * 90) % 360;
}
