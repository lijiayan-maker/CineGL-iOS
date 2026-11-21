// ---- 波形图：用顶点着色器做「散点」----
// 不传任何顶点数据，drawPrimitives(point, 0, w * h) 画 w*h 个点；
// 每个点用 vertex_id 找到缩小画面里对应的像素，横坐标 = 像素所在列，纵坐标 = 它的亮度。
// 配合加法混合，同一位置落的点越多就越亮——这就是波形示波器。
#include "CINShaderCommon.h"
#include "CINShaderTypes.h"

struct WaveformPoint {
    float4 position [[position]];
    float pointSize [[point_size]];
};

vertex WaveformPoint cin_waveform_vertex(uint vid [[vertex_id]], texture2d<float> source [[texture(0)]],
                                         constant CINWaveformUniforms &u [[buffer(0)]]) {
    const int id = int(vid);
    const uint2 p = uint2(id % u.sourceSize.x, id / u.sourceSize.x);
    const float3 c = source.read(p).rgb;
    const float l = clamp(luma709(c), 0.0, 1.0);
    const float x = (float(p.x) + 0.5) / float(u.sourceSize.x);
    WaveformPoint out;
    out.position = float4(x * 2.0 - 1.0, l * 1.96 - 0.98, 0.0, 1.0);
    out.pointSize = 1.0;
    return out;
}

fragment float4 cin_waveform_fragment(constant CINWaveformUniforms &u [[buffer(0)]]) {
    return float4(u.color, 1.0);
}
