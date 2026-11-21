// CineGL — 相机页的大脑（对应安卓 ui/CameraViewModel.kt）
//
// 持有相机、渲染器、录音和录像器，把界面操作翻译成它们的调用；状态变了就通知界面刷新。
// 所有公开方法都在主线程调用。
#pragma once

#import <QuartzCore/CAMetalLayer.h>

#import "CINAudioCapture.h"
#import "CINCameraState.h"

NS_ASSUME_NONNULL_BEGIN

@class CINCameraViewModel;

@protocol CINCameraViewModelDelegate <NSObject>
/** 状态变了（同一轮里的多次修改合并成一次）。 */
- (void)viewModelDidChange:(CINCameraViewModel *)viewModel;
/** 电平表（约 20 Hz，单独走，不触发整页刷新）。 */
- (void)viewModel:(CINCameraViewModel *)viewModel audioLevelsDidChange:(CINAudioLevels)levels;
@end

@interface CINCameraViewModel : NSObject

@property (nonatomic, readonly) CINCameraState *state;
@property (nonatomic, weak) id<CINCameraViewModelDelegate> delegate;

/** settings 传 nil 用标准的 NSUserDefaults。 */
- (instancetype)initWithDefaults:(nullable NSUserDefaults *)defaults;

// —— 生命周期 ——
- (void)onPermissionsCamera:(BOOL)camera microphone:(BOOL)microphone;
- (void)onResume;
- (void)onPause;
- (void)attachLayer:(CAMetalLayer *)layer;
- (void)detachLayer;
- (void)setOverlayCornerRadius:(float)radiusPx topInset:(float)topInsetPx;

// —— 拍摄设置 ——
- (void)setMode:(CINCaptureMode)mode;
- (void)flipCamera;
- (void)setAspect:(CINAspectRatio)aspect;
- (void)setResolution:(CINResolution)resolution;
- (void)setFps:(int)fps;
- (void)setLogMode:(CINLogMode)mode;
- (void)setBurnIn:(BOOL)on;
- (void)setShowSignal:(BOOL)on;
- (void)setAssist:(CINAssist)assist;
- (void)onDeviceOrientation:(int)degrees;

// —— 影调 / 效果 ——
- (void)selectLook:(NSInteger)index;
- (void)setEffects:(CINEffects)effects;
/** 影调面板的「重置」：影调强度和胶片效果恢复默认，选中的影调不变。 */
- (void)resetEffects;
- (void)importCubeFromURL:(NSURL *)url;

// —— 面板 / 工具 ——
- (void)toggleTool:(CINTool)tool;
- (void)togglePanel:(CINPanel)panel;
- (void)closePanels;

// —— 手动参数 ——
- (void)updateControls:(CINCameraControls)controls;
/** 从自动切到手动时，用相机当前的实际值做起点，画面不会跳。 */
- (void)setAuto:(CINTool)tool auto:(BOOL)isAuto;
/** 一键重置：对焦、白平衡、ISO、快门、曝光补偿全部回到自动，并取消点击对焦锁定的区域。 */
- (void)resetControls;
- (void)tapToFocusFrameX:(float)x y:(float)y;
- (void)resetFocus;
/** 手动白平衡在 ISP 里做（色温是绝对值）还是在 GPU 里做（相对 5500K）。 */
@property (nonatomic, readonly) BOOL wbOnIsp;

// —— 拍摄 ——
- (void)onShutter;

- (void)toast:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
