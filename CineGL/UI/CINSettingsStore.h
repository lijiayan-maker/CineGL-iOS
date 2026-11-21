// CineGL — 记住用户上次的选择（模式、画幅、影调、效果……），键名和安卓 SettingsStore.kt 一致
#pragma once

#import "CINCameraState.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINSettingsStore : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
/** 读出来的设置填进一个新的默认状态。 */
- (CINCameraState *)load;
- (void)save:(CINCameraState *)state;
@end

NS_ASSUME_NONNULL_END
