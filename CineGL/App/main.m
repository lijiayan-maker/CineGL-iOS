#import <UIKit/UIKit.h>

#import "CINAppDelegate.h"

int main(int argc, char *argv[]) {
    NSString *appDelegateClassName;
    @autoreleasepool {
        appDelegateClassName = NSStringFromClass([CINAppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
