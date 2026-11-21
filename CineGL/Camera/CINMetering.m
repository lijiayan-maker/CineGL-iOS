#import "CINMetering.h"

CGPoint CINFrameToBuffer(float frameX, float frameY, CINFrameGeometry geo, int sensorOrientation, BOOL front) {
    const float px = geo.cropX + frameX * geo.cropW;
    const float py = geo.cropY + frameY * geo.cropH;
    const float ux = front ? 1.f - px : px;
    const float uy = py;
    // 直立图像 = 缓冲顺时针转 sensorOrientation 度，反推回缓冲坐标
    switch (((sensorOrientation % 360) + 360) % 360) {
        case 90: return CGPointMake(uy, 1.f - ux);
        case 180: return CGPointMake(1.f - ux, 1.f - uy);
        case 270: return CGPointMake(1.f - uy, ux);
        default: return CGPointMake(ux, uy);
    }
}
