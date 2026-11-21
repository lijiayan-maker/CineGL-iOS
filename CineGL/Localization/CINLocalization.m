#import "CINLocalization.h"

static NSString *gOverride;

BOOL CINIsSimplifiedChineseLanguage(NSString *language) {
    NSString *l = language.lowercaseString;
    return [l hasPrefix:@"zh-hans"] || [l isEqualToString:@"zh"] || [l hasPrefix:@"zh-cn"] || [l hasPrefix:@"zh-sg"];
}

BOOL CINUIIsChinese(void) {
    if (gOverride) return CINIsSimplifiedChineseLanguage(gOverride);
    NSString *first = NSLocale.preferredLanguages.firstObject ?: @"en";
    return CINIsSimplifiedChineseLanguage(first);
}

static NSBundle *CINBundleFor(NSString *lproj) {
    NSString *path = [NSBundle.mainBundle pathForResource:lproj ofType:@"lproj"];
    return path ? [NSBundle bundleWithPath:path] : nil;
}

NSString *CINL(NSString *key) {
    static NSBundle *zh, *en;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        zh = CINBundleFor(@"zh-Hans");
        en = CINBundleFor(@"en");
    });
    static NSString *const kMissing = @"\x01missing";
    if (CINUIIsChinese()) {
        NSString *s = [zh localizedStringForKey:key value:kMissing table:nil];
        if (s && ![s isEqualToString:kMissing]) return s;
    }
    NSString *s = [en localizedStringForKey:key value:kMissing table:nil];
    return s && ![s isEqualToString:kMissing] ? s : key;
}

void CINSetLanguageOverride(NSString *language) {
    gOverride = [language copy];
}
