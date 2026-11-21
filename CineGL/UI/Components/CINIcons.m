#import "CINIcons.h"

/** SVG 圆弧（rx = ry、无旋转）换成圆心表示，再用 UIBezierPath 画。 */
static void CINAddArc(UIBezierPath *path, CGPoint p1, CGPoint p2, CGFloat r, BOOL largeArc, BOOL sweep) {
    const CGFloat dx2 = (p1.x - p2.x) / 2, dy2 = (p1.y - p2.y) / 2;
    const CGFloat lambda = (dx2 * dx2 + dy2 * dy2) / (r * r);
    if (lambda > 1) r *= sqrt(lambda);
    const CGFloat r2 = r * r;
    const CGFloat num = r2 * r2 - r2 * dy2 * dy2 - r2 * dx2 * dx2;
    const CGFloat den = r2 * dy2 * dy2 + r2 * dx2 * dx2;
    const CGFloat coef = (largeArc == sweep ? -1 : 1) * sqrt(MAX(0, num / den));
    const CGFloat cxp = coef * dy2, cyp = -coef * dx2;
    const CGPoint c = CGPointMake(cxp + (p1.x + p2.x) / 2, cyp + (p1.y + p2.y) / 2);
    const CGFloat start = atan2((dy2 - cyp) / r, (dx2 - cxp) / r);
    const CGFloat end = atan2((-dy2 - cyp) / r, (-dx2 - cxp) / r);
    // SVG 的 sweep = 1 是「角度增大」方向；y 轴朝下时就是屏幕上的顺时针，和 UIKit 的 clockwise 一致
    [path addArcWithCenter:c radius:r startAngle:start endAngle:end clockwise:sweep];
}

UIBezierPath *CINPathFromSVG(NSString *d) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSScanner *s = [NSScanner scannerWithString:d];
    s.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,\n\t"];
    NSCharacterSet *commands = [NSCharacterSet characterSetWithCharactersInString:@"MmLlHhVvAaZz"];
    CGPoint cur = CGPointZero, start = CGPointZero;
    unichar cmd = 'M';
    while (!s.isAtEnd) {
        NSString *c = nil;
        if ([s scanCharactersFromSet:commands intoString:&c]) {
            cmd = [c characterAtIndex:c.length - 1];
            if (cmd == 'Z' || cmd == 'z') {
                [path closePath];
                cur = start;
                continue;
            }
        }
        const BOOL rel = cmd >= 'a';
        double v[7] = {0};
        switch (cmd) {
            case 'M': case 'm': case 'L': case 'l': {
                if (![s scanDouble:&v[0]] || ![s scanDouble:&v[1]]) return path;
                const CGPoint p = rel ? CGPointMake(cur.x + v[0], cur.y + v[1]) : CGPointMake(v[0], v[1]);
                if (cmd == 'M' || cmd == 'm') {
                    [path moveToPoint:p];
                    start = p;
                    cmd = rel ? 'l' : 'L';   // M 后面跟的坐标按 L 处理
                } else {
                    [path addLineToPoint:p];
                }
                cur = p;
                break;
            }
            case 'H': case 'h':
                if (![s scanDouble:&v[0]]) return path;
                cur = CGPointMake(rel ? cur.x + v[0] : v[0], cur.y);
                [path addLineToPoint:cur];
                break;
            case 'V': case 'v':
                if (![s scanDouble:&v[0]]) return path;
                cur = CGPointMake(cur.x, rel ? cur.y + v[0] : v[0]);
                [path addLineToPoint:cur];
                break;
            case 'A': case 'a': {
                for (int i = 0; i < 7; ++i) {
                    if (![s scanDouble:&v[i]]) return path;
                }
                const CGPoint p = rel ? CGPointMake(cur.x + v[5], cur.y + v[6]) : CGPointMake(v[5], v[6]);
                CINAddArc(path, cur, p, (CGFloat)v[0], v[3] != 0, v[4] != 0);
                cur = p;
                break;
            }
            default:
                return path;
        }
    }
    return path;
}

static NSArray<NSString *> *CINIconPaths(CINIcon icon, BOOL *filled) {
    *filled = NO;
    switch (icon) {
        case CINIconTorch: return @[@"M13 2.5 L5 13.5 H11 L10 21.5 L19 10 H13 Z"];
        case CINIconFlip:
            return @[@"M4.5 11.5 A7.5 7.5 0 0 1 18 7.2", @"M18.6 3.6 V7.6 H14.6", @"M19.5 12.5 A7.5 7.5 0 0 1 6 16.8", @"M5.4 20.4 V16.4 H9.4"];
        case CINIconMore:
            *filled = YES;
            return @[@"M5 12 m-1.6 0 a1.6 1.6 0 1 0 3.2 0 a1.6 1.6 0 1 0 -3.2 0",
                     @"M12 12 m-1.6 0 a1.6 1.6 0 1 0 3.2 0 a1.6 1.6 0 1 0 -3.2 0",
                     @"M19 12 m-1.6 0 a1.6 1.6 0 1 0 3.2 0 a1.6 1.6 0 1 0 -3.2 0"];
        case CINIconFocus:
            return @[@"M4 9 V4 H9", @"M15 4 H20 V9", @"M20 15 V20 H15", @"M9 20 H4 V15", @"M12 12 m-3 0 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0"];
        case CINIconWhiteBalance:
            return @[@"M12 12 m-4 0 a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0", @"M12 2.5 V4.5", @"M12 19.5 V21.5", @"M2.5 12 H4.5", @"M19.5 12 H21.5",
                     @"M5.3 5.3 L6.7 6.7", @"M17.3 17.3 L18.7 18.7", @"M5.3 18.7 L6.7 17.3", @"M17.3 6.7 L18.7 5.3"];
        case CINIconShutter:
            return @[@"M12 12 m-9 0 a9 9 0 1 0 18 0 a9 9 0 1 0 -18 0", @"M12 3 L14.6 10.5", @"M19.8 7.5 L13.4 13", @"M19.8 16.5 L11 15.2",
                     @"M12 21 L9.4 13.5", @"M4.2 16.5 L10.6 11", @"M4.2 7.5 L13 8.8"];
        case CINIconExposure: return @[@"M4 4 H20 V20 H4 Z", @"M20 4 L4 20", @"M6.5 8.5 H11.5", @"M9 6 V11", @"M12.5 15.5 H17.5"];
        case CINIconClose: return @[@"M6 6 L18 18", @"M18 6 L6 18"];
        case CINIconPlus: return @[@"M12 5 V19", @"M5 12 H19"];
        case CINIconReset: return @[@"M5 12 A7 7 0 1 0 7.5 6.6", @"M4.5 3.5 V7.5 H8.5"];
    }
    return @[];
}

UIImage *CINIconImage(CINIcon icon, CGFloat size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
    });
    NSString *key = [NSString stringWithFormat:@"%ld/%.1f", (long)icon, size];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    BOOL filled = NO;
    NSArray<NSString *> *paths = CINIconPaths(icon, &filled);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        const CGFloat scale = size / 24.0;
        CGContextScaleCTM(ctx.CGContext, scale, scale);
        [UIColor.whiteColor set];
        for (NSString *d in paths) {
            UIBezierPath *p = CINPathFromSVG(d);
            if (filled) {
                [p fill];
            } else {
                p.lineWidth = 1.7;
                p.lineCapStyle = kCGLineCapRound;
                p.lineJoinStyle = kCGLineJoinRound;
                [p stroke];
            }
        }
    }];
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:image forKey:key];
    return image;
}
