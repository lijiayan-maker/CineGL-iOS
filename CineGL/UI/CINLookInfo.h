// CineGL — 影调信息（给界面用；对应安卓 core/CineCore.kt 里的 LookInfo）
// name 是中文名（导入的 LUT 为文件名），nameEn 是英文名（导入的 LUT 为 .cube 里的 TITLE，可能为空）。
// 界面语言跟随系统：简体中文用中文名，其他语言一律用英文名。
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CINLookInfo : NSObject

@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly, copy) NSString *lookId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *nameEn;
@property (nonatomic, readonly) BOOL isCube;

- (instancetype)initWithIndex:(NSInteger)index lookId:(NSString *)lookId name:(NSString *)name nameEn:(NSString *)nameEn isCube:(BOOL)isCube;
- (instancetype)init NS_UNAVAILABLE;

/** 卡片大字、角标、面板标题用的名字。导入的 LUT 两种语言都用文件名（那是用户自己起的名字）。 */
- (NSString *)titleForChinese:(BOOL)zh;
/** 卡片小字：中文界面配英文名；导入的 LUT 配 TITLE，没有 TITLE 返回 nil（界面显示「导入的 LUT」）；英文界面的内置影调不配小字。 */
- (nullable NSString *)subtitleForChinese:(BOOL)zh;
/** 缩略图出来之前影调按钮里的字：中文取前两个字，英文取前两个单词的首字母。 */
- (NSString *)badgeForChinese:(BOOL)zh;

/** 当前影调库的全部影调。 */
+ (NSArray<CINLookInfo *> *)allLooks;

@end

NS_ASSUME_NONNULL_END
