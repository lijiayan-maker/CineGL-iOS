// CineGL — 颜色与字体（和安卓 ui/theme/Theme.kt 的 CineColors 一致）
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/** 0xAARRGGBB → UIColor（和 Compose 的 Color(0xAARRGGBB) 写法一致）。 */
UIColor *CINColorARGB(uint32_t argb);

@interface CINColors : NSObject
@property (class, nonatomic, readonly) UIColor *background;
@property (class, nonatomic, readonly) UIColor *panel;
@property (class, nonatomic, readonly) UIColor *surface;
@property (class, nonatomic, readonly) UIColor *surfaceHigh;
@property (class, nonatomic, readonly) UIColor *accent;
@property (class, nonatomic, readonly) UIColor *textPrimary;
@property (class, nonatomic, readonly) UIColor *textSecondary;
@property (class, nonatomic, readonly) UIColor *record;
@property (class, nonatomic, readonly) UIColor *meterGreen;
@property (class, nonatomic, readonly) UIColor *meterYellow;
@property (class, nonatomic, readonly) UIColor *meterRed;
// Material 3 深色主题里开关用到的默认色（安卓没改它们）
@property (class, nonatomic, readonly) UIColor *outline;
@property (class, nonatomic, readonly) UIColor *surfaceContainerHighest;
@end

/** 系统字体。weight 用 UIFontWeight*（安卓的 SemiBold = Semibold，Medium = Medium）。 */
UIFont *CINFont(CGFloat size, UIFontWeight weight);

NS_ASSUME_NONNULL_END
