// CineGL — 点击对焦：把「画面上点了哪里」换算成相机缓冲里的归一化坐标。
//
// 一路要撤销的变换（和渲染时正好相反）：
//   画面坐标 → 撤销画幅裁切 → 撤销前置镜像 → 撤销传感器安装角度
// iOS 的 focusPointOfInterest / exposurePointOfInterest 用的正是「传感器方向、未镜像的缓冲坐标」
// （左上 (0,0)、右下 (1,1)），算到这一步就可以直接交给 AVCaptureDevice，不用像 Camera2 那样再换到 active array。
#pragma once

#import <CoreGraphics/CoreGraphics.h>

#import "CINFrameGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/** frameX / frameY：点击点在画面里的归一化坐标（左上原点）。返回缓冲里的归一化坐标。 */
CGPoint CINFrameToBuffer(float frameX, float frameY, CINFrameGeometry geo, int sensorOrientation, BOOL front);

NS_ASSUME_NONNULL_END
