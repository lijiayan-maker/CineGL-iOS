#import "CINCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <QuickLook/QuickLook.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "CINCameraViewModel.h"
#import "CINControls.h"
#import "CINLocalization.h"
#import "CINPanels.h"
#import "CINPreviewView.h"
#import "CINRulerDial.h"
#import "CINTheme.h"

static const CGFloat kTopBarHeight = 52;
static const CGFloat kBottomBarHeight = 112;

@interface CINCameraViewController () <CINCameraViewModelDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource>
@end

@implementation CINCameraViewController {
    CINCameraViewModel *_vm;
    // 顶栏
    CINAudioMeterView *_meter;
    CINTextTabs *_tabs;
    CINRoundIconButton *_torch, *_flip, *_more;
    // 预览区
    UIView *_previewBox;
    CINPreviewView *_preview;
    UIView *_permission;
    UILabel *_permissionText;
    CINPressableControl *_permissionButton;
    UILabel *_permissionButtonText;
    CINLookPanel *_lookPanel;
    CINSettingsPanel *_settingsPanel;
    CINPanel _shownPanel;
    // 工具栏 + 刻度盘
    NSArray<CINToolButton *> *_tools;
    CINResetToolButton *_resetTool;
    UIView *_dialArea;
    CINAutoButton *_autoButton;
    CINRulerDial *_dial;
    UIView *_tintRow;
    UILabel *_tintLabel, *_tintValue;
    CINSlider *_tintSlider;
    CINTool _dialTool;
    BOOL _dialShown;
    // 底栏
    CINGalleryButton *_gallery;
    CINShutterButton *_shutter;
    CINLookButton *_lookButton;
    // 提示
    UILabel *_toast;
    NSInteger _toastId;
    // 传感器
    CMMotionManager *_motion;
    float _roll;
    BOOL _visible;
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _vm = [[CINCameraViewModel alloc] initWithDefaults:nil];
        _vm.delegate = self;
        _dialTool = CINToolNone;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - 搭界面

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CINColors.background;
    __weak CINCameraViewController *weakSelf = self;

    // —— 顶栏 ——
    _meter = [[CINAudioMeterView alloc] init];
    _meter.isAccessibilityElement = YES;
    _meter.accessibilityIdentifier = @"meter";
    _tabs = [[CINTextTabs alloc] init];
    _tabs.accessibilityIdentifier = @"mode";
    _tabs.onSelect = ^(NSInteger i) {
        CINCameraViewController *vc = weakSelf;
        [vc->_vm setMode:(CINCaptureMode)i];
    };
    _torch = [[CINRoundIconButton alloc] initWithIcon:CINIconTorch];
    [_torch addTarget:self action:@selector(torchTapped) forControlEvents:UIControlEventTouchUpInside];
    _flip = [[CINRoundIconButton alloc] initWithIcon:CINIconFlip];
    [_flip addTarget:self action:@selector(flipTapped) forControlEvents:UIControlEventTouchUpInside];
    _more = [[CINRoundIconButton alloc] initWithIcon:CINIconMore];
    [_more addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    _torch.accessibilityIdentifier = @"torch";
    _flip.accessibilityIdentifier = @"flip";
    _more.accessibilityIdentifier = @"more";
    for (UIView *v in @[_meter, _tabs, _torch, _flip, _more]) [self.view addSubview:v];

    // —— 预览区 ——
    _previewBox = [[UIView alloc] init];
    _previewBox.clipsToBounds = YES;
    [self.view addSubview:_previewBox];
    _preview = [[CINPreviewView alloc] init];
    _preview.onTap = ^(CGPoint p) {
        [weakSelf previewTapped:p];
    };
    _preview.onLongPress = ^{
        CINCameraViewController *vc = weakSelf;
        [vc->_vm resetFocus];
    };
    _preview.onPinch = ^(CGFloat scale) {
        [weakSelf pinched:scale];
    };
    _preview.onZoomPreset = ^(float z) {
        CINCameraViewController *vc = weakSelf;
        CINCameraControls c = vc->_vm.state.controls;
        c.zoom = z;
        [vc->_vm updateControls:c];
    };
    _preview.accessibilityIdentifier = @"preview";
    [_previewBox addSubview:_preview];
    [self buildPermissionHint];
    _lookPanel = [[CINLookPanel alloc] init];
    _lookPanel.viewModel = _vm;
    _lookPanel.onImport = ^{
        [weakSelf openImporter];
    };
    _settingsPanel = [[CINSettingsPanel alloc] init];
    _settingsPanel.viewModel = _vm;
    _lookPanel.hidden = _settingsPanel.hidden = YES;
    [_previewBox addSubview:_lookPanel];
    [_previewBox addSubview:_settingsPanel];

    // —— 工具栏 ——
    NSMutableArray *tools = [NSMutableArray array];
    const CINIcon icons[5] = {CINIconFocus, CINIconWhiteBalance, CINIconFocus, CINIconShutter, CINIconExposure};
    for (NSInteger i = 0; i < 5; ++i) {
        CINToolButton *b = i == CINToolISO ? [[CINToolButton alloc] initWithIconText:CINL(@"tool_iso")]
                                           : [[CINToolButton alloc] initWithIcon:icons[i]];
        b.tag = i;
        b.accessibilityIdentifier = @[@"tool.focus", @"tool.wb", @"tool.iso", @"tool.shutter", @"tool.ev"][(NSUInteger)i];
        [b addTarget:self action:@selector(toolTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        [tools addObject:b];
    }
    _tools = tools;
    _resetTool = [[CINResetToolButton alloc] init];
    _resetTool.label = CINL(@"reset");
    _resetTool.accessibilityIdentifier = @"tool.reset";
    [_resetTool addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_resetTool];
    [self buildDialArea];

    // —— 底栏 ——
    _gallery = [[CINGalleryButton alloc] init];
    [_gallery addTarget:self action:@selector(galleryTapped) forControlEvents:UIControlEventTouchUpInside];
    _shutter = [[CINShutterButton alloc] init];
    [_shutter addTarget:self action:@selector(shutterTapped) forControlEvents:UIControlEventTouchUpInside];
    _lookButton = [[CINLookButton alloc] init];
    [_lookButton addTarget:self action:@selector(lookTapped) forControlEvents:UIControlEventTouchUpInside];
    _gallery.accessibilityIdentifier = @"gallery";
    _shutter.accessibilityIdentifier = @"shutter";
    _lookButton.accessibilityIdentifier = @"looks";
    for (UIView *v in @[_gallery, _shutter, _lookButton]) [self.view addSubview:v];

    // —— 提示 ——
    _toast = [[UILabel alloc] init];
    _toast.font = CINFont(13, UIFontWeightRegular);
    _toast.textColor = UIColor.whiteColor;
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.layer.cornerRadius = 10;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0;
    _toast.numberOfLines = 0;
    [self.view addSubview:_toast];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResign) name:UIApplicationWillResignActiveNotification object:nil];

    [_vm attachLayer:_preview.metalLayer];
    [self render];
}

- (void)buildPermissionHint {
    _permission = [[UIView alloc] init];
    _permissionText = [[UILabel alloc] init];
    _permissionText.font = CINFont(15, UIFontWeightRegular);
    _permissionText.textColor = CINColors.textPrimary;
    _permissionText.text = CINL(@"permission_camera");
    _permissionText.textAlignment = NSTextAlignmentCenter;
    _permissionButton = [[CINPressableControl alloc] init];
    _permissionButton.pressCornerRadius = 8;
    _permissionButtonText = [[UILabel alloc] init];
    _permissionButtonText.font = CINFont(15, UIFontWeightSemibold);
    _permissionButtonText.textColor = CINColors.accent;
    _permissionButtonText.text = CINL(@"permission_grant");
    [_permissionButton addSubview:_permissionButtonText];
    [_permissionButton addTarget:self action:@selector(requestPermissionsAgain) forControlEvents:UIControlEventTouchUpInside];
    [_permission addSubview:_permissionText];
    [_permission addSubview:_permissionButton];
    _permission.hidden = YES;
    [_previewBox addSubview:_permission];
}

- (void)buildDialArea {
    _dialArea = [[UIView alloc] init];
    _dialArea.clipsToBounds = YES;
    _dialArea.alpha = 0;
    [self.view addSubview:_dialArea];
    _autoButton = [[CINAutoButton alloc] init];
    [_autoButton addTarget:self action:@selector(autoTapped) forControlEvents:UIControlEventTouchUpInside];
    _autoButton.accessibilityIdentifier = @"dial.auto";
    _dial = [[CINRulerDial alloc] init];
    _dial.accessibilityIdentifier = @"dial";
    __weak CINCameraViewController *weakSelf = self;
    _dial.onValueChange = ^(float v) {
        [weakSelf dialChanged:v];
    };
    _tintRow = [[UIView alloc] init];
    _tintLabel = [[UILabel alloc] init];
    _tintLabel.font = CINFont(12, UIFontWeightRegular);
    _tintLabel.textColor = CINColors.textSecondary;
    _tintLabel.text = CINL(@"dial_tint");
    _tintSlider = [[CINSlider alloc] init];
    _tintSlider.minimumValue = -10;
    _tintSlider.maximumValue = 10;
    _tintSlider.thumbColor = UIColor.whiteColor;
    _tintSlider.activeTrackColor = CINColorARGB(0xFFD16BA5);
    _tintSlider.inactiveTrackColor = CINColorARGB(0xFF6BD18A);
    [_tintSlider addTarget:self action:@selector(tintChanged) forControlEvents:UIControlEventValueChanged];
    _tintSlider.accessibilityIdentifier = @"dial.tint";
    _tintValue = [[UILabel alloc] init];
    _tintValue.font = CINFont(12, UIFontWeightRegular);
    _tintValue.textColor = CINColors.textSecondary;
    for (UIView *v in @[_tintLabel, _tintSlider, _tintValue]) [_tintRow addSubview:v];
    for (UIView *v in @[_autoButton, _dial, _tintRow]) [_dialArea addSubview:v];
}

#pragma mark - 生命周期

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    [self checkPermissions];
    [_vm onResume];
    [self startMotion];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
}

- (void)appBecameActive {
    if (!self.view.window) return;
    [self checkPermissions];
    [_vm onResume];
    [self startMotion];
}

- (void)appWillResign {
    // 弹出系统权限框、看相册预览时 App 也会「失去活跃」，相机先停，回来再开
    if (self.presentedViewController && ![self.presentedViewController isKindOfClass:[UIAlertController class]]) return;
    [_vm onPause];
    [_motion stopDeviceMotionUpdates];
}

/** 相机必须授权才能取景；麦克风没授权时录像不带声音。 */
- (void)checkPermissions {
    const AVAuthorizationStatus cam = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    const AVAuthorizationStatus mic = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (cam == AVAuthorizationStatusNotDetermined || mic == AVAuthorizationStatusNotDetermined) {
        [self requestPermissions];
        return;
    }
    [_vm onPermissionsCamera:cam == AVAuthorizationStatusAuthorized microphone:mic == AVAuthorizationStatusAuthorized];
}

- (void)requestPermissions {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL camera) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL microphone) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_vm onPermissionsCamera:camera microphone:microphone];
                [self->_vm onResume];
            });
        }];
    }];
}

/** 「授权」：还没问过就问；拒绝过就去系统设置里改。 */
- (void)requestPermissionsAgain {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
        [self requestPermissions];
    } else {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }
}

/** 设备朝向（拍照/录像转正用）和水平仪的倾角，都从重力方向算。 */
- (void)startMotion {
    if (!_motion) {
        _motion = [[CMMotionManager alloc] init];
        _motion.deviceMotionUpdateInterval = 1.0 / 30.0;
    }
    if (!_motion.deviceMotionAvailable || _motion.deviceMotionActive) return;
    __weak CINCameraViewController *weakSelf = self;
    [_motion startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *m, NSError *error) {
        if (m) [weakSelf onGravity:m.gravity];
    }];
}

- (void)onGravity:(CMAcceleration)g {
    // 设备顺时针转了多少度（左侧朝上 = 90）；平放时朝向未知（-1），和安卓 OrientationEventListener 一致
    int degrees = -1;
    if (4 * (g.x * g.x + g.y * g.y) >= g.z * g.z) {
        degrees = (int)lround(atan2(g.x, -g.y) * 180.0 / M_PI);
        degrees = (degrees + 360) % 360;
    }
    [_vm onDeviceOrientation:degrees];
    if (!_vm.state.assist.level) return;
    // 水平仪：绕屏幕法线的旋转角，低通一下免得抖
    const float angle = (float)(atan2(-g.x, -g.y) * 180.0 / M_PI);
    const float delta = fmodf(angle - _roll + 540.f, 360.f) - 180.f;   // 处理 ±180° 处的跳变
    _roll = fmodf(_roll + delta * 0.25f + 540.f, 360.f) - 180.f;
    [_preview setRoll:_roll];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutAll];
}

- (CGFloat)toolRowHeight {
    return _tools.firstObject.intrinsicContentSize.height + 4;
}

- (CGFloat)dialAreaHeight {
    if (_dialTool == CINToolNone) return 0;
    const CGFloat dialH = [_dial sizeThatFits:CGSizeMake(100, 100)].height;
    CGFloat h = 4 + MAX(40, dialH) + 4;
    if (_dialTool == CINToolWB) h += 44;
    return h;
}

- (void)layoutAll {
    const CGRect b = self.view.bounds;
    const UIEdgeInsets safe = self.view.safeAreaInsets;
    const CGFloat w = b.size.width;

    // 顶栏
    const CGFloat top = safe.top;
    const CGSize ms = _meter.intrinsicContentSize;
    _meter.frame = CGRectMake(14, top + (kTopBarHeight - ms.height) / 2, ms.width, ms.height);
    const CGSize ts = _tabs.intrinsicContentSize;
    _tabs.frame = CGRectMake((w - ts.width) / 2, top, ts.width, kTopBarHeight);
    CGFloat right = w - 14;
    for (CINRoundIconButton *btn in @[_more, _flip, _torch]) {
        if (btn.hidden) continue;
        btn.frame = CGRectMake(right - 38, top + (kTopBarHeight - 38) / 2, 38, 38);
        right -= 38;
    }

    // 底栏：两头靠边，中间按 SpaceBetween 平分
    const CGFloat bottom = b.size.height - safe.bottom;
    const CGFloat barTop = bottom - kBottomBarHeight;
    const CGFloat inner = w - 56;
    const CGFloat gap = (inner - 52 - 78 - 56) / 2;
    _gallery.frame = CGRectMake(28, barTop + (kBottomBarHeight - 52) / 2, 52, 52);
    _shutter.frame = CGRectMake(28 + 52 + gap, barTop + (kBottomBarHeight - 78) / 2, 78, 78);
    _lookButton.frame = CGRectMake(w - 28 - 56, barTop + (kBottomBarHeight - 56) / 2, 56, 56);

    // 刻度盘（展开时占位）
    const CGFloat dialH = _dialShown ? [self dialAreaHeight] : 0;
    _dialArea.frame = CGRectMake(0, barTop - dialH, w, dialH);
    [self layoutDialArea];

    // 工具栏：按权重平分宽度（5 个工具各 1 份，重置 0.8 份）
    const CGFloat rowH = [self toolRowHeight];
    const CGFloat rowTop = barTop - dialH - rowH;
    const CGFloat unit = (w - 16) / 5.8;
    for (NSUInteger i = 0; i < _tools.count; ++i) {
        _tools[i].frame = CGRectMake(8 + i * unit, rowTop + 2, unit, rowH - 4);
    }
    _resetTool.frame = CGRectMake(8 + 5 * unit, rowTop + 2, unit * 0.8, rowH - 4);

    // 预览区：顶栏和工具栏之间，左右各留 6
    _previewBox.frame = CGRectMake(0, top + kTopBarHeight, w, MAX(0, rowTop - top - kTopBarHeight));
    const CGRect pb = _previewBox.bounds;
    _preview.frame = CGRectMake(6, 0, pb.size.width - 12, pb.size.height);
    _permission.frame = pb;
    const CGSize pts = [_permissionText sizeThatFits:CGSizeMake(pb.size.width - 32, CGFLOAT_MAX)];
    const CGSize pts2 = [_permissionButtonText intrinsicContentSize];
    const CGSize pbs = CGSizeMake(ceil(pts2.width) + 32, ceil(pts2.height) + 16);
    _permissionButtonText.frame = CGRectMake(16, 8, ceil(pts2.width), ceil(pts2.height));
    const CGFloat ph = pts.height + 12 + pbs.height;
    _permissionText.frame = CGRectMake(16, (pb.size.height - ph) / 2, pb.size.width - 32, pts.height);
    _permissionButton.frame = CGRectMake((pb.size.width - pbs.width) / 2, CGRectGetMaxY(_permissionText.frame) + 12, pbs.width, pbs.height);
    [self layoutPanels];

    // 提示：安卓是离屏幕顶部 96dp（状态栏 + 顶栏下面一点）；iPhone 的安全区高低不一，按「顶栏下方 12」放
    if (_toast.text.length) {
        const CGSize s = [_toast sizeThatFits:CGSizeMake(w - 64 - 28, CGFLOAT_MAX)];
        _toast.frame = CGRectMake((w - s.width - 28) / 2, top + kTopBarHeight + 12, s.width + 28, s.height + 16);
    }

    // 圆角、角标行高度交给 GPU（像素）
    const CGFloat scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    [_vm setOverlayCornerRadius:(float)(16 * scale) topInset:(float)(40 * scale)];
}

- (void)layoutPanels {
    const CGRect pb = _previewBox.bounds;
    for (CINPanelView *panel in @[_lookPanel, _settingsPanel]) {
        const CGFloat h = [panel heightForWidth:pb.size.width maxHeight:pb.size.height];
        const BOOL shown = (panel == _lookPanel && _shownPanel == CINPanelLooks) || (panel == _settingsPanel && _shownPanel == CINPanelSettings);
        panel.frame = CGRectMake(0, shown ? pb.size.height - h : pb.size.height, pb.size.width, h);
    }
}

- (void)layoutDialArea {
    const CGFloat w = _dialArea.bounds.size.width;
    const CGFloat dialH = [_dial sizeThatFits:CGSizeMake(w, 100)].height;
    const CGFloat rowH = MAX(40, dialH);
    _autoButton.frame = CGRectMake(14, 4 + (rowH - 40) / 2, 40, 40);
    _dial.frame = CGRectMake(14 + 40 + 12, 4 + (rowH - dialH) / 2, w - 28 - 52, dialH);
    _tintRow.frame = CGRectMake(14, 4 + rowH, w - 28, 44);
    const CGFloat tw = _tintRow.bounds.size.width;
    _tintLabel.frame = CGRectMake(0, 0, 52, 44);
    _tintSlider.frame = CGRectMake(52, 0, tw - 52 - 40, 44);
    _tintValue.frame = CGRectMake(tw - 40 + 8, 0, 32, 44);
}

#pragma mark - 刷新

- (void)viewModelDidChange:(CINCameraViewModel *)viewModel {
    [self render];
}

- (void)viewModel:(CINCameraViewModel *)viewModel audioLevelsDidChange:(CINAudioLevels)levels {
    _meter.levels = levels;
}

- (void)render {
    CINCameraState *s = _vm.state;
    const BOOL zh = CINUIIsChinese();
    CINCameraCaps *caps = s.caps;

    // 顶栏
    _meter.hidden = !(s.mode == CINCaptureModeVideo && s.micPermission);
    [_tabs setItems:@[CINL(@"mode_photo"), CINL(@"mode_video")] selected:s.mode enabled:!s.recording];
    const BOOL torchWasHidden = _torch.hidden;
    _torch.hidden = !caps.hasFlash;
    _torch.active = s.controls.torch;
    _flip.enabled = !s.recording;
    _more.active = s.panel == CINPanelSettings;
    if (torchWasHidden != _torch.hidden) [self.view setNeedsLayout];

    // 预览区
    _preview.hidden = !s.cameraPermission;
    _permission.hidden = s.cameraPermission;
    [_preview render:s];
    [_lookPanel render:s];
    [_settingsPanel render:s];
    [self showPanel:s.panel];

    // 工具栏
    [self renderTools:s];
    [self renderDial:s];

    // 底栏
    _gallery.thumb = s.lastThumb;
    [_shutter setVideo:s.mode == CINCaptureModeVideo recording:s.recording busy:s.busy];
    CINLookInfo *look = s.currentLook;
    [_lookButton setThumb:look ? s.lookThumbs[@(look.index)] : nil badge:look ? [look badgeForChinese:zh] : CINL(@"looks")];

    [self showToast:s];
}

- (void)renderTools:(CINCameraState *)s {
    const CINCameraControls c = s.controls;
    const CINReadout r = s.readout;
    for (CINToolButton *b in _tools) {
        NSString *value = @"";
        BOOL manual = NO;
        switch ((CINTool)b.tag) {
            case CINToolFocus:
                value = c.focusAuto ? (r.afLocked ? @"AF-L" : @"AF") : CINFormatFocus(c.focusDiopters);
                manual = !c.focusAuto;
                break;
            case CINToolWB:
                value = c.wbAuto ? @"AWB" : [NSString stringWithFormat:@"%ldK", lroundf(c.kelvin)];
                manual = !c.wbAuto;
                break;
            case CINToolISO:
                value = c.isoAuto ? [NSString stringWithFormat:@"A %d", r.iso] : [NSString stringWithFormat:@"%d", c.iso];
                manual = !c.isoAuto;
                break;
            case CINToolShutter:
                value = c.shutterAuto ? [@"A " stringByAppendingString:CINFormatShutter(r.exposureNs)] : CINFormatShutter(c.exposureNs);
                manual = !c.shutterAuto;
                break;
            case CINToolEV:
                value = CINFormatEv(c.evIndex * (s.caps ? s.caps.evStep : 0.f));
                manual = c.evIndex != 0;
                break;
            case CINToolNone:
                break;
        }
        [b setLabel:CINL(CINToolLabelKey((CINTool)b.tag)) value:value selected:s.activeTool == b.tag manual:manual];
    }
    _resetTool.enabled = s.canResetControls;
}

/** 选中某个工具后出现的刻度盘。 */
- (void)renderDial:(CINCameraState *)s {
    CINCameraCaps *caps = s.caps;
    const CINTool tool = caps ? s.activeTool : CINToolNone;
    const BOOL show = tool != CINToolNone;
    if (show) {
        const BOOL toolChanged = tool != _dialTool;
        const BOOL wasWB = _dialTool == CINToolWB;
        _dialTool = tool;
        [self configureDial:tool state:s];
        // 白平衡多一行色调：在工具之间直接切换时高度也要跟着变
        if (toolChanged && _dialShown && wasWB != (tool == CINToolWB)) {
            [UIView animateWithDuration:0.25 animations:^{
                [self layoutAll];
            }];
        }
    }
    if (show != _dialShown) {
        _dialShown = show;
        // 安卓 AnimatedVisibility 默认的「展开 + 淡入」
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self->_dialArea.alpha = show ? 1 : 0;
            [self layoutAll];
        } completion:^(BOOL finished) {
            if (!self->_dialShown) self->_dialTool = CINToolNone;
        }];
    }
}

static NSString *CINIsoLabel(float log2Value) {
    return [NSString stringWithFormat:@"%ld", lroundf(exp2f(log2Value))];
}

- (void)configureDial:(CINTool)tool state:(CINCameraState *)s {
    CINCameraCaps *caps = s.caps;
    const CINCameraControls c = s.controls;
    const CINReadout r = s.readout;
    CINRulerDial *d = _dial;
    _tintRow.hidden = tool != CINToolWB;
    switch (tool) {
        case CINToolISO: {
            const float lo = log2f(caps.isoMin), hi = log2f(caps.isoMax);
            const int iso = c.isoAuto ? (r.iso > 0 ? r.iso : c.iso) : c.iso;
            [_autoButton setText:@"A" isAuto:c.isoAuto];
            _autoButton.enabled = caps.manualSensor;
            d.minimumValue = lo;
            d.maximumValue = hi;
            d.value = fminf(fmaxf(log2f(iso), lo), hi);
            d.step = 1.f / 3.f;
            d.majorEvery = 3;
            d.enabled = caps.manualSensor;
            d.labelForValue = ^NSString *(float v) {
                return [@"ISO " stringByAppendingString:CINIsoLabel(v)];
            };
            d.tickLabel = ^NSString *(float v) {
                return CINIsoLabel(v);
            };
            break;
        }
        case CINToolShutter: {
            const int64_t maxNs = s.mode == CINCaptureModeVideo ? 1000000000LL / s.fps : 66666666LL;
            const float lo = log2f(caps.exposureMinNs / 1e9f), hi = log2f(MIN(caps.exposureMaxNs, maxNs) / 1e9f);
            const int64_t ns = c.shutterAuto ? (r.exposureNs > 0 ? r.exposureNs : c.exposureNs) : c.exposureNs;
            [_autoButton setText:@"A" isAuto:c.shutterAuto];
            _autoButton.enabled = caps.manualSensor;
            d.minimumValue = lo;
            d.maximumValue = hi;
            d.value = fminf(fmaxf(log2f(ns / 1e9f), lo), hi);
            d.step = 1.f / 3.f;
            d.majorEvery = 3;
            d.enabled = caps.manualSensor;
            d.labelForValue = ^NSString *(float v) {
                return [NSString stringWithFormat:CINL(@"dial_shutter"), CINFormatShutter((int64_t)(exp2f(v) * 1e9f))];
            };
            d.tickLabel = ^NSString *(float v) {
                return CINFormatShutter((int64_t)(exp2f(v) * 1e9f));
            };
            break;
        }
        case CINToolEV: {
            const float step = caps.evStep;
            const BOOL enabled = caps.evMax > caps.evMin;
            [_autoButton setText:@"0" isAuto:c.evIndex == 0];
            _autoButton.enabled = enabled;
            d.minimumValue = caps.evMin * step;
            d.maximumValue = caps.evMax * step;
            d.value = c.evIndex * step;
            d.step = step;
            d.majorEvery = MAX(1, (int)lroundf(1.f / step));
            d.enabled = enabled;
            d.labelForValue = ^NSString *(float v) {
                return [NSString stringWithFormat:CINL(@"dial_ev"), CINFormatEv(v)];
            };
            d.tickLabel = ^NSString *(float v) {
                return CINFormatEv(v);
            };
            break;
        }
        case CINToolFocus: {
            const float maxD = fmaxf(caps.minFocusDiopters, 0.1f);
            const float dv = c.focusAuto ? r.focusDiopters : c.focusDiopters;
            const BOOL manualFocus = caps.manualFocus;
            [_autoButton setText:@"A" isAuto:c.focusAuto];
            _autoButton.enabled = manualFocus;
            d.minimumValue = 0;
            d.maximumValue = maxD;
            d.value = fminf(fmaxf(dv, 0.f), maxD);
            d.step = maxD / 40.f;
            d.majorEvery = 10;
            d.enabled = manualFocus;
            d.labelForValue = ^NSString *(float v) {
                return manualFocus ? [NSString stringWithFormat:CINL(@"dial_focus"), CINFormatFocus(v)] : CINL(@"dial_focus_unsupported");
            };
            d.tickLabel = ^NSString *(float v) {
                return CINFormatFocus(v);
            };
            break;
        }
        case CINToolWB: {
            [_autoButton setText:@"A" isAuto:c.wbAuto];
            _autoButton.enabled = YES;
            // 自动白平衡时，能读到相机当前色温（ISP 白平衡）就显示它，拖动从这里起步不会跳
            const float kelvin = c.wbAuto && _vm.wbOnIsp && r.kelvin > 0 ? fminf(10000.f, fmaxf(2000.f, r.kelvin)) : c.kelvin;
            d.minimumValue = 2000;
            d.maximumValue = 10000;
            d.value = kelvin;
            d.step = 100;
            d.majorEvery = 10;
            d.enabled = YES;
            d.labelForValue = ^NSString *(float v) {
                return [NSString stringWithFormat:CINL(@"dial_kelvin"), (int)lroundf(v)];
            };
            d.tickLabel = ^NSString *(float v) {
                return [NSString stringWithFormat:@"%ldk", lroundf(v / 1000.f)];
            };
            if (!_tintSlider.isDragging) _tintSlider.value = c.tint * 10.f;
            _tintValue.text = [NSString stringWithFormat:@"%+.1f", c.tint * 10.f];
            break;
        }
        case CINToolNone:
            break;
    }
    [d refresh];
}

- (void)showPanel:(CINPanel)panel {
    if (panel == _shownPanel) return;
    _shownPanel = panel;
    // 从底部滑上来 + 淡入；收起时滑下去 + 淡出
    if (panel == CINPanelLooks) _lookPanel.hidden = NO;
    if (panel == CINPanelSettings) _settingsPanel.hidden = NO;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self layoutPanels];
        self->_lookPanel.alpha = panel == CINPanelLooks ? 1 : 0;
        self->_settingsPanel.alpha = panel == CINPanelSettings ? 1 : 0;
    } completion:^(BOOL finished) {
        self->_lookPanel.hidden = self->_shownPanel != CINPanelLooks;
        self->_settingsPanel.hidden = self->_shownPanel != CINPanelSettings;
    }];
}

- (void)showToast:(CINCameraState *)s {
    if (s.messageId == _toastId || !s.message) return;
    _toastId = s.messageId;
    const NSInteger myId = _toastId;
    _toast.text = s.message;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.view bringSubviewToFront:_toast];
    [UIView animateWithDuration:0.2 animations:^{
        self->_toast.alpha = 1;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_toastId != myId) return;
        [UIView animateWithDuration:0.2 animations:^{
            self->_toast.alpha = 0;
        }];
    });
}

#pragma mark - 操作

- (void)torchTapped {
    CINCameraControls c = _vm.state.controls;
    c.torch = !c.torch;
    [_vm updateControls:c];
}

- (void)flipTapped {
    [_vm flipCamera];
}

- (void)moreTapped {
    [_vm togglePanel:CINPanelSettings];
}

- (void)lookTapped {
    [_vm togglePanel:CINPanelLooks];
}

- (void)toolTapped:(UIControl *)b {
    [_vm toggleTool:(CINTool)b.tag];
}

- (void)resetTapped {
    [_vm resetControls];
}

- (void)shutterTapped {
    [_vm onShutter];
}

- (void)autoTapped {
    const CINCameraControls c = _vm.state.controls;
    switch (_dialTool) {
        case CINToolISO: [_vm setAuto:CINToolISO auto:!c.isoAuto]; break;
        case CINToolShutter: [_vm setAuto:CINToolShutter auto:!c.shutterAuto]; break;
        case CINToolEV: [_vm setAuto:CINToolEV auto:YES]; break;
        case CINToolFocus: [_vm setAuto:CINToolFocus auto:!c.focusAuto]; break;
        case CINToolWB: [_vm setAuto:CINToolWB auto:!c.wbAuto]; break;
        case CINToolNone: break;
    }
}

- (void)dialChanged:(float)v {
    CINCameraControls c = _vm.state.controls;
    switch (_dialTool) {
        case CINToolISO:
            c.isoAuto = false;
            c.iso = (int)lroundf(exp2f(v));
            break;
        case CINToolShutter:
            c.shutterAuto = false;
            c.exposureNs = llroundf(exp2f(v) * 1e9f);
            break;
        case CINToolEV:
            c.evIndex = (int)lroundf(v / _vm.state.caps.evStep);
            break;
        case CINToolFocus:
            c.focusAuto = false;
            c.focusDiopters = v;
            break;
        case CINToolWB:
            c.wbAuto = false;
            c.kelvin = v;
            break;
        case CINToolNone:
            return;
    }
    [_vm updateControls:c];
}

- (void)tintChanged {
    CINCameraControls c = _vm.state.controls;
    c.wbAuto = false;
    c.tint = _tintSlider.value / 10.f;
    _tintValue.text = [NSString stringWithFormat:@"%+.1f", c.tint * 10.f];
    [_vm updateControls:c];
}

- (void)previewTapped:(CGPoint)p {
    CINCameraState *s = _vm.state;
    if (s.panel != CINPanelNone || s.activeTool != CINToolNone) {
        [_vm closePanels];
        return;
    }
    const CGRect f = _preview.frameRect;
    if (CGRectContainsPoint(f, p)) [_vm tapToFocusFrameX:(float)((p.x - f.origin.x) / f.size.width) y:(float)((p.y - f.origin.y) / f.size.height)];
}

- (void)pinched:(CGFloat)scale {
    CINCameraCaps *caps = _vm.state.caps;
    if (!caps || scale == 1) return;
    CINCameraControls c = _vm.state.controls;
    c.zoom = fminf(fmaxf(c.zoom * (float)scale, caps.zoomMin), caps.zoomMax);
    [_vm updateControls:c];
}

- (void)openImporter {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.firstObject) [_vm importCubeFromURL:urls.firstObject];
}

- (void)galleryTapped {
    if (!_vm.state.lastURL) return;
    if (![QLPreviewController canPreviewItem:_vm.state.lastURL]) {
        [_vm toast:CINL(@"no_viewer_app")];
        return;
    }
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _vm.state.lastURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return _vm.state.lastURL;
}

@end
