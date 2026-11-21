#import "CINLooks.h"

#import <os/lock.h>

CINLookRecipe CINLookRecipeDefault(void) {
    CINLookRecipe r;
    memset(&r, 0, sizeof(r));
    r.saturation = 1.f;
    r.monoWeights = CINVec3Make(0.30f, 0.59f, 0.11f);
    r.contrast = 1.f;
    r.pivot = 0.43f;
    r.whitePoint = 1.f;
    return r;
}

@interface CINLook ()
- (instancetype)initWithId:(NSString *)lookId name:(NSString *)name nameEn:(NSString *)nameEn
                    recipe:(CINLookRecipe)recipe cube:(nullable CINCubeLut *)cube;
@end

@implementation CINLook

- (instancetype)initWithId:(NSString *)lookId name:(NSString *)name nameEn:(NSString *)nameEn
                    recipe:(CINLookRecipe)recipe cube:(CINCubeLut *)cube {
    if ((self = [super init])) {
        _lookId = [lookId copy];
        _name = [name copy];
        _nameEn = [nameEn copy];
        _recipe = recipe;
        _cube = cube;
        _isCube = cube != nil;
    }
    return self;
}

@end

static void CINAddHue(CINLookRecipe *r, float center, float width, float shift, float saturation) {
    if (r->hueCount >= CIN_MAX_HUE_ADJUSTS) return;
    r->hues[r->hueCount++] = (CINHueAdjust){center, width, shift, saturation};
}

static CINLook *CINRecipeLook(NSString *lookId, NSString *name, NSString *nameEn, CINLookRecipe r) {
    return [[CINLook alloc] initWithId:lookId name:name nameEn:nameEn recipe:r cube:nil];
}

// 中文名是数据（显示哪个由界面按系统语言决定），用 \u 转义写，避免代码里出现中文字面量
static NSArray<CINLook *> *CINBuiltInLooks(void) {
    NSMutableArray<CINLook *> *looks = [NSMutableArray array];

    // 原生：什么都不做，用来单独看「镜头 + 胶片效果」
    [looks addObject:CINRecipeLook(@"natural", @"原生", @"Natural", CINLookRecipeDefault())];

    {   // 青橙：好莱坞大片的经典配色，肤色推橙、环境推青
        CINLookRecipe r = CINLookRecipeDefault();
        r.contrast = 1.18f;
        r.saturation = 1.05f;
        CINAddHue(&r, 30.f, 35.f, 4.f, 1.15f);     // 橙/肤色：略往橙推、加饱和
        CINAddHue(&r, 120.f, 50.f, 45.f, 0.75f);   // 绿 → 青
        CINAddHue(&r, 200.f, 45.f, -8.f, 1.1f);    // 青蓝：统一到青
        r.shadowTint = CINVec3Make(0.0f, 0.45f, 0.55f);
        r.shadowTintAmount = 0.10f;
        r.highlightTint = CINVec3Make(1.0f, 0.62f, 0.3f);
        r.highlightTintAmount = 0.06f;
        [looks addObject:CINRecipeLook(@"teal_orange", @"青橙", @"Teal & Orange", r)];
    }
    {   // 暖阳：低反差、暖白、柔和的人像胶片感
        CINLookRecipe r = CINLookRecipeDefault();
        r.temperature = 0.35f;
        r.crossTalk = 0.25f;
        r.saturation = 0.92f;
        r.contrast = 0.92f;
        CINAddHue(&r, 100.f, 40.f, -10.f, 0.85f);   // 绿色偏黄一点
        r.highlightTint = CINVec3Make(1.0f, 0.85f, 0.65f);
        r.highlightTintAmount = 0.06f;
        r.fade = 0.035f;
        [looks addObject:CINRecipeLook(@"warm_film", @"暖阳", @"Warm Film", r)];
    }
    {   // 冷冽：北欧风，低饱和、冷影
        CINLookRecipe r = CINLookRecipeDefault();
        r.temperature = -0.35f;
        r.saturation = 0.72f;
        r.contrast = 1.06f;
        r.shadowTint = CINVec3Make(0.2f, 0.4f, 0.75f);
        r.shadowTintAmount = 0.08f;
        r.fade = 0.03f;
        [looks addObject:CINRecipeLook(@"nordic", @"冷冽", @"Nordic", r)];
    }
    {   // 褪色：低对比、黑位发灰、带一点青绿
        CINLookRecipe r = CINLookRecipeDefault();
        r.contrast = 0.82f;
        r.saturation = 0.8f;
        r.crossTalk = 0.2f;
        r.shadowTint = CINVec3Make(0.2f, 0.55f, 0.5f);
        r.shadowTintAmount = 0.07f;
        r.fade = 0.09f;
        r.whitePoint = 0.96f;
        [looks addObject:CINRecipeLook(@"matte", @"褪色", @"Matte", r)];
    }
    {   // 银盐：红滤镜味道的高反差黑白
        CINLookRecipe r = CINLookRecipeDefault();
        r.mono = true;
        r.monoWeights = CINVec3Make(0.42f, 0.48f, 0.10f);
        r.contrast = 1.28f;
        r.fade = 0.015f;
        [looks addObject:CINRecipeLook(@"silver", @"银盐", @"Silver", r)];
    }
    {   // 霓虹：夜景用，红推品、蓝推青，冷暖对撞
        CINLookRecipe r = CINLookRecipeDefault();
        r.temperature = -0.15f;
        r.saturation = 1.2f;
        r.contrast = 1.1f;
        CINAddHue(&r, 0.f, 30.f, -14.f, 1.2f);      // 红 → 品
        CINAddHue(&r, 220.f, 45.f, -22.f, 1.15f);   // 蓝 → 青
        r.shadowTint = CINVec3Make(0.35f, 0.2f, 0.7f);
        r.shadowTintAmount = 0.08f;
        r.highlightTint = CINVec3Make(1.0f, 0.4f, 0.75f);
        r.highlightTintAmount = 0.05f;
        [looks addObject:CINRecipeLook(@"neon", @"霓虹", @"Neon Night", r)];
    }
    {   // 森屿：绿色压成橄榄、整体偏暖、轻微褪色
        CINLookRecipe r = CINLookRecipeDefault();
        r.temperature = 0.12f;
        r.contrast = 1.04f;
        CINAddHue(&r, 110.f, 50.f, -22.f, 0.7f);   // 绿 → 橄榄黄绿，降饱和
        CINAddHue(&r, 200.f, 40.f, 10.f, 0.8f);
        r.highlightTint = CINVec3Make(1.0f, 0.9f, 0.6f);
        r.highlightTintAmount = 0.05f;
        r.fade = 0.03f;
        [looks addObject:CINRecipeLook(@"forest", @"森屿", @"Forest", r)];
    }
    {   // 黄昏：大面积暖橙，亮部金色
        CINLookRecipe r = CINLookRecipeDefault();
        r.temperature = 0.6f;
        r.tint = 0.08f;
        r.saturation = 1.08f;
        r.contrast = 1.06f;
        r.highlightTint = CINVec3Make(1.0f, 0.68f, 0.25f);
        r.highlightTintAmount = 0.08f;
        r.shadowTint = CINVec3Make(0.45f, 0.25f, 0.4f);
        r.shadowTintAmount = 0.05f;
        [looks addObject:CINRecipeLook(@"golden_hour", @"黄昏", @"Golden Hour", r)];
    }
    {   // 漂白：跳过漂白工艺的银盐残留——低饱和、高反差、金属感
        CINLookRecipe r = CINLookRecipeDefault();
        r.saturation = 0.85f;
        r.contrast = 1.12f;
        r.bleach = 0.75f;
        [looks addObject:CINRecipeLook(@"bleach", @"漂白", @"Bleach Bypass", r)];
    }
    {   // 浓彩：反转片式的浓郁红蓝、深阴影
        CINLookRecipe r = CINLookRecipeDefault();
        r.saturation = 1.18f;
        r.contrast = 1.2f;
        r.pivot = 0.46f;
        CINAddHue(&r, 0.f, 35.f, 0.f, 1.2f);     // 红更浓
        CINAddHue(&r, 225.f, 40.f, 5.f, 1.2f);   // 蓝更深
        CINAddHue(&r, 55.f, 25.f, -6.f, 0.9f);   // 黄略压
        [looks addObject:CINRecipeLook(@"chrome", @"浓彩", @"Rich Chrome", r)];
    }
    return looks;
}

@implementation CINLookLibrary {
    os_unfair_lock _lock;
    NSMutableArray<CINLook *> *_looks;
}

+ (CINLookLibrary *)shared {
    static CINLookLibrary *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = [[CINLookLibrary alloc] initPrivate];
    });
    return library;
}

- (instancetype)initPrivate {
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _looks = [CINBuiltInLooks() mutableCopy];
    }
    return self;
}

- (NSInteger)count {
    os_unfair_lock_lock(&_lock);
    NSInteger n = (NSInteger)_looks.count;
    os_unfair_lock_unlock(&_lock);
    return n;
}

- (CINLook *)lookAtIndex:(NSInteger)index {
    os_unfair_lock_lock(&_lock);
    CINLook *look = index >= 0 && index < (NSInteger)_looks.count ? _looks[(NSUInteger)index] : nil;
    os_unfair_lock_unlock(&_lock);
    return look;
}

- (NSInteger)indexOfId:(NSString *)lookId {
    os_unfair_lock_lock(&_lock);
    NSInteger found = -1;
    for (NSUInteger i = 0; i < _looks.count; ++i) {
        if ([_looks[i].lookId isEqualToString:lookId]) {
            found = (NSInteger)i;
            break;
        }
    }
    os_unfair_lock_unlock(&_lock);
    return found;
}

- (NSInteger)addCubeWithId:(NSString *)lookId name:(NSString *)name cube:(CINCubeLut *)cube {
    // 英文名用 .cube 里的 TITLE；没有就留空，由界面按系统语言显示「导入的 LUT」
    CINLook *look = [[CINLook alloc] initWithId:lookId name:name nameEn:cube.title recipe:CINLookRecipeDefault() cube:cube];
    os_unfair_lock_lock(&_lock);
    NSInteger index = -1;
    for (NSUInteger i = 0; i < _looks.count; ++i) {
        if ([_looks[i].lookId isEqualToString:lookId]) {
            _looks[i] = look;
            index = (NSInteger)i;
            break;
        }
    }
    if (index < 0) {
        [_looks addObject:look];
        index = (NSInteger)_looks.count - 1;
    }
    os_unfair_lock_unlock(&_lock);
    return index;
}

@end
