#include <stdlib.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ColorSync/ColorSync.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach_time.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include "PrivateApi.h"

static int major_version(void);

typedef int (*MainConnectionFn)(void);
typedef CFArrayRef (*CopyManagedDisplaySpacesFn)(int cid);
typedef uint64_t (*ManagedDisplayCurrentSpaceFn)(int cid, CFStringRef uuid);
typedef int (*SpaceTypeFn)(int cid, uint64_t sid);
typedef CFArrayRef (*CopySpacesForWindowsFn)(int cid, int selector, CFArrayRef windows);
typedef int64_t (*AsyncBridgedOperationFn)(void *operation);

typedef id (*SyncBridgedOperationFn)(id operation);

static MainConnectionFn mainConnection;
static SyncBridgedOperationFn syncBridgedOperation;
static CopyManagedDisplaySpacesFn copyManagedDisplaySpaces;
static ManagedDisplayCurrentSpaceFn managedDisplayCurrentSpace;
static SpaceTypeFn spaceType;
static CopySpacesForWindowsFn copySpacesForWindows;
static AsyncBridgedOperationFn asyncBridgedOperation;
static dispatch_once_t loaded;

static void *skylight_symbol(const char *mangled) {
    static const char *image = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight";
    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, image) == 0) {
            header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!header) return NULL;

    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const uint8_t *cursor = (const uint8_t *)header + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT) == 0) {
            linkedit = (const struct segment_command_64 *)command;
        } else if (command->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)command;
        }
        cursor += command->cmdsize;
    }
    if (!linkedit || !symtab) return NULL;

    const uint8_t *base = (const uint8_t *)(uintptr_t)(linkedit->vmaddr - linkedit->fileoff + slide);
    const char *strings = (const char *)(base + symtab->stroff);
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        if (strcmp(strings + symbols[i].n_un.n_strx, mangled) == 0) return (void *)(uintptr_t)(symbols[i].n_value + slide);
    }
    return NULL;
}

static void load(void *unused) {
    void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!library) return;
    mainConnection = (MainConnectionFn)dlsym(library, "SLSMainConnectionID");
    copyManagedDisplaySpaces = (CopyManagedDisplaySpacesFn)dlsym(library, "SLSCopyManagedDisplaySpaces");
    managedDisplayCurrentSpace = (ManagedDisplayCurrentSpaceFn)dlsym(library, "SLSManagedDisplayGetCurrentSpace");
    spaceType = (SpaceTypeFn)dlsym(library, "SLSSpaceGetType");
    copySpacesForWindows = (CopySpacesForWindowsFn)dlsym(library, "SLSCopySpacesForWindows");
    syncBridgedOperation = (SyncBridgedOperationFn)skylight_symbol(
        "__ZL54_SLSPerformSynchronousBridgedWindowManagementOperationP46SLSSynchronousBridgedWindowManagementOperation");
    asyncBridgedOperation = (AsyncBridgedOperationFn)skylight_symbol(
        "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
}

static bool query_ready(void) {
    dispatch_once_f(&loaded, NULL, load);
    return mainConnection && copyManagedDisplaySpaces && managedDisplayCurrentSpace && spaceType;
}

int32_t wm_spaces_support(void) {
    dispatch_once_f(&loaded, NULL, load);
    int32_t bits = 0;
    if (query_ready()) bits |= 1;
    if (asyncBridgedOperation && objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation")) bits |= 2;
    if (major_version() >= 27 && syncBridgedOperation && objc_getClass("SLSBridgedSpaceCreateOperation")) bits |= 4;
    return bits;
}

static uint64_t number_u64(CFTypeRef value) {
    uint64_t result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &result);
    return result;
}

static CFStringRef copy_uuid_string(CGDirectDisplayID display) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
    if (!uuid) return NULL;
    CFStringRef text = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return text;
}

static CGDirectDisplayID display_with_uuid(CFStringRef text) {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess) return 0;
    for (uint32_t i = 0; i < count; i++) {
        CFStringRef candidate = copy_uuid_string(ids[i]);
        bool same = candidate && CFStringCompare(candidate, text, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
        if (candidate) CFRelease(candidate);
        if (same) return ids[i];
    }
    return 0;
}

static void put_number(CFMutableDictionaryRef dictionary, CFStringRef key, int64_t value) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt64Type, &value);
    CFDictionarySetValue(dictionary, key, number);
    CFRelease(number);
}

CFArrayRef wm_spaces_copy_displays(void) {
    if (!query_ready()) return NULL;
    int cid = mainConnection();
    CFArrayRef managed = copyManagedDisplaySpaces(cid);
    if (!managed) return NULL;
    CFMutableArrayRef result = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < CFArrayGetCount(managed); i++) {
        CFDictionaryRef entry = CFArrayGetValueAtIndex(managed, i);
        CFStringRef identifier = CFDictionaryGetValue(entry, CFSTR("Display Identifier"));
        if (!identifier) continue;
        CGDirectDisplayID display = 0;
        CFStringRef uuid = NULL;
        if (CFStringCompare(identifier, CFSTR("Main"), 0) == kCFCompareEqualTo) {
            display = CGMainDisplayID();
            uuid = copy_uuid_string(display);
        } else {
            uuid = CFStringCreateCopy(NULL, identifier);
            display = display_with_uuid(identifier);
        }
        if (!uuid || display == 0) {
            if (uuid) CFRelease(uuid);
            continue;
        }
        CFMutableDictionaryRef item = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(item, CFSTR("uuid"), uuid);
        put_number(item, CFSTR("displayID"), display);
        put_number(item, CFSTR("current"), (int64_t)managedDisplayCurrentSpace(cid, identifier));
        CFMutableArrayRef spaces = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
        CFArrayRef listed = CFDictionaryGetValue(entry, CFSTR("Spaces"));
        for (CFIndex j = 0; listed && j < CFArrayGetCount(listed); j++) {
            CFDictionaryRef space = CFArrayGetValueAtIndex(listed, j);
            uint64_t sid = number_u64(CFDictionaryGetValue(space, CFSTR("id64")));
            CFMutableDictionaryRef row = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            put_number(row, CFSTR("id"), (int64_t)sid);
            put_number(row, CFSTR("type"), spaceType(cid, sid));
            CFArrayAppendValue(spaces, row);
            CFRelease(row);
        }
        CFDictionarySetValue(item, CFSTR("spaces"), spaces);
        CFRelease(spaces);
        CFArrayAppendValue(result, item);
        CFRelease(item);
        CFRelease(uuid);
    }
    CFRelease(managed);
    return result;
}

uint64_t wm_space_of_window(uint32_t window_id) {
    if (!query_ready() || !copySpacesForWindows) return 0;
    int64_t wanted = window_id;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt64Type, &wanted);
    CFArrayRef ids = CFArrayCreate(NULL, (const void **)&number, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    CFArrayRef spaces = copySpacesForWindows(mainConnection(), 0x7, ids);
    CFRelease(ids);
    if (!spaces) return 0;
    uint64_t first = CFArrayGetCount(spaces) > 0 ? number_u64(CFArrayGetValueAtIndex(spaces, 0)) : 0;
    CFRelease(spaces);
    return first;
}

uint64_t wm_create_space(CFStringRef display_uuid) {
    dispatch_once_f(&loaded, NULL, load);
    if ((wm_spaces_support() & 4) == 0) {
        fputs("spaces: making a desktop needs macOS 27 or later\n", stderr);
        return 0;
    }
    if (mainConnection) mainConnection();
    Class operationClass = objc_getClass("SLSBridgedSpaceCreateOperation");
    int32_t user = 0;
    CFNumberRef type = CFNumberCreate(NULL, kCFNumberSInt32Type, &user);
    const void *keys[] = {CFSTR("type"), CFSTR("Display Identifier")};
    const void *values[] = {type, display_uuid};
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(type);
    id allocated = ((id(*)(id, SEL))objc_msgSend)((id)operationClass, sel_registerName("alloc"));
    id operation = ((id(*)(id, SEL, uint32_t, id))objc_msgSend)(allocated, sel_registerName("initWithOptions:values:"), 0, (id)options);
    CFRelease(options);
    if (!operation) {
        fputs("spaces: initWithOptions:values: returned nil\n", stderr);
        return 0;
    }
    id result = syncBridgedOperation(operation);
    SEL spaceID = sel_registerName("spaceID");
    uint64_t space = 0;
    if (result && class_respondsToSelector(object_getClass(result), spaceID)) {
        space = ((uint64_t(*)(id, SEL))objc_msgSend)(result, spaceID);
    } else {
        fputs("spaces: making a desktop did not return a Space ID\n", stderr);
    }
    ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName("release"));
    return space;
}

bool wm_move_windows_to_space(const uint32_t *window_ids, int count, uint64_t space) {
    dispatch_once_f(&loaded, NULL, load);
    Class operationClass = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!asyncBridgedOperation || !operationClass) {
        fputs("spaces: the bridged window move is not available on this macOS\n", stderr);
        return false;
    }
    CFMutableArrayRef windows = CFArrayCreateMutable(NULL, count, &kCFTypeArrayCallBacks);
    for (int i = 0; i < count; i++) {
        int32_t id = (int32_t)window_ids[i];
        CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &id);
        CFArrayAppendValue(windows, number);
        CFRelease(number);
    }
    id allocated = ((id(*)(id, SEL))objc_msgSend)((id)operationClass, sel_registerName("alloc"));
    id operation = ((id(*)(id, SEL, id, uint64_t))objc_msgSend)(allocated, sel_registerName("initWithWindows:spaceID:"), (id)windows, space);
    CFRelease(windows);
    if (!operation) {
        fputs("spaces: initWithWindows:spaceID: returned nil\n", stderr);
        return false;
    }
    asyncBridgedOperation((void *)operation);
    ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName("release"));
    return true;
}

enum {
    kEventTypeField = 55,
    kEventDockControl = 30,
    kGestureHIDType = 110,
    kHIDEventTypeDockSwipe = 23,
    kGestureSwipeMask = 115,
    kGestureSwipeMotion = 123,
    kGestureMotionHorizontal = 1,
    kGestureSwipeProgress = 124,
    kGestureSwipePositionX = 125,
    kGestureSwipePositionY = 126,
    kGestureSwipeVelocityX = 129,
    kGestureSwipeVelocityY = 130,
    kGesturePhase = 132,
    kGesturePhaseAlias = 134,
    kGestureZoomDeltaY = 138,
    kSourceUnixProcessIDAlias = 169,
    kPhaseBegan = 1,
    kPhaseChanged = 2,
    kPhaseEnded = 4,
};

#pragma pack(push, 1)
typedef struct { uint32_t size, type, options; uint8_t depth, reserved[3]; } IOHIDEventBase;
typedef struct {
    IOHIDEventBase base;
    int32_t positionX, positionY, positionZ;
    uint32_t swipeMask;
    uint16_t gestureMotion, gestureFlavor;
    int32_t swipeProgress;
} IOHIDFluidTouchGestureData;
typedef struct { IOHIDEventBase base; int32_t velocityX, velocityY, velocityZ; } IOHIDVelocityEventData;
typedef struct { uint64_t timestamp, senderID; uint32_t options, attributeLength, eventCount; } IOHIDSystemQueueElementHeader;
#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "IOHID base layout");
_Static_assert(sizeof(IOHIDFluidTouchGestureData) == 40, "IOHID fluid gesture layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28, "IOHID velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28, "IOHID queue header layout");

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;
static const uint16_t kRawIOHIDPayloadField = 4205;
static const uint8_t kEventDataFormatVersion = 2;
static const double kZoomDeltaY = 3.0;
static const double kPositionX = 0.1;
static const double kVelocity = 600.0;
static const int kDragFrames = 8;
static const CFTimeInterval kFrameDelay = 0.012;
static const double kLegacyVelocity = 50.0;
/// The velocity of the last event of an instant swipe: so fast that the Dock has no slide left to draw. `WM_SPACE_INSTANT_VELOCITY`
/// changes it, to find a value that the Dock honors on a given macOS.
static const double kInstantVelocity = 20000.0;

static bool instant_switch = false;
void wm_set_instant_space_switch(bool on) { instant_switch = on; }

static double instant_velocity(void) {
    const char *text = getenv("WM_SPACE_INSTANT_VELOCITY");
    double value = text ? atof(text) : 0.0;
    return value > 0.0 ? value : kInstantVelocity;
}
static const CFTimeInterval kStepDelay = 0.03;

static int major_version(void) {
    char text[32] = {0};
    size_t size = sizeof(text) - 1;
    if (sysctlbyname("kern.osproductversion", text, &size, NULL, 0) != 0) return 0;
    return atoi(text);
}

static bool requires_augmentation(void) { return major_version() >= 27; }

static int64_t own_swipe_tag(void) { return ((int64_t)0x574D4D00 << 32) | (uint32_t)getpid(); }

static void post_dock_event(CGEventRef event) {
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, own_swipe_tag());
    CGEventPost(kCGSessionEventTap, event);
}

static int32_t fixed_1616(double value) {
    int32_t fixed = (int32_t)(value * 65536.0);
    if (fixed == 0 && value != 0.0) return value > 0.0 ? 1 : -1;
    return fixed;
}

static uint8_t *build_iohid_payload(CGEventRef event, size_t *length_out) {
    int64_t phase = CGEventGetIntegerValueField(event, kGesturePhase);
    int64_t motion = CGEventGetIntegerValueField(event, kGestureSwipeMotion);
    int64_t mask = CGEventGetIntegerValueField(event, kGestureSwipeMask);
    double progress = CGEventGetDoubleValueField(event, kGestureSwipeProgress);
    double positionX = CGEventGetDoubleValueField(event, kGestureSwipePositionX);
    double positionY = CGEventGetDoubleValueField(event, kGestureSwipePositionY);
    double velocityX = CGEventGetDoubleValueField(event, kGestureSwipeVelocityX);
    double velocityY = CGEventGetDoubleValueField(event, kGestureSwipeVelocityY);
    bool velocity = (velocityX != 0.0 || velocityY != 0.0 || phase == kPhaseEnded);

    size_t length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData);
    if (velocity) length += sizeof(IOHIDVelocityEventData);
    uint8_t *payload = calloc(1, length);
    if (!payload) return NULL;

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    header->timestamp = timestamp != 0 ? timestamp : mach_absolute_time();
    header->eventCount = velocity ? 2 : 1;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->positionX = fixed_1616(positionX);
    fluid->positionY = fixed_1616(positionY);
    fluid->swipeMask = (uint32_t)mask;
    fluid->gestureMotion = (uint16_t)motion;
    fluid->gestureFlavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipeProgress = fixed_1616(progress);

    if (velocity) {
        IOHIDVelocityEventData *data =
            (IOHIDVelocityEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData));
        data->base.size = sizeof(IOHIDVelocityEventData);
        data->base.type = kIOHIDEventTypeVelocity;
        data->base.depth = 1;
        data->velocityX = fixed_1616(velocityX);
        data->velocityY = fixed_1616(velocityY);
    }
    *length_out = length;
    return payload;
}

static CGEventRef augment(CGEventRef event) {
    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) return NULL;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0 || bytes[3] != kEventDataFormatVersion) {
        fprintf(stderr, "spaces: unexpected event data format (length %ld)\n", (long)length);
        CFRelease(data);
        return NULL;
    }
    size_t payload_length = 0;
    uint8_t *payload = build_iohid_payload(event, &payload_length);
    if (!payload) {
        CFRelease(data);
        return NULL;
    }
    size_t total = (size_t)length + 4 + payload_length;
    uint8_t *combined = malloc(total);
    if (!combined) {
        free(payload);
        CFRelease(data);
        return NULL;
    }
    memcpy(combined, bytes, (size_t)length);
    combined[length] = (uint8_t)((payload_length >> 8) & 0xFF);
    combined[length + 1] = (uint8_t)(payload_length & 0xFF);
    combined[length + 2] = (uint8_t)((kRawIOHIDPayloadField >> 8) & 0xFF);
    combined[length + 3] = (uint8_t)(kRawIOHIDPayloadField & 0xFF);
    memcpy(combined + length + 4, payload, payload_length);
    free(payload);
    CFRelease(data);
    CFDataRef extended = CFDataCreate(kCFAllocatorDefault, combined, (CFIndex)total);
    free(combined);
    if (!extended) return NULL;
    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, extended);
    CFRelease(extended);
    return result;
}

static double augmented_sign(double sign) {
    Boolean valid = false;
    Boolean natural = CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"), kCFPreferencesAnyApplication, &valid);
    return (valid ? natural : true) ? -sign : sign;
}

static CGEventRef create_augmented_event(int phase, double raw_sign, double progress) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;
    CGEventSetIntegerValueField(event, kEventTypeField, kEventDockControl);
    CGEventSetIntegerValueField(event, kGestureHIDType, kHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kGestureSwipeMotion, kGestureMotionHorizontal);
    CGEventSetIntegerValueField(event, kGesturePhase, phase);
    CGEventSetIntegerValueField(event, kGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(event, kGestureSwipeProgress, raw_sign * progress);
    CGEventSetDoubleValueField(event, kGestureSwipePositionX, kPositionX);
    CGEventSetDoubleValueField(event, kGestureZoomDeltaY, kZoomDeltaY);
    CGEventSetDoubleValueField(event, kSourceUnixProcessIDAlias, (double)mach_absolute_time());
    if (phase == kPhaseEnded) CGEventSetDoubleValueField(event, kGestureSwipeVelocityX, raw_sign * (instant_switch ? instant_velocity() : kVelocity));
    CGEventRef result = augment(event);
    CFRelease(event);
    return result;
}

static bool post_legacy_swipe(double sign) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return false;
    CGEventSetIntegerValueField(event, kEventTypeField, kEventDockControl);
    CGEventSetIntegerValueField(event, kGestureHIDType, kHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kGestureSwipeMotion, kGestureMotionHorizontal);
    CGEventSetDoubleValueField(event, kGestureSwipeProgress, sign);
    CGEventSetDoubleValueField(event, kGestureSwipeVelocityX, sign * (instant_switch ? instant_velocity() : kLegacyVelocity));
    CGEventSetIntegerValueField(event, kGesturePhase, kPhaseBegan);
    post_dock_event(event);
    CGEventSetIntegerValueField(event, kGesturePhase, kPhaseEnded);
    post_dock_event(event);
    CFRelease(event);
    return true;
}

static bool post_augmented_phase(int phase, double raw, double progress) {
    CGEventRef event = create_augmented_event(phase, raw, progress);
    if (!event) return false;
    post_dock_event(event);
    CFRelease(event);
    return true;
}

static bool post_augmented_swipes(double sign, int count) {
    double raw = augmented_sign(sign);
    for (int n = 0; n < count; n++) {
        if (!post_augmented_phase(kPhaseBegan, raw, 0.0)) return false;
        // An instant switch skips the drag: one step to the end, so the Dock has nothing to follow and nothing to slide.
        if (instant_switch) {
            if (!post_augmented_phase(kPhaseChanged, raw, 1.0)) return false;
            if (!post_augmented_phase(kPhaseEnded, raw, 1.0)) return false;
            continue;
        }
        for (int frame = 1; frame <= kDragFrames; frame++) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, kFrameDelay, false);
            double eased = 1.0 - (1.0 - (double)frame / kDragFrames) * (1.0 - (double)frame / kDragFrames);
            if (!post_augmented_phase(kPhaseChanged, raw, eased)) return false;
        }
        if (!post_augmented_phase(kPhaseEnded, raw, 1.0)) return false;
    }
    return true;
}

static CGPoint cursor_location(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    return point;
}

bool wm_can_batch_space_swipes(void) { return requires_augmentation(); }

bool wm_switch_space_index(int from_index, int to_index, uint32_t display) {
    if (display == 0) return false;
    bool batch = requires_augmentation();
    if (!batch && abs(to_index - from_index) > 1) {
        fputs("spaces: before macOS 27 the swipe goes one desktop at a time\n", stderr);
        return false;
    }
    if (from_index == to_index) return true;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGSetLocalEventsSuppressionInterval(0.0);
#pragma clang diagnostic pop
    });

    CGPoint restore = cursor_location();
    bool warp = !CGRectContainsPoint(CGDisplayBounds(display), restore);
    if (warp) {
        CGRect bounds = CGDisplayBounds(display);
        CGWarpMouseCursorPosition(CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)));
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, kStepDelay, false);
    }
    double sign = to_index > from_index ? 1.0 : -1.0;
    bool posted = batch ? post_augmented_swipes(sign, abs(to_index - from_index)) : post_legacy_swipe(sign);
    if (warp) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, kStepDelay, false);
        CGWarpMouseCursorPosition(restore);
        CGAssociateMouseAndMouseCursorPosition(true);
    }
    return posted;
}
