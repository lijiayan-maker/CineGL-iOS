// 双语检查（对应安卓 I18nTest.kt）：系统为简体中文时显示中文，其他语言一律显示英文。
//  - 英文和简体中文的 Localizable.strings 键、占位符必须一一对应
//  - OC 代码里不能出现中文字符串字面量，否则英文界面会漏出中文（注释不算）
#import <XCTest/XCTest.h>

#import "CINLocalization.h"

@interface CINI18nTests : XCTestCase
@end

static NSString *CINSourcePath(NSString *relative) {
    return [@CIN_SRCROOT stringByAppendingPathComponent:relative];
}

static NSDictionary<NSString *, NSString *> *CINStrings(NSString *lproj) {
    NSString *path = CINSourcePath([NSString stringWithFormat:@"CineGL/Localization/%@.lproj/Localizable.strings", lproj]);
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

static NSArray<NSString *> *CINPlaceholders(NSString *text) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"%(\\d+\\$)?[-#+ 0,(]*\\d*(\\.\\d+)?[a-zA-Z@]" options:0 error:nil];
    NSMutableArray *out = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [out addObject:[text substringWithRange:m.range]];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

/** 去掉行尾的 // 注释（// 前面的引号数为偶数时才是注释，不是字符串里的 //）。 */
static NSString *CINStripLineComment(NSString *line) {
    NSUInteger from = 0;
    while (YES) {
        const NSRange r = [line rangeOfString:@"//" options:0 range:NSMakeRange(from, line.length - from)];
        if (r.location == NSNotFound) return line;
        NSString *before = [line substringToIndex:r.location];
        const NSUInteger quotes = [before componentsSeparatedByString:@"\""].count - 1;
        if (quotes % 2 == 0) return before;
        from = r.location + 2;
    }
}

@implementation CINI18nTests

- (void)tearDown {
    CINSetLanguageOverride(nil);
}

- (void)testSimplifiedChineseCoversEveryEnglishString {
    NSDictionary *en = CINStrings(@"en"), *zh = CINStrings(@"zh-Hans");
    XCTAssertGreaterThan(en.count, 80u);
    NSMutableSet *missing = [NSMutableSet setWithArray:en.allKeys];
    [missing minusSet:[NSSet setWithArray:zh.allKeys]];
    XCTAssertEqualObjects(missing, [NSSet set], @"zh-Hans is missing keys");
    NSMutableSet *extra = [NSMutableSet setWithArray:zh.allKeys];
    [extra minusSet:[NSSet setWithArray:en.allKeys]];
    XCTAssertEqualObjects(extra, [NSSet set], @"zh-Hans has keys English doesn't");
    for (NSString *key in en) {
        XCTAssertEqualObjects(CINPlaceholders(en[key]), CINPlaceholders(zh[key] ?: @""), @"placeholders differ for %@", key);
    }
}

- (void)testOnlySimplifiedChineseShowsChinese {
    XCTAssertTrue(CINIsSimplifiedChineseLanguage(@"zh-Hans-CN"));
    XCTAssertTrue(CINIsSimplifiedChineseLanguage(@"zh-Hans"));
    XCTAssertTrue(CINIsSimplifiedChineseLanguage(@"zh-CN"));
    XCTAssertFalse(CINIsSimplifiedChineseLanguage(@"zh-Hant-TW"));
    XCTAssertFalse(CINIsSimplifiedChineseLanguage(@"zh-Hant-HK"));
    XCTAssertFalse(CINIsSimplifiedChineseLanguage(@"en-US"));
    XCTAssertFalse(CINIsSimplifiedChineseLanguage(@"ja-JP"));
    CINSetLanguageOverride(@"zh-Hans-CN");
    XCTAssertEqualObjects(CINL(@"looks"), @"\u5f71\u8c03");
    CINSetLanguageOverride(@"zh-Hant-TW");
    XCTAssertEqualObjects(CINL(@"looks"), @"Looks");
    CINSetLanguageOverride(@"fr-FR");
    XCTAssertEqualObjects(CINL(@"looks"), @"Looks");
}

- (void)testNoHardcodedChineseInCode {
    NSRegularExpression *cjk = [NSRegularExpression regularExpressionWithPattern:@"\"[^\"\\n]*[\\u4e00-\\u9fff\\u3000-\\u303f\\uff00-\\uffef][^\"\\n]*\""
                                                                         options:0 error:nil];
    NSMutableArray *offenders = [NSMutableArray array];
    NSString *root = CINSourcePath(@"CineGL");
    NSDirectoryEnumerator *it = [NSFileManager.defaultManager enumeratorAtPath:root];
    for (NSString *rel in it) {
        if (![@[@"m", @"h"] containsObject:rel.pathExtension]) continue;
        NSString *text = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:rel] encoding:NSUTF8StringEncoding error:nil];
        __block BOOL inBlock = NO;
        __block NSUInteger lineNo = 0;
        [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            lineNo++;
            NSString *s = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (inBlock) {
                if ([s containsString:@"*/"]) inBlock = NO;
                return;
            }
            if ([s hasPrefix:@"/*"]) {
                inBlock = ![s containsString:@"*/"];
                return;
            }
            if ([s hasPrefix:@"*"]) return;
            NSString *code = CINStripLineComment(line);
            if ([cjk firstMatchInString:code options:0 range:NSMakeRange(0, code.length)]) {
                [offenders addObject:[NSString stringWithFormat:@"%@:%lu  %@", rel, (unsigned long)lineNo, s]];
            }
        }];
    }
    XCTAssertEqual(offenders.count, 0u, @"UI text belongs in Localizable.strings:\n%@", [offenders componentsJoinedByString:@"\n"]);
}

@end
