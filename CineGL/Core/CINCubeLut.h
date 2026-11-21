// CineGL core — .cube 3D LUT 解析（Adobe / Resolve 通用格式）
#pragma once

#import "CINColor.h"

NS_ASSUME_NONNULL_BEGIN

/** .cube 解析失败的原因。数值与界面侧的错误文案一一对应，只能追加、不要改已有的值。 */
typedef NS_ENUM(int, CINCubeError) {
    CINCubeErrorNone = 0,
    CINCubeErrorSizeOutOfRange = 1,   // LUT_3D_SIZE 不在 2..256
    CINCubeErrorUnsupported1D = 2,    // 1D LUT（LUT_1D_SIZE）
    CINCubeErrorBadDomain = 3,        // DOMAIN_MIN / DOMAIN_MAX 不是 3 个数（line 有效）
    CINCubeErrorBadData = 4,          // 数据行不是 3 个数（line 有效）
    CINCubeErrorDataBeforeSize = 5,   // 数据出现在 LUT_3D_SIZE 之前（line 有效）
    CINCubeErrorCountMismatch = 6,    // 数据行数与 LUT_3D_SIZE³ 不符（count / expected 有效）
    CINCubeErrorDomainOrder = 7,      // DOMAIN_MAX 没有大于 DOMAIN_MIN
    CINCubeErrorMissingSize = 8,      // 整个文件都没有 LUT_3D_SIZE
};

/**
 * 失败原因 + 定位信息。核心只给错误码和数字，界面文案由调用方按系统语言生成，
 * 这样核心不用关心界面是中文还是英文。
 */
typedef struct {
    CINCubeError code;
    int line;       // 出错的行号（从 1 开始）
    int count;      // CountMismatch：实际的数据行数
    int expected;   // CountMismatch：应有的行数（LUT_3D_SIZE³）
} CINCubeParseError;

/** 英文描述，只给日志和单测用。 */
NSString *CINCubeParseErrorDescribe(CINCubeParseError error);

@interface CINCubeLut : NSObject

@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) int size;   // 每个维度的格点数
@property (nonatomic, readonly) CINVec3 domainMin;
@property (nonatomic, readonly) CINVec3 domainMax;

/** 格点值。数据顺序：R 变化最快，其次 G，最后 B。 */
- (CINVec3)atR:(int)r g:(int)g b:(int)b;

/** 三线性插值采样（输入按 DOMAIN 归一化）。 */
- (CINVec3)sample:(CINVec3)input;

/**
 * 解析 .cube 文本。只支持 3D LUT（LUT_3D_SIZE），1D LUT 会报错。
 * 失败返回 nil，并把原因写进 error（可为 NULL）。
 */
+ (nullable CINCubeLut *)parseText:(NSString *)text error:(nullable CINCubeParseError *)error;
+ (nullable CINCubeLut *)parseData:(NSData *)data error:(nullable CINCubeParseError *)error;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
