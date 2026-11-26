import Foundation

/// Where macOS has a window that the Accessibility API did not list.
public enum WindowPlace: Sendable, Equatable {
    /// On the active Space.
    case here
    /// On another Space, for example the windows behind a window in native fullscreen.
    case elsewhere
    /// On no Space: the window is closed, or on its way between two Spaces.
    case gone
    /// The private functions that tell are missing.
    case unknown
}

/// How long a window that is on no Space may stay there before it counts as closed. A window that leaves native fullscreen is on
/// no Space, and not listed by the Accessibility API, for about a second.
public let spaceTransitionGrace: TimeInterval = 2

/// A window that the last scan did not list. The Accessibility API lists only the windows of the active Space, so a window on
/// another Space is not gone: if wm forgot it, it would lose its workspace and its place in the layout, and open again as a new
/// window on the active workspace when the user comes back. An app that could not be read says nothing about its windows either.
/// `goneFor` is how long the window has been on no Space: one that the system still lists may be on its way between two.
/// A hidden app (Cmd-H) is not listed either, but its windows are still there while the system lists them.
public func shouldForgetMissingWindow(
    appUnreadable: Bool, appHidden: Bool, inSystemList: Bool, place: WindowPlace, goneFor: TimeInterval
) -> Bool {
    if place == .elsewhere { return false }
    if place == .gone && inSystemList && goneFor < spaceTransitionGrace { return false }
    if (appUnreadable || appHidden) && inSystemList { return false }
    return true
}
