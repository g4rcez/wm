import Foundation

public enum DoctorStatus: String, Codable, Sendable {
    case ok, warn, fail
    case skip
}

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

public struct DoctorFacts: Codable, Equatable, Sendable {
    public var accessibility: Bool
    public var keyTap: Bool
    public var screenRecording: Bool
    public var loginItemWanted: Bool
    public var loginItemEnabled: Bool
    public var isAppBundle: Bool
    public var onboarded: Bool
    public var native: NativeFacts?
    /// The app that holds Secure Event Input now, or `nil` when it is off.
    public var secureInput: String?
    /// `binds.event_level = "hid"` is set, but macOS refused the HID tap and the session tap runs.
    public var keyLevelRefused: Bool?
    /// Whether the icon of wm is on screen. A daemon older than this check does not say.
    public var menuBarShown: Bool?
    /// The `wm.gesture` swipes that macOS uses, so they do not run. `nil` with the trackpad off, or from an older daemon.
    public var takenGestures: [String]?
    /// The swipes that wm has without a config and that macOS uses.
    public var takenSwipes: [String]?

    public init(
        accessibility: Bool, keyTap: Bool, screenRecording: Bool, loginItemWanted: Bool, loginItemEnabled: Bool, isAppBundle: Bool,
        onboarded: Bool, native: NativeFacts? = nil, secureInput: String? = nil, keyLevelRefused: Bool = false, menuBarShown: Bool? = nil
    ) {
        self.menuBarShown = menuBarShown
        self.keyLevelRefused = keyLevelRefused
        self.native = native
        self.secureInput = secureInput
        self.accessibility = accessibility
        self.keyTap = keyTap
        self.screenRecording = screenRecording
        self.loginItemWanted = loginItemWanted
        self.loginItemEnabled = loginItemEnabled
        self.isAppBundle = isAppBundle
        self.onboarded = onboarded
    }
}

public struct NativeFacts: Codable, Equatable, Sendable {
    public var canList: Bool
    public var canMoveWindows: Bool
    public var canCreate: Bool
    public var rearrangesSpaces: Bool
    public var separateSpaces: Bool
    public var desktops: Int
    public var missing: [String]

    public init(canList: Bool, canMoveWindows: Bool, canCreate: Bool = false, rearrangesSpaces: Bool, separateSpaces: Bool, desktops: Int, missing: [String]) {
        self.canList = canList
        self.canMoveWindows = canMoveWindows
        self.canCreate = canCreate
        self.rearrangesSpaces = rearrangesSpaces
        self.separateSpaces = separateSpaces
        self.desktops = desktops
        self.missing = missing
    }
}

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
            : DoctorCheck("screen recording", .warn, "not granted: the switcher and the overview show no thumbnails, and `select` reads no terminal", hint: "optional: turn wm on in \(privacy) > Screen & System Audio Recording"))
    if !facts.isAppBundle {
        checks.append(DoctorCheck("login item", .skip, "this wmd does not run from a wm.app"))
    } else if facts.loginItemWanted == facts.loginItemEnabled {
        checks.append(DoctorCheck("login item", .ok, facts.loginItemEnabled ? "wm starts at login" : "off (start_at_login is not set)"))
    } else if facts.loginItemWanted {
        checks.append(DoctorCheck("login item", .warn, "start_at_login is on, but wm is not a login item", hint: "look in System Settings > General > Login Items"))
    } else {
        checks.append(DoctorCheck("login item", .warn, "wm is a login item, but start_at_login is off", hint: "set start_at_login = true, or turn wm off in System Settings > General > Login Items"))
    }
    if facts.keyLevelRefused == true {
        checks.append(DoctorCheck(
            "key level", .warn, "binds.event_level = \"hid\", but macOS refused a HID event tap: wm listens at the session level",
            hint: "remove event_level, or run wm from a terminal that has Input Monitoring and Accessibility permission"))
    }
    if facts.menuBarShown == false {
        checks.append(DoctorCheck("menu bar", .warn, "macOS hides the icon of wm", hint: "turn wm on in System Settings > Menu Bar"))
    }
    if let holder = facts.secureInput {
        checks.append(DoctorCheck(
            "secure input", .warn, "on, held by \(holder): macOS hides the keys from wm, so no bind works",
            hint: "leave the password field, or turn off Secure Keyboard Entry in \(holder)"))
    }
    if let user = facts.takenGestures, let builtIn = facts.takenSwipes { checks.append(gesturesCheck(user: user, builtIn: builtIn)) }
    if let native = facts.native { checks += nativeChecks(native) }
    return checks
}

/// Swipes that macOS uses are off in wm. Only a swipe that the user asked for is a warning: a Mac as it comes uses them all.
public func gesturesCheck(user: [String], builtIn: [String]) -> DoctorCheck {
    let hint = "to use them in wm, turn the macOS gesture off in System Settings > Trackpad > More Gestures "
        + "(three-finger drag: Accessibility > Pointer Control > Trackpad Options)"
    if !user.isEmpty {
        return DoctorCheck(
            "gestures", .warn, "macOS uses these swipes, so wm.gesture does not run: " + user.joined(separator: ", "), hint: hint)
    }
    if !builtIn.isEmpty {
        return DoctorCheck("gestures", .skip, "left to macOS, which uses them: " + builtIn.joined(separator: ", "), hint: hint)
    }
    return DoctorCheck("gestures", .ok, "macOS uses no swipe of wm")
}

/// A wm.app on this Mac. macOS keeps one permission for all the copies with the same bundle id, by the signature.
public struct AppCopy: Equatable, Sendable {
    public var path: String
    /// The designated requirement of its signature, nil without one.
    public var requirement: String?
    /// The mount point, when the copy is on a disk image.
    public var diskImage: String?

    public init(path: String, requirement: String?, diskImage: String? = nil) {
        self.path = path
        self.requirement = requirement
        self.diskImage = diskImage
    }
}

public func copiesCheck(own: AppCopy?, others: [AppCopy]) -> DoctorCheck {
    guard let own else { return DoctorCheck("copies", .skip, "this wm is not in a wm.app") }
    let different = others.filter { $0.requirement != own.requirement }
    guard !different.isEmpty else { return DoctorCheck("copies", .ok, "no other wm.app with another signature") }
    var hints: [String] = []
    if different.contains(where: { $0.diskImage != nil }) { hints.append("`wm doctor fix` ejects the disk images") }
    if different.contains(where: { $0.diskImage == nil }) { hints.append("remove the copies that you do not use") }
    return DoctorCheck(
        "copies", .warn, "another signature, which can take the permissions of this one: " + different.map(\.path).joined(separator: ", "),
        hint: hints.joined(separator: "; "))
}

/// Nil when no other window manager runs.
public func windowManagersCheck(running: [String]) -> DoctorCheck? {
    guard !running.isEmpty else { return nil }
    let names = running.joined(separator: ", ")
    return DoctorCheck("window managers", .warn, "\(names) runs too: both move the same windows", hint: "quit \(names)")
}

public func nativeChecks(_ facts: NativeFacts) -> [DoctorCheck] {
    let mission = "System Settings > Desktop & Dock > Mission Control"
    var checks: [DoctorCheck] = []
    checks.append(
        facts.canList
            ? DoctorCheck("desktops", .ok, "\(facts.desktops) desktops")
            : DoctorCheck("desktops", .fail, "macOS does not list the desktops to wm: native workspaces do not work", hint: "set workspaces = \"emulated\""))
    if facts.canList, !facts.missing.isEmpty {
        let names = facts.missing.joined(separator: ", ")
        checks.append(
            facts.canCreate
                ? DoctorCheck("desktops needed", .ok, "no desktop yet for workspace \(names): wm makes it when the workspace is shown")
                : DoctorCheck(
                    "desktops needed", .warn, "no desktop for workspace \(names)",
                    hint: "add desktops in Mission Control (Control-Up): this macOS does not let wm make them"))
    }
    checks.append(
        facts.canMoveWindows
            ? DoctorCheck("send to desktop", .ok, "wm can move a window to a desktop")
            : DoctorCheck("send to desktop", .warn, "`window send workspace` cannot move windows to another desktop on this macOS"))
    checks.append(
        facts.rearrangesSpaces
            ? DoctorCheck(
                "desktop order", .warn, "macOS rearranges the desktops by use: workspace 2 may not stay desktop 2",
                hint: "turn off Automatically rearrange Spaces based on most recent use in \(mission)")
            : DoctorCheck("desktop order", .ok, "the desktops keep their order"))
    checks.append(
        facts.separateSpaces
            ? DoctorCheck("separate spaces", .ok, "each display has its own desktops")
            : DoctorCheck(
                "separate spaces", .warn, "the displays share their desktops: wm cannot tell the displays apart",
                hint: "turn on Displays have separate Spaces in \(mission), then log out"))
    return checks
}

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

public func doctorExitCode(_ checks: [DoctorCheck]) -> Int32 {
    checks.contains { $0.status == .fail } ? 1 : 0
}
