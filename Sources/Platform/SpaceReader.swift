import CoreGraphics
import Foundation

/// Reads macOS Spaces through SkyLight. Read-only and loaded at runtime, so a missing symbol on a future macOS
/// returns `nil` instead of crashing.
public enum SpaceReader {
    public struct DisplaySpaces: Sendable, Equatable {
        public var displayID: UInt32
        /// Ordered Space ids of regular desktops (full-screen Spaces are left out).
        public var spaces: [UInt64]
        public var current: UInt64
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    public static func read() -> [DisplaySpaces]? {
        guard let handle,
              let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
              let copySymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)()
        let copy = unsafeBitCast(copySymbol, to: CopyManagedDisplaySpaces.self)
        guard let list = copy(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }

        return list.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String,
                  let displayID = displayID(for: identifier),
                  let current = (entry["Current Space"] as? [String: Any])?["id64"] as? UInt64,
                  let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
            let desktops = spaces.compactMap { space -> UInt64? in
                (space["type"] as? Int ?? 0) == 0 ? space["id64"] as? UInt64 : nil
            }
            return DisplaySpaces(displayID: displayID, spaces: desktops, current: current)
        }
    }

    private static func displayID(for identifier: String) -> UInt32? {
        if identifier == "Main" { return CGMainDisplayID() }
        guard let uuid = CFUUIDCreateFromString(nil, identifier as CFString) else { return nil }
        let id = CGDisplayGetDisplayIDFromUUID(uuid)
        return id == 0 ? nil : id
    }
}

@_silgen_name("CGDisplayGetDisplayIDFromUUID")
private func CGDisplayGetDisplayIDFromUUID(_ uuid: CFUUID) -> UInt32
