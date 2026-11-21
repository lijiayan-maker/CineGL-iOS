#import "CINSettingsStore.h"

@implementation CINSettingsStore {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}

/** 按名字找回枚举值，找不到用默认值。 */
static NSInteger CINEnumOr(NSString *name, NSInteger count, NSString *(^nameOf)(NSInteger), NSInteger fallback) {
    if (!name) return fallback;
    for (NSInteger i = 0; i < count; ++i) {
        if ([nameOf(i) isEqualToString:name]) return i;
    }
    return fallback;
}

- (float)floatFor:(NSString *)key or:(float)fallback {
    id v = [_defaults objectForKey:key];
    return v ? [v floatValue] : fallback;
}

- (BOOL)boolFor:(NSString *)key or:(BOOL)fallback {
    id v = [_defaults objectForKey:key];
    return v ? [v boolValue] : fallback;
}

- (CINCameraState *)load {
    CINCameraState *s = [[CINCameraState alloc] init];
    s.mode = (CINCaptureMode)CINEnumOr([_defaults stringForKey:@"mode"], 2, ^NSString *(NSInteger i) {
        return CINCaptureModeName((CINCaptureMode)i);
    }, s.mode);
    s.aspect = (CINAspectRatio)CINEnumOr([_defaults stringForKey:@"aspect"], 4, ^NSString *(NSInteger i) {
        return CINAspectName((CINAspectRatio)i);
    }, s.aspect);
    s.resolution = (CINResolution)CINEnumOr([_defaults stringForKey:@"resolution"], 2, ^NSString *(NSInteger i) {
        return CINResolutionName((CINResolution)i);
    }, s.resolution);
    id fps = [_defaults objectForKey:@"fps"];
    if (fps) s.fps = [fps intValue];
    s.logMode = (CINLogMode)CINEnumOr([_defaults stringForKey:@"logMode"], 3, ^NSString *(NSInteger i) {
        return CINLogModeName((CINLogMode)i);
    }, s.logMode);
    s.burnIn = [self boolFor:@"burnIn" or:s.burnIn];
    s.lookId = [_defaults stringForKey:@"lookId"] ?: s.lookId;
    const CINEffects e = CINEffectsDefault();
    s.effects = (CINEffects){
        [self floatFor:@"fx.look" or:e.lookStrength], [self floatFor:@"fx.halation" or:e.halation],
        [self floatFor:@"fx.mist" or:e.mist], [self floatFor:@"fx.grain" or:e.grain],
        [self floatFor:@"fx.grainSize" or:e.grainSize], [self floatFor:@"fx.vignette" or:e.vignette],
        [self floatFor:@"fx.aberration" or:e.aberration],
    };
    const CINAssist a = CINAssistDefault();
    s.assist = (CINAssist){
        [self boolFor:@"as.grid" or:a.grid], [self boolFor:@"as.level" or:a.level], [self boolFor:@"as.zebra" or:a.zebra],
        [self boolFor:@"as.peaking" or:a.peaking], [self boolFor:@"as.waveform" or:a.waveform],
    };
    return s;
}

- (void)save:(CINCameraState *)s {
    NSUserDefaults *d = _defaults;
    [d setObject:CINCaptureModeName(s.mode) forKey:@"mode"];
    [d setObject:CINAspectName(s.aspect) forKey:@"aspect"];
    [d setObject:CINResolutionName(s.resolution) forKey:@"resolution"];
    [d setInteger:s.fps forKey:@"fps"];
    [d setObject:CINLogModeName(s.logMode) forKey:@"logMode"];
    [d setBool:s.burnIn forKey:@"burnIn"];
    [d setObject:s.lookId forKey:@"lookId"];
    const CINEffects e = s.effects;
    [d setFloat:e.lookStrength forKey:@"fx.look"];
    [d setFloat:e.halation forKey:@"fx.halation"];
    [d setFloat:e.mist forKey:@"fx.mist"];
    [d setFloat:e.grain forKey:@"fx.grain"];
    [d setFloat:e.grainSize forKey:@"fx.grainSize"];
    [d setFloat:e.vignette forKey:@"fx.vignette"];
    [d setFloat:e.aberration forKey:@"fx.aberration"];
    const CINAssist a = s.assist;
    [d setBool:a.grid forKey:@"as.grid"];
    [d setBool:a.level forKey:@"as.level"];
    [d setBool:a.zebra forKey:@"as.zebra"];
    [d setBool:a.peaking forKey:@"as.peaking"];
    [d setBool:a.waveform forKey:@"as.waveform"];
}

@end
