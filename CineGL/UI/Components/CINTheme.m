#import "CINTheme.h"

UIColor *CINColorARGB(uint32_t argb) {
    return [UIColor colorWithRed:((argb >> 16) & 0xFF) / 255.0
                           green:((argb >> 8) & 0xFF) / 255.0
                            blue:(argb & 0xFF) / 255.0
                           alpha:((argb >> 24) & 0xFF) / 255.0];
}

@implementation CINColors
+ (UIColor *)background { return CINColorARGB(0xFF000000); }
+ (UIColor *)panel { return CINColorARGB(0xF0111113); }
+ (UIColor *)surface { return CINColorARGB(0xFF1A1A1D); }
+ (UIColor *)surfaceHigh { return CINColorARGB(0xFF2A2A2E); }
+ (UIColor *)accent { return CINColorARGB(0xFFFF8A3D); }
+ (UIColor *)textPrimary { return CINColorARGB(0xFFF2F2F2); }
+ (UIColor *)textSecondary { return CINColorARGB(0xFF8E8E93); }
+ (UIColor *)record { return CINColorARGB(0xFFFF3B30); }
+ (UIColor *)meterGreen { return CINColorARGB(0xFF34D399); }
+ (UIColor *)meterYellow { return CINColorARGB(0xFFFBBF24); }
+ (UIColor *)meterRed { return CINColorARGB(0xFFF87171); }
+ (UIColor *)outline { return CINColorARGB(0xFF938F99); }
+ (UIColor *)surfaceContainerHighest { return CINColorARGB(0xFF36343B); }
@end

UIFont *CINFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}
