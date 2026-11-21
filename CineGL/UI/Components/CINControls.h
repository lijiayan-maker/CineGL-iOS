// CineGL — 相机页的小控件（对应安卓 ui/components/Controls.kt，尺寸、颜色、字号一一照搬）
#pragma once

#import <UIKit/UIKit.h>

#import "CINAudioCapture.h"
#import "CINIcons.h"
#import "CINSlider.h"
#import "CINSwitch.h"

NS_ASSUME_NONNULL_BEGIN

/** 按下时盖一层淡白色（相当于 Material 的水波纹），形状跟 cornerRadius 走。 */
@interface CINPressableControl : UIControl
@property (nonatomic) CGFloat pressCornerRadius;   // < 0 表示圆形
@property (nonatomic) BOOL showsPress;
@end

/** 顶部「照片 / 视频」文字标签。 */
@interface CINTextTabs : UIView
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);
- (void)setItems:(NSArray<NSString *> *)items selected:(NSInteger)selected enabled:(BOOL)enabled;
@end

/** 左上角的 L/R 电平表：每声道 10 颗点，绿 → 黄 → 红。 */
@interface CINAudioMeterView : UIView
@property (nonatomic) CINAudioLevels levels;
@end

/** 38pt 圆形图标按钮。 */
@interface CINRoundIconButton : CINPressableControl
- (instancetype)initWithIcon:(CINIcon)icon;
@property (nonatomic) BOOL active;
@end

/** 底部工具栏的一项：图标（或文字图标）+ 名称 + 当前值。 */
@interface CINToolButton : CINPressableControl
- (instancetype)initWithIcon:(CINIcon)icon;
- (instancetype)initWithIconText:(NSString *)iconText;
- (void)setLabel:(NSString *)label value:(NSString *)value selected:(BOOL)selected manual:(BOOL)manual;
@end

/** 工具栏末尾的「重置」：有手动参数时可点，都在自动时置灰。 */
@interface CINResetToolButton : CINPressableControl
@property (nonatomic, copy) NSString *label;
@end

/** 刻度盘左边的圆形「自动」按钮。 */
@interface CINAutoButton : CINPressableControl
- (void)setText:(NSString *)text isAuto:(BOOL)isAuto;
@end

/** 快门：拍照是白色实心圆；录像是红色圆，录制中变成圆角方块。 */
@interface CINShutterButton : UIControl
- (void)setVideo:(BOOL)video recording:(BOOL)recording busy:(BOOL)busy;
@end

/** 影调按钮：彩色渐变圈 + 当前影调的实时缩略图；缩略图出来之前显示 badge。 */
@interface CINLookButton : CINPressableControl
- (void)setThumb:(nullable UIImage *)thumb badge:(NSString *)badge;
@end

/** 左下角最近一次拍摄的缩略图。 */
@interface CINGalleryButton : CINPressableControl
@property (nonatomic, strong, nullable) UIImage *thumb;
@end

/** 变焦预设：显示成 35mm 等效焦距。 */
@interface CINZoomPills : UIView
@property (nonatomic, copy, nullable) void (^onSelect)(float zoom);
- (void)setPresets:(NSArray<NSNumber *> *)presets current:(float)current baseFocal:(float)baseFocal;
@end

/** 小角标：实心（18% 底色）或描边。 */
@interface CINInfoChip : UILabel
- (void)setText:(NSString *)text color:(UIColor *)color outlined:(BOOL)outlined;
@end

/** 分段选择（画幅、分辨率、帧率、Log）。 */
@interface CINSegmented : UIView
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index);
- (void)setItems:(NSArray<NSString *> *)items selected:(NSInteger)selected enabled:(nullable NSArray<NSNumber *> *)enabled;
@end

/** 设置里的一行开关：标题 + 小字说明 + 开关。 */
@interface CINSettingSwitchRow : CINPressableControl
@property (nonatomic, copy, nullable) void (^onChange)(BOOL on);
- (void)setTitle:(NSString *)title subtitle:(nullable NSString *)subtitle checked:(BOOL)checked enabled:(BOOL)enabled;
@end

/** 0..10 连续滑杆：左边名称，右边数值。 */
@interface CINLabeledSlider : UIView
@property (nonatomic, copy, nullable) void (^onChange)(float value);
@property (nonatomic) CGFloat labelWidth;
- (void)setLabel:(NSString *)label value:(float)value;
@end

/** 面板标题栏的「重置」：图标 + 文字，都是默认值时置灰。 */
@interface CINResetAction : CINPressableControl
@property (nonatomic, copy) NSString *label;
@end

/** 面板里的滚动视图：按在按钮、开关上也能拖动滚动（和 Compose 的滚动容器一样）。 */
@interface CINScrollView : UIScrollView
@end

/** 小节标题（设置面板）。 */
UILabel *CINSectionTitle(NSString *text);

NS_ASSUME_NONNULL_END
