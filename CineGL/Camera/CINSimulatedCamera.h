// CineGL — 模拟器里的虚拟相机
//
// 模拟器没有摄像头，安卓模拟器至少还有个 3D 房间（virtualscene）可以拍，iOS 模拟器什么都没有。
// 为了在模拟器上也能把整条管线跑起来、截图、调手动参数，这里按 CINCameraSource 的接口
// 造一台「全手动」的相机：
//   * 后置是一个有窗户、色卡、显示器、绿植和台灯的房间；前置是色轮 + 色条的彩色场景；
//   * 输出和真机一样是传感器方向的横向缓冲，要顺时针转 90 度才正；
//   * ISO、快门、曝光补偿真的改变画面亮度（高光会过曝），手动对焦会失焦，补光会提亮，数码变焦会裁切；
//   * 拍照输出 4032x3024 的 BGRA 缓冲。
// 白平衡不在「ISP」里做（manualPostProcessing = NO），所以手动白平衡走 GPU 兜底那条路。
#pragma once

#import "CINCameraSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINSimulatedCamera : NSObject <CINCameraSource>
@end

NS_ASSUME_NONNULL_END
