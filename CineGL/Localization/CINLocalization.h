// CineGL — 界面语言
//
// 规则（和安卓版一致）：系统首选语言是简体中文才显示中文，其他语言（包括繁体中文）一律显示英文。
// 这条规则在代码里判断，不交给系统按 CFBundleLocalizations 自动匹配——系统遇到繁体中文时
// 可能退回简体，和「非简体一律英文」不符。
// 文案在 en.lproj / zh-Hans.lproj 的 Localizable.strings，新增文案两边都要加（单测会检查键和占位符）。
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** 首选语言是不是简体中文（zh-Hans-*、zh-CN、zh-SG、不带地区的 zh）。 */
BOOL CINIsSimplifiedChineseLanguage(NSString *language);
/** 当前界面是不是简体中文。 */
BOOL CINUIIsChinese(void);
/** 按当前界面语言取文案；找不到就退回英文，再找不到返回键名。 */
NSString *CINL(NSString *key);
/** 单测用：强制界面语言（"zh-Hans" / "en"），传 nil 恢复跟随系统。 */
void CINSetLanguageOverride(NSString *_Nullable language);

NS_ASSUME_NONNULL_END
