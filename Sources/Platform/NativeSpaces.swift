import AppKit
import Core
import PrivateApi

@MainActor
public enum NativeSpaces {
    public struct Listing: Sendable, Equatable {
        public var display: NativeDisplay
        public var allSpaces: [UInt64]
    }

    public static var canList: Bool { wm_spaces_support() & 1 != 0 }
    public static var canMoveWindows: Bool { wm_spaces_support() & 2 != 0 }
    public static var canCreate: Bool { wm_spaces_support() & 4 != 0 }

    public static func create(on display: String) -> UInt64? {
        let space = wm_create_space(display as CFString)
        return space == 0 ? nil : space
    }

    public static func listings() -> [Listing] {
        guard let rows = wm_spaces_copy_displays().map({ $0 as NSArray as? [[String: Any]] }) ?? nil else { return [] }
        let frames = Dictionary(uniqueKeysWithValues: Displays.all().map { ($0.id, $0.frame.minX) })
        return rows.compactMap { row in
            guard let uuid = row["uuid"] as? String, let id = (row["displayID"] as? NSNumber)?.uint32Value,
                let current = (row["current"] as? NSNumber)?.uint64Value, let spaces = row["spaces"] as? [[String: Any]]
            else { return nil }
            let all = spaces.compactMap { ($0["id"] as? NSNumber)?.uint64Value }
            let users = spaces.compactMap { space -> UInt64? in
                (space["type"] as? NSNumber)?.intValue == 0 ? (space["id"] as? NSNumber)?.uint64Value : nil
            }
            let display = NativeDisplay(uuid: uuid, displayID: id, minX: frames[id] ?? 0, current: current, spaces: users)
            return Listing(display: display, allSpaces: all)
        }
    }

    public static func space(of window: UInt32) -> UInt64? {
        let space = wm_space_of_window(window)
        return space == 0 ? nil : space
    }

    @discardableResult
    public static func move(_ windows: [UInt32], to space: UInt64) -> Bool {
        guard !windows.isEmpty else { return true }
        return windows.withUnsafeBufferPointer { wm_move_windows_to_space($0.baseAddress, Int32(windows.count), space) }
    }

    /// `true`: a desktop switch jumps (the swipe has no drag and ends very fast), so the Dock plays little or no slide.
    public static func setInstantSwitch(_ on: Bool) { wm_set_instant_space_switch(on) }

    public static func makeSwitcher() -> SpaceSwitcher {
        SpaceSwitcher(
            currentSpace: { uuid in listings().first { $0.display.uuid == uuid }?.display.current ?? 0 },
            spaceIDs: { uuid in listings().first { $0.display.uuid == uuid }?.allSpaces ?? [] },
            swipe: { from, to, uuid in
                guard let display = listings().first(where: { $0.display.uuid == uuid })?.display.displayID else { return false }
                return wm_switch_space_index(from, to, display)
            },
            batchMovement: wm_can_batch_space_swipes(),
            dockProcess: {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            })
    }

    public static var rearrangesSpaces: Bool {
        (UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "mru-spaces") as? Bool) ?? true
    }

    public static var displaysHaveSeparateSpaces: Bool {
        (UserDefaults(suiteName: "com.apple.spaces")?.object(forKey: "spans-displays") as? Bool).map { !$0 } ?? true
    }
}
