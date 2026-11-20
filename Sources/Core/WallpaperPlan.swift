import Foundation

/// Which wallpaper a monitor should show, from the workspace that it shows.
public enum WallpaperPlan {
    /// The wallpaper path of the workspace that a monitor shows: the one of a special workspace that covers it, else the one of its
    /// normal workspace. `nil` when neither has one: the monitor keeps the wallpaper that it had before wm changed anything.
    public static func path(workspace: String, special: String?, in wallpapers: [String: String]) -> String? {
        special.flatMap { wallpapers[$0] } ?? wallpapers[workspace]
    }
}
