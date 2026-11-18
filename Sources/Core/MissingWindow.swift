/// Where macOS has a window that the Accessibility API did not list.
public enum WindowPlace: Sendable, Equatable {
    /// On the active Space.
    case here
    /// On another Space, for example the windows behind a window in native fullscreen.
    case elsewhere
    /// On no Space: the window is closed.
    case gone
    /// The private functions that tell are missing.
    case unknown
}

/// A window that the last scan did not list. The Accessibility API lists only the windows of the active Space, so a window on
/// another Space is not gone: if wm forgot it, it would lose its workspace and its place in the layout, and open again as a new
/// window on the active workspace when the user comes back. An app that could not be read says nothing about its windows either.
public func shouldForgetMissingWindow(appUnreadable: Bool, inSystemList: Bool, place: WindowPlace) -> Bool {
    if place == .elsewhere { return false }
    if appUnreadable && inSystemList { return false }
    return true
}
