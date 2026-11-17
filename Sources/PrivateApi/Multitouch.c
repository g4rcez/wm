#include "PrivateApi.h"
#include <dlfcn.h>
#include <string.h>

// The layout of a touch in the private framework, as far as wm reads it: 96 bytes per touch. It is copied into the
// stable WMTouch at once, so no other code depends on this layout.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t fingerId;
    int32_t handId;
    float normalizedX, normalizedY;
    float velocityX, velocityY;
    float size;
    int32_t zero1;
    float angle, majorAxis, minorAxis;
    float absoluteX, absoluteY, absoluteVelocityX, absoluteVelocityY;
    int32_t zero2[2];
    float density;
} MTTouchRaw;

typedef void *MTDeviceRef;
typedef int (*ContactCallback)(MTDeviceRef, MTTouchRaw *, int, double, int);

static void *library;
static CFArrayRef (*createList)(void);
static void (*registerCallback)(MTDeviceRef, ContactCallback);
static void (*unregisterCallback)(MTDeviceRef, ContactCallback);
static void (*startDevice)(MTDeviceRef, int);
static void (*stopDevice)(MTDeviceRef);

static CFArrayRef devices;
static WMTouchFrameHandler frameHandler;
static void *frameContext;

#define MAX_TOUCHES 16

static int contact(MTDeviceRef device, MTTouchRaw *raw, int count, double timestamp, int frame) {
    WMTouchFrameHandler handler = frameHandler;
    if (!handler) return 0;
    if (count > MAX_TOUCHES) count = MAX_TOUCHES;
    WMTouch touches[MAX_TOUCHES];
    for (int i = 0; i < count; i++) {
        touches[i].id = raw[i].identifier;
        touches[i].state = raw[i].state;
        touches[i].x = raw[i].normalizedX;
        touches[i].y = raw[i].normalizedY;
    }
    handler(touches, count, timestamp, frameContext);
    return 0;
}

bool wm_multitouch_start(WMTouchFrameHandler handler, void *context) {
    wm_multitouch_stop();
    if (!library) {
        library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
        if (!library) return false;
        createList = dlsym(library, "MTDeviceCreateList");
        registerCallback = dlsym(library, "MTRegisterContactFrameCallback");
        unregisterCallback = dlsym(library, "MTUnregisterContactFrameCallback");
        startDevice = dlsym(library, "MTDeviceStart");
        stopDevice = dlsym(library, "MTDeviceStop");
    }
    if (!createList || !registerCallback || !unregisterCallback || !startDevice || !stopDevice) return false;
    devices = createList();
    if (!devices || CFArrayGetCount(devices) == 0) return false;
    frameHandler = handler;
    frameContext = context;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        registerCallback(device, contact);
        startDevice(device, 0);
    }
    return true;
}

void wm_multitouch_stop(void) {
    frameHandler = NULL;
    if (!devices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        unregisterCallback(device, contact);
        stopDevice(device);
    }
    CFRelease(devices);
    devices = NULL;
}
