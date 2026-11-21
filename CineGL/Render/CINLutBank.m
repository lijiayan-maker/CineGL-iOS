#import "CINLutBank.h"

#import "CINLooks.h"
#import "CINLutBaker.h"

@implementation CINLutBank {
    CINEngine *_engine;
    dispatch_queue_t _renderQueue;
    dispatch_queue_t _baker;
    int _encoding;
    NSUInteger _generation;
    NSMutableIndexSet *_ready;
}

- (instancetype)initWithEngine:(CINEngine *)engine renderQueue:(dispatch_queue_t)queue {
    if ((self = [super init])) {
        _engine = engine;
        _renderQueue = queue;
        _baker = dispatch_queue_create("CineGL-LutBaker", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _encoding = -1;
        _ready = [NSMutableIndexSet indexSet];
    }
    return self;
}

- (NSArray<NSNumber *> *)readyLooks {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:_ready.count];
    [_ready enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [out addObject:@(idx)];
    }];
    return out;
}

- (void)ensureEncoding:(CINEncoding)encoding priority:(NSInteger)priority {
    if ((int)encoding == _encoding) return;
    _encoding = encoding;
    _generation++;
    [_ready removeAllIndexes];
    [_engine clearLookLuts];
    // 中性 LUT 同步烘（约 10ms），保证切换的这一帧颜色就是对的
    [_engine uploadNeutralLut:CINLutBakeNeutral(encoding, kCINLutDefaultSize) size:kCINLutDefaultSize];
    const NSInteger count = CINLookLibrary.shared.count;
    if (priority >= 0 && priority < count) [self bake:priority];
    for (NSInteger i = 0; i < count; ++i) {
        if (i != priority) [self bake:i];
    }
}

- (void)bake:(NSInteger)index {
    if (_encoding < 0 || index < 0) return;
    const NSUInteger gen = _generation;
    const CINEncoding enc = (CINEncoding)_encoding;
    CINEngine *engine = _engine;
    dispatch_queue_t renderQueue = _renderQueue;
    __weak CINLutBank *weakSelf = self;
    dispatch_async(_baker, ^{
        CINLook *look = [CINLookLibrary.shared lookAtIndex:index];
        if (!look) return;
        NSData *data = CINLutBake(look, enc, kCINLutDefaultSize);
        dispatch_async(renderQueue, ^{
            CINLutBank *bank = weakSelf;
            if (!bank || gen != bank->_generation) return;
            [engine uploadLookLut:data size:kCINLutDefaultSize index:index];
            [bank->_ready addIndex:(NSUInteger)index];
        });
    });
}

@end
