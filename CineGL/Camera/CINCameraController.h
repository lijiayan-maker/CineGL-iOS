// CineGL — AVFoundation 相机（对应安卓 camera/CameraController.kt）
//
// 开相机、按画幅/分辨率/帧率挑格式、按 CINCameraControls 下发参数、拍照。
// 所有 AVCaptureSession 配置都在自己的串行队列上；帧直接投递到渲染队列。
#pragma once

#import "CINCameraSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINCameraController : NSObject <CINCameraSource>
/** 这台设备有没有能用的摄像头（模拟器没有）。 */
+ (BOOL)hasCamera;
@end

NS_ASSUME_NONNULL_END
