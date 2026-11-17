import Core
import Foundation

/// Makes CapsLock send F18 (`binds.capslock = "hyper"`), so that wm sees the key down and the key up. With the key as it is,
/// macOS gives a toggle and no key up. It sets `UserKeyMapping` of the keyboards, as `hidutil` does.
///
/// The mapping lasts until it is removed or the Mac restarts. wm removes it when it quits. It owns the whole property of the keyboards
/// that it manages while it is on: any other `UserKeyMapping` set with `hidutil` is replaced. A keyboard that connects later gets the
/// mapping when `KeyboardWatcher` sees it, and after wake and `wm daemon reload`.
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

    /// Does what `KeyboardPlan` decided for each keyboard: the keyboards that the config enables send CapsLock as F18, and the
    /// ones that it turns off get wm's mapping taken away. Each keyboard is matched by its ids and its place, so two keyboards
    /// get their own answer.
    public static func apply(_ plan: [(keyboard: KeyboardInfo, action: KeyboardAction)]) {
        for (keyboard, action) in plan where action != .leave {
            let mapping = action == .map ? caps : "[]"
            run(["property", "--matching", matching(keyboard), "--set", #"{"UserKeyMapping":\#(mapping)}"#])
        }
    }

    private static let caps = #"[{"HIDKeyboardModifierMappingSrc":\#(capsLockUsage),"HIDKeyboardModifierMappingDst":\#(f18Usage)}]"#

    /// The properties of the event service of one keyboard, as `hidutil --matching` takes them. Its own main usage is in it, so a
    /// keyboard with a mouse or consumer part gets the mapping on the service that handles the keys and on no other.
    static func matching(_ keyboard: KeyboardInfo) -> String {
        #"{"PrimaryUsagePage":\#(keyboard.primaryUsagePage),"PrimaryUsage":\#(keyboard.primaryUsage),"VendorID":\#(keyboard.vendorID),"ProductID":\#(keyboard.productID),"LocationID":\#(keyboard.locationID)}"#
    }

    /// Takes wm's mapping off every keyboard that has it, also the ones that the general matching of `setCapsLockToF18` does not reach.
    public static func removeCapsLockMapping() {
        setCapsLockToF18(false)
        for keyboard in KeyboardDevices.list() where keyboard.hyperMapped {
            run(["property", "--matching", matching(keyboard), "--set", #"{"UserKeyMapping":[]}"#])
        }
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
