// Turns the symbolic hot keys of macOS on or off. SkyLight is private, so it is loaded at run time: when it or the function is
// missing, nothing happens.
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include "PrivateApi.h"

typedef int32_t (*SetHotKeyFn)(int32_t hotKey, bool enabled);

static SetHotKeyFn setHotKey;

static void load(void *unused) {
    void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (library) setHotKey = (SetHotKeyFn)dlsym(library, "CGSSetSymbolicHotKeyEnabled");
    if (!setHotKey) setHotKey = (SetHotKeyFn)dlsym(RTLD_DEFAULT, "CGSSetSymbolicHotKeyEnabled");
}

// 1 is Cmd+Tab and 2 is Cmd+Shift+Tab.
void wm_set_system_cmd_tab(bool enabled) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, load);
    if (!setHotKey) return;
    setHotKey(1, enabled);
    setHotKey(2, enabled);
}
