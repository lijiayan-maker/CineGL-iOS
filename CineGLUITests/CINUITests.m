// CineGL — UI 测试：把主要功能点一遍；设置了截图目录时顺便拍 README 用的截图。
//
// 截图：TEST_RUNNER_CIN_SHOT_DIR=<目录> TEST_RUNNER_CIN_LANG=zh-Hans|en xcodebuild test ... -only-testing:CineGLUITests/CINUITests/testScreenshots
// 每张图存成 <名字>.png，同时把关键控件的位置写进 <名字>.json（点为单位），tools/make_readme_images.py 用它们裁图、标号。
#import <XCTest/XCTest.h>

@interface CINUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@property (nonatomic, copy) NSString *shotDir;
@property (nonatomic, copy) NSString *lang;
@end

@implementation CINUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    self.shotDir = env[@"CIN_SHOT_DIR"];
    self.lang = env[@"CIN_LANG"] ?: @"zh-Hans";
}

- (void)launchWith:(NSArray<NSString *> *)extra {
    [self.app terminate];
    XCUIApplication *app = [[XCUIApplication alloc] init];
    NSString *locale = [self.lang hasPrefix:@"zh"] ? @"zh_CN" : @"en_US";
    app.launchArguments = [@[@"-AppleLanguages", [NSString stringWithFormat:@"(%@)", self.lang], @"-AppleLocale", locale,
                             @"-CINResetState", @"YES"] arrayByAddingObjectsFromArray:extra];
    [app launch];
    self.app = app;
    XCTAssertTrue([[self e:@"shutter"] waitForExistenceWithTimeout:10]);
    [self pause:2.0];   // 等 LUT 烘完、缩略图出来
}

- (XCUIElement *)e:(NSString *)identifier {
    return [[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:identifier].firstMatch;
}

- (void)tap:(NSString *)identifier {
    XCUIElement *el = [self e:identifier];
    XCTAssertTrue([el waitForExistenceWithTimeout:5], @"%@ not found", identifier);
    [el tap];
    [self pause:0.4];
}

- (void)pause:(NSTimeInterval)seconds {
    [NSThread sleepForTimeInterval:seconds];
}

/** 把 0..10 的滑杆点到某个值（滑块中心在 [2, w - 2] 之间）。滑杆在滚动区外面时先滚进来。 */
- (void)setSlider:(NSString *)identifier value:(double)v {
    XCUIElement *s = [self e:identifier];
    XCTAssertTrue([s waitForExistenceWithTimeout:5]);
    XCUIElement *box = [self e:@"looks.sliders"];
    for (int i = 0; i < 3 && box.exists; ++i) {
        const CGRect f = s.frame, b = box.frame;
        if (CGRectGetMaxY(f) > CGRectGetMaxY(b) + 1) {
            [[box coordinateWithNormalizedOffset:CGVectorMake(0.05, 0.8)] pressForDuration:0.05
                                                                     thenDragToCoordinate:[box coordinateWithNormalizedOffset:CGVectorMake(0.05, 0.3)]];
        } else if (CGRectGetMinY(f) < CGRectGetMinY(b) - 1) {
            [[box coordinateWithNormalizedOffset:CGVectorMake(0.05, 0.3)] pressForDuration:0.05
                                                                     thenDragToCoordinate:[box coordinateWithNormalizedOffset:CGVectorMake(0.05, 0.8)]];
        } else {
            break;
        }
        [self pause:0.5];
    }
    const CGFloat w = s.frame.size.width;
    const CGFloat x = (2 + v / 10.0 * (w - 4)) / w;
    [[s coordinateWithNormalizedOffset:CGVectorMake(x, 0.5)] tap];
    [self pause:0.2];
}

/** 刻度盘往左拖（正数）或往右拖（负数）dx 点。 */
- (void)dragDial:(CGFloat)dx {
    XCUIElement *dial = [self e:@"dial"];
    XCTAssertTrue([dial waitForExistenceWithTimeout:5]);
    XCUICoordinate *start = [dial coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.7)];
    XCUICoordinate *end = [start coordinateWithOffset:CGVectorMake(-dx, 0)];
    [start pressForDuration:0.05 thenDragToCoordinate:end];
    [self pause:0.5];
}

- (void)setEffects:(NSArray<NSNumber *> *)values {
    for (NSUInteger i = 0; i < values.count; ++i) [self setSlider:[NSString stringWithFormat:@"fx.%lu", (unsigned long)i] value:values[i].doubleValue];
}

- (void)snap:(NSString *)name {
    if (!self.shotDir) return;
    [self pause:0.6];
    NSData *png = XCUIScreen.mainScreen.screenshot.PNGRepresentation;
    [NSFileManager.defaultManager createDirectoryAtPath:self.shotDir withIntermediateDirectories:YES attributes:nil error:nil];
    [png writeToFile:[self.shotDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
    NSMutableDictionary *frames = [NSMutableDictionary dictionary];
    for (NSString *ident in @[@"meter", @"mode.0", @"mode.1", @"torch", @"flip", @"more", @"chips", @"preview", @"tool.focus",
                              @"tool.ev", @"tool.reset", @"gallery", @"shutter", @"looks"]) {
        XCUIElement *el = [self e:ident];
        if (!el.exists) continue;
        const CGRect f = el.frame;
        frames[ident] = @[@(f.origin.x), @(f.origin.y), @(f.size.width), @(f.size.height)];
    }
    XCUIElement *preview = [self e:@"preview"];
    if (preview.exists) frames[@"frameRect"] = preview.value ?: @"";
    frames[@"scale"] = @(UIScreen.mainScreen.scale);
    NSData *json = [NSJSONSerialization dataWithJSONObject:frames options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[self.shotDir stringByAppendingPathComponent:[name stringByAppendingString:@".json"]] atomically:YES];
}

#pragma mark - 功能走查

- (void)testBasicFlow {
    [self launchWith:@[]];
    // 影调面板：选影调、调效果、重置
    [self tap:@"looks"];
    XCTAssertTrue([[self e:@"look.silver"] waitForExistenceWithTimeout:3]);
    [self tap:@"look.silver"];
    [self setSlider:@"fx.1" value:8];
    XCTAssertTrue([self e:@"looks.reset"].isEnabled);
    [self tap:@"looks.reset"];
    [self tap:@"panel.close"];
    // 手动 ISO：切手动、拖刻度盘，工具栏的「重置」亮起，再一键恢复
    [self tap:@"tool.iso"];
    [self tap:@"dial.auto"];
    [self dragDial:60];
    XCTAssertTrue([self e:@"tool.reset"].isEnabled);
    [self tap:@"tool.reset"];
    XCTAssertFalse([self e:@"tool.reset"].isEnabled);
    // 设置：画幅、Log、辅助
    [self tap:@"more"];
    [self tap:@"aspect.1"];
    [self tap:@"log.1"];
    XCTAssertTrue([self e:@"burnIn"].isEnabled);
    [self tap:@"log.0"];
    [self tap:@"panel.close"];
    // 录 2 秒视频
    [self tap:@"shutter"];
    [self pause:2.5];
    [self tap:@"shutter"];
    XCTAssertTrue([self waitForGallery]);
    // 拍一张照片
    [self tap:@"mode.0"];
    [self pause:1.5];
    [self tap:@"shutter"];
    XCTAssertTrue([self waitForGallery]);
}

- (BOOL)waitForGallery {
    XCUIElement *g = [self e:@"gallery"];
    NSPredicate *enabled = [NSPredicate predicateWithFormat:@"enabled == YES"];
    XCTNSPredicateExpectation *exp = [[XCTNSPredicateExpectation alloc] initWithPredicate:enabled object:g];
    return [XCTWaiter waitForExpectations:@[exp] timeout:15] == XCTWaiterResultCompleted;
}

#pragma mark - README 截图

- (void)testScreenshots {
    if (!self.shotDir) {
        XCTSkip(@"set TEST_RUNNER_CIN_SHOT_DIR to take screenshots");
    }
    NSString *seed = NSProcessInfo.processInfo.environment[@"CIN_SEED_LUT"];

    // —— 界面一览、影调面板 ——
    [self launchWith:@[]];
    [self snap:@"ui-overview"];
    [self tap:@"looks"];
    [self snap:@"look-panel"];

    // —— 11 个影调对比：胶片效果全部为 0 ——
    [self setEffects:@[@10, @0, @0, @0, @3, @0, @0]];
    NSArray *looks = @[@"natural", @"teal_orange", @"warm_film", @"nordic", @"matte", @"silver", @"neon", @"forest",
                       @"golden_hour", @"bleach", @"chrome"];
    [self setSlider:@"fx.0" value:0];
    [self tap:@"panel.close"];
    [self snap:@"look-original"];
    [self tap:@"looks"];
    [self setSlider:@"fx.0" value:10];
    for (NSString *look in looks) {
        [self tap:[@"look." stringByAppendingString:look]];
        [self tap:@"panel.close"];
        [self pause:0.3];
        [self snap:[@"look-" stringByAppendingString:look]];
        [self tap:@"looks"];
    }

    // —— 胶片效果对比（影调：原生）——
    [self tap:@"look.natural"];
    NSArray *fx = @[@[@"fx-none", @[@10, @0, @0, @0, @3, @0, @0]], @[@"fx-halation", @[@10, @10, @0, @0, @3, @0, @0]],
                    @[@"fx-mist", @[@10, @0, @10, @0, @3, @0, @0]], @[@"fx-grain", @[@10, @0, @0, @10, @3, @0, @0]],
                    @[@"fx-vignette", @[@10, @0, @0, @0, @3, @10, @0]], @[@"fx-aberration", @[@10, @0, @0, @0, @3, @0, @10]]];
    for (NSArray *item in fx) {
        [self setEffects:item[1]];
        [self tap:@"panel.close"];
        [self snap:item[0]];
        [self tap:@"looks"];
    }
    [self tap:@"looks.reset"];
    [self tap:@"look.teal_orange"];
    [self tap:@"panel.close"];

    // —— Log：直出 / Log 原片 / Log + 影调，设置面板，Log 监看 ——
    [self tap:@"looks"];
    [self tap:@"look.natural"];
    [self setEffects:@[@10, @0, @0, @0, @3, @0, @0]];
    [self tap:@"panel.close"];
    [self snap:@"log-709"];
    [self tap:@"more"];
    [self tap:@"log.1"];
    [self tap:@"showSignal"];
    [self tap:@"panel.close"];
    [self snap:@"log-signal"];
    [self tap:@"looks"];
    [self tap:@"look.teal_orange"];
    [self tap:@"panel.close"];
    [self tap:@"more"];
    [self tap:@"showSignal"];
    [self tap:@"panel.close"];
    [self snap:@"log-graded"];
    [self tap:@"looks"];
    [self tap:@"looks.reset"];
    [self tap:@"panel.close"];
    [self tap:@"more"];
    [self snap:@"settings"];
    [[self e:@"settings.scroll"] swipeUp];
    [self pause:0.6];
    [self snap:@"settings-assist"];
    [self tap:@"showSignal"];
    [self tap:@"assist.waveform"];
    [self tap:@"panel.close"];
    [self snap:@"log-monitor"];
    [self tap:@"more"];
    [[self e:@"settings.scroll"] swipeUp];
    [self tap:@"showSignal"];
    [self tap:@"assist.waveform"];
    [[self e:@"settings.scroll"] swipeDown];
    [self tap:@"log.0"];
    [self tap:@"panel.close"];

    // —— 监看辅助 ——
    for (NSString *assist in @[@"zebra", @"peaking", @"waveform"]) {
        [self tap:@"more"];
        [[self e:@"settings.scroll"] swipeUp];
        [self tap:[@"assist." stringByAppendingString:assist]];
        [self tap:@"panel.close"];
        if ([assist isEqualToString:@"zebra"]) {
            // 斑马纹：曝光补偿 +1，让窗户和墙面亮部过曝
            [self tap:@"tool.ev"];
            [self dragDial:27];
            [self tap:@"tool.ev"];
        }
        [self snap:[@"assist-" stringByAppendingString:assist]];
        if ([assist isEqualToString:@"zebra"]) {
            [self tap:@"tool.ev"];
            [self tap:@"dial.auto"];
            [self tap:@"tool.ev"];
        }
        [self tap:@"more"];
        [[self e:@"settings.scroll"] swipeUp];
        [self tap:[@"assist." stringByAppendingString:assist]];
        [self tap:@"panel.close"];
    }

    // —— 手动参数、一键重置 ——
    [self tap:@"tool.iso"];
    [self tap:@"dial.auto"];
    [self dragDial:-60];
    [self snap:@"manual-iso"];
    [self tap:@"dial.auto"];
    [self tap:@"tool.wb"];
    [self dragDial:200];
    [self snap:@"manual-wb"];
    [self tap:@"tool.wb"];
    [self tap:@"tool.shutter"];
    [self tap:@"dial.auto"];
    [self dragDial:40];
    [self tap:@"tool.shutter"];
    [self snap:@"reset-before"];
    [self tap:@"tool.reset"];
    [self pause:0.3];
    [self snap:@"reset-after"];
    [self pause:2.5];   // 等提示消失

    // —— 画幅 ——
    for (NSUInteger i = 0; i < 4; ++i) {
        [self tap:@"more"];
        [self tap:[NSString stringWithFormat:@"aspect.%lu", (unsigned long)i]];
        [self tap:@"panel.close"];
        [self pause:1.0];
        [self snap:[NSString stringWithFormat:@"aspect-%lu", (unsigned long)i]];
    }
    [self tap:@"more"];
    [self tap:@"aspect.0"];
    [self tap:@"panel.close"];

    // —— 录像、照片模式、拍一张 ——
    [self tap:@"shutter"];
    [self pause:4.2];
    [self snap:@"recording"];
    [self tap:@"shutter"];
    XCTAssertTrue([self waitForGallery]);
    [self tap:@"mode.0"];
    [self pause:1.5];
    [self snap:@"ui-photo"];
    [self tap:@"shutter"];
    XCTAssertTrue([self waitForGallery]);
    [self pause:1.0];
    [self snap:@"ui-photo-taken"];

    // —— 导入的 .cube（文件选择器是系统界面，改用启动参数把文件放进导入目录）——
    if (seed.length) {
        [self launchWith:@[@"-CINSeedLut", seed]];
        [self tap:@"looks"];
        XCUIElement *card = [[self.app descendantsMatchingType:XCUIElementTypeAny]
                             matchingPredicate:[NSPredicate predicateWithFormat:@"identifier BEGINSWITH 'look.cube:'"]].firstMatch;
        XCTAssertTrue([card waitForExistenceWithTimeout:5]);
        [card tap];
        [self pause:1.5];
        [self snap:@"cube-import"];
    }
}

@end
