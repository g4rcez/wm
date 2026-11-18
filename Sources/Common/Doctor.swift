import Foundation

public enum DoctorStatus: String, Codable, Sendable {
    case ok, warn, fail
    /// The check cannot run (the daemon is off, or the system has no such thing).
    case skip
}

/// One line of `wm doctor`: what was checked, the result, and what to do when it is not ok.
public struct DoctorCheck: Codable, Equatable, Sendable {
    public var name: String
    public var status: DoctorStatus
    public var detail: String
    public var hint: String?

    public init(_ name: String, _ status: DoctorStatus, _ detail: String, hint: String? = nil) {
        self.name = name
        self.status = status
        self.detail = detail
        self.hint = hint
    }
}

/// What the daemon knows about itself. The daemon sends these facts as JSON and `wm doctor` makes the checks from them, so the
/// text of the checks is in one place and the daemon stays small.
public struct DoctorFacts: Codable, Equatable, Sendable {
    public var accessibility: Bool
    /// The tap that reads the keys runs.
    public var keyTap: Bool
    public var screenRecording: Bool
    /// `start_at_login` of the config.
    public var loginItemWanted: Bool
    public var loginItemEnabled: Bool
    /// Only an installed wm.app can be a login item.
    public var isAppBundle: Bool
    /// The user pressed Start in the setup window (`Onboarding`). Until then wm moves no window.
    public var onboarded: Bool

    public init(
        accessibility: Bool, keyTap: Bool, screenRecording: Bool, loginItemWanted: Bool, loginItemEnabled: Bool, isAppBundle: Bool,
        onboarded: Bool
    ) {
        self.accessibility = accessibility
        self.keyTap = keyTap
        self.screenRecording = screenRecording
        self.loginItemWanted = loginItemWanted
        self.loginItemEnabled = loginItemEnabled
        self.isAppBundle = isAppBundle
        self.onboarded = onboarded
    }
}

/// The check of `shortcuts.toml`. `problem` is the message of reading the file. `overrides` are the binds that replaced a
/// bind of the other file (`wm.shortcuts()` and `wm.bind` for the same keys).
public func shortcutsCheck(fileExists: Bool, imported: Bool, count: Int, problem: String?, overrides: [String]) -> DoctorCheck {
    if let problem {
        return DoctorCheck("shortcuts", .fail, problem, hint: "fix the line, or open Shortcuts… in the wm menu to save the file again")
    }
    guard fileExists else { return DoctorCheck("shortcuts", .skip, "no shortcuts.toml: init.lua is the only source of binds") }
    guard imported else {
        return DoctorCheck(
            "shortcuts", .warn, "shortcuts.toml has \(count) shortcuts, but init.lua does not call wm.shortcuts(): none is bound",
            hint: "add `wm.shortcuts()` to init.lua")
    }
    guard overrides.isEmpty else {
        return DoctorCheck(
            "shortcuts", .warn, "\(overrides.count) in conflict: " + overrides.joined(separator: "; "),
            hint: "remove one of the two binds, or move `wm.shortcuts()` in init.lua to choose which one wins")
    }
    return DoctorCheck("shortcuts", .ok, "\(count) shortcuts")
}

public func daemonChecks(_ facts: DoctorFacts) -> [DoctorCheck] {
    let privacy = "System Settings > Privacy & Security"
    var checks: [DoctorCheck] = []
    checks.append(
        facts.onboarded
            ? DoctorCheck("setup", .ok, "done")
            : DoctorCheck("setup", .warn, "not finished: wm moves no window yet", hint: "choose Setup… in the wm menu bar menu, then press Start"))
    checks.append(
        facts.accessibility
            ? DoctorCheck("accessibility", .ok, "granted")
            : DoctorCheck("accessibility", .fail, "not granted: wm cannot move windows or read keys", hint: "turn wm on in \(privacy) > Accessibility"))
    checks.append(
        facts.keyTap
            ? DoctorCheck("keys", .ok, "wm reads the keys")
            : DoctorCheck("keys", .fail, "the key tap does not run: no bind works", hint: facts.accessibility
                ? "run `wm daemon stop`, then `wm daemon start`"
                : "grant Accessibility first"))
    checks.append(
        facts.screenRecording
            ? DoctorCheck("screen recording", .ok, "granted")
            : DoctorCheck("screen recording", .warn, "not granted: the switcher and the overview show no thumbnails", hint: "optional: turn wm on in \(privacy) > Screen & System Audio Recording"))
    if !facts.isAppBundle {
        checks.append(DoctorCheck("login item", .skip, "this wmd does not run from a wm.app"))
    } else if facts.loginItemWanted == facts.loginItemEnabled {
        checks.append(DoctorCheck("login item", .ok, facts.loginItemEnabled ? "wm starts at login" : "off (start_at_login is not set)"))
    } else if facts.loginItemWanted {
        checks.append(DoctorCheck("login item", .warn, "start_at_login is on, but wm is not a login item", hint: "look in System Settings > General > Login Items"))
    } else {
        checks.append(DoctorCheck("login item", .warn, "wm is a login item, but start_at_login is off", hint: "set start_at_login = true, or turn wm off in System Settings > General > Login Items"))
    }
    return checks
}

/// The text of `wm doctor`: one line for each check, and its hint under it when it is not ok.
public func renderDoctor(_ checks: [DoctorCheck]) -> String {
    let width = checks.map(\.name.count).max() ?? 0
    var lines: [String] = []
    for check in checks {
        let status = check.status.rawValue.padding(toLength: 4, withPad: " ", startingAt: 0)
        lines.append("\(status)  \(check.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(check.detail)")
        if let hint = check.hint, check.status != .ok { lines.append("      \(String(repeating: " ", count: width))  hint: \(hint)") }
    }
    return lines.joined(separator: "\n") + "\n"
}

/// `wm doctor` exits with 1 when a check failed. A warning is not a failure.
public func doctorExitCode(_ checks: [DoctorCheck]) -> Int32 {
    checks.contains { $0.status == .fail } ? 1 : 0
}
