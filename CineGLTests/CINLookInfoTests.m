// 影调名字跟随界面语言（对应安卓 LookInfoTest.kt）：简体中文界面用中文名，其他语言用英文名；导入的 LUT 始终用文件名。
// 另外检查设置的读写：键名、枚举名和安卓 SharedPreferences 里的一致。
#import <XCTest/XCTest.h>

#import "CINCameraState.h"
#import "CINCubeLut.h"
#import "CINLookInfo.h"
#import "CINSettingsStore.h"

@interface CINLookInfoTests : XCTestCase
@end

@implementation CINLookInfoTests

- (CINLookInfo *)tealOrange {
    return [[CINLookInfo alloc] initWithIndex:1 lookId:@"teal_orange" name:@"青橙" nameEn:@"Teal & Orange" isCube:NO];
}

- (void)testBuiltinLookFollowsUiLanguage {
    CINLookInfo *t = [self tealOrange];
    XCTAssertEqualObjects([t titleForChinese:YES], @"青橙");
    XCTAssertEqualObjects([t subtitleForChinese:YES], @"Teal & Orange");
    XCTAssertEqualObjects([t titleForChinese:NO], @"Teal & Orange");
    XCTAssertNil([t subtitleForChinese:NO]);   // 英文界面不配中文小字
}

- (void)testImportedLutKeepsFileName {
    CINLookInfo *cyan = [[CINLookInfo alloc] initWithIndex:11 lookId:@"cube:Cyan.cube" name:@"Cyan" nameEn:@"Cyan Fade" isCube:YES];
    CINLookInfo *untitled = [[CINLookInfo alloc] initWithIndex:12 lookId:@"cube:mine.cube" name:@"我的胶片" nameEn:@"" isCube:YES];
    XCTAssertEqualObjects([cyan titleForChinese:YES], @"Cyan");
    XCTAssertEqualObjects([cyan titleForChinese:NO], @"Cyan");
    XCTAssertEqualObjects([cyan subtitleForChinese:NO], @"Cyan Fade");   // .cube 里的 TITLE
    XCTAssertEqualObjects([untitled titleForChinese:NO], @"我的胶片");
    XCTAssertNil([untitled subtitleForChinese:YES]);   // 没有 TITLE：界面显示「导入的 LUT / Imported LUT」
}

- (void)testBadgeBeforeThumbnailArrives {
    XCTAssertEqualObjects([[self tealOrange] badgeForChinese:YES], @"青橙");
    XCTAssertEqualObjects([[self tealOrange] badgeForChinese:NO], @"TO");
    CINLookInfo *natural = [[CINLookInfo alloc] initWithIndex:0 lookId:@"natural" name:@"原生" nameEn:@"Natural" isCube:NO];
    XCTAssertEqualObjects([natural badgeForChinese:NO], @"N");
    CINLookInfo *bleach = [[CINLookInfo alloc] initWithIndex:9 lookId:@"bleach" name:@"漂白" nameEn:@"Bleach Bypass" isCube:NO];
    XCTAssertEqualObjects([bleach badgeForChinese:NO], @"BB");
    CINLookInfo *untitled = [[CINLookInfo alloc] initWithIndex:12 lookId:@"cube:mine.cube" name:@"我的胶片" nameEn:@"" isCube:YES];
    XCTAssertEqualObjects([untitled badgeForChinese:YES], @"我的");
}

- (void)testAllLooksComeFromLibrary {
    NSArray<CINLookInfo *> *looks = [CINLookInfo allLooks];
    XCTAssertGreaterThanOrEqual(looks.count, 11u);
    XCTAssertEqualObjects(looks[1].lookId, @"teal_orange");
    XCTAssertEqual(looks[1].index, 1);
}

- (void)testCubeErrorCodesAreStable {
    // 数值和安卓 cinegl::CubeError 一致，界面按它们挑文案
    XCTAssertEqual(CINCubeErrorSizeOutOfRange, 1);
    XCTAssertEqual(CINCubeErrorCountMismatch, 6);
    XCTAssertEqual(CINCubeErrorMissingSize, 8);
}

#pragma mark - 设置

- (void)testSettingsRoundTrip {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"cinegl-tests"];
    [d removePersistentDomainForName:@"cinegl-tests"];
    CINSettingsStore *store = [[CINSettingsStore alloc] initWithDefaults:d];
    CINCameraState *s = [store load];
    // 默认值和安卓一致：视频、16:9、1080p、30fps、Log 关、LUT 烧录开、青橙
    XCTAssertEqual(s.mode, CINCaptureModeVideo);
    XCTAssertEqual(s.aspect, CINAspectRatio16x9);
    XCTAssertEqual(s.fps, 30);
    XCTAssertTrue(s.burnIn);
    XCTAssertEqualObjects(s.lookId, @"teal_orange");
    XCTAssertTrue(CINEffectsEqual(s.effects, CINEffectsDefault()));
    XCTAssertTrue(s.assist.grid && s.assist.level && !s.assist.zebra);

    s.mode = CINCaptureModePhoto;
    s.aspect = CINAspectRatio239x1;
    s.logMode = CINLogModeGpu;
    s.lookId = @"silver";
    CINEffects e = s.effects;
    e.halation = 7.5f;
    s.effects = e;
    CINAssist a = s.assist;
    a.waveform = true;
    s.assist = a;
    [store save:s];
    XCTAssertEqualObjects([d stringForKey:@"aspect"], @"R239");
    XCTAssertEqualObjects([d stringForKey:@"logMode"], @"GPU");
    XCTAssertEqualWithAccuracy([d floatForKey:@"fx.halation"], 7.5, 1e-6);

    CINCameraState *back = [store load];
    XCTAssertEqual(back.mode, CINCaptureModePhoto);
    XCTAssertEqual(back.aspect, CINAspectRatio239x1);
    XCTAssertEqual(back.logMode, CINLogModeGpu);
    XCTAssertEqualObjects(back.lookId, @"silver");
    XCTAssertEqualWithAccuracy(back.effects.halation, 7.5, 1e-6);
    XCTAssertTrue(back.assist.waveform);
    [d removePersistentDomainForName:@"cinegl-tests"];
}

- (void)testUnknownEnumNamesFallBack {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"cinegl-tests-2"];
    [d setObject:@"R21x9" forKey:@"aspect"];
    CINCameraState *s = [[[CINSettingsStore alloc] initWithDefaults:d] load];
    XCTAssertEqual(s.aspect, CINAspectRatio16x9);
    [d removePersistentDomainForName:@"cinegl-tests-2"];
}

- (void)testCanResetControls {
    CINCameraState *s = [[CINCameraState alloc] init];
    XCTAssertFalse(s.canResetControls);
    s.hasFocusPoint = YES;   // 点击对焦锁定了区域也算
    XCTAssertTrue(s.canResetControls);
    s.hasFocusPoint = NO;
    CINCameraControls c = s.controls;
    c.isoAuto = false;
    s.controls = c;
    XCTAssertTrue(s.canResetControls);
}

@end
