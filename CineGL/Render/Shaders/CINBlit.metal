// 纯拷贝：配合 texMatrix 完成缩放、旋转、镜像（录像、拍照输出、缩略图源、波形图源）
#include "CINShaderCommon.h"

fragment float4 cin_blit_fragment(QuadOut in [[stage_in]], texture2d<float> input [[texture(0)]]) {
    return float4(input.sample(kLinearClamp, tc(in.uv)).rgb, 1.0);
}
