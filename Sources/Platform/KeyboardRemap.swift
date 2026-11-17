import Foundation

/// Makes CapsLock send F18 (`binds.capslock = "hyper"`), so that wm sees the key down and the key up. With the key as it is,
/// macOS gives a toggle and no key up. It sets `UserKeyMapping` of the keyboards, as `hidutil` does.
///
/// The mapping lasts until it is removed or the Mac restarts. wm removes it when it quits. It owns the whole property while it is on:
/// any other `UserKeyMapping` set with `hidutil` is replaced. A keyboard that connects later (Bluetooth) gets the mapping on the next
/// `apply`: after wake, or `wm daemon reload`.
public enum KeyboardRemap {
    /// The virtual key code of F18. The event tap reads CapsLock as this key.
    public static let hyperKeyCode = 79

    private static let capsLockUsage = 0x7_0000_0039
    private static let f18Usage = 0x7_0000_006D
    /// Only keyboards: usage page 1 (generic desktop), usage 6 (keyboard).
    private static let keyboards = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#

    /// CapsLock → F18 for every keyboard, or the plain mapping again.
    public static func setCapsLockToF18(_ on: Bool) {
        let mapping = on ? #"[{"HIDKeyboardModifierMappingSrc":\#(capsLockUsage),"HIDKeyboardModifierMappingDst":\#(f18Usage)}]"# : "[]"
        run(["property", "--matching", keyboards, "--set", #"{"UserKeyMapping":\#(mapping)}"#])
    }

    private static func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
