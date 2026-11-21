// 全屏四边形：所有「一个像素算一个像素」的 pass 都用它。不需要顶点缓冲，按 vertex_id 生成 4 个角（三角形带）。
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

vertex QuadOut cin_quad_vertex(uint vid [[vertex_id]], constant CINQuadUniforms &u [[buffer(0)]]) {
    const float2 p = float2((vid & 1) ? 1.0 : 0.0, (vid & 2) ? 1.0 : 0.0);
    QuadOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = (u.texMatrix * float4(p, 0.0, 1.0)).xy;   // 变换后的坐标：用来采样输入纹理
    out.frameUv = p;                                   // 原始 0..1 坐标：用来做「和画面位置有关」的计算
    return out;
}
