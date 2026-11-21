#import <XCTest/XCTest.h>

/** 工程骨架冒烟测试：测试 target 能挂到 App 上跑起来。 */
@interface CINSmokeTests : XCTestCase
@end

@implementation CINSmokeTests

- (void)testHostAppLoaded {
    XCTAssertNotNil(NSClassFromString(@"CINRootViewController"));
}

@end
