import Core
import PrivateApi

public enum WindowSpace {
    /// Where the window is. Ask for a window that the Accessibility API did not list.
    public static func place(of id: WindowID) -> WindowPlace {
        switch wm_window_space(id) {
        case 0: .gone
        case 1: .here
        case 2: .elsewhere
        default: .unknown
        }
    }
}
