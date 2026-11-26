import Foundation

/// The macOS settings that say which trackpad swipes macOS uses itself.
public enum SystemGestures {
    private static let trackpadDomains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// Whether macOS tiles a window that is dragged by its title bar to an edge of the screen (System Settings > Desktop & Dock >
    /// Drag windows to screen edges to tile). On by default.
    public static var tilesByEdgeDrag: Bool {
        (UserDefaults.standard.persistentDomain(forName: "com.apple.WindowManager")?["EnableTilingByEdgeDrag"] as? NSNumber)?.boolValue ?? true
    }

    /// The preferences of the built-in and the Bluetooth trackpad, and of the Dock, as they are now. A domain that does not
    /// exist is empty.
    public static func read() -> (trackpads: [[String: Any]], dock: [String: Any]) {
        func domain(_ name: String) -> [String: Any] { UserDefaults.standard.persistentDomain(forName: name) ?? [:] }
        return (trackpadDomains.map(domain), domain("com.apple.dock"))
    }
}
