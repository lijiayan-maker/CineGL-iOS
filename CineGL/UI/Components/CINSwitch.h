// CineGL — Material 3 风格的开关（安卓 Compose Material3 Switch 的样子）
//
// 轨道 52x32 胶囊形。关：深灰轨道 + 2pt 灰边 + 16pt 灰色小圆；开：强调色轨道 + 24pt 白色大圆。
// 按下时圆点放大到 28pt。触控区域 52x48（Material 的最小点击尺寸）。
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CINSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
