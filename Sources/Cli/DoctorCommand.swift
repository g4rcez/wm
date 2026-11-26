import AppKit
import Common
import Foundation
import Scripting
import Security

/// What `wm doctor` found: the lines to print and the state that `wm doctor fix` works from.
struct Diagnosis {
    var checks: [DoctorCheck]
    var state: DoctorState
}

func diagnose() -> Diagnosis {
    var checks: [DoctorCheck] = []
    let config = defaultConfigURL()
    var summary = ConfigSummary(binds: 0)
    var configLoads = true
    if !FileManager.default.fileExists(atPath: config.path) {
        checks.append(DoctorCheck("config", .warn, "no config at \(config.path): wm has no key binds", hint: "run `wm init <osx|windows|i3|hyprland|niri>`"))
    } else {
        switch checkConfig(at: config) {
        case .success(let result):
            summary = result
            checks.append(DoctorCheck("config", .ok, "\(config.path) (\(result.binds) binds)"))
        case .failure(let error):
            configLoads = false
            checks.append(DoctorCheck("config", .fail, error.message, hint: "fix the line, then save: wm loads the file again"))
        }
    }
    let shortcutsFile = shortcutsURL(for: config)
    var shortcutCount = 0
    var shortcutProblem: String?
    do { shortcutCount = try readShortcuts(at: shortcutsFile).count } catch { shortcutProblem = "\(error)" }
    checks.append(shortcutsCheck(
        fileExists: FileManager.default.fileExists(atPath: shortcutsFile.path), imported: summary.shortcutsImported,
        count: shortcutCount, problem: shortcutProblem, overrides: summary.overrides.map(\.description)))

    let daemon: DaemonState
    if let running = runningDaemon() {
        let stale = isStale(running)
        if isOlderThan(running) {
            checks.append(DoctorCheck(
                "daemon", .warn, "runs version \(running.version), and this wm is older (\(wmVersion))", hint: olderCopyHint(running)))
        } else if running.version != wmVersion {
            checks.append(DoctorCheck("daemon", .warn, "runs version \(running.version), and this wm is \(wmVersion)", hint: "run `wm daemon reload`"))
        } else if stale {
            checks.append(DoctorCheck("daemon", .warn, "runs from \(running.bundle ?? "another place"), and this wm is not that one", hint: "run `wm daemon reload`"))
        } else {
            checks.append(DoctorCheck("daemon", .ok, "runs, version \(running.version)"))
        }
        let facts = daemonFacts()
        if let facts {
            checks += daemonChecks(facts)
        } else {
            checks.append(DoctorCheck("permissions", .warn, "the daemon did not answer the checks", hint: "it may be older than this wm: run `wm daemon stop`, then `wm daemon start`"))
        }
        daemon = stale ? .stale : facts.map(DaemonState.answers) ?? .silent
    } else {
        daemon = .down
        checks.append(DoctorCheck("daemon", .fail, "wm does not run", hint: "run `wm daemon start`"))
        checks.append(DoctorCheck("permissions", .skip, "they need the daemon"))
    }

    let copies = installedCopies()
    checks.append(copiesCheck(own: copies.own, others: copies.others))
    if let check = windowManagersCheck(running: runningWindowManagers()) { checks.append(check) }
    let oldImages = copies.own.map { own in copies.others.filter { $0.requirement != own.requirement }.compactMap(\.diskImage) } ?? []
    return Diagnosis(checks: checks, state: DoctorState(daemon: daemon, configLoads: configLoads, oldDiskImages: oldImages))
}

private func daemonFacts() -> DoctorFacts? {
    guard let answer = try? sendRequest(ClientRequest(args: ["doctor"]), timeoutSeconds: 2) else { return nil }
    return try? JSONDecoder().decode(DoctorFacts.self, from: Data(answer.stdout.utf8))
}

// MARK: - The copies of wm.app

private func bundleIdentifier(of app: URL) -> String {
    Bundle(url: app)?.bundleIdentifier ?? "local.wm"
}

/// The designated requirement of the signature: what macOS stores with a permission.
private func designatedRequirement(of app: URL) -> String? {
    var code: SecStaticCode?
    var requirement: SecRequirement?
    var text: CFString?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
          SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
    return text as String
}

/// The mount points of the disk images that are open now. Another volume (a backup drive) is not one, and is never ejected.
private func diskImageMounts() -> [String] {
    let output = commandOutput("/usr/bin/hdiutil", ["info", "-plist"])
    guard let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
          let images = plist["images"] as? [[String: Any]] else { return [] }
    return images.flatMap { $0["system-entities"] as? [[String: Any]] ?? [] }.compactMap { $0["mount-point"] as? String }
}

/// The wm.app of this `wm`, and every other one that macOS knows or that a mounted disk image holds.
private func installedCopies() -> (own: AppCopy?, others: [AppCopy]) {
    guard let bundle = appBundle() else { return (nil, []) }
    let ownPath = bundle.resolvingSymlinksInPath().path
    let mounts = diskImageMounts()
    let found = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier(of: bundle))
        + mounts.map { URL(fileURLWithPath: $0).appendingPathComponent("wm.app") }
    var seen: Set<String> = [ownPath]
    var others: [AppCopy] = []
    for url in found {
        let path = url.resolvingSymlinksInPath().path
        guard !path.contains("/.Trash/"), FileManager.default.fileExists(atPath: path), seen.insert(path).inserted else { continue }
        others.append(AppCopy(path: path, requirement: designatedRequirement(of: url), diskImage: mounts.first { path.hasPrefix($0 + "/") }))
    }
    return (AppCopy(path: ownPath, requirement: designatedRequirement(of: bundle)), others)
}

private func runningWindowManagers() -> [String] {
    String(decoding: commandOutput("/usr/bin/pgrep", ["-lix", "AeroSpace|yabai|Amethyst"]), as: UTF8.self)
        .split(separator: "\n").compactMap { $0.split(separator: " ", maxSplits: 1).last.map(String.init) }
}

private func commandOutput(_ path: String, _ arguments: [String]) -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return Data() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

/// Whether the command ended without an error.
private func succeeds(_ path: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

// MARK: - Fixing

/// A daemon that just started or loaded its config needs a moment: asking too soon would show a problem that is not there.
private func settle(until done: (DoctorFacts) -> Bool) {
    _ = retry(timeoutSeconds: 4, intervalSeconds: 0.25) { daemonFacts().map(done) ?? false }
}

/// The key tap starts a moment after the daemon, once it has Accessibility.
private func settleKeys() {
    settle { $0.keyTap || !$0.accessibility || !$0.onboarded }
}

private func apply(_ fix: DoctorFix) {
    switch fix {
    case .ejectDiskImage(let volume):
        if !succeeds("/usr/bin/hdiutil", ["detach", volume]) { print("      could not eject it: eject it in the Finder") }
    case .startDaemon:
        startDaemon()
        settleKeys()
    case .replaceDaemon:
        replaceDaemon()
        settleKeys()
    case .resetPermissions(let screenRecording):
        resetPermissions(screenRecording: screenRecording)
    case .restartForKeys:
        _ = quitDaemon()
        startDaemon()
        settleKeys()
    case .reloadForLoginItem:
        _ = try? sendRequest(ClientRequest(args: ["daemon", "reload"]))
        settle { $0.loginItemEnabled == $0.loginItemWanted }
    }
}

private func resetPermissions(screenRecording: Bool) {
    guard let bundle = appBundle() else { return }
    // wm must not run: an old build that loses the permission while it listens for keys can block all input.
    _ = quitDaemon()
    let identifier = bundleIdentifier(of: bundle)
    for service in ["Accessibility"] + (screenRecording ? ["ScreenCapture"] : []) {
        if !succeeds("/usr/bin/tccutil", ["reset", service, identifier]) { print("      tccutil could not reset \(service)") }
    }
    startDaemon()
    _ = succeeds("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
    print("      turn wm on in System Settings > Privacy & Security > Accessibility")
    // Only a person at a terminal can turn the switch on while the command waits.
    guard isatty(STDOUT_FILENO) == 1 else { return }
    print("      waiting up to 60 seconds…")
    fflush(stdout)
    let granted = retry(timeoutSeconds: 60, intervalSeconds: 1) {
        guard let facts = daemonFacts() else { return false }
        return facts.accessibility && facts.keyTap
    }
    print(granted ? "      granted" : "      not granted yet: wm starts managing the windows as soon as you grant it")
}

/// `wm doctor show`: asks the daemon to open its Doctor window.
func showDoctorWindow() -> Never {
    guard let answer = try? sendRequest(ClientRequest(args: ["doctor", "show"])) else {
        die("wm does not run", hint: "run `wm doctor fix`, or `wm daemon start`")
    }
    // A daemon from before the window answers `doctor` with its facts.
    if answer.stdout.hasPrefix("{") { die("the running wm has no Doctor window: it is older than this wm", hint: "run `wm daemon reload`") }
    write(answer.stdout, to: .standardOutput)
    printError(answer.stderr)
    exit(answer.exitCode)
}

/// `wm doctor fix`: runs the fixes one at a time, looks again after each, then prints what is left for the user.
func doctorFix(dryRun: Bool, json: Bool, show: Bool) -> Never {
    // The Doctor window starts this command, and a fix may quit that wm: a session of its own keeps this process running.
    if show {
        _ = setsid()
        signal(SIGHUP, SIG_IGN)
    }
    var diagnosis = diagnose()
    if dryRun, json {
        let report = DoctorReport(checks: diagnosis.checks, fixes: doctorFixes(diagnosis.state).map(\.title))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: (try? encoder.encode(report)) ?? Data("{}".utf8), as: UTF8.self))
        exit(doctorExitCode(diagnosis.checks))
    }
    var done: Set<String> = []
    if dryRun {
        let fixes = doctorFixes(diagnosis.state)
        if fixes.isEmpty { print("nothing that wm can fix by itself") }
        for fix in fixes { print("would \(fix.title)") }
        print("")
    } else {
        while let fix = doctorFixes(diagnosis.state).first(where: { !done.contains($0.id) }) {
            done.insert(fix.id)
            print("fix   \(fix.title)")
            fflush(stdout)
            apply(fix)
            diagnosis = diagnose()
        }
        print(done.isEmpty ? "nothing that wm can fix by itself\n" : "")
    }
    let left = diagnosis.checks.filter { $0.status == .fail || $0.status == .warn }
    print(renderDoctor(diagnosis.checks), terminator: "")
    if !dryRun {
        print(left.isEmpty ? "\nno problem left" : "\n\(left.count) left for you: follow the hint of each warn and fail line")
    }
    // After a permission reset the user is in System Settings: the window would cover it.
    if show, !dryRun, !done.contains(DoctorFix.resetPermissions(screenRecording: false).id) {
        _ = try? sendRequest(ClientRequest(args: ["doctor", "show"]))
    }
    exit(doctorExitCode(diagnosis.checks))
}
