#import "CINPreviewView.h"

#import "CINControls.h"
#import "CINLocalization.h"
#import "CINTheme.h"

/** Metal 图层的宿主。 */
@interface CINMetalView : UIView
@end
@implementation CINMetalView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

/** 网格 + 水平仪。 */
@interface CINGuideOverlay : UIView
@property (nonatomic) CGRect frameRect;
@property (nonatomic) BOOL grid;
@property (nonatomic) BOOL level;
@property (nonatomic) float roll;
@end

@implementation CINGuideOverlay

- (void)drawRect:(CGRect)rect {
    const CGRect f = self.frameRect;
    if (f.size.width <= 0) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    const CGFloat px = 1.0 / self.window.screen.scale;
    if (self.grid) {
        [[UIColor colorWithWhite:1 alpha:0.28] setStroke];
        CGContextSetLineWidth(ctx, px);
        for (int i = 1; i <= 2; ++i) {
            const CGFloat x = f.origin.x + f.size.width * i / 3.0;
            const CGFloat y = f.origin.y + f.size.height * i / 3.0;
            CGContextMoveToPoint(ctx, x, CGRectGetMinY(f));
            CGContextAddLineToPoint(ctx, x, CGRectGetMaxY(f));
            CGContextMoveToPoint(ctx, CGRectGetMinX(f), y);
            CGContextAddLineToPoint(ctx, CGRectGetMaxX(f), y);
        }
        CGContextStrokePath(ctx);
    }
    if (self.level) {
        // 水平仪：中间那条线始终和真实世界的地平线平行，对齐时变绿
        const float angle = self.roll;
        const float nearest = roundf(angle / 90.f) * 90.f;
        const BOOL level = fabsf(angle - nearest) < 1.f;
        UIColor *color = level ? CINColors.meterGreen : [UIColor colorWithWhite:1 alpha:0.8];
        const CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
        const CGFloat half = f.size.width * 0.12;
        const CGFloat gap = 10;
        CGContextSetLineCap(ctx, kCGLineCapButt);
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, c.x, c.y);
        CGContextRotateCTM(ctx, angle * M_PI / 180.0);
        [color setStroke];
        CGContextSetLineWidth(ctx, 2);
        CGContextMoveToPoint(ctx, -half, 0);
        CGContextAddLineToPoint(ctx, -gap, 0);
        CGContextMoveToPoint(ctx, gap, 0);
        CGContextAddLineToPoint(ctx, half, 0);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, c.x, c.y);
        CGContextRotateCTM(ctx, nearest * M_PI / 180.0);
        [[UIColor colorWithWhite:1 alpha:0.45] setStroke];
        CGContextSetLineWidth(ctx, 1.5);
        CGContextMoveToPoint(ctx, -half - 14, 0);
        CGContextAddLineToPoint(ctx, -half - 4, 0);
        CGContextMoveToPoint(ctx, half + 4, 0);
        CGContextAddLineToPoint(ctx, half + 14, 0);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }
}

@end

@implementation CINPreviewView {
    CINMetalView *_metal;
    CINGuideOverlay *_guides;
    UIView *_chips;
    NSMutableArray<CINInfoChip *> *_chipViews;
    UIView *_timer;
    UILabel *_timerLabel;
    NSTimer *_timerTick;
    CFTimeInterval _recordStart;
    UIView *_focus;
    UILabel *_focusLabel;
    NSInteger _focusEventId;
    CINZoomPills *_zoom;
    int _frameW, _frameH;
    BOOL _hasState;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _metal = [[CINMetalView alloc] init];
        _metal.userInteractionEnabled = NO;
        _metal.backgroundColor = UIColor.blackColor;
        [self addSubview:_metal];

        _guides = [[CINGuideOverlay alloc] init];
        _guides.userInteractionEnabled = NO;
        _guides.backgroundColor = UIColor.clearColor;
        _guides.contentMode = UIViewContentModeRedraw;
        [self addSubview:_guides];

        _chips = [[UIView alloc] init];
        _chips.userInteractionEnabled = NO;
        _chips.isAccessibilityElement = YES;
        _chips.accessibilityIdentifier = @"chips";
        _chipViews = [NSMutableArray array];
        [self addSubview:_chips];

        _timer = [[UIView alloc] init];
        _timer.backgroundColor = [CINColors.record colorWithAlphaComponent:0.85];
        _timer.layer.cornerRadius = 6;
        _timer.hidden = YES;
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(10, 0, 7, 7)];
        dot.backgroundColor = UIColor.whiteColor;
        dot.layer.cornerRadius = 3.5;
        dot.tag = 1001;
        [_timer addSubview:dot];
        _timerLabel = [[UILabel alloc] init];
        _timerLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        _timerLabel.textColor = UIColor.whiteColor;
        [_timer addSubview:_timerLabel];
        [self addSubview:_timer];

        _focus = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 72)];
        _focus.userInteractionEnabled = NO;
        _focus.layer.borderColor = CINColors.accent.CGColor;
        _focus.layer.borderWidth = 1.5;
        _focus.layer.cornerRadius = 6;
        _focus.hidden = YES;
        _focusLabel = [[UILabel alloc] init];
        _focusLabel.text = @"AF-L";
        _focusLabel.font = CINFont(9, UIFontWeightRegular);
        _focusLabel.textColor = CINColors.accent;
        _focusLabel.textAlignment = NSTextAlignmentCenter;
        _focusLabel.frame = CGRectMake(0, 72 - 2 - ceil(_focusLabel.font.lineHeight), 72, ceil(_focusLabel.font.lineHeight));
        [_focus addSubview:_focusLabel];
        [self addSubview:_focus];

        _zoom = [[CINZoomPills alloc] init];
        __weak CINPreviewView *weakSelf = self;
        _zoom.onSelect = ^(float z) {
            CINPreviewView *v = weakSelf;
            if (v.onZoomPreset) v.onZoomPreset(z);
        };
        [self addSubview:_zoom];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapGesture:)];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressGesture:)];
        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinchGesture:)];
        [self addGestureRecognizer:tap];
        [self addGestureRecognizer:longPress];
        [self addGestureRecognizer:pinch];
    }
    return self;
}

- (void)dealloc {
    [_timerTick invalidate];
}

- (CAMetalLayer *)metalLayer {
    return (CAMetalLayer *)_metal.layer;
}

- (CGRect)frameRect {
    const CINRectF r = CINFitCenter(_frameW, _frameH, (float)self.bounds.size.width, (float)self.bounds.size.height);
    return CGRectMake(r.x, r.y, r.w, r.h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _metal.frame = self.bounds;
    const CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    self.metalLayer.contentsScale = scale;
    self.metalLayer.drawableSize = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    _guides.frame = self.bounds;
    [self layoutOverlays];
}

- (void)layoutOverlays {
    const CGRect f = self.frameRect;
    // UI 测试和截图脚本靠它找到画面的位置（预览视图坐标，点）
    self.accessibilityValue = NSStringFromCGRect(f);
    _guides.frameRect = f;
    [_guides setNeedsDisplay];
    // 左上角角标
    CGFloat x = 0;
    CGFloat h = 0;
    for (CINInfoChip *c in _chipViews) {
        if (c.hidden) continue;
        const CGSize s = c.intrinsicContentSize;
        c.frame = CGRectMake(x, 0, s.width, s.height);
        x += s.width + 6;
        h = MAX(h, s.height);
    }
    _chips.frame = CGRectMake(f.origin.x + 12, f.origin.y + 12, MAX(0, x - 6), h);
    // 录制计时：画面顶部往下 48，水平居中
    const CGSize ts = [_timerLabel intrinsicContentSize];
    const CGFloat tw = 10 + 7 + ceil(ts.width) + 10, th = 3 + ceil(ts.height) + 3;
    _timer.frame = CGRectMake(CGRectGetMidX(f) - tw / 2, f.origin.y + 48, tw, th);
    [_timer viewWithTag:1001].frame = CGRectMake(10, (th - 7) / 2, 7, 7);
    _timerLabel.frame = CGRectMake(17, 3, ceil(ts.width), ceil(ts.height));
    // 变焦：画面底部往上 60，水平居中
    const CGSize zs = _zoom.intrinsicContentSize;
    _zoom.frame = CGRectMake(CGRectGetMidX(f) - zs.width / 2, CGRectGetMaxY(f) - 60, zs.width, zs.height);
}

- (void)render:(CINCameraState *)s {
    const BOOL sizeChanged = s.frameWidth != _frameW || s.frameHeight != _frameH;
    _frameW = s.frameWidth;
    _frameH = s.frameHeight;
    if (_guides.grid != s.assist.grid || _guides.level != s.assist.level || sizeChanged) {
        _guides.grid = s.assist.grid;
        _guides.level = s.assist.level;
        [_guides setNeedsDisplay];
    }

    // 角标：LOG、LUT 烧录 / 仅监看、Log 原片、当前影调
    NSMutableArray *chips = [NSMutableArray array];
    if (s.logOn) {
        [chips addObject:@[CINL(@"chip_log"), CINColors.accent, @NO]];
        [chips addObject:@[CINL(s.burnIn ? @"chip_burn_in" : @"chip_monitor_only"), s.burnIn ? CINColors.record : CINColors.textSecondary, @YES]];
    }
    if (s.showSignal && s.logOn) [chips addObject:@[CINL(@"chip_signal"), UIColor.whiteColor, @NO]];
    CINLookInfo *look = s.currentLook;
    if (look) [chips addObject:@[[look titleForChinese:CINUIIsChinese()], UIColor.whiteColor, @NO]];
    while (_chipViews.count < chips.count) {
        CINInfoChip *c = [[CINInfoChip alloc] init];
        [_chips addSubview:c];
        [_chipViews addObject:c];
    }
    for (NSUInteger i = 0; i < _chipViews.count; ++i) {
        CINInfoChip *c = _chipViews[i];
        c.hidden = i >= chips.count;
        if (!c.hidden) [c setText:chips[i][0] color:chips[i][1] outlined:[chips[i][2] boolValue]];
    }

    // 录制计时
    if (s.recording && _timer.hidden) {
        _recordStart = s.recordStart;
        _timer.hidden = NO;
        [self tickTimer];
        _timerTick = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tickTimer) userInfo:nil repeats:YES];
    } else if (!s.recording && !_timer.hidden) {
        _timer.hidden = YES;
        [_timerTick invalidate];
        _timerTick = nil;
    }

    // 对焦框：点一下全亮，1.5 秒后淡到 35%
    if (!s.hasFocusPoint) {
        _focus.hidden = YES;
    } else {
        const CGRect f = self.frameRect;
        _focus.center = CGPointMake(f.origin.x + s.focusPoint.x * f.size.width, f.origin.y + s.focusPoint.y * f.size.height);
        if (s.focusEventId != _focusEventId) {
            _focusEventId = s.focusEventId;
            _focus.hidden = NO;
            [_focus.layer removeAllAnimations];
            _focus.alpha = 1;
            [UIView animateWithDuration:0.4 delay:1.5 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                self->_focus.alpha = 0.35;
            } completion:nil];
        }
        _focusLabel.hidden = !(s.readout.afLocked && s.controls.focusAuto);
    }

    [_zoom setPresets:s.zoomPresets current:s.controls.zoom baseFocal:s.caps ? s.caps.equivalentFocal : 24.f];
    _hasState = YES;
    [self layoutOverlays];
}

- (void)tickTimer {
    const long seconds = MAX(0, (long)(CACurrentMediaTime() - _recordStart));
    _timerLabel.text = [NSString stringWithFormat:@"  %02ld:%02ld", seconds / 60, seconds % 60];
    [self setNeedsLayout];
}

- (void)setRoll:(float)degrees {
    if (fabsf(_guides.roll - degrees) < 0.05f) return;
    _guides.roll = degrees;
    if (_guides.level) [_guides setNeedsDisplay];
}

#pragma mark - 手势

- (void)onTapGesture:(UITapGestureRecognizer *)g {
    if (self.onTap) self.onTap([g locationInView:self]);
}

- (void)onLongPressGesture:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan && self.onLongPress) self.onLongPress();
}

- (void)onPinchGesture:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateChanged && self.onPinch) self.onPinch(g.scale);
    g.scale = 1;
}

@end
