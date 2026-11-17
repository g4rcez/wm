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

// Turns the macOS shortcuts Cmd+Tab and Cmd+Shift+Tab on or off for this login session. The state stays until it is set
// again or the user logs out, so the caller must turn them on again when it quits. Does nothing when the private function
// is missing.
void wm_set_system_cmd_tab(bool enabled);

#endif
