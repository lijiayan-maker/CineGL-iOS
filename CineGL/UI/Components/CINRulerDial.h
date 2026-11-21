// CineGL — 横向刻度盘：左右拖动刻度来调值（像专业相机的拨轮）。对应安卓 RulerDial.kt。
//
// value / range / step 都在同一个「刻度域」里：ISO、快门用 log2 域（每格 1/3 档），色温用开尔文。
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CINRulerDial : UIView

@property (nonatomic) float value;
@property (nonatomic) float minimumValue;
@property (nonatomic) float maximumValue;
@property (nonatomic) float step;
@property (nonatomic) int majorEvery;
@property (nonatomic) BOOL enabled;
/** 刻度盘上方的大字（比如「ISO 400」）。 */
@property (nonatomic, copy) NSString *(^labelForValue)(float value);
/** 主刻度下面的小字，nil 表示不画。 */
@property (nonatomic, copy, nullable) NSString *(^tickLabel)(float value);
/** 拖动时回调（未取整的连续值，调用方自己取整）。 */
@property (nonatomic, copy, nullable) void (^onValueChange)(float value);

/** 重新算标签、重画（value / 区间 / 文案变了之后调）。 */
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
