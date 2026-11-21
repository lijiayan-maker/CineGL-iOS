#import "CINAppDelegate.h"

@implementation CINAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
#if DEBUG
    [self applyDebugLaunchArguments];
#endif
    return YES;
}

#if DEBUG
/**
 * 只在 Debug 包里生效的启动参数，给 UI 测试和截图用：
 *   -CINResetState YES   清掉设置、导入的 LUT 和「最近一次拍摄」，从出厂状态启动
 *   -CINSeedLut <路径>    启动前把一个 .cube 放进导入目录（截「导入的 LUT」用，文件选择器是系统界面，测试点不了）
 */
- (void)applyDebugLaunchArguments {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *luts = [support URLByAppendingPathComponent:@"luts" isDirectory:YES];
    if ([d boolForKey:@"CINResetState"]) {
        [d removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        [fm removeItemAtURL:luts error:nil];
        NSURL *caches = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        [fm removeItemAtURL:[caches URLByAppendingPathComponent:@"LastCapture"] error:nil];
    }
    NSString *seed = [d stringForKey:@"CINSeedLut"];
    if (seed.length) {
        [fm createDirectoryAtURL:luts withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *dst = [luts URLByAppendingPathComponent:seed.lastPathComponent];
        [fm removeItemAtURL:dst error:nil];
        [fm copyItemAtURL:[NSURL fileURLWithPath:seed] toURL:dst error:nil];
    }
}
#endif

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

@end
