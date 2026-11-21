#import "CINCubeLut.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

NSString *CINCubeParseErrorDescribe(CINCubeParseError e) {
    NSString *at = [NSString stringWithFormat:@"line %d: ", e.line];
    switch (e.code) {
        case CINCubeErrorNone: return @"ok";
        case CINCubeErrorSizeOutOfRange: return @"LUT_3D_SIZE out of range (2..256)";
        case CINCubeErrorUnsupported1D: return @"1D LUTs are not supported";
        case CINCubeErrorBadDomain: return [at stringByAppendingString:@"DOMAIN needs 3 numbers"];
        case CINCubeErrorBadData: return [at stringByAppendingString:@"expected 3 numbers"];
        case CINCubeErrorDataBeforeSize: return [at stringByAppendingString:@"data before LUT_3D_SIZE"];
        case CINCubeErrorCountMismatch:
            return [NSString stringWithFormat:@"found %d data lines, LUT_3D_SIZE needs %d", e.count, e.expected];
        case CINCubeErrorDomainOrder: return @"DOMAIN_MAX must be greater than DOMAIN_MIN";
        case CINCubeErrorMissingSize: return @"LUT_3D_SIZE is missing";
    }
    return @"unknown error";
}

@implementation CINCubeLut {
    NSMutableData *_data;   // size³ × 3 个 float
}

- (instancetype)initWithTitle:(NSString *)title size:(int)size min:(CINVec3)min max:(CINVec3)max data:(NSMutableData *)data {
    if ((self = [super init])) {
        _title = [title copy];
        _size = size;
        _domainMin = min;
        _domainMax = max;
        _data = data;
    }
    return self;
}

static inline CINVec3 CINCubeAt(const float *d, int size, int r, int g, int b) {
    const float *p = d + ((size_t)(b * size + g) * size + r) * 3;
    return CINVec3Make(p[0], p[1], p[2]);
}

- (CINVec3)atR:(int)r g:(int)g b:(int)b {
    return CINCubeAt(_data.bytes, _size, r, g, b);
}

- (CINVec3)sample:(CINVec3)in {
    const float *d = _data.bytes;
    const int size = _size;
    const CINVec3 range = _domainMax - _domainMin;
    const float n = (float)(size - 1);
    const float fr = CINClamp01((in.x - _domainMin.x) / range.x) * n;
    const float fg = CINClamp01((in.y - _domainMin.y) / range.y) * n;
    const float fb = CINClamp01((in.z - _domainMin.z) / range.z) * n;
    const int r0 = MIN((int)fr, size - 2);
    const int g0 = MIN((int)fg, size - 2);
    const int b0 = MIN((int)fb, size - 2);
    const float tr = fr - r0, tg = fg - g0, tb = fb - b0;

    // 三线性：先沿 R 插 4 次，再沿 G 插 2 次，最后沿 B 插 1 次
    const CINVec3 c00 = CINMixV(CINCubeAt(d, size, r0, g0, b0), CINCubeAt(d, size, r0 + 1, g0, b0), tr);
    const CINVec3 c10 = CINMixV(CINCubeAt(d, size, r0, g0 + 1, b0), CINCubeAt(d, size, r0 + 1, g0 + 1, b0), tr);
    const CINVec3 c01 = CINMixV(CINCubeAt(d, size, r0, g0, b0 + 1), CINCubeAt(d, size, r0 + 1, g0, b0 + 1), tr);
    const CINVec3 c11 = CINMixV(CINCubeAt(d, size, r0, g0 + 1, b0 + 1), CINCubeAt(d, size, r0 + 1, g0 + 1, b0 + 1), tr);
    return CINMixV(CINMixV(c00, c10, tg), CINMixV(c01, c11, tg), tb);
}

#pragma mark - 解析

static void CINSetError(CINCubeParseError *error, CINCubeError code, int line, int count, int expected) {
    if (error) *error = (CINCubeParseError){code, line, count, expected};
}

/** 连续读 n 个浮点数（多出来的忽略）。s 必须以 '\0' 结尾。 */
static BOOL CINParseFloats(const char *s, float *out, int n) {
    const char *p = s;
    for (int i = 0; i < n; ++i) {
        char *end = NULL;
        out[i] = strtof(p, &end);
        if (end == p) return NO;
        p = end;
    }
    return YES;
}

+ (CINCubeLut *)parseText:(NSString *)text error:(CINCubeParseError *)error {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [self parseData:data error:error];
}

+ (CINCubeLut *)parseData:(NSData *)input error:(CINCubeParseError *)error {
    const char *p = input.bytes;
    const char *end = p + input.length;
    NSString *title = @"";
    int size = 0;
    CINVec3 domainMin = CINVec3Make(0.f, 0.f, 0.f);
    CINVec3 domainMax = CINVec3Make(1.f, 1.f, 1.f);
    NSMutableData *data = [NSMutableData data];
    size_t count = 0;

    // 每行拷进一块以 '\0' 结尾的缓冲，strtof 才能安全地用
    size_t bufCap = 256;
    char *buf = malloc(bufCap);
    int lineNo = 0;
    CINCubeLut *result = nil;

    while (p < end) {
        const char *ls = p;
        while (p < end && *p != '\n') ++p;
        const char *le = p;
        if (p < end) ++p;
        ++lineNo;
        while (ls < le && isspace((unsigned char)*ls)) ++ls;
        while (le > ls && isspace((unsigned char)le[-1])) --le;
        if (ls == le || *ls == '#') continue;

        const size_t len = (size_t)(le - ls);
        if (len + 1 > bufCap) {
            bufCap = len + 1;
            buf = realloc(buf, bufCap);
        }
        memcpy(buf, ls, len);
        buf[len] = '\0';

        if (isalpha((unsigned char)buf[0])) {
            size_t k = 0;
            while (k < len && !isspace((unsigned char)buf[k])) ++k;
            char *rest = buf + k;
            while (*rest && isspace((unsigned char)*rest)) ++rest;
            buf[k] = '\0';
            const char *key = buf;
            if (strcmp(key, "TITLE") == 0) {
                size_t rl = strlen(rest);
                if (rl >= 2 && rest[0] == '"' && rest[rl - 1] == '"') {
                    rest[rl - 1] = '\0';
                    ++rest;
                }
                title = [NSString stringWithUTF8String:rest] ?: @"";
            } else if (strcmp(key, "LUT_3D_SIZE") == 0) {
                size = atoi(rest);
                if (size < 2 || size > 256) {
                    CINSetError(error, CINCubeErrorSizeOutOfRange, lineNo, 0, 0);
                    goto done;
                }
                if (count == 0) data = [NSMutableData dataWithCapacity:(size_t)size * size * size * 3 * sizeof(float)];
            } else if (strcmp(key, "LUT_1D_SIZE") == 0) {
                CINSetError(error, CINCubeErrorUnsupported1D, lineNo, 0, 0);
                goto done;
            } else if (strcmp(key, "DOMAIN_MIN") == 0 || strcmp(key, "DOMAIN_MAX") == 0) {
                float v[3];
                if (!CINParseFloats(rest, v, 3)) {
                    CINSetError(error, CINCubeErrorBadDomain, lineNo, 0, 0);
                    goto done;
                }
                if (strcmp(key, "DOMAIN_MIN") == 0) domainMin = CINVec3Make(v[0], v[1], v[2]);
                else domainMax = CINVec3Make(v[0], v[1], v[2]);
            }
            // 其他关键字（LUT_IN_VIDEO_RANGE 等）忽略
            continue;
        }

        float v[3];
        if (!CINParseFloats(buf, v, 3)) {
            CINSetError(error, CINCubeErrorBadData, lineNo, 0, 0);
            goto done;
        }
        if (size == 0) {
            CINSetError(error, CINCubeErrorDataBeforeSize, lineNo, 0, 0);
            goto done;
        }
        [data appendBytes:v length:sizeof(v)];
        ++count;
    }

    if (size == 0) {
        CINSetError(error, CINCubeErrorMissingSize, 0, 0, 0);
        goto done;
    }
    {
        const size_t expected = (size_t)size * size * size;
        if (count != expected) {
            CINSetError(error, CINCubeErrorCountMismatch, 0, (int)count, (int)expected);
            goto done;
        }
        const CINVec3 range = domainMax - domainMin;
        if (range.x <= 0.f || range.y <= 0.f || range.z <= 0.f) {
            CINSetError(error, CINCubeErrorDomainOrder, 0, 0, 0);
            goto done;
        }
        CINSetError(error, CINCubeErrorNone, 0, 0, 0);
        result = [[CINCubeLut alloc] initWithTitle:title size:size min:domainMin max:domainMax data:data];
    }

done:
    free(buf);
    return result;
}

@end
