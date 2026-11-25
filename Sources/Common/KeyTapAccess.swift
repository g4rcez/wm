/// What the daemon does with its key taps, from the Accessibility permission and whether the taps are installed.
public enum KeyTapAccess: Equatable, Sendable {
    /// The permission is there and no tap listens: install the taps.
    case start
    /// The permission is gone and the taps are installed: remove them at once, or they block all input of the Mac.
    case stop
    case keep

    public static func action(trusted: Bool, listening: Bool) -> KeyTapAccess {
        switch (trusted, listening) {
        case (true, false): .start
        case (false, true): .stop
        default: .keep
        }
    }
}
