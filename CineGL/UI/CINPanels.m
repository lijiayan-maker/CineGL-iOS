#import "CINPanels.h"

#import "CINCameraViewModel.h"
#import "CINControls.h"
#import "CINLocalization.h"
#import "CINTheme.h"

static const CGFloat kHeaderHeight = 38;
static const CGFloat kPadH = 16, kPadV = 10;

#pragma mark - 面板骨架

@implementation CINPanelView {
    @protected
    UILabel *_title;
    UILabel *_trailing;
    CINRoundIconButton *_close;
    UIView *_action;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = CINColors.panel;
        self.layer.cornerRadius = 20;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.clipsToBounds = YES;
        _title = [[UILabel alloc] init];
        _title.font = CINFont(16, UIFontWeightSemibold);
        _title.textColor = CINColors.textPrimary;
        _trailing = [[UILabel alloc] init];
        _trailing.font = CINFont(13, UIFontWeightRegular);
        _trailing.textColor = CINColors.textSecondary;
        _close = [[CINRoundIconButton alloc] initWithIcon:CINIconClose];
        _close.accessibilityIdentifier = @"panel.close";
        [_close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_title];
        [self addSubview:_trailing];
        [self addSubview:_close];
    }
    return self;
}

- (void)closeTapped {
    [self.viewModel closePanels];
}

- (void)render:(CINCameraState *)state {
}

- (CGFloat)heightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    return maxHeight;
}

- (void)layoutHeader {
    const CGFloat w = self.bounds.size.width;
    _close.frame = CGRectMake(w - kPadH - 38, kPadV, 38, 38);
    CGFloat right = w - kPadH - 38;
    if (_action) {
        const CGSize s = _action.intrinsicContentSize;
        _action.frame = CGRectMake(right - s.width, kPadV + (kHeaderHeight - s.height) / 2, s.width, s.height);
        right -= s.width;
    }
    const CGSize ts = [_title intrinsicContentSize];
    _title.frame = CGRectMake(kPadH, kPadV + (kHeaderHeight - ts.height) / 2, ceil(ts.width), ts.height);
    const CGSize rs = [_trailing intrinsicContentSize];
    const CGFloat rx = CGRectGetMaxX(_title.frame);
    _trailing.frame = CGRectMake(rx, kPadV + (kHeaderHeight - rs.height) / 2, MAX(0, MIN(ceil(rs.width), right - rx - 4)), rs.height);
}

@end

#pragma mark - 影调卡片

/** 中文界面：大字中文名 + 小字英文名；英文界面：只显示英文名（较长，字号小一档、最多两行）。 */
@interface CINLookCard : CINPressableControl
- (void)setLook:(CINLookInfo *)look zh:(BOOL)zh thumb:(nullable UIImage *)thumb selected:(BOOL)selected;
@end

@implementation CINLookCard {
    UIImageView *_image;
    CAGradientLayer *_shade;
    UILabel *_title;
    UILabel *_subtitle;
    CINInfoChip *_lut;
    BOOL _oneLine;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 88, 124)])) {
        self.pressCornerRadius = 12;
        self.layer.cornerRadius = 12;
        self.clipsToBounds = YES;
        self.backgroundColor = CINColors.surfaceHigh;
        _image = [[UIImageView alloc] initWithFrame:self.bounds];
        _image.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_image];
        _shade = [CAGradientLayer layer];
        _shade.frame = self.bounds;
        _shade.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:0.8].CGColor];
        _shade.locations = @[@0.4, @1.0];
        [self.layer addSublayer:_shade];
        _title = [[UILabel alloc] init];
        _title.textColor = UIColor.whiteColor;
        _subtitle = [[UILabel alloc] init];
        _subtitle.font = CINFont(9, UIFontWeightRegular);
        _subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.7];
        [self addSubview:_title];
        [self addSubview:_subtitle];
        _lut = [[CINInfoChip alloc] init];
        [_lut setText:@"LUT" color:UIColor.whiteColor outlined:NO];
        [self addSubview:_lut];
    }
    return self;
}

- (void)setLook:(CINLookInfo *)look zh:(BOOL)zh thumb:(UIImage *)thumb selected:(BOOL)selected {
    if (_image.image != thumb) _image.image = thumb;
    _oneLine = zh || look.isCube;
    _title.text = [look titleForChinese:zh];
    _title.font = CINFont(_oneLine ? 17 : 14, UIFontWeightBold);
    _title.numberOfLines = _oneLine ? 1 : 2;
    NSString *sub = [look subtitleForChinese:zh] ?: (look.isCube ? CINL(@"look_imported") : nil);
    _subtitle.text = sub;
    _subtitle.hidden = sub == nil;
    _lut.hidden = !look.isCube;
    self.layer.borderWidth = selected ? 2 : 1;
    self.layer.borderColor = (selected ? CINColors.accent : [UIColor colorWithWhite:1 alpha:0.12]).CGColor;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = 88 - 16;
    const CGFloat sh = _subtitle.hidden ? 0 : ceil(_subtitle.font.lineHeight);
    CGFloat th;
    if (_oneLine) {
        th = ceil(_title.font.lineHeight);
    } else {
        // 英文两行时行高 16（安卓 lineHeight = 16.sp）
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.minimumLineHeight = ps.maximumLineHeight = 16;
        ps.lineBreakMode = NSLineBreakByTruncatingTail;
        _title.attributedText = [[NSAttributedString alloc] initWithString:_title.text ?: @""
                                                                 attributes:@{NSFontAttributeName: _title.font, NSParagraphStyleAttributeName: ps,
                                                                              NSForegroundColorAttributeName: UIColor.whiteColor}];
        th = [_title sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height;
    }
    _subtitle.frame = CGRectMake(8, 124 - 8 - sh, w, sh);
    _title.frame = CGRectMake(8, 124 - 8 - sh - th, w, th);
    const CGSize ls = _lut.intrinsicContentSize;
    _lut.frame = CGRectMake(88 - 6 - ls.width, 6, ls.width, ls.height);
}

@end

@interface CINImportCard : CINPressableControl
@end

@implementation CINImportCard

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 88, 124)])) {
        self.pressCornerRadius = 12;
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        UIImageView *plus = [[UIImageView alloc] initWithImage:CINIconImage(CINIconPlus, 26)];
        plus.tintColor = CINColors.textPrimary;
        UILabel *text = [[UILabel alloc] init];
        text.font = CINFont(11, UIFontWeightRegular);
        text.textColor = CINColors.textSecondary;
        text.text = CINL(@"import_cube");
        text.textAlignment = NSTextAlignmentCenter;
        const CGFloat th = ceil(text.font.lineHeight);
        const CGFloat top = (124 - 26 - 6 - th) / 2;
        plus.frame = CGRectMake((88 - 26) / 2, top, 26, 26);
        text.frame = CGRectMake(0, top + 26 + 6, 88, th);
        [self addSubview:plus];
        [self addSubview:text];
    }
    return self;
}

@end

#pragma mark - 影调面板

@implementation CINLookPanel {
    CINResetAction *_reset;
    UIScrollView *_cardsScroll;
    NSMutableArray<CINLookCard *> *_cards;
    CINImportCard *_import;
    UIScrollView *_slidersScroll;
    NSArray<CINLabeledSlider *> *_sliders;
    UIView *_divider;
    NSArray<CINLookInfo *> *_looks;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _title.text = CINL(@"looks");
        _reset = [[CINResetAction alloc] init];
        _reset.label = CINL(@"reset");
        _reset.accessibilityIdentifier = @"looks.reset";
        [_reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        _action = _reset;
        [self addSubview:_reset];

        _cardsScroll = [[CINScrollView alloc] init];
        _cardsScroll.showsHorizontalScrollIndicator = NO;
        _cardsScroll.alwaysBounceHorizontal = YES;
        [self addSubview:_cardsScroll];
        _cards = [NSMutableArray array];
        _import = [[CINImportCard alloc] init];
        [_import addTarget:self action:@selector(importTapped) forControlEvents:UIControlEventTouchUpInside];
        _import.accessibilityIdentifier = @"look.import";
        [_cardsScroll addSubview:_import];

        _slidersScroll = [[CINScrollView alloc] init];
        _slidersScroll.accessibilityIdentifier = @"looks.sliders";
        _slidersScroll.showsVerticalScrollIndicator = NO;
        [self addSubview:_slidersScroll];
        NSMutableArray *sliders = [NSMutableArray array];
        for (int i = 0; i < 7; ++i) {
            CINLabeledSlider *s = [[CINLabeledSlider alloc] init];
            s.tag = i;
            s.accessibilityIdentifier = [NSString stringWithFormat:@"fx.%d", i];
            __weak CINLookPanel *weakSelf = self;
            s.onChange = ^(float v) {
                [weakSelf slider:i changed:v];
            };
            [_slidersScroll addSubview:s];
            [sliders addObject:s];
        }
        _sliders = sliders;
        _divider = [[UIView alloc] init];
        _divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        [_slidersScroll addSubview:_divider];
    }
    return self;
}

- (void)resetTapped {
    [self.viewModel resetEffects];
}

- (void)importTapped {
    if (self.onImport) self.onImport();
}

- (void)slider:(int)index changed:(float)v {
    CINEffects fx = self.viewModel.state.effects;
    switch (index) {
        case 0: fx.lookStrength = v; break;
        case 1: fx.halation = v; break;
        case 2: fx.mist = v; break;
        case 3: fx.grain = v; break;
        case 4: fx.grainSize = v; break;
        case 5: fx.vignette = v; break;
        default: fx.aberration = v; break;
    }
    [self.viewModel setEffects:fx];
}

- (void)cardTapped:(CINLookCard *)card {
    [self.viewModel selectLook:card.tag];
}

- (void)render:(CINCameraState *)s {
    const BOOL zh = CINUIIsChinese();
    CINLookInfo *current = s.currentLook;
    _trailing.text = current ? [NSString stringWithFormat:@"  ·  %@", [current titleForChinese:zh]] : nil;
    _reset.enabled = !CINEffectsEqual(s.effects, CINEffectsDefault());

    while (_cards.count < s.looks.count) {
        CINLookCard *card = [[CINLookCard alloc] init];
        [card addTarget:self action:@selector(cardTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_cardsScroll addSubview:card];
        [_cards addObject:card];
    }
    for (NSUInteger i = 0; i < _cards.count; ++i) {
        CINLookCard *card = _cards[i];
        card.hidden = i >= s.looks.count;
        if (card.hidden) continue;
        CINLookInfo *look = s.looks[i];
        card.tag = look.index;
        card.accessibilityIdentifier = [@"look." stringByAppendingString:look.lookId];
        [card setLook:look zh:zh thumb:s.lookThumbs[@(look.index)] selected:look.index == s.lookIndex];
    }
    _looks = s.looks;

    const CINEffects fx = s.effects;
    NSArray *keys = @[@"fx_look_strength", @"fx_halation", @"fx_mist", @"fx_grain", @"fx_grain_size", @"fx_vignette", @"fx_aberration"];
    const float values[7] = {fx.lookStrength, fx.halation, fx.mist, fx.grain, fx.grainSize, fx.vignette, fx.aberration};
    // 滑杆左侧名称的宽度：英文名（Look strength、Aberration）比中文长
    const CGFloat labelWidth = zh ? 64 : 96;
    for (NSUInteger i = 0; i < 7; ++i) {
        _sliders[i].labelWidth = labelWidth;
        [_sliders[i] setLabel:CINL(keys[i]) value:values[i]];
    }
    [self setNeedsLayout];
}

- (CGFloat)slidersContentHeight {
    return 40 * 7 + 9;   // 7 行滑杆 + 分隔线（上下各 4）
}

- (CGFloat)heightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    const CGFloat natural = kPadV + kHeaderHeight + 6 + 124 + 8 + 260 + kPadV;
    return MIN(natural, maxHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutHeader];
    const CGFloat w = self.bounds.size.width;
    CGFloat y = kPadV + kHeaderHeight + 6;
    _cardsScroll.frame = CGRectMake(kPadH, y, w - 2 * kPadH, 124);
    CGFloat x = 0;
    for (CINLookCard *card in _cards) {
        if (card.hidden) continue;
        card.frame = CGRectMake(x, 0, 88, 124);
        x += 88 + 8;
    }
    _import.frame = CGRectMake(x, 0, 88, 124);
    _cardsScroll.contentSize = CGSizeMake(x + 88, 124);
    y += 124 + 8;
    const CGFloat sh = MAX(0, MIN(260, self.bounds.size.height - y - kPadV));
    _slidersScroll.frame = CGRectMake(kPadH, y, w - 2 * kPadH, sh);
    CGFloat sy = 0;
    for (NSUInteger i = 0; i < _sliders.count; ++i) {
        _sliders[i].frame = CGRectMake(0, sy, w - 2 * kPadH, 40);
        sy += 40;
        if (i == 0) {
            _divider.frame = CGRectMake(0, sy + 4, w - 2 * kPadH, 1);
            sy += 9;
        }
    }
    _slidersScroll.contentSize = CGSizeMake(w - 2 * kPadH, sy);
}

@end

#pragma mark - 设置面板

@implementation CINSettingsPanel {
    UIScrollView *_scroll;
    UILabel *_aspectTitle, *_resTitle, *_logTitle, *_assistTitle;
    CINSegmented *_aspect, *_resolution, *_fps, *_log;
    UILabel *_logDesc;
    CINSettingSwitchRow *_burnIn, *_showSignal, *_grid, *_level, *_zebra, *_peaking, *_waveform, *_stabilization;
    UILabel *_footer;
    BOOL _video;
    NSArray<NSNumber *> *_fpsList;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _title.text = CINL(@"settings");
        _scroll = [[CINScrollView alloc] init];
        _scroll.showsVerticalScrollIndicator = NO;
        [self addSubview:_scroll];
        _aspectTitle = CINSectionTitle(CINL(@"settings_aspect"));
        _resTitle = CINSectionTitle(CINL(@"settings_resolution_fps"));
        _logTitle = CINSectionTitle(CINL(@"settings_log"));
        _assistTitle = CINSectionTitle(CINL(@"settings_assist"));
        _aspect = [[CINSegmented alloc] init];
        _resolution = [[CINSegmented alloc] init];
        _fps = [[CINSegmented alloc] init];
        _log = [[CINSegmented alloc] init];
        _aspect.accessibilityIdentifier = @"aspect";
        _resolution.accessibilityIdentifier = @"resolution";
        _fps.accessibilityIdentifier = @"fps";
        _log.accessibilityIdentifier = @"log";
        _scroll.accessibilityIdentifier = @"settings.scroll";
        _logDesc = [[UILabel alloc] init];
        _logDesc.font = CINFont(11, UIFontWeightRegular);
        _logDesc.textColor = CINColors.textSecondary;
        _logDesc.numberOfLines = 0;
        _burnIn = [[CINSettingSwitchRow alloc] init];
        _showSignal = [[CINSettingSwitchRow alloc] init];
        _grid = [[CINSettingSwitchRow alloc] init];
        _level = [[CINSettingSwitchRow alloc] init];
        _zebra = [[CINSettingSwitchRow alloc] init];
        _peaking = [[CINSettingSwitchRow alloc] init];
        _waveform = [[CINSettingSwitchRow alloc] init];
        _stabilization = [[CINSettingSwitchRow alloc] init];
        NSArray *ids = @[@"burnIn", @"showSignal", @"assist.grid", @"assist.level", @"assist.zebra", @"assist.peaking", @"assist.waveform", @"stabilization"];
        NSArray *rows = @[_burnIn, _showSignal, _grid, _level, _zebra, _peaking, _waveform, _stabilization];
        for (NSUInteger i = 0; i < rows.count; ++i) [rows[i] setAccessibilityIdentifier:ids[i]];
        _footer = [[UILabel alloc] init];
        _footer.font = CINFont(11, UIFontWeightRegular);
        _footer.textColor = [CINColors.textSecondary colorWithAlphaComponent:0.6];
        _footer.numberOfLines = 0;
        _footer.text = CINL(@"settings_footer");
        for (UIView *v in @[_aspectTitle, _aspect, _resTitle, _resolution, _fps, _logTitle, _log, _logDesc, _burnIn, _showSignal,
                            _assistTitle, _grid, _level, _zebra, _peaking, _waveform, _stabilization, _footer]) {
            [_scroll addSubview:v];
        }
        [self wireActions];
    }
    return self;
}

- (void)wireActions {
    __weak CINSettingsPanel *weakSelf = self;
    _aspect.onSelect = ^(NSInteger i) {
        [weakSelf.viewModel setAspect:(CINAspectRatio)i];
    };
    _resolution.onSelect = ^(NSInteger i) {
        [weakSelf.viewModel setResolution:(CINResolution)i];
    };
    _fps.onSelect = ^(NSInteger i) {
        CINSettingsPanel *p = weakSelf;
        if (p && i < (NSInteger)p->_fpsList.count) [p.viewModel setFps:p->_fpsList[(NSUInteger)i].intValue];
    };
    _log.onSelect = ^(NSInteger i) {
        [weakSelf.viewModel setLogMode:(CINLogMode)i];
    };
    _burnIn.onChange = ^(BOOL on) {
        [weakSelf.viewModel setBurnIn:on];
    };
    _showSignal.onChange = ^(BOOL on) {
        [weakSelf.viewModel setShowSignal:on];
    };
    void (^assist)(void (^)(CINAssist *)) = ^(void (^edit)(CINAssist *)) {
        CINCameraViewModel *vm = weakSelf.viewModel;
        CINAssist a = vm.state.assist;
        edit(&a);
        [vm setAssist:a];
    };
    _grid.onChange = ^(BOOL on) {
        assist(^(CINAssist *a) { a->grid = on; });
    };
    _level.onChange = ^(BOOL on) {
        assist(^(CINAssist *a) { a->level = on; });
    };
    _zebra.onChange = ^(BOOL on) {
        assist(^(CINAssist *a) { a->zebra = on; });
    };
    _peaking.onChange = ^(BOOL on) {
        assist(^(CINAssist *a) { a->peaking = on; });
    };
    _waveform.onChange = ^(BOOL on) {
        assist(^(CINAssist *a) { a->waveform = on; });
    };
    _stabilization.onChange = ^(BOOL on) {
        CINCameraViewModel *vm = weakSelf.viewModel;
        CINCameraControls c = vm.state.controls;
        c.stabilization = on;
        [vm updateControls:c];
    };
}

- (void)render:(CINCameraState *)s {
    [_aspect setItems:@[CINL(@"aspect_16x9"), CINL(@"aspect_4x3"), CINL(@"aspect_1x1"), CINL(@"aspect_239")] selected:s.aspect enabled:nil];
    _video = s.mode == CINCaptureModeVideo;
    _resTitle.hidden = _resolution.hidden = _fps.hidden = !_video;
    [_resolution setItems:@[CINResolutionLabel(CINResolutionFHD), CINResolutionLabel(CINResolutionUHD)] selected:s.resolution
                  enabled:@[@YES, @(s.uhdAvailable)]];
    _fpsList = s.availableFps;
    NSMutableArray *fpsLabels = [NSMutableArray array];
    for (NSNumber *f in _fpsList) [fpsLabels addObject:[NSString stringWithFormat:@"%d fps", f.intValue]];
    [_fps setItems:fpsLabels selected:(NSInteger)[_fpsList indexOfObject:@(s.fps)] enabled:nil];
    [_log setItems:@[CINL(@"log_off"), CINL(@"log_gpu"), CINL(@"log_isp")] selected:s.logMode enabled:@[@YES, @YES, @(s.ispLogAvailable)]];
    NSArray *descs = @[@"log_off_desc", @"log_gpu_desc", @"log_isp_desc"];
    _logDesc.text = CINL(descs[(NSUInteger)s.logMode]);
    [_burnIn setTitle:CINL(@"burn_in") subtitle:CINL(@"burn_in_desc") checked:s.burnIn enabled:s.logOn];
    [_showSignal setTitle:CINL(@"show_signal") subtitle:CINL(@"show_signal_desc") checked:s.showSignal enabled:s.logOn];
    [_grid setTitle:CINL(@"assist_grid") subtitle:nil checked:s.assist.grid enabled:YES];
    [_level setTitle:CINL(@"assist_level") subtitle:nil checked:s.assist.level enabled:YES];
    [_zebra setTitle:CINL(@"assist_zebra") subtitle:CINL(@"assist_zebra_desc") checked:s.assist.zebra enabled:YES];
    [_peaking setTitle:CINL(@"assist_peaking") subtitle:CINL(@"assist_peaking_desc") checked:s.assist.peaking enabled:YES];
    [_waveform setTitle:CINL(@"assist_waveform") subtitle:CINL(@"assist_waveform_desc") checked:s.assist.waveform enabled:YES];
    _stabilization.hidden = !s.caps.previewStabilization;
    [_stabilization setTitle:CINL(@"stabilization") subtitle:nil checked:s.controls.stabilization enabled:YES];
    [self setNeedsLayout];
}

- (CGFloat)heightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight {
    return MIN(kPadV + kHeaderHeight + 420 + kPadV, maxHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutHeader];
    const CGFloat w = self.bounds.size.width;
    const CGFloat top = kPadV + kHeaderHeight;
    _scroll.frame = CGRectMake(kPadH, top, w - 2 * kPadH, MAX(0, self.bounds.size.height - top - kPadV));
    const CGFloat cw = w - 2 * kPadH;
    __block CGFloat y = 0;
    void (^title)(UILabel *) = ^(UILabel *l) {
        y += 14;
        const CGFloat h = ceil(l.font.lineHeight);
        l.frame = CGRectMake(0, y, cw, h);
        y += h + 6;
    };
    void (^place)(UIView *) = ^(UIView *v) {
        const CGFloat h = [v sizeThatFits:CGSizeMake(cw, CGFLOAT_MAX)].height;
        v.frame = CGRectMake(0, y, cw, h);
        y += h;
    };
    title(_aspectTitle);
    place(_aspect);
    if (_video) {
        title(_resTitle);
        place(_resolution);
        y += 8;
        place(_fps);
    }
    title(_logTitle);
    place(_log);
    y += 6;
    place(_logDesc);
    place(_burnIn);
    place(_showSignal);
    title(_assistTitle);
    for (CINSettingSwitchRow *row in @[_grid, _level, _zebra, _peaking, _waveform]) place(row);
    if (!_stabilization.hidden) place(_stabilization);
    y += 16;
    const CGFloat fh = [_footer sizeThatFits:CGSizeMake(MIN(cw, 400), CGFLOAT_MAX)].height;
    _footer.frame = CGRectMake(0, y, MIN(cw, 400), fh);
    y += fh + 8;
    _scroll.contentSize = CGSizeMake(cw, y);
}

@end
