// CineGL — Material 3 风格的连续滑杆（安卓用的是 Compose Material3 Slider，这里照它的尺寸画）
//
// 轨道 16pt 高、两端圆角 8；滑块是 4x44 的竖条，按住时变成 2pt 宽；滑块两侧各留 6pt 空隙；
// 轨道末端有一个 4pt 的「终点」圆点（颜色和已选部分一致）。点哪里跳到哪里，拖动连续变化。
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CINSlider : UIControl
@property (nonatomic) float minimumValue;
@property (nonatomic) float maximumValue;
@property (nonatomic) float value;
@property (nonatomic, strong) UIColor *thumbColor;
@property (nonatomic, strong) UIColor *activeTrackColor;
@property (nonatomic, strong) UIColor *inactiveTrackColor;
/** 拖动中（valueChanged 连续发）。 */
@property (nonatomic, readonly, getter=isDragging) BOOL dragging;
@end

NS_ASSUME_NONNULL_END
