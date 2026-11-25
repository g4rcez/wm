import Foundation

/// A problem that `wm doctor fix` repairs by itself. A problem that needs a choice of the user (a config error, a permission
/// switch, a setting of macOS, another copy of wm on the disk) is not one: its check says what to do.
public enum DoctorFix: Equatable, Sendable {
    /// A mounted disk image holds a wm with another signature: macOS could open that one.
    case ejectDiskImage(String)
    case startDaemon
    /// The daemon is another build than this `wm`, or does not answer the checks.
    case replaceDaemon
    /// Accessibility is not granted. An entry for an older signature shows as switched on and grants nothing: remove it, so
    /// that the switch the user turns on counts. Screen Recording goes with it only when it is not granted either.
    case resetPermissions(screenRecording: Bool)
    /// Accessibility is granted and the key tap does not run.
    case restartForKeys
    /// The login item does not match `start_at_login`: wm sets it when it loads the config.
    case reloadForLoginItem

    /// What names the fix: `wm doctor fix` runs each one once.
    public var id: String {
        switch self {
        case .ejectDiskImage(let volume): "eject \(volume)"
        case .startDaemon: "start"
        case .replaceDaemon: "replace"
        case .resetPermissions: "permissions"
        case .restartForKeys: "keys"
        case .reloadForLoginItem: "login item"
        }
    }

    public var title: String {
        switch self {
        case .ejectDiskImage(let volume): "eject the disk image at \(volume), which holds a wm with another signature"
        case .startDaemon: "start wm"
        case .replaceDaemon: "restart wm from this build"
        case .resetPermissions(let screenRecording):
            "remove the old Accessibility\(screenRecording ? " and Screen Recording" : "") entry of wm, restart it and ask again"
        case .restartForKeys: "restart wm, so that it reads the keys"
        case .reloadForLoginItem: "load the config again, which sets the login item"
        }
    }
}

public enum DaemonState: Equatable, Sendable {
    case down
    /// Another build than this `wm`.
    case stale
    /// It runs and does not answer the checks.
    case silent
    case answers(DoctorFacts)
}

public struct DoctorState: Equatable, Sendable {
    public var daemon: DaemonState
    public var configLoads: Bool
    /// The mount points of the disk images that hold a wm with another signature.
    public var oldDiskImages: [String]

    public init(daemon: DaemonState, configLoads: Bool = true, oldDiskImages: [String] = []) {
        self.daemon = daemon
        self.configLoads = configLoads
        self.oldDiskImages = oldDiskImages
    }
}

/// What `wm doctor fix --dry-run --json` prints, and what the Doctor window shows.
public struct DoctorReport: Codable, Equatable, Sendable {
    public var checks: [DoctorCheck]
    /// What `wm doctor fix` would do, one sentence each.
    public var fixes: [String]

    public init(checks: [DoctorCheck], fixes: [String]) {
        self.checks = checks
        self.fixes = fixes
    }
}

/// The fixes for what is wrong now, in the order to run them. What the daemon knows (the permissions, the keys) shows only
/// after it runs, so `wm doctor fix` asks again after each fix.
public func doctorFixes(_ state: DoctorState) -> [DoctorFix] {
    var fixes = state.oldDiskImages.map(DoctorFix.ejectDiskImage)
    switch state.daemon {
    case .down: fixes.append(.startDaemon)
    case .stale, .silent: fixes.append(.replaceDaemon)
    case .answers(let facts):
        // Before the setup is finished, wm has not asked for any permission yet.
        if facts.onboarded {
            if !facts.accessibility {
                fixes.append(.resetPermissions(screenRecording: !facts.screenRecording))
            } else if !facts.keyTap {
                fixes.append(.restartForKeys)
            }
        }
        // A config with an error is not applied, so a reload would change nothing.
        if state.configLoads, facts.isAppBundle, facts.loginItemWanted != facts.loginItemEnabled {
            fixes.append(.reloadForLoginItem)
        }
    }
    return fixes
}
