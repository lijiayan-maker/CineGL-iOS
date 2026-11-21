#import "CINSwitch.h"

#import "CINTheme.h"

static const CGFloat kTrackW = 52, kTrackH = 32;

@implementation CINSwitch {
    CAShapeLayer *_track;
    CAShapeLayer *_thumb;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _track = [CAShapeLayer layer];
        _thumb = [CAShapeLayer layer];
        [self.layer addSublayer:_track];
        [self.layer addSublayer:_thumb];
        _track.lineWidth = 2;
        [self applyAnimated:NO];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(kTrackW, 48);
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (on == _on) return;
    _on = on;
    [self applyAnimated:animated];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    // Material 3 的禁用态：整体降到 38% 不透明
    self.alpha = enabled ? 1.0 : 0.38;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self applyAnimated:YES];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyAnimated:NO];
}

- (void)applyAnimated:(BOOL)animated {
    const CGRect b = self.bounds;
    const CGRect track = CGRectMake((b.size.width - kTrackW) / 2, (b.size.height - kTrackH) / 2, kTrackW, kTrackH);
    const CGFloat d = self.highlighted ? 28 : (_on ? 24 : 16);
    const CGFloat cx = _on ? CGRectGetMaxX(track) - 16 : CGRectGetMinX(track) + 16;
    const CGRect thumb = CGRectMake(cx - d / 2, CGRectGetMidY(track) - d / 2, d, d);
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:0.15];
    _track.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(track, _on ? 0 : 1, _on ? 0 : 1) cornerRadius:kTrackH / 2].CGPath;
    _track.fillColor = (_on ? CINColors.accent : CINColors.surfaceContainerHighest).CGColor;
    _track.strokeColor = _on ? UIColor.clearColor.CGColor : CINColors.outline.CGColor;
    _thumb.path = [UIBezierPath bezierPathWithOvalInRect:thumb].CGPath;
    _thumb.fillColor = (_on ? UIColor.whiteColor : CINColors.outline).CGColor;
    [CATransaction commit];
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    if ([self pointInside:[touch locationInView:self] withEvent:event]) {
        [self setOn:!_on animated:YES];
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

@end
