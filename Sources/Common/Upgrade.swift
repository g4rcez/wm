import Foundation

/// Homebrew keeps each version in `<prefix>/Cellar/wm/<version>/wm.app` and links the current one at `<prefix>/opt/wm/wm.app`.
/// The `opt` path survives `brew upgrade`; the Cellar one is removed. wm starts from the `opt` path, so the login item and
/// the running daemon do not point at a folder that brew deletes. Any other path (and a Cellar path without an `opt` twin)
/// comes back unchanged.
public func stableBundlePath(_ path: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
    let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    // ... / Cellar / wm / <version> / wm.app
    guard parts.count >= 4, parts[parts.count - 1] == "wm.app", parts[parts.count - 3] == "wm", parts[parts.count - 4] == "Cellar" else {
        return path
    }
    let prefix = "/" + parts.dropLast(4).joined(separator: "/")
    let stable = (prefix == "/" ? "" : prefix) + "/opt/wm/wm.app"
    return fileExists(stable) ? stable : path
}

/// Whether version `a` is older than `b`, part by part as numbers: `0.9.1` is older than `0.10.0`. A part that is not a number
/// (`1.2.0-beta`) counts by its leading digits; a missing part is 0.
public func isOlderVersion(_ a: String, than b: String) -> Bool {
    func parts(_ text: String) -> [Int] {
        text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    let left = parts(a), right = parts(b)
    for index in 0..<max(left.count, right.count) {
        let x = index < left.count ? left[index] : 0, y = index < right.count ? right[index] : 0
        if x != y { return x < y }
    }
    return false
}

/// Whether the running daemon has to be replaced by the build of this `wm`: it is another version, its bundle is gone
/// (brew removed the old version) or it runs from another bundle. A daemon that does not report its bundle (older
/// than this feature) is judged by its version alone.
public func needsRestart(
    daemonVersion: String, daemonBundle: String?, cliVersion: String, cliBundle: String?,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> Bool {
    if daemonVersion != cliVersion { return true }
    guard let daemonBundle else { return false }
    if !fileExists(daemonBundle) { return true }
    guard let cliBundle else { return false }
    return resolved(daemonBundle) != resolved(cliBundle)
}

private func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}
