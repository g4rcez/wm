// A picture of a window that ScreenCaptureKit cannot take, for example a window that wm parked off screen.
// SkyLight is private, so it is loaded at run time: when it or one of its functions is missing, nothing is captured.
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include "PrivateApi.h"

typedef int32_t (*MainConnectionFn)(void);
typedef CFArrayRef (*CaptureListFn)(int32_t connection, const uint32_t *windows, uint32_t count, uint32_t options);

// kCGSCaptureIgnoreGlobalClipShape (1 << 11): the part that is off screen is not cut away.
// kCGSWindowCaptureNominalResolution (1 << 9): one pixel per point.
#define CAPTURE_OPTIONS ((1u << 11) | (1u << 9))

static MainConnectionFn mainConnection;
static CaptureListFn captureList;

static void load(void *unused) {
    void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!library) return;
    mainConnection = (MainConnectionFn)dlsym(library, "CGSMainConnectionID");
    captureList = (CaptureListFn)dlsym(library, "CGSHWCaptureWindowList");
}

CGImageRef wm_capture_window(uint32_t window_id) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, load);
    if (!mainConnection || !captureList) return NULL;
    CFArrayRef images = captureList(mainConnection(), &window_id, 1, CAPTURE_OPTIONS);
    if (!images) return NULL;
    CGImageRef image = NULL;
    if (CFArrayGetCount(images) > 0) image = (CGImageRef)CFRetain(CFArrayGetValueAtIndex(images, 0));
    CFRelease(images);
    return image;
}
