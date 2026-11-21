#import "CINLookInfo.h"

#import "CINLooks.h"

@implementation CINLookInfo

- (instancetype)initWithIndex:(NSInteger)index lookId:(NSString *)lookId name:(NSString *)name nameEn:(NSString *)nameEn isCube:(BOOL)isCube {
    if ((self = [super init])) {
        _index = index;
        _lookId = [lookId copy];
        _name = [name copy];
        _nameEn = [nameEn copy];
        _isCube = isCube;
    }
    return self;
}

- (NSString *)titleForChinese:(BOOL)zh {
    return self.isCube || zh ? self.name : self.nameEn;
}

- (NSString *)subtitleForChinese:(BOOL)zh {
    if (self.isCube) return self.nameEn.length ? self.nameEn : nil;
    return zh ? self.nameEn : nil;
}

/** 前 n 个「字」（按用户看到的字符算，不会把 emoji、组合字符劈开）。 */
static NSString *CINPrefix(NSString *s, NSUInteger n) {
    __block NSUInteger count = 0;
    __block NSUInteger end = 0;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length) options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *sub, NSRange range, NSRange enclosing, BOOL *stop) {
        if (count == n) {
            *stop = YES;
            return;
        }
        count++;
        end = NSMaxRange(range);
    }];
    return [s substringToIndex:end];
}

- (NSString *)badgeForChinese:(BOOL)zh {
    NSString *t = [self titleForChinese:zh];
    if (zh) return CINPrefix(t, 2);
    NSMutableString *initials = [NSMutableString string];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" -_"];
    for (NSString *word in [t componentsSeparatedByCharactersInSet:separators]) {
        if (word.length == 0 || ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[word characterAtIndex:0]]) continue;
        [initials appendString:[CINPrefix(word, 1) uppercaseString]];
        if (initials.length >= 2) break;
    }
    return initials.length ? initials : CINPrefix(t, 2);
}

+ (NSArray<CINLookInfo *> *)allLooks {
    CINLookLibrary *lib = CINLookLibrary.shared;
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger i = 0; i < lib.count; ++i) {
        CINLook *look = [lib lookAtIndex:i];
        if (!look) continue;
        [out addObject:[[CINLookInfo alloc] initWithIndex:i lookId:look.lookId name:look.name nameEn:look.nameEn isCube:look.isCube]];
    }
    return out;
}

@end
