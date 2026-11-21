// CineGL core — 影调（Look）定义与注册表
//
// 一个影调 = 一组「配方」参数（曝光、白平衡、饱和、S 曲线、分离色调、色相微调……），
// 或者一张用户导入的 .cube。配方在 CPU 上被「烘焙」成 3D LUT（见 CINLutBaker.h），
// GPU 每个像素只需要查一次表——这就是实时调色的基本套路。
#pragma once

#import "CINColor.h"
#import "CINCubeLut.h"

NS_ASSUME_NONNULL_BEGIN

/** 针对某个色相区间的微调（例如把皮肤推向橙色、把绿色推向橄榄色）。 */
typedef struct {
    float centerDeg;    // 区间中心色相
    float widthDeg;     // 半宽：距离中心超过它就不受影响
    float shiftDeg;     // 色相偏移
    float saturation;   // 饱和度倍数
} CINHueAdjust;

#define CIN_MAX_HUE_ADJUSTS 4

typedef struct {
    // —— 线性空间 ——
    float exposure;      // 档
    float temperature;   // -1 冷 .. +1 暖
    float tint;          // -1 绿 .. +1 品
    float crossTalk;     // 通道串扰 0..1：胶片三层乳剂互相「串色」，让颜色更柔和
    float saturation;
    bool mono;           // 黑白
    CINVec3 monoWeights;

    // —— 显示编码空间（更接近人眼感受）——
    int hueCount;
    CINHueAdjust hues[CIN_MAX_HUE_ADJUSTS];
    float contrast;      // S 曲线斜率（1 = 不变）
    float pivot;         // S 曲线支点
    CINVec3 shadowTint;
    float shadowTintAmount;
    CINVec3 highlightTint;
    float highlightTintAmount;
    float bleach;        // 跳漂（留银）0..1
    float fade;          // 黑位抬升（褪色感）
    float whitePoint;    // 白位
} CINLookRecipe;

/** 什么都不做的配方。 */
CINLookRecipe CINLookRecipeDefault(void);

/** 一个影调。创建后不再修改，可以放心跨线程传。 */
@interface CINLook : NSObject
@property (nonatomic, readonly, copy) NSString *lookId;
@property (nonatomic, readonly, copy) NSString *name;     // 中文名（导入的 LUT 为文件名）
@property (nonatomic, readonly, copy) NSString *nameEn;   // 英文名（导入的 LUT 为 TITLE，可能为空）
@property (nonatomic, readonly) BOOL isCube;
@property (nonatomic, readonly) CINLookRecipe recipe;
@property (nonatomic, readonly, nullable) CINCubeLut *cube;   // isCube 时有效；约定输入为 Rec.709 显示编码
@end

/** 全局影调表：内置影调 + 运行时导入的 .cube。线程安全。 */
@interface CINLookLibrary : NSObject

@property (class, nonatomic, readonly) CINLookLibrary *shared;

- (NSInteger)count;
/** 越界返回 nil。 */
- (nullable CINLook *)lookAtIndex:(NSInteger)index;
- (NSInteger)indexOfId:(NSString *)lookId;
/** 注册（或替换同 id 的）.cube 影调，返回索引。 */
- (NSInteger)addCubeWithId:(NSString *)lookId name:(NSString *)name cube:(CINCubeLut *)cube;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
