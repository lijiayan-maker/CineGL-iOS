#import "CINSceneDelegate.h"

#import "CINRootViewController.h"

@implementation CINSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.backgroundColor = UIColor.blackColor;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.rootViewController = [[CINRootViewController alloc] init];
    [window makeKeyAndVisible];
    self.window = window;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // 取景时别息屏
    UIApplication.sharedApplication.idleTimerDisabled = YES;
}

- (void)sceneWillResignActive:(UIScene *)scene {
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

@end
