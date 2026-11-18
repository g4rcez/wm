#ifndef WM_PRIVATE_API_H
#define WM_PRIVATE_API_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

// Maps an Accessibility window element to its CGWindowID. Private, but used by every macOS tiling WM.
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

// Trackpad contacts. The framework is private (MultitouchSupport), so it is loaded at run time: when it or one of its
// functions is missing, `wm_multitouch_start` returns false and nothing else happens.
typedef struct {
    int32_t id;
    // 4 is a finger that touches the pad.
    int32_t state;
    // Position on the pad, 0 to 1, with the origin at the bottom left.
    float x;
    float y;
} WMTouch;

// Called on a thread of the framework, once per frame of every trackpad.
typedef void (*WMTouchFrameHandler)(const WMTouch *touches, int32_t count, double timestamp, void *context);

bool wm_multitouch_start(WMTouchFrameHandler handler, void *context);
void wm_multitouch_stop(void);

// A picture of one window, also when it is off screen. Returns a retained image, or NULL when the private function is missing
// or the capture fails. SkyLight is loaded at run time.
CGImageRef wm_capture_window(uint32_t window_id) CF_RETURNS_RETAINED;

// Where a window is, among the Spaces of macOS: -1 when the private functions are missing, 0 when no Space has the window (it is
// gone), 1 when it is on the active Space, 2 when it is on another Space (for example behind a window in native fullscreen).
// The Accessibility API lists only the windows of the active Space. SkyLight is loaded at run time.
int32_t wm_window_space(uint32_t window_id);

// Turns the macOS shortcuts Cmd+Tab and Cmd+Shift+Tab on or off for this login session. The state stays until it is set
// again or the user logs out, so the caller must turn them on again when it quits. Does nothing when the private function
// is missing.
void wm_set_system_cmd_tab(bool enabled);

#endif
