#import "CINRulerDial.h"

#import "CINTheme.h"

static const CGFloat kSpacing = 9;      // 相邻刻度的间距
static const CGFloat kCanvasHeight = 44;

/** 只负责画刻度的那一层。 */
@interface CINRulerCanvas : UIView
@property (nonatomic, weak) CINRulerDial *dial;
@end

@implementation CINRulerDial {
    UILabel *_label;
    CINRulerCanvas *_canvas;
    float _dragValue;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _step = 1.f;
        _majorEvery = 10;
        _maximumValue = 1.f;
        _enabled = YES;
        self.isAccessibilityElement = YES;
        _label = [[UILabel alloc] init];
        _label.font = CINFont(15, UIFontWeightSemibold);
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];
        _canvas = [[CINRulerCanvas alloc] init];
        _canvas.dial = self;
        _canvas.backgroundColor = UIColor.clearColor;
        _canvas.contentMode = UIViewContentModeRedraw;
        [self addSubview:_canvas];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [_canvas addGestureRecognizer:pan];
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, ceil(_label.font.lineHeight) + kCanvasHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat lh = ceil(_label.font.lineHeight);
    _label.frame = CGRectMake(0, 0, self.bounds.size.width, lh);
    _canvas.frame = CGRectMake(0, lh, self.bounds.size.width, kCanvasHeight);
}

- (UIColor *)accent {
    return _enabled ? CINColors.accent : CINColors.textSecondary;
}

- (void)refresh {
    _label.text = self.labelForValue ? self.labelForValue(_value) : @"";
    self.accessibilityValue = _label.text;
    _label.textColor = [self accent];
    [_canvas setNeedsDisplay];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    if (!_enabled || _step <= 0.f) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        // 拖动量在这里累积，不能每次都从调用方传回来的 value 重算：曝光补偿这类参数会被取整到整格，
        // 一次拖动事件只有几个像素、不到半格，取整后又回到原值，慢慢拖就永远拖不动
        _dragValue = _value;
    }
    const CGFloat dx = [pan translationInView:_canvas].x;
    [pan setTranslation:CGPointZero inView:_canvas];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        _dragValue = fminf(fmaxf(_dragValue - (float)(dx / kSpacing) * _step, _minimumValue), _maximumValue);
        if (self.onValueChange) self.onValueChange(_dragValue);
    }
}

@end

@implementation CINRulerCanvas

- (void)drawRect:(CGRect)rect {
    CINRulerDial *d = self.dial;
    const float step = d.step, value = d.value;
    if (step <= 0.f) return;
    const CGFloat w = self.bounds.size.width;
    const CGFloat center = w / 2;
    const int halfTicks = (int)(center / kSpacing) + 2;
    const int first = (int)ceilf((value - halfTicks * step) / step);
    const int last = (int)floorf((value + halfTicks * step) / step);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineCap(ctx, kCGLineCapRound);
    UIFont *tickFont = CINFont(9, UIFontWeightRegular);
    CGFloat lastLabelRight = -CGFLOAT_MAX;
    for (int i = first; i <= last; ++i) {
        const float tickValue = i * step;
        if (tickValue < d.minimumValue - step * 0.01f || tickValue > d.maximumValue + step * 0.01f) continue;
        const CGFloat x = center + (tickValue - value) / step * kSpacing;
        const BOOL major = d.majorEvery > 0 && abs(i % d.majorEvery) == 0;
        // 越靠边越淡，像刻度盘弯过去了
        const CGFloat fade = 1 - MIN(MAX(fabs(x - center) / center, 0), 1);
        const CGFloat alpha = 0.25 + 0.75 * fade;
        const CGFloat h = major ? 16 : 9;
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:alpha * (d.enabled ? 1 : 0.4)].CGColor);
        CGContextSetLineWidth(ctx, major ? 1.6 : 1.0);
        CGContextMoveToPoint(ctx, x, 4);
        CGContextAddLineToPoint(ctx, x, 4 + h);
        CGContextStrokePath(ctx);
        if (major && d.tickLabel) {
            NSString *text = d.tickLabel(tickValue);
            NSDictionary *attrs = @{NSFontAttributeName: tickFont,
                                    NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:alpha * 0.8]};
            const CGSize size = [text sizeWithAttributes:attrs];
            const CGFloat left = x - size.width / 2;
            // 标签太长（比如 1/16384）就隔一个画一个，避免挤成一团
            if (left > lastLabelRight + 6) {
                [text drawAtPoint:CGPointMake(left, 24) withAttributes:attrs];
                lastLabelRight = left + size.width;
            }
        }
    }
    // 中心指针：从上到下渐淡
    UIColor *accent = d.enabled ? CINColors.accent : CINColors.textSecondary;
    CGContextSaveGState(ctx);
    CGContextAddRect(ctx, CGRectMake(center - 1, 0, 2, 26));
    CGContextClip(ctx);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)accent.CGColor, (id)[accent colorWithAlphaComponent:0.3].CGColor];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, g, CGPointMake(center, 0), CGPointMake(center, 26), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);
}

@end
