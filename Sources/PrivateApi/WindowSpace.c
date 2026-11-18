// Which Space a window is on. The Accessibility API shows the windows of the active Space only, so while a window of another app
// is in native fullscreen every other window looks gone. SkyLight is private, so it is loaded at run time: when it or one of its
// functions is missing, the answer is "unknown".
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include "PrivateApi.h"

typedef int32_t (*MainConnectionFn)(void);
typedef uint64_t (*ActiveSpaceFn)(int32_t connection);
typedef CFArrayRef (*SpacesForWindowsFn)(int32_t connection, int32_t mask, CFArrayRef windows);

// The Spaces that include the active one, the others, and the user's (fullscreen Spaces too).
#define ALL_SPACES 0x7

static MainConnectionFn mainConnection;
static ActiveSpaceFn activeSpace;
static SpacesForWindowsFn spacesForWindows;

static void load(void *unused) {
    void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!library) return;
    mainConnection = (MainConnectionFn)dlsym(library, "CGSMainConnectionID");
    activeSpace = (ActiveSpaceFn)dlsym(library, "CGSGetActiveSpace");
    spacesForWindows = (SpacesForWindowsFn)dlsym(library, "CGSCopySpacesForWindows");
}

int32_t wm_window_space(uint32_t window_id) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, load);
    if (!mainConnection || !activeSpace || !spacesForWindows) return -1;
    int32_t connection = mainConnection();
    int64_t wanted = window_id;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt64Type, &wanted);
    CFArrayRef ids = CFArrayCreate(NULL, (const void **)&number, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    CFArrayRef spaces = spacesForWindows(connection, ALL_SPACES, ids);
    CFRelease(ids);
    if (!spaces) return -1;
    int32_t answer = 0;
    uint64_t active = activeSpace(connection);
    for (CFIndex i = 0; i < CFArrayGetCount(spaces); i++) {
        int64_t space = 0;
        if (!CFNumberGetValue((CFNumberRef)CFArrayGetValueAtIndex(spaces, i), kCFNumberSInt64Type, &space)) continue;
        if ((uint64_t)space == active) {
            answer = 1;
            break;
        }
        answer = 2;
    }
    CFRelease(spaces);
    return answer;
}
