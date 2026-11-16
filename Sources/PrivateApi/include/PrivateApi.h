#ifndef WM_PRIVATE_API_H
#define WM_PRIVATE_API_H

#include <ApplicationServices/ApplicationServices.h>

// Maps an Accessibility window element to its CGWindowID. Private, but used by every macOS tiling WM.
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

#endif
