// CineGL — 影调 LUT 的「烘焙 → 上传」调度
//
// 烘焙（CPU 算 33³ 个格点）放在后台队列，上传必须回到渲染队列（引擎只在那里用）。
// 工作信号的编码一变（开/关 Log），所有表都要重烘：表里已经包含了「解码 Log」这一步。
// 用 generation 计数丢弃过期结果——切得快时，旧编码的表烘完了也不能再上传。
//
// 除构造外，所有方法都只能在渲染队列上调用。
#pragma once

#import "CINEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface CINLutBank : NSObject

- (instancetype)initWithEngine:(CINEngine *)engine renderQueue:(dispatch_queue_t)queue;
- (instancetype)init NS_UNAVAILABLE;

/** 已经上传完、可以用的影调索引（升序）。 */
@property (nonatomic, readonly) NSArray<NSNumber *> *readyLooks;

/** 编码变了就作废所有表：中性 LUT 同步烘，影调 LUT 后台烘（priority 先烘）。 */
- (void)ensureEncoding:(CINEncoding)encoding priority:(NSInteger)priority;
/** 烘一张（新导入的 .cube 也走这里）。 */
- (void)bake:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
