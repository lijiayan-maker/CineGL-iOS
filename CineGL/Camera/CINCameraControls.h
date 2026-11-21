// CineGL — 用户可调的相机参数，以及和平台无关的相机数学（半自动曝光、选流尺寸、变焦预设、格式化……）
// 全是纯函数，单测直接调（对应安卓 camera/CameraControls.kt）。
#pragma once

#import <Foundation/Foundation.h>

#import "CINPassPlan.h"

NS_ASSUME_NONNULL_BEGIN

/** 用户可调的相机参数。每一项都有「自动 / 手动」两种状态。 */
typedef struct {
    bool isoAuto;
    int iso;
    bool shutterAuto;
    int64_t exposureNs;
    int evIndex;
    bool focusAuto;
    float focusDiopters;
    bool wbAuto;
    float kelvin;
    float tint;          // -1..1
    float zoom;
    bool torch;
    bool stabilization;
} CINCameraControls;

CINCameraControls CINCameraControlsDefault(void);
BOOL CINCameraControlsEqual(CINCameraControls a, CINCameraControls b);
static inline BOOL CINCameraControlsExposureAuto(CINCameraControls c) { return c.isoAuto && c.shutterAuto; }
/** 是否有哪一项不在自动。自动白平衡下残留的色温/色调只是下次切手动的起点，不算手动。 */
BOOL CINCameraControlsHasManual(CINCameraControls c);
/** 一键重置：曝光、对焦、白平衡回到自动并恢复初始值；变焦、补光、防抖属于取景和设备状态，保留。 */
CINCameraControls CINCameraControlsResetToAuto(CINCameraControls c);

/** 相机实际在用的参数（自动模式下给 UI 显示）。kelvin 是自动白平衡当前的色温（iOS 能读到；0 = 不知道）。 */
typedef struct {
    int iso;
    int64_t exposureNs;
    float focusDiopters;
    bool afLocked;
    float kelvin;
} CINReadout;

/**
 * 半自动曝光：ISO、快门只有一个是手动时，另一个由「测光值」推出来。
 *
 * iOS 和 Camera2 一样只有「全自动」和「全手动（custom）」两档，没有快门优先/感光度优先。
 * 做法：在自动曝光时记下当时的曝光量 meteredProduct = ISO × 曝光时间（纳秒），
 * 手动改其中一个时保持乘积不变（再叠加曝光补偿），另一个反算出来。
 */
void CINResolveExposure(CINCameraControls c, int isoMin, int isoMax, int64_t exposureMinNs, int64_t exposureMaxNs,
                        double meteredProduct, float evStep, int *outIso, int64_t *outExposureNs);

/**
 * 选相机流尺寸：按宽高比筛一遍（筛不出来就用全部），
 * 短边尽量等于目标（1080 / 2160），找不到就取不超过目标的最大一个，再不行取最小的。
 * 返回下标，空列表返回 -1。
 */
NSInteger CINPickStreamSize(const CINSize *sizes, NSInteger count, float aspect, int targetShort);

/** 拍照尺寸：4:3、不超过约 1300 万像素、长边不超过 4096（GPU 纹理和内存都吃得消）。返回下标。 */
NSInteger CINPickPhotoSize(const CINSize *sizes, NSInteger count);

/** 变焦预设：在支持范围内挑几个常用倍率（显示成等效焦距）。 */
NSArray<NSNumber *> *CINZoomPresets(float lower, float upper);

/** 快门显示：1/50、1/1000、0.5"。 */
NSString *CINFormatShutter(int64_t ns);
NSString *CINFormatEv(float ev);
NSString *CINFormatFocus(float diopters);

/** 设备朝向吸附到 0/90/180/270，带回差，避免在 45° 附近来回跳。degrees < 0（平放）时保持不变。 */
int CINSnapOrientation(int degrees, int current);

NS_ASSUME_NONNULL_END
