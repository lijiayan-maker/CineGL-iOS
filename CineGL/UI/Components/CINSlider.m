#import "CINSlider.h"

static const CGFloat kTrackHeight = 16;
static const CGFloat kThumbWidth = 4;
static const CGFloat kThumbPressedWidth = 2;
static const CGFloat kThumbHeight = 44;
static const CGFloat kGap = 6;
static const CGFloat kInsideCorner = 2;
static const CGFloat kStopSize = 4;

@implementation CINSlider

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _maximumValue = 1.f;
        _thumbColor = UIColor.whiteColor;
        _activeTrackColor = UIColor.whiteColor;
        _inactiveTrackColor = [UIColor colorWithWhite:1 alpha:0.15];
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    }
    return self;
}

- (void)setValue:(float)value {
    value = fminf(fmaxf(value, _minimumValue), _maximumValue);
    if (value == _value) return;
    _value = value;
    [self setNeedsDisplay];
}

- (CGFloat)fraction {
    const float range = _maximumValue - _minimumValue;
    return range > 0 ? (_value - _minimumValue) / range : 0;
}

/** 一边两个角大、一边两个角小的圆角矩形。 */
static UIBezierPath *CINTrackPath(CGRect r, CGFloat leftRadius, CGFloat rightRadius) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    const CGFloat lr = MIN(leftRadius, r.size.width / 2), rr = MIN(rightRadius, r.size.width / 2);
    [p moveToPoint:CGPointMake(CGRectGetMinX(r) + lr, CGRectGetMinY(r))];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r) - rr, CGRectGetMinY(r))];
    [p addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - rr, CGRectGetMinY(r) + rr) radius:rr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r) - rr)];
    [p addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - rr, CGRectGetMaxY(r) - rr) radius:rr startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + lr, CGRectGetMaxY(r))];
    [p addArcWithCenter:CGPointMake(CGRectGetMinX(r) + lr, CGRectGetMaxY(r) - lr) radius:lr startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r) + lr)];
    [p addArcWithCenter:CGPointMake(CGRectGetMinX(r) + lr, CGRectGetMinY(r) + lr) radius:lr startAngle:M_PI endAngle:-M_PI_2 clockwise:YES];
    [p closePath];
    return p;
}

- (void)drawRect:(CGRect)rect {
    const CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    const CGFloat midY = h / 2;
    const CGFloat thumbW = _dragging ? kThumbPressedWidth : kThumbWidth;
    // 滑块中心在 [2, w - 2] 之间移动（以静止时 4pt 宽的滑块为准）
    const CGFloat thumbX = kThumbWidth / 2 + [self fraction] * (w - kThumbWidth);
    const CGFloat outer = kTrackHeight / 2;
    const CGFloat activeEnd = thumbX - thumbW / 2 - kGap;
    if (activeEnd > 0) {
        [_activeTrackColor setFill];
        [CINTrackPath(CGRectMake(0, midY - kTrackHeight / 2, activeEnd, kTrackHeight), outer, kInsideCorner) fill];
    }
    const CGFloat inactiveStart = thumbX + thumbW / 2 + kGap;
    if (inactiveStart < w) {
        [_inactiveTrackColor setFill];
        [CINTrackPath(CGRectMake(inactiveStart, midY - kTrackHeight / 2, w - inactiveStart, kTrackHeight), kInsideCorner, outer) fill];
        // 终点圆点：还没被滑块越过时才画
        const CGFloat stopX = w - kTrackHeight / 2;
        if (stopX - kStopSize / 2 > inactiveStart) {
            [_activeTrackColor setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(stopX - kStopSize / 2, midY - kStopSize / 2, kStopSize, kStopSize)] fill];
        }
    }
    [_thumbColor setFill];
    const CGFloat th = MIN(kThumbHeight, h);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(thumbX - thumbW / 2, midY - th / 2, thumbW, th) cornerRadius:thumbW / 2] fill];
}

- (void)updateValueForTouch:(UITouch *)touch {
    const CGFloat w = self.bounds.size.width;
    const CGFloat x = [touch locationInView:self].x;
    const CGFloat f = w > kThumbWidth ? (x - kThumbWidth / 2) / (w - kThumbWidth) : 0;
    const float v = _minimumValue + (float)fmin(1, fmax(0, f)) * (_maximumValue - _minimumValue);
    if (v != _value) {
        self.value = v;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _dragging = YES;
    [self updateValueForTouch:touch];
    [self setNeedsDisplay];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self updateValueForTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _dragging = NO;
    [self setNeedsDisplay];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    _dragging = NO;
    [self setNeedsDisplay];
}

/** 横向拖动归滑杆，竖向留给外面的滚动视图。 */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g isKindOfClass:[UIPanGestureRecognizer class]] && g.view != self) {
        const CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
        return fabs(v.y) > fabs(v.x);
    }
    return YES;
}

@end
