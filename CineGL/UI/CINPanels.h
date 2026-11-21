// CineGL — 影调面板、设置面板（对应安卓 ui/Panels.kt）
//
// 两个面板都从底部滑上来，盖在预览区下半部分；圆角 20、半透明深色底。
#pragma once

#import <UIKit/UIKit.h>

#import "CINCameraState.h"

NS_ASSUME_NONNULL_BEGIN

@class CINCameraViewModel;

@interface CINPanelView : UIView
@property (nonatomic, weak) CINCameraViewModel *viewModel;
- (void)render:(CINCameraState *)state;
/** 给定可用的最大高度，面板实际要多高（内容区会跟着缩，不会超出预览区）。 */
- (CGFloat)heightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;
@end

/** 影调面板：实时缩略图选影调 + 影调强度 + 胶片效果。 */
@interface CINLookPanel : CINPanelView
@property (nonatomic, copy, nullable) void (^onImport)(void);
@end

/** 设置面板：画幅、分辨率、帧率、Log、辅助功能。 */
@interface CINSettingsPanel : CINPanelView
@end

NS_ASSUME_NONNULL_END
