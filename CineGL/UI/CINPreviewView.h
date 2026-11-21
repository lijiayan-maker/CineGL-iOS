// CineGL — 预览区：Metal 图层（GPU 画在这里）+ 叠加层（网格、水平仪、对焦框、角标、录制计时、变焦）
//
// 画面框用 CINFitCenter 计算，和 GPU 上屏用的是同一个函数，所以叠加层能严丝合缝地贴着画面。
// 对应安卓 ui/PreviewArea.kt。
#pragma once

#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#import "CINCameraState.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINPreviewView : UIView

@property (nonatomic, readonly) CAMetalLayer *metalLayer;
/** 画面在本视图里的位置（点）。 */
@property (nonatomic, readonly) CGRect frameRect;

@property (nonatomic, copy, nullable) void (^onTap)(CGPoint pointInView);
@property (nonatomic, copy, nullable) void (^onLongPress)(void);
@property (nonatomic, copy, nullable) void (^onPinch)(CGFloat scale);
@property (nonatomic, copy, nullable) void (^onZoomPreset)(float zoom);

- (void)render:(CINCameraState *)state;
/** 设备绕屏幕法线的旋转角（度），竖持端正时为 0。 */
- (void)setRoll:(float)degrees;

@end

NS_ASSUME_NONNULL_END
