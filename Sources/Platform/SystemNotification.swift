import Foundation
import UserNotifications

/// A native notification of macOS (Notification Center). The first one asks the user for permission.
///
/// Only an installed `.app` can post: from a bare executable (`swift run`, `.build/debug/wmd`) `UNUserNotificationCenter`
/// would crash, so there `post` does nothing.
public enum SystemNotification {
    public struct Denied: Error, CustomStringConvertible {
        public var description: String { "notifications are not allowed for wm (System Settings > Notifications)" }
    }

    /// An app that runs in the background has no front window, so macOS would hide the banner without this.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .list]
        }
    }

    private static let presenter = Presenter()

    /// `id` replaces the notification with the same id that is still in Notification Center, so a repeated event
    /// shows one notification and not a pile.
    public static func post(title: String, body: String, id: String) async throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        guard try await center.requestAuthorization(options: [.alert]) else { throw Denied() }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
