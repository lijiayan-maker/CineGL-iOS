#import "CINControls.h"

#import "CINTheme.h"

// 子视图的 tag：别和按钮自己的 tag（序号）撞上，viewWithTag 会先比较自己
static const NSInteger kLabelTag = 1001;
static const NSInteger kUnitTag = 1002;

#pragma mark - 按压反馈

@implementation CINPressableControl {
    UIView *_press;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _showsPress = YES;
        self.isAccessibilityElement = YES;
        _press = [[UIView alloc] init];
        _press.userInteractionEnabled = NO;
        _press.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        _press.alpha = 0;
        [self addSubview:_press];
    }
    return self;
}

/** 按钮 + 是否可点（UI 测试和旁白都靠它判断「重置」之类的按钮有没有置灰）。 */
- (UIAccessibilityTraits)accessibilityTraits {
    return UIAccessibilityTraitButton | (self.enabled ? 0 : UIAccessibilityTraitNotEnabled);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _press.frame = self.bounds;
    _press.layer.cornerRadius = _pressCornerRadius < 0 ? MIN(self.bounds.size.width, self.bounds.size.height) / 2 : _pressCornerRadius;
    [self bringSubviewToFront:_press];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (!_showsPress) return;
    [UIView animateWithDuration:highlighted ? 0.05 : 0.25 animations:^{
        self->_press.alpha = highlighted ? 1 : 0;
    }];
}

@end

static UILabel *CINLabel(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.font = CINFont(size, weight);
    l.textColor = color;
    return l;
}

@implementation CINScrollView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.delaysContentTouches = NO;
        self.canCancelContentTouches = YES;
    }
    return self;
}

/** 默认对 UIControl 返回 NO：手指按在开关行、卡片上就滑不动了。这里统一允许滚动接管。 */
- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    return YES;
}

@end

UILabel *CINSectionTitle(NSString *text) {
    UILabel *l = CINLabel(12, UIFontWeightRegular, CINColors.textSecondary);
    l.text = text;
    return l;
}

#pragma mark - 文字标签

@implementation CINTextTabs {
    NSMutableArray<UIButton *> *_buttons;
    NSInteger _selected;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) _buttons = [NSMutableArray array];
    return self;
}

- (void)setItems:(NSArray<NSString *> *)items selected:(NSInteger)selected enabled:(BOOL)enabled {
    while (_buttons.count < items.count) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)_buttons.count;
        b.accessibilityIdentifier = [NSString stringWithFormat:@"%@.%lu", self.accessibilityIdentifier ?: @"tab", (unsigned long)_buttons.count];
        [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [_buttons addObject:b];
    }
    _selected = selected;
    for (NSUInteger i = 0; i < items.count; ++i) {
        UIButton *b = _buttons[i];
        const BOOL isSelected = (NSInteger)i == selected;
        NSDictionary *attrs = @{
            NSFontAttributeName: isSelected ? CINFont(16, UIFontWeightSemibold) : CINFont(15, UIFontWeightRegular),
            NSForegroundColorAttributeName: isSelected ? CINColors.textPrimary : CINColors.textSecondary,
        };
        [b setAttributedTitle:[[NSAttributedString alloc] initWithString:items[i] attributes:attrs] forState:UIControlStateNormal];
        [b setAttributedTitle:[[NSAttributedString alloc] initWithString:items[i] attributes:attrs] forState:UIControlStateDisabled];
        b.enabled = enabled && !isSelected;
    }
    [self setNeedsLayout];
    [self invalidateIntrinsicContentSize];
}

- (CGSize)intrinsicContentSize {
    CGFloat w = 0, h = 0;
    for (UIButton *b in _buttons) {
        const CGSize s = b.currentAttributedTitle.size;
        w += ceil(s.width);
        h = MAX(h, ceil(s.height));
    }
    if (_buttons.count > 1) w += 22 * (_buttons.count - 1);
    return CGSizeMake(w, h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGSize total = self.intrinsicContentSize;
    CGFloat x = (self.bounds.size.width - total.width) / 2;
    for (UIButton *b in _buttons) {
        const CGSize s = b.currentAttributedTitle.size;
        // 点击区域上下放大一些，文字本身对齐中线
        b.frame = CGRectMake(x, 0, ceil(s.width), self.bounds.size.height);
        x += ceil(s.width) + 22;
    }
}

- (void)tap:(UIButton *)b {
    if (self.onSelect) self.onSelect(b.tag);
}

@end

#pragma mark - 电平表

@implementation CINAudioMeterView {
    UILabel *_l, *_r;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _l = CINLabel(8, UIFontWeightRegular, CINColors.textSecondary);
        _l.text = @"L";
        _r = CINLabel(8, UIFontWeightRegular, CINColors.textSecondary);
        _r.text = @"R";
        [self addSubview:_l];
        [self addSubview:_r];
    }
    return self;
}

- (CGFloat)rowHeight {
    return MAX(5, ceil(_l.font.lineHeight));
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(9 + 64, [self rowHeight] * 2 + 3);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat rh = [self rowHeight];
    _l.frame = CGRectMake(0, 0, 9, rh);
    _r.frame = CGRectMake(0, rh + 3, 9, rh);
}

- (void)setLevels:(CINAudioLevels)levels {
    _levels = levels;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    const CGFloat rh = [self rowHeight];
    const float values[2] = {_levels.left, _levels.right};
    for (int row = 0; row < 2; ++row) {
        const CGFloat top = row * (rh + 3) + (rh - 5) / 2;
        const int n = 10;
        const CGFloat gap = 64.0 / n, r = 2.5;
        for (int i = 0; i < n; ++i) {
            const BOOL lit = values[row] >= (i + 1) / (float)n;
            UIColor *c = !lit ? [UIColor colorWithWhite:1 alpha:0.18] : i < 7 ? CINColors.meterGreen : i < 9 ? CINColors.meterYellow : CINColors.meterRed;
            [c setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9 + gap * i, top, 2 * r, 2 * r)] fill];
        }
    }
}

@end

#pragma mark - 圆形图标按钮

@implementation CINRoundIconButton {
    UIImageView *_icon;
}

- (instancetype)initWithIcon:(CINIcon)icon {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 38, 38)])) {
        self.pressCornerRadius = -1;
        self.layer.cornerRadius = 19;
        _icon = [[UIImageView alloc] initWithImage:CINIconImage(icon, 22)];
        _icon.frame = CGRectMake(8, 8, 22, 22);
        [self addSubview:_icon];
        [self apply];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(38, 38);
}

- (void)setActive:(BOOL)active {
    _active = active;
    [self apply];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self apply];
}

- (void)apply {
    self.backgroundColor = _active ? [CINColors.accent colorWithAlphaComponent:0.18] : UIColor.clearColor;
    _icon.tintColor = !self.enabled ? [CINColors.textSecondary colorWithAlphaComponent:0.4] : _active ? CINColors.accent : CINColors.textPrimary;
}

@end

#pragma mark - 工具栏按钮

@implementation CINToolButton {
    UIImageView *_icon;
    UILabel *_iconText;
    UILabel *_label;
    UILabel *_value;
    BOOL _selected;
}

- (void)setupCommon {
    self.pressCornerRadius = 12;
    _label = CINLabel(10, UIFontWeightRegular, CINColors.textSecondary);
    _label.textAlignment = NSTextAlignmentCenter;
    _value = CINLabel(11, UIFontWeightMedium, CINColors.textPrimary);
    _value.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_label];
    [self addSubview:_value];
}

- (instancetype)initWithIcon:(CINIcon)icon {
    if ((self = [super initWithFrame:CGRectZero])) {
        _icon = [[UIImageView alloc] initWithImage:CINIconImage(icon, 20)];
        _icon.tintColor = CINColors.textPrimary;
        [self addSubview:_icon];
        [self setupCommon];
    }
    return self;
}

- (instancetype)initWithIconText:(NSString *)iconText {
    if ((self = [super initWithFrame:CGRectZero])) {
        _iconText = CINLabel(13, UIFontWeightBold, CINColors.textPrimary);
        _iconText.text = iconText;
        _iconText.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_iconText];
        [self setupCommon];
    }
    return self;
}

- (void)setLabel:(NSString *)label value:(NSString *)value selected:(BOOL)selected manual:(BOOL)manual {
    if (![_label.text isEqualToString:label]) _label.text = label;
    if (![_value.text isEqualToString:value]) _value.text = value;
    _value.textColor = manual ? CINColors.accent : CINColors.textPrimary;
    if (selected != _selected) {
        _selected = selected;
        UIColor *tint = selected ? CINColors.accent : CINColors.textPrimary;
        [UIView transitionWithView:self duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self->_icon.tintColor = tint;
            self->_iconText.textColor = tint;
        } completion:nil];
    }
}

+ (CGFloat)heightFor:(UILabel *)label value:(UILabel *)value {
    return 6 + 22 + 2 + ceil(label.font.lineHeight) + ceil(value.font.lineHeight) + 6;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, [CINToolButton heightFor:_label value:_value]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = self.bounds.size.width;
    _icon.frame = CGRectMake((w - 20) / 2, 6 + 1, 20, 20);
    _iconText.frame = CGRectMake(0, 6, w, 22);
    const CGFloat lh = ceil(_label.font.lineHeight);
    _label.frame = CGRectMake(0, 6 + 22 + 2, w, lh);
    _value.frame = CGRectMake(0, 6 + 22 + 2 + lh, w, ceil(_value.font.lineHeight));
}

@end

@implementation CINResetToolButton {
    UIImageView *_icon;
    UILabel *_text;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.pressCornerRadius = 12;
        _icon = [[UIImageView alloc] initWithImage:CINIconImage(CINIconReset, 20)];
        _text = CINLabel(10, UIFontWeightRegular, CINColors.textSecondary);
        _text.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_icon];
        [self addSubview:_text];
        [self apply];
    }
    return self;
}

- (void)setLabel:(NSString *)label {
    _label = [label copy];
    _text.text = label;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == self.enabled) return;
    [super setEnabled:enabled];
    [UIView transitionWithView:self duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self apply];
    } completion:nil];
}

- (void)apply {
    UIColor *tint = self.enabled ? CINColors.textPrimary : [CINColors.textSecondary colorWithAlphaComponent:0.35];
    _icon.tintColor = tint;
    _text.textColor = self.enabled ? CINColors.textSecondary : tint;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = self.bounds.size.width;
    _icon.frame = CGRectMake((w - 20) / 2, 6 + 1, 20, 20);
    _text.frame = CGRectMake(0, 6 + 22 + 2, w, ceil(_text.font.lineHeight));
}

@end

#pragma mark - 自动按钮

@implementation CINAutoButton {
    UILabel *_text;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 40, 40)])) {
        self.pressCornerRadius = -1;
        self.layer.cornerRadius = 20;
        self.layer.borderWidth = 1.5;
        _text = CINLabel(14, UIFontWeightBold, CINColors.accent);
        _text.textAlignment = NSTextAlignmentCenter;
        _text.frame = self.bounds;
        [self addSubview:_text];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(40, 40);
}

- (void)setText:(NSString *)text isAuto:(BOOL)isAuto {
    _text.text = text;
    UIColor *c = isAuto ? CINColors.accent : CINColors.textSecondary;
    _text.textColor = c;
    self.layer.borderColor = c.CGColor;
    self.backgroundColor = isAuto ? [CINColors.accent colorWithAlphaComponent:0.15] : UIColor.clearColor;
}

@end

#pragma mark - 快门

@implementation CINShutterButton {
    CAShapeLayer *_ring;
    UIView *_inner;
    CAShapeLayer *_spinner;
    BOOL _video, _recording, _busy, _configured;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 78, 78)])) {
        _ring = [CAShapeLayer layer];
        _ring.fillColor = UIColor.clearColor.CGColor;
        _ring.strokeColor = UIColor.whiteColor.CGColor;
        _ring.lineWidth = 3.5;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(0, 0, 78, 78), 1.75, 1.75)].CGPath;
        [self.layer addSublayer:_ring];
        _inner = [[UIView alloc] init];
        _inner.userInteractionEnabled = NO;
        [self addSubview:_inner];
        // 忙的时候外圈转一个进度弧（安卓的 CircularProgressIndicator）
        _spinner = [CAShapeLayer layer];
        _spinner.frame = CGRectMake(4, 4, 70, 70);
        _spinner.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(35, 35) radius:34 startAngle:0 endAngle:M_PI * 1.5 clockwise:YES].CGPath;
        _spinner.strokeColor = CINColors.accent.CGColor;
        _spinner.fillColor = UIColor.clearColor.CGColor;
        _spinner.lineWidth = 2;
        _spinner.lineCap = kCALineCapRound;
        _spinner.hidden = YES;
        [self.layer addSublayer:_spinner];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(78, 78);
}

- (void)setVideo:(BOOL)video recording:(BOOL)recording busy:(BOOL)busy {
    const BOOL changed = !_configured || video != _video || recording != _recording;
    _configured = YES;
    _video = video;
    _recording = recording;
    _busy = busy;
    self.enabled = !busy || recording;
    const CGFloat size = recording ? 30 : 60;
    const CGFloat corner = recording ? 8 : 30;
    void (^apply)(void) = ^{
        self->_inner.frame = CGRectMake((78 - size) / 2, (78 - size) / 2, size, size);
        self->_inner.layer.cornerRadius = corner;
        self->_inner.backgroundColor = video ? CINColors.record : UIColor.whiteColor;
    };
    if (changed) [UIView animateWithDuration:0.25 animations:apply];
    const BOOL spin = busy && !recording;
    if (spin && _spinner.hidden) {
        _spinner.hidden = NO;
        CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        rot.fromValue = @0;
        rot.toValue = @(2 * M_PI);
        rot.duration = 1.0;
        rot.repeatCount = HUGE_VALF;
        [_spinner addAnimation:rot forKey:@"spin"];
    } else if (!spin && !_spinner.hidden) {
        _spinner.hidden = YES;
        [_spinner removeAllAnimations];
    }
}

@end

#pragma mark - 影调按钮

@implementation CINLookButton {
    CAGradientLayer *_ring;
    UIView *_innerBg;
    UIImageView *_thumb;
    UILabel *_badge;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 56, 56)])) {
        self.pressCornerRadius = -1;
        // 彩色渐变圈：圆锥渐变 + 圆环遮罩
        _ring = [CAGradientLayer layer];
        _ring.type = kCAGradientLayerConic;
        _ring.frame = CGRectMake(0, 0, 56, 56);
        _ring.startPoint = CGPointMake(0.5, 0.5);
        _ring.endPoint = CGPointMake(1, 0.5);
        _ring.colors = @[(id)CINColorARGB(0xFFFF8A3D).CGColor, (id)CINColorARGB(0xFFFFD166).CGColor, (id)CINColorARGB(0xFF06D6A0).CGColor,
                         (id)CINColorARGB(0xFF118AB2).CGColor, (id)CINColorARGB(0xFFB5179E).CGColor, (id)CINColorARGB(0xFFFF8A3D).CGColor];
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(0, 0, 56, 56), 1.25, 1.25)].CGPath;
        mask.fillColor = UIColor.clearColor.CGColor;
        mask.strokeColor = UIColor.blackColor.CGColor;
        mask.lineWidth = 2.5;
        _ring.mask = mask;
        [self.layer addSublayer:_ring];
        _innerBg = [[UIView alloc] initWithFrame:CGRectMake(5, 5, 46, 46)];
        _innerBg.userInteractionEnabled = NO;
        _innerBg.backgroundColor = CINColors.surfaceHigh;
        _innerBg.layer.cornerRadius = 23;
        _innerBg.clipsToBounds = YES;
        [self addSubview:_innerBg];
        _thumb = [[UIImageView alloc] initWithFrame:_innerBg.bounds];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        [_innerBg addSubview:_thumb];
        _badge = CINLabel(13, UIFontWeightBold, CINColors.textPrimary);
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.frame = _innerBg.bounds;
        [_innerBg addSubview:_badge];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(56, 56);
}

- (void)setThumb:(UIImage *)thumb badge:(NSString *)badge {
    if (_thumb.image != thumb) _thumb.image = thumb;
    _badge.hidden = thumb != nil;
    _badge.text = badge;
}

@end

@implementation CINGalleryButton {
    UIImageView *_image;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 52, 52)])) {
        self.pressCornerRadius = 12;
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        self.backgroundColor = CINColors.surface;
        self.clipsToBounds = YES;
        _image = [[UIImageView alloc] initWithFrame:self.bounds];
        _image.contentMode = UIViewContentModeScaleAspectFill;
        [self insertSubview:_image atIndex:0];
        self.enabled = NO;
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(52, 52);
}

- (void)setThumb:(UIImage *)thumb {
    _thumb = thumb;
    _image.image = thumb;
    self.enabled = thumb != nil;
}

@end

#pragma mark - 变焦

@implementation CINZoomPills {
    NSMutableArray<CINPressableControl *> *_items;
    NSArray<NSNumber *> *_presets;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _items = [NSMutableArray array];
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    }
    return self;
}

- (void)setPresets:(NSArray<NSNumber *> *)presets current:(float)current baseFocal:(float)baseFocal {
    _presets = presets;
    self.hidden = presets.count <= 1;
    if (self.hidden) return;
    while (_items.count < presets.count) {
        CINPressableControl *c = [[CINPressableControl alloc] init];
        c.pressCornerRadius = -1;
        c.layer.cornerRadius = 19;
        c.tag = (NSInteger)_items.count;
        c.accessibilityIdentifier = [NSString stringWithFormat:@"zoom.%lu", (unsigned long)_items.count];
        [c addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *num = CINLabel(12, UIFontWeightSemibold, CINColors.textPrimary);
        num.tag = kLabelTag;
        num.textAlignment = NSTextAlignmentCenter;
        UILabel *mm = CINLabel(7, UIFontWeightRegular, CINColors.accent);
        mm.tag = kUnitTag;
        mm.text = @"mm";
        mm.textAlignment = NSTextAlignmentCenter;
        [c addSubview:num];
        [c addSubview:mm];
        [self addSubview:c];
        [_items addObject:c];
    }
    NSInteger active = 0;
    float best = FLT_MAX;
    for (NSUInteger i = 0; i < presets.count; ++i) {
        const float d = fabsf(presets[i].floatValue - current);
        if (d < best) {
            best = d;
            active = (NSInteger)i;
        }
    }
    for (NSUInteger i = 0; i < _items.count; ++i) {
        CINPressableControl *c = _items[i];
        c.hidden = i >= presets.count;
        if (c.hidden) continue;
        const BOOL selected = (NSInteger)i == active;
        const float z = selected ? current : presets[i].floatValue;
        UILabel *num = [c viewWithTag:kLabelTag], *mm = [c viewWithTag:kUnitTag];
        num.text = [NSString stringWithFormat:@"%ld", lroundf(baseFocal * z)];
        num.textColor = selected ? CINColors.accent : CINColors.textPrimary;
        mm.hidden = !selected;
        c.backgroundColor = selected ? [UIColor colorWithWhite:1 alpha:0.16] : UIColor.clearColor;
    }
    [self setNeedsLayout];
}

- (CGSize)intrinsicContentSize {
    const NSUInteger n = _presets.count;
    return CGSizeMake(n * 38 + (n > 0 ? (n - 1) * 4 : 0) + 8, 46);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        CINPressableControl *c = _items[i];
        c.frame = CGRectMake(4 + i * 42, 4, 38, 38);
        UILabel *num = [c viewWithTag:kLabelTag], *mm = [c viewWithTag:kUnitTag];
        const CGFloat nh = ceil(num.font.lineHeight), mh = mm.hidden ? 0 : ceil(mm.font.lineHeight);
        const CGFloat top = (38 - nh - mh) / 2;
        num.frame = CGRectMake(0, top, 38, nh);
        mm.frame = CGRectMake(0, top + nh, 38, mh);
    }
}

- (void)tap:(UIControl *)c {
    if (self.onSelect && c.tag < (NSInteger)_presets.count) self.onSelect(_presets[(NSUInteger)c.tag].floatValue);
}

@end

#pragma mark - 角标

@implementation CINInfoChip

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.font = CINFont(10, UIFontWeightSemibold);
        self.textAlignment = NSTextAlignmentCenter;
        self.layer.cornerRadius = 5;
        self.clipsToBounds = YES;
    }
    return self;
}

- (void)setText:(NSString *)text color:(UIColor *)color outlined:(BOOL)outlined {
    self.text = text;
    self.textColor = color;
    self.backgroundColor = outlined ? UIColor.clearColor : [color colorWithAlphaComponent:0.18];
    self.layer.borderWidth = outlined ? 1 : 0;
    self.layer.borderColor = color.CGColor;
    [self invalidateIntrinsicContentSize];
}

- (CGSize)intrinsicContentSize {
    const CGSize s = [super intrinsicContentSize];
    return CGSizeMake(ceil(s.width) + 12, ceil(self.font.lineHeight) + 4);
}

@end

#pragma mark - 分段选择

@implementation CINSegmented {
    NSMutableArray<CINPressableControl *> *_items;
    NSInteger _count;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _items = [NSMutableArray array];
        self.backgroundColor = CINColors.surface;
        self.layer.cornerRadius = 10;
    }
    return self;
}

- (void)setItems:(NSArray<NSString *> *)items selected:(NSInteger)selected enabled:(NSArray<NSNumber *> *)enabled {
    _count = (NSInteger)items.count;
    while (_items.count < items.count) {
        CINPressableControl *c = [[CINPressableControl alloc] init];
        c.pressCornerRadius = 8;
        c.layer.cornerRadius = 8;
        c.tag = (NSInteger)_items.count;
        c.accessibilityIdentifier = [NSString stringWithFormat:@"%@.%lu", self.accessibilityIdentifier ?: @"segment", (unsigned long)_items.count];
        [c addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *l = CINLabel(13, UIFontWeightRegular, CINColors.textPrimary);
        l.textAlignment = NSTextAlignmentCenter;
        l.tag = kLabelTag;
        [c addSubview:l];
        [self addSubview:c];
        [_items addObject:c];
    }
    for (NSUInteger i = 0; i < _items.count; ++i) {
        CINPressableControl *c = _items[i];
        c.hidden = i >= items.count;
        if (c.hidden) continue;
        const BOOL isSelected = (NSInteger)i == selected;
        const BOOL on = enabled ? enabled[i].boolValue : YES;
        UILabel *l = [c viewWithTag:kLabelTag];
        l.text = items[i];
        l.font = CINFont(13, isSelected ? UIFontWeightSemibold : UIFontWeightRegular);
        l.textColor = !on ? [CINColors.textSecondary colorWithAlphaComponent:0.35] : isSelected ? CINColors.accent : CINColors.textPrimary;
        c.backgroundColor = isSelected ? CINColors.surfaceHigh : UIColor.clearColor;
        c.enabled = on && !isSelected;
    }
    [self setNeedsLayout];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 3 + 8 + ceil(CINFont(13, UIFontWeightRegular).lineHeight) + 8 + 3);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_count == 0) return;
    const CGFloat w = (self.bounds.size.width - 6) / _count;
    for (NSInteger i = 0; i < _count; ++i) {
        CINPressableControl *c = _items[(NSUInteger)i];
        c.frame = CGRectMake(3 + i * w, 3, w, self.bounds.size.height - 6);
        [c viewWithTag:kLabelTag].frame = c.bounds;
    }
}

- (void)tap:(UIControl *)c {
    if (self.onSelect) self.onSelect(c.tag);
}

@end

#pragma mark - 开关行

@implementation CINSettingSwitchRow {
    UILabel *_title;
    UILabel *_subtitle;
    CINSwitch *_switch;
    BOOL _checked;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _title = CINLabel(14, UIFontWeightRegular, CINColors.textPrimary);
        _subtitle = CINLabel(11, UIFontWeightRegular, CINColors.textSecondary);
        _subtitle.numberOfLines = 0;
        _title.numberOfLines = 0;
        _switch = [[CINSwitch alloc] init];
        [_switch addTarget:self action:@selector(switched) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_title];
        [self addSubview:_subtitle];
        [self addSubview:_switch];
        [self addTarget:self action:@selector(tapRow) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle checked:(BOOL)checked enabled:(BOOL)enabled {
    _title.text = title;
    _title.textColor = enabled ? CINColors.textPrimary : CINColors.textSecondary;
    _subtitle.text = subtitle;
    _subtitle.hidden = subtitle == nil;
    _checked = checked;
    [_switch setOn:checked animated:self.window != nil];
    _switch.enabled = enabled;
    self.enabled = enabled;
    [self setNeedsLayout];
}

- (void)tapRow {
    if (self.onChange) self.onChange(!_checked);
}

- (void)switched {
    if (self.onChange) self.onChange(_switch.isOn);
}

- (CGFloat)textWidthFor:(CGFloat)width {
    return width - 12 - 52;
}

- (CGSize)sizeThatFits:(CGSize)size {
    const CGFloat tw = [self textWidthFor:size.width];
    CGFloat h = [_title sizeThatFits:CGSizeMake(tw, CGFLOAT_MAX)].height;
    if (!_subtitle.hidden) h += [_subtitle sizeThatFits:CGSizeMake(tw, CGFLOAT_MAX)].height;
    return CGSizeMake(size.width, MAX(h, 48) + 12);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    const CGFloat tw = [self textWidthFor:w];
    const CGFloat th = [_title sizeThatFits:CGSizeMake(tw, CGFLOAT_MAX)].height;
    const CGFloat sh = _subtitle.hidden ? 0 : [_subtitle sizeThatFits:CGSizeMake(tw, CGFLOAT_MAX)].height;
    const CGFloat top = (h - th - sh) / 2;
    _title.frame = CGRectMake(0, top, tw, th);
    _subtitle.frame = CGRectMake(0, top + th, tw, sh);
    _switch.frame = CGRectMake(w - 52, (h - 48) / 2, 52, 48);
}

@end

#pragma mark - 带标签的滑杆

@implementation CINLabeledSlider {
    UILabel *_label;
    CINSlider *_slider;
    UILabel *_value;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _labelWidth = 96;
        _label = CINLabel(13, UIFontWeightRegular, CINColors.textPrimary);
        _slider = [[CINSlider alloc] init];
        _slider.minimumValue = 0;
        _slider.maximumValue = 10;
        _slider.thumbColor = UIColor.whiteColor;
        _slider.activeTrackColor = CINColors.accent;
        _slider.inactiveTrackColor = [UIColor colorWithWhite:1 alpha:0.15];
        [_slider addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
        _value = CINLabel(12, UIFontWeightRegular, CINColors.textSecondary);
        [self addSubview:_label];
        [self addSubview:_slider];
        [self addSubview:_value];
    }
    return self;
}

/** 标识只给里面的滑杆（UI 测试要点的是它，不是整行）。 */
- (void)setAccessibilityIdentifier:(NSString *)identifier {
    _slider.accessibilityIdentifier = identifier;
}

- (void)setLabel:(NSString *)label value:(float)value {
    _label.text = label;
    if (!_slider.isDragging) _slider.value = value;
    _value.text = [NSString stringWithFormat:@"%.1f", value];
}

- (void)changed {
    _value.text = [NSString stringWithFormat:@"%.1f", _slider.value];
    if (self.onChange) self.onChange(_slider.value);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 40);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _label.frame = CGRectMake(0, 0, _labelWidth, h);
    _slider.frame = CGRectMake(_labelWidth, (h - 44) / 2, w - _labelWidth - 36, 44);
    _value.frame = CGRectMake(w - 36 + 8, 0, 28, h);
}

@end

@implementation CINResetAction {
    UIImageView *_icon;
    UILabel *_text;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.pressCornerRadius = 8;
        _icon = [[UIImageView alloc] initWithImage:CINIconImage(CINIconReset, 16)];
        _icon.tintColor = CINColors.textPrimary;
        _text = CINLabel(13, UIFontWeightRegular, CINColors.textPrimary);
        [self addSubview:_icon];
        [self addSubview:_text];
    }
    return self;
}

- (void)setLabel:(NSString *)label {
    _label = [label copy];
    _text.text = label;
    [self invalidateIntrinsicContentSize];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    UIColor *c = enabled ? CINColors.textPrimary : [CINColors.textSecondary colorWithAlphaComponent:0.35];
    _icon.tintColor = c;
    _text.textColor = c;
}

- (CGSize)intrinsicContentSize {
    const CGSize t = [_text intrinsicContentSize];
    return CGSizeMake(10 + 16 + 4 + ceil(t.width) + 10, 8 + MAX(16, ceil(t.height)) + 8);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat h = self.bounds.size.height;
    _icon.frame = CGRectMake(10, (h - 16) / 2, 16, 16);
    const CGSize t = [_text intrinsicContentSize];
    _text.frame = CGRectMake(30, (h - t.height) / 2, ceil(t.width), t.height);
}

@end
