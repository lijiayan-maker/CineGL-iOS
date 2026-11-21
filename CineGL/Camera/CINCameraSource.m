#import "CINCameraSource.h"

@implementation CINCameraCaps
- (BOOL)manualFocus {
    return self.focusLock && self.minFocusDiopters > 0.f;
}
@end

@implementation CINSessionConfig
@end

@implementation CINSessionInfo
@end

@implementation CINStillCapture
- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == _pixelBuffer) return;
    CVPixelBufferRetain(pixelBuffer);
    CVPixelBufferRelease(_pixelBuffer);
    _pixelBuffer = pixelBuffer;
}
- (void)dealloc {
    CVPixelBufferRelease(_pixelBuffer);
}
@end
