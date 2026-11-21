// CineGL — 相机页（对应安卓 ui/CameraScreen.kt）
//
// 从上到下：顶栏（电平表 · 照片/视频 · 补光/翻转/设置）→ 预览区（面板从底部滑上来盖住它）
// → 工具栏（对焦/白平衡/ISO/快门/曝光补偿/重置）→ 刻度盘（选中工具时出现）→ 底栏（相册 · 快门 · 影调）。
#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CINCameraViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
