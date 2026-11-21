// CineGL — 相机页的界面状态（对应安卓 ui/CameraUiState.kt）
//
// 状态只在主线程读写；ViewModel 改完一处就通知界面整体刷新一遍（各控件自己比较，没变就不动）。
#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#import "CINCameraControls.h"
#import "CINCameraSource.h"
#import "CINFrameGeometry.h"
#import "CINLookInfo.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CINCaptureMode) { CINCaptureModePhoto = 0, CINCaptureModeVideo = 1 };
typedef NS_ENUM(NSInteger, CINResolution) { CINResolutionFHD = 0, CINResolutionUHD = 1 };
typedef NS_ENUM(NSInteger, CINLogMode) { CINLogModeOff = 0, CINLogModeGpu = 1, CINLogModeIsp = 2 };
typedef NS_ENUM(NSInteger, CINTool) {
    CINToolNone = -1,
    CINToolFocus = 0,
    CINToolWB = 1,
    CINToolISO = 2,
    CINToolShutter = 3,
    CINToolEV = 4,
};
typedef NS_ENUM(NSInteger, CINPanel) { CINPanelNone = 0, CINPanelLooks = 1, CINPanelSettings = 2 };

/** 所有视觉效果都是 0..10 的连续值。 */
typedef struct {
    float lookStrength;
    float halation;
    float mist;
    float grain;
    float grainSize;
    float vignette;
    float aberration;
} CINEffects;

CINEffects CINEffectsDefault(void);
BOOL CINEffectsEqual(CINEffects a, CINEffects b);

typedef struct {
    bool grid;
    bool level;
    bool zebra;
    bool peaking;
    bool waveform;
} CINAssist;

CINAssist CINAssistDefault(void);

/** 界面文案的键（安卓的 @StringRes）。 */
NSString *CINCaptureModeLabelKey(CINCaptureMode m);
NSString *CINAspectLabelKey(CINAspectRatio a);
NSString *CINResolutionLabel(CINResolution r);
NSString *CINLogModeLabelKey(CINLogMode m);
NSString *CINToolLabelKey(CINTool t);
/** 设置里存的名字（和安卓 SharedPreferences 里存的枚举名一致）。 */
NSString *CINCaptureModeName(CINCaptureMode m);
NSString *CINAspectName(CINAspectRatio a);
NSString *CINResolutionName(CINResolution r);
NSString *CINLogModeName(CINLogMode m);

@interface CINCameraState : NSObject

@property (nonatomic) BOOL cameraPermission;
@property (nonatomic) BOOL micPermission;
@property (nonatomic) CINCaptureMode mode;
@property (nonatomic) BOOL front;
@property (nonatomic) CINAspectRatio aspect;
@property (nonatomic) CINResolution resolution;
@property (nonatomic) int fps;
@property (nonatomic, copy) NSArray<NSNumber *> *availableFps;
@property (nonatomic) BOOL uhdAvailable;
@property (nonatomic) CINLogMode logMode;
@property (nonatomic) BOOL ispLogAvailable;
@property (nonatomic) BOOL burnIn;
@property (nonatomic) BOOL showSignal;
@property (nonatomic, copy) NSString *lookId;
@property (nonatomic) NSInteger lookIndex;
@property (nonatomic, copy) NSArray<CINLookInfo *> *looks;
@property (nonatomic, copy) NSDictionary<NSNumber *, UIImage *> *lookThumbs;
@property (nonatomic) CINEffects effects;
@property (nonatomic) CINAssist assist;
@property (nonatomic) CINCameraControls controls;
@property (nonatomic, strong, nullable) CINCameraCaps *caps;
@property (nonatomic) CINReadout readout;
@property (nonatomic, copy) NSArray<NSNumber *> *zoomPresets;
@property (nonatomic) CINTool activeTool;
@property (nonatomic) CINPanel panel;
@property (nonatomic) int frameWidth;
@property (nonatomic) int frameHeight;
@property (nonatomic) BOOL recording;
@property (nonatomic) CFTimeInterval recordStart;
@property (nonatomic) BOOL busy;
@property (nonatomic, strong, nullable) NSURL *lastURL;
@property (nonatomic) BOOL lastIsVideo;
@property (nonatomic, strong, nullable) UIImage *lastThumb;
@property (nonatomic) int deviceRotation;
@property (nonatomic) BOOL hasFocusPoint;
@property (nonatomic) CGPoint focusPoint;
@property (nonatomic) NSInteger focusEventId;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic) NSInteger messageId;

@property (nonatomic, readonly) BOOL logOn;
@property (nonatomic, readonly, nullable) CINLookInfo *currentLook;
/** 一键重置是否可用：有手动参数，或点击对焦锁定了对焦/测光区域。 */
@property (nonatomic, readonly) BOOL canResetControls;

@end

NS_ASSUME_NONNULL_END
