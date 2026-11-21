// CineGL — 自绘线条图标（24x24 视口，1.7 线宽、圆头圆角），路径和安卓 CineIcons.kt 一字不差
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CINIcon) {
    CINIconTorch,
    CINIconFlip,
    CINIconMore,
    CINIconFocus,
    CINIconWhiteBalance,
    CINIconShutter,
    CINIconExposure,
    CINIconClose,
    CINIconPlus,
    CINIconReset,
};

/** 模板图（跟着 tintColor 变色），size 为点。 */
UIImage *CINIconImage(CINIcon icon, CGFloat size);

/** SVG path 子集（M L H V A Z 及小写相对形式）→ UIBezierPath。暴露出来方便测试。 */
UIBezierPath *CINPathFromSVG(NSString *d);

NS_ASSUME_NONNULL_END
