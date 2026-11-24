import AppKit
import Carbon.HIToolbox

/// Secure Event Input: while a password field has focus (or an app turned on "Secure Keyboard Entry"), macOS gives no key events to
/// event taps, so no wm bind runs.
public enum SecureInput {
    public static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// The process that turned it on, as far as the session says; `nil` when it is off or the session does not name one.
    public static func holder() -> (pid: pid_t, name: String)? {
        guard isEnabled, let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        return (pid, name)
    }

    /// What to show for the state now: `nil` when Secure Input is off, else the name of the app that holds it ("an app" if unknown).
    public static func state() -> String? {
        guard isEnabled else { return nil }
        return holder()?.name ?? "an app"
    }
}
