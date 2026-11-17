import PrivateApi

/// The macOS shortcuts that a wm bind can replace.
public enum SystemShortcuts {
    /// Cmd+Tab and Cmd+Shift+Tab of macOS. The state belongs to the login session, so turn them on again when wm quits.
    public static func setCommandTab(enabled: Bool) {
        wm_set_system_cmd_tab(enabled)
    }
}
