#import "CINCameraState.h"

CINEffects CINEffectsDefault(void) {
    return (CINEffects){10.f, 3.f, 0.f, 3.f, 3.f, 3.f, 0.f};
}

BOOL CINEffectsEqual(CINEffects a, CINEffects b) {
    return a.lookStrength == b.lookStrength && a.halation == b.halation && a.mist == b.mist && a.grain == b.grain &&
           a.grainSize == b.grainSize && a.vignette == b.vignette && a.aberration == b.aberration;
}

CINAssist CINAssistDefault(void) {
    return (CINAssist){true, true, false, false, false};
}

NSString *CINCaptureModeLabelKey(CINCaptureMode m) { return m == CINCaptureModePhoto ? @"mode_photo" : @"mode_video"; }

NSString *CINAspectLabelKey(CINAspectRatio a) {
    switch (a) {
        case CINAspectRatio16x9: return @"aspect_16x9";
        case CINAspectRatio4x3: return @"aspect_4x3";
        case CINAspectRatio1x1: return @"aspect_1x1";
        case CINAspectRatio239x1: return @"aspect_239";
    }
    return @"aspect_16x9";
}

NSString *CINResolutionLabel(CINResolution r) { return r == CINResolutionUHD ? @"4K" : @"1080p"; }

NSString *CINLogModeLabelKey(CINLogMode m) {
    switch (m) {
        case CINLogModeOff: return @"log_off";
        case CINLogModeGpu: return @"log_gpu";
        case CINLogModeIsp: return @"log_isp";
    }
    return @"log_off";
}

NSString *CINToolLabelKey(CINTool t) {
    switch (t) {
        case CINToolFocus: return @"tool_focus";
        case CINToolWB: return @"tool_wb";
        case CINToolISO: return @"tool_iso";
        case CINToolShutter: return @"tool_shutter";
        case CINToolEV: return @"tool_ev";
        case CINToolNone: return @"";
    }
    return @"";
}

NSString *CINCaptureModeName(CINCaptureMode m) { return m == CINCaptureModePhoto ? @"PHOTO" : @"VIDEO"; }

NSString *CINAspectName(CINAspectRatio a) {
    switch (a) {
        case CINAspectRatio16x9: return @"R16x9";
        case CINAspectRatio4x3: return @"R4x3";
        case CINAspectRatio1x1: return @"R1x1";
        case CINAspectRatio239x1: return @"R239";
    }
    return @"R16x9";
}

NSString *CINResolutionName(CINResolution r) { return r == CINResolutionUHD ? @"UHD" : @"FHD"; }

NSString *CINLogModeName(CINLogMode m) {
    switch (m) {
        case CINLogModeOff: return @"OFF";
        case CINLogModeGpu: return @"GPU";
        case CINLogModeIsp: return @"ISP";
    }
    return @"OFF";
}

@implementation CINCameraState

- (instancetype)init {
    if ((self = [super init])) {
        _mode = CINCaptureModeVideo;
        _aspect = CINAspectRatio16x9;
        _resolution = CINResolutionFHD;
        _fps = 30;
        _availableFps = @[@24, @25, @30];
        _logMode = CINLogModeOff;
        _burnIn = YES;
        _lookId = @"teal_orange";
        _looks = @[];
        _lookThumbs = @{};
        _effects = CINEffectsDefault();
        _assist = CINAssistDefault();
        _controls = CINCameraControlsDefault();
        _zoomPresets = @[@1];
        _activeTool = CINToolNone;
        _panel = CINPanelNone;
        _frameWidth = 1080;
        _frameHeight = 1920;
    }
    return self;
}

- (BOOL)logOn {
    return self.logMode != CINLogModeOff;
}

- (CINLookInfo *)currentLook {
    return self.lookIndex >= 0 && self.lookIndex < (NSInteger)self.looks.count ? self.looks[(NSUInteger)self.lookIndex] : nil;
}

- (BOOL)canResetControls {
    return CINCameraControlsHasManual(self.controls) || self.hasFocusPoint;
}

@end
