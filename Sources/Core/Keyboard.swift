import Foundation

/// A keyboard that macOS has, as the HID system reports it.
public struct KeyboardInfo: Sendable, Equatable {
    /// The registry id of its event service. It changes when the keyboard connects again.
    public var registryID: UInt64
    public var name: String
    public var manufacturer: String?
    public var vendorID: Int
    public var productID: Int
    public var locationID: Int
    /// The main usage of its event service. A keyboard is usually 1 and 6, but some (the Dygma Raise) give their keys through a
    /// service whose main usage is consumer control, and name the keyboard only as one of their other usages.
    public var primaryUsagePage: Int
    public var primaryUsage: Int
    public var transport: String
    public var isBuiltIn: Bool
    /// CapsLock is mapped to F18 on this keyboard now (the hyper key of wm), as the system says.
    public var hyperMapped: Bool

    public init(
        registryID: UInt64 = 0, name: String, manufacturer: String? = nil, vendorID: Int = 0, productID: Int = 0, locationID: Int = 0,
        primaryUsagePage: Int = 1, primaryUsage: Int = 6, transport: String = "", isBuiltIn: Bool = false, hyperMapped: Bool = false
    ) {
        self.registryID = registryID
        self.name = name
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
        self.transport = transport
        self.isBuiltIn = isBuiltIn
        self.hyperMapped = hyperMapped
    }

    /// `vendor:product` in hex, for example `046d:c52b`. A built-in keyboard has no ids (`0000:0000`): use its name.
    public var id: String { String(format: "%04x:%04x", vendorID, productID) }
}

/// Which keyboards wm manages (`wm.config { keyboards = { ... } }`). A keyboard that wm manages gets the CapsLock-as-hyper mapping.
public struct KeyboardSettings: Sendable, Equatable {
    /// What a keyboard that the config does not name gets.
    public var defaultEnabled = true
    /// By lower case name or `vendor:product`.
    public var overrides: [String: Bool] = [:]

    public init(defaultEnabled: Bool = true, overrides: [String: Bool] = [:]) {
        self.defaultEnabled = defaultEnabled
        self.overrides = overrides
    }

    /// `vendor:product` wins over the name, and the name over the default.
    public func isEnabled(_ keyboard: KeyboardInfo) -> Bool {
        overrides[keyboard.id] ?? overrides[keyboard.name.lowercased()] ?? defaultEnabled
    }
}

public enum KeyboardAction: Sendable, Equatable {
    /// Send CapsLock as F18 from this keyboard.
    case map
    /// Take wm's mapping off this keyboard again.
    case clear
    case leave
}

public enum KeyboardPlan {
    /// What to do with each keyboard so that the keyboards the config enables have the hyper key, and the others do not. A
    /// keyboard is left alone when it is already as wanted, so that nothing runs for it, and a mapping that is not wm's stays.
    public static func plan(_ keyboards: [KeyboardInfo], settings: KeyboardSettings) -> [(keyboard: KeyboardInfo, action: KeyboardAction)] {
        keyboards.map { keyboard in
            switch (settings.isEnabled(keyboard), keyboard.hyperMapped) {
            case (true, false): (keyboard, .map)
            case (false, true): (keyboard, .clear)
            default: (keyboard, .leave)
            }
        }
    }
}
