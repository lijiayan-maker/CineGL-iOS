// CineGL core — 把影调「烘焙」成 3D LUT
//
// 输入是管线里的「工作信号」（Rec709 或 CineLog 编码），输出是显示用的 sRGB 编码值。
// 所以同一个影调在 Log 开/关两种模式下要各烘一张表：表里已经包含了「解码 Log」这一步，
// 着色器里只管查表，不关心信号是什么曲线。
#pragma once

#import "CINColor.h"
#import "CINLooks.h"

NS_ASSUME_NONNULL_BEGIN

static const int kCINLutDefaultSize = 33;   // 33³ 是行业常用精度：够细，又只有 3.6 万个格点

/** 中性渲染：只做「解码 → 高光肩部 → sRGB 编码」，不带任何风格。 */
CINVec3 CINLutEvaluateNeutral(CINEncoding signal, CINVec3 signalValue);

/** 完整影调：中性渲染 + 配方（或 .cube）。 */
CINVec3 CINLutEvaluate(CINLook *look, CINEncoding signal, CINVec3 signalValue);

/**
 * 烘焙成 size³ 的 RGBA float 数组（4 * size³ 个 float）。
 * 内存顺序：R 变化最快，其次 G，最后 B——和 Metal 3D 纹理的 (x, y, z) 顺序、.cube 文件顺序都一致。
 */
NSData *CINLutBake(CINLook *look, CINEncoding signal, int size);
NSData *CINLutBakeNeutral(CINEncoding signal, int size);

/** S 曲线（显示编码空间）：端点 0、1 不动，支点处斜率 = contrast。暴露出来方便测试。 */
float CINLutSCurve(float x, float contrast, float pivot);

NS_ASSUME_NONNULL_END
