#ifndef WM_PRIVATE_API_H
#define WM_PRIVATE_API_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

typedef struct {
    int32_t id;
    int32_t state;
    float x;
    float y;
} WMTouch;

typedef void (*WMTouchFrameHandler)(const WMTouch *touches, int32_t count, double timestamp, void *context);

bool wm_multitouch_start(WMTouchFrameHandler handler, void *context);
void wm_multitouch_stop(void);

CGImageRef wm_capture_window(uint32_t window_id) CF_RETURNS_RETAINED;

int32_t wm_window_space(uint32_t window_id);

void wm_set_system_cmd_tab(bool enabled);

int32_t wm_spaces_support(void);

CFArrayRef wm_spaces_copy_displays(void) CF_RETURNS_RETAINED;

uint64_t wm_create_space(CFStringRef display_uuid);

uint64_t wm_space_of_window(uint32_t window_id);

bool wm_move_windows_to_space(const uint32_t *window_ids, int count, uint64_t space);

bool wm_can_batch_space_swipes(void);

bool wm_switch_space_index(int from_index, int to_index, uint32_t display);

#endif
