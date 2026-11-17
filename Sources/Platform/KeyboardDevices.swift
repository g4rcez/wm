import Core
import Foundation
import IOKit

/// The keyboards of the Mac, read from the I/O Registry (no permission is needed, nothing is opened).
public enum KeyboardDevices {
    private static let capsLockUsage = 0x7_0000_0039
    private static let f18Usage = 0x7_0000_006D

    /// Every event service that handles keys: the built-in keyboard, USB and Bluetooth keyboards. A service counts when its main usage
    /// is keyboard (page 1, usage 6) or when keyboard is one of the usages of its device (a keyboard with a consumer control or a
    /// mouse part, such as the Dygma Raise, gives its keys through that service). Empty when the registry cannot be read.
    public static func list() -> [KeyboardInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [KeyboardInfo] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let keyboard = keyboard(at: entry) { found.append(keyboard) }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return found.sorted { ($0.name, $0.registryID) < ($1.name, $1.registryID) }
    }

    private static func keyboard(at entry: io_registry_entry_t) -> KeyboardInfo? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        let page = int(properties["PrimaryUsagePage"]) ?? 0, usage = int(properties["PrimaryUsage"]) ?? 0
        let pairs = properties["DeviceUsagePairs"] as? [[String: Any]] ?? []
        let handlesKeys = (page == 1 && usage == 6) || pairs.contains { int($0["DeviceUsagePage"]) == 1 && int($0["DeviceUsage"]) == 6 }
        guard handlesKeys else { return nil }
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &registryID)
        // hidutil keeps the mapping in the properties of the event service.
        let service = properties["HIDEventServiceProperties"] as? [String: Any]
        let mapping = service?["UserKeyMapping"] as? [[String: Any]] ?? []
        let mapped = mapping.contains { int($0["HIDKeyboardModifierMappingSrc"]) == capsLockUsage && int($0["HIDKeyboardModifierMappingDst"]) == f18Usage }
        return KeyboardInfo(
            registryID: registryID, name: properties["Product"] as? String ?? "Keyboard", manufacturer: properties["Manufacturer"] as? String,
            vendorID: int(properties["VendorID"]) ?? 0, productID: int(properties["ProductID"]) ?? 0, locationID: int(properties["LocationID"]) ?? 0,
            primaryUsagePage: page, primaryUsage: usage, transport: properties["Transport"] as? String ?? "", isBuiltIn: (properties["Built-In"] as? NSNumber)?.boolValue ?? false,
            hyperMapped: mapped)
    }

    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
}

/// Tells when a keyboard connects or goes away (USB, Bluetooth), so that the mapping of the hyper key reaches it at once. Several
/// events that come together (a keyboard has more than one interface) give one call, after a short pause.
@MainActor
public final class KeyboardWatcher {
    private static let pause: TimeInterval = 0.8

    private let onChange: @MainActor () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pending: DispatchWorkItem?

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            guard IOServiceAddMatchingNotification(port, notification, IOServiceMatching("IOHIDEventService"), keyboardNotification, context, &iterator) == KERN_SUCCESS else { continue }
            // The first drain arms the notification; the keyboards that are there now are not news.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    public func stop() {
        pending?.cancel()
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    fileprivate func changed() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pause, execute: item)
    }

    fileprivate nonisolated static func drain(_ iterator: io_iterator_t) {
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }
}

/// The notification port runs on the main queue, so the callback is on the main thread.
private let keyboardNotification: IOServiceMatchingCallback = { context, iterator in
    KeyboardWatcher.drain(iterator)
    guard let context else { return }
    let watcher = Unmanaged<KeyboardWatcher>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.changed() }
}
