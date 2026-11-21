#import "CINFrameGeometry.h"

CINMat4 CINMat4Identity(void) {
    CINMat4 r = {{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}};
    return r;
}

CINMat4 CINMat4Affine(float ox, float oy, float ux, float uy, float vx, float vy) {
    // out = o + u_axis * u + v_axis * v，其中 u_axis = f(1,0) - f(0,0)，v_axis = f(0,1) - f(0,0)
    CINMat4 r = CINMat4Identity();
    r.m[0] = ux - ox;
    r.m[1] = uy - oy;
    r.m[4] = vx - ox;
    r.m[5] = vy - oy;
    r.m[12] = ox;
    r.m[13] = oy;
    return r;
}

CINMat4 CINMat4Multiply(CINMat4 a, CINMat4 b) {
    CINMat4 r = {{0}};
    for (int col = 0; col < 4; ++col) {
        for (int row = 0; row < 4; ++row) {
            float s = 0.f;
            for (int k = 0; k < 4; ++k) s += a.m[k * 4 + row] * b.m[col * 4 + k];
            r.m[col * 4 + row] = s;
        }
    }
    return r;
}

void CINMat4Apply(CINMat4 m, float u, float v, float *outU, float *outV) {
    *outU = m.m[0] * u + m.m[4] * v + m.m[12];
    *outV = m.m[1] * u + m.m[5] * v + m.m[13];
}

simd_float4x4 CINMat4ToSimd(CINMat4 m) {
    return (simd_float4x4){{
        {m.m[0], m.m[1], m.m[2], m.m[3]},
        {m.m[4], m.m[5], m.m[6], m.m[7]},
        {m.m[8], m.m[9], m.m[10], m.m[11]},
        {m.m[12], m.m[13], m.m[14], m.m[15]},
    }};
}

static int CINNormalizeDegrees(int deg) {
    deg %= 360;
    if (deg < 0) deg += 360;
    return (deg + 45) / 90 * 90 % 360;   // 吸附到 0/90/180/270
}

/**
 * 「顺时针旋转 deg 度」的逆映射：已知旋转后图像里的点 (x, y)，求它在旋转前图像里的位置。
 * 都是图像坐标（左上原点、归一化）。推导：顺时针转 90° 时，原图左上角 (0,0) 跑到右上角 (1,0)，
 * 原图左下角 (0,1) 跑到左上角 (0,0)，于是 src = (y, 1 - x)。
 */
static void CINUnrotate(int deg, float x, float y, float *sx, float *sy) {
    switch (deg) {
        case 90: *sx = y; *sy = 1.f - x; break;
        case 180: *sx = 1.f - x; *sy = 1.f - y; break;
        case 270: *sx = 1.f - y; *sy = x; break;
        default: *sx = x; *sy = y; break;
    }
}

typedef void (^CINUvMap)(float u, float v, float *outU, float *outV);

static CINMat4 CINAffineFrom(CINUvMap f) {
    float ox, oy, ux, uy, vx, vy;
    f(0.f, 0.f, &ox, &oy);
    f(1.f, 0.f, &ux, &uy);
    f(0.f, 1.f, &vx, &vy);
    return CINMat4Affine(ox, oy, ux, uy, vx, vy);
}

static int CINAlignDown(int v, int align) { return MAX(align, v / align * align); }

float CINAspectLongOverShort(CINAspectRatio a) {
    switch (a) {
        case CINAspectRatio16x9: return 16.f / 9.f;
        case CINAspectRatio4x3: return 4.f / 3.f;
        case CINAspectRatio1x1: return 1.f;
        case CINAspectRatio239x1: return 2.39f;
    }
    return 16.f / 9.f;
}

CINFrameGeometry CINComputeFrame(int bufferWidth, int bufferHeight, int sensorOrientation, CINAspectRatio aspect, int align) {
    const bool swap = CINNormalizeDegrees(sensorOrientation) % 180 == 90;
    // 直立图像尺寸：传感器横放、装成 90/270 度时宽高互换，得到竖直的长方形
    const int uprightW = swap ? bufferHeight : bufferWidth;
    const int uprightH = swap ? bufferWidth : bufferHeight;
    // 画面长边沿手机长轴（竖直）：目标宽高比 = 短 / 长
    const bool portrait = uprightH >= uprightW;
    const float target = portrait ? 1.f / CINAspectLongOverShort(aspect) : CINAspectLongOverShort(aspect);

    CINFrameGeometry g;
    const float current = (float)uprightW / (float)uprightH;
    int w = uprightW, h = uprightH;
    // 比例本来就一样（比如 16:9 的流配 16:9 画幅）就别裁，避免浮点误差 + 对齐白白裁掉 8 个像素
    if (fabsf(current - target) > 1e-3f) {
        if (current > target) {
            w = CINAlignDown((int)lroundf(uprightH * target), align);   // 太宽：裁左右
        } else {
            h = CINAlignDown((int)lroundf(uprightW / target), align);   // 太高：裁上下
        }
    }
    g.frameWidth = w;
    g.frameHeight = h;
    g.cropW = (float)w / (float)uprightW;
    g.cropH = (float)h / (float)uprightH;
    g.cropX = (1.f - g.cropW) * 0.5f;
    g.cropY = (1.f - g.cropH) * 0.5f;
    return g;
}

CINMat4 CINCropMatrix(CINFrameGeometry g) {
    // 图像坐标的 cropY 从上往下量；换成 GL 的 v（从下往上）是 1 - cropY - cropH。居中裁切时两者相等。
    const float v0 = 1.f - g.cropY - g.cropH;
    return CINMat4Affine(g.cropX, v0, g.cropX + g.cropW, v0, g.cropX, v0 + g.cropH);
}

CINMat4 CINStillInputMatrix(int sensorOrientation, bool frontFacing) {
    const int deg = CINNormalizeDegrees(sensorOrientation);
    return CINAffineFrom(^(float u, float v, float *s, float *t) {
        // 画面 uv → 画面图像坐标
        const float px = u, py = 1.f - v;
        // 前置的画面是镜像的，先翻回「真实直立图像」
        const float ux = frontFacing ? 1.f - px : px;
        const float uy = py;
        // 直立图像 = 缓冲顺时针转 deg → 反推缓冲坐标
        float bx, by;
        CINUnrotate(deg, ux, uy, &bx, &by);
        // 缓冲第 0 行在 t = 0，所以 t 直接等于图像坐标 y
        *s = bx;
        *t = by;
    });
}

CINMat4 CINOutputMatrix(int rotationCw, bool unmirror, bool flipY) {
    const int deg = CINNormalizeDegrees(rotationCw);
    return CINAffineFrom(^(float ou, float ov, float *u, float *v) {
        // 输出 uv → 输出图像坐标（flipY 时让图像顶部落在第 0 行）
        const float ox = ou;
        const float oy = flipY ? ov : 1.f - ov;
        // 输出图像 = 去镜像后的画面顺时针转 deg → 反推
        float gx, gy;
        CINUnrotate(deg, ox, oy, &gx, &gy);
        const float fx = unmirror ? 1.f - gx : gx;
        const float fy = gy;
        *u = fx;
        *v = 1.f - fy;
    });
}

int CINUprightRotation(int deviceOrientationDeg) {
    // 设备顺时针转了 d 度（左侧朝上 = 90），画面跟着顺时针歪了 d 度，要逆时针转回来 = 顺时针 360 - d
    return (360 - CINNormalizeDegrees(deviceOrientationDeg)) % 360;
}

CINOutputPlan CINPlanVideoOutput(int frameWidth, int frameHeight, int deviceOrientationDeg) {
    const int upright = CINUprightRotation(deviceOrientationDeg);
    CINOutputPlan p;
    if (upright == 90 || upright == 270) {
        // 横拿手机：直接把画面转正，缓冲本身就是横的，不需要旋转元数据
        p.rotationCw = upright;
        p.orientationHint = 0;
    } else {
        // 竖拿：缓冲仍然做成横的（画面顺时针转 90），再让播放器补转回来
        p.rotationCw = 90;
        p.orientationHint = (upright - 90 + 360) % 360;
    }
    // 旋转 90/270 后宽高互换
    p.width = frameHeight;
    p.height = frameWidth;
    return p;
}

CINOutputPlan CINPlanPhotoOutput(int frameWidth, int frameHeight, int deviceOrientationDeg) {
    CINOutputPlan p;
    p.rotationCw = CINUprightRotation(deviceOrientationDeg);
    const bool swap = p.rotationCw % 180 == 90;
    p.width = swap ? frameHeight : frameWidth;
    p.height = swap ? frameWidth : frameHeight;
    p.orientationHint = 0;
    return p;
}

CINRectF CINFitCenter(float contentW, float contentH, float boxW, float boxH) {
    CINRectF r = {0.f, 0.f, 0.f, 0.f};
    if (contentW <= 0.f || contentH <= 0.f || boxW <= 0.f || boxH <= 0.f) return r;
    const float scale = fminf(boxW / contentW, boxH / contentH);
    r.w = contentW * scale;
    r.h = contentH * scale;
    r.x = (boxW - r.w) * 0.5f;
    r.y = (boxH - r.h) * 0.5f;
    return r;
}
