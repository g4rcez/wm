import AppKit
import Common
import Core

/// Changes the desktop picture of a monitor to the one of the workspace that it shows (`wallpaper` in `wm.workspace`). A workspace
/// without one gives the monitor back the picture that it had when wm first changed it. The pictures that wm replaced are saved in the
/// state folder, so a daemon that stops without cleaning up still puts them back at its next start.
///
/// macOS sets the picture of the current Space only, and gives no way to set a dynamic or aerial wallpaper again, so those come back as
/// the still picture that macOS reports for them.
@MainActor
final class WallpaperSwitcher {
    private var wallpapers: [String: String] = [:]
    /// The picture of each monitor before wm changed it.
    private var original: [UInt32: URL] = [:]
    private var applied: [UInt32: URL] = [:]
    private var missing: Set<String> = []
    /// Counts the times that the originals came back: a change that was waiting for its turn then does not undo it.
    private var generation = 0

    private static var originalsURL: URL {
        StateStore.url.deletingLastPathComponent().appendingPathComponent("wallpaper-original.json")
    }

    init() {
        restoreAfterCrash()
    }

    /// The pictures of the config, by workspace name. With none, the original pictures come back.
    func configure(_ next: [String: String]) {
        wallpapers = next
        missing = []
        if next.isEmpty { restore() }
    }

    /// The workspace that each monitor shows now (and the special workspace over it, if any). Changes a picture only when it differs.
    func update(shown: [UInt32: (workspace: String, special: String?)]) {
        guard !wallpapers.isEmpty else { return }
        for (id, place) in shown {
            guard let screen = Self.screen(id) else { continue }
            let wanted: URL?
            if let path = WallpaperPlan.path(workspace: place.workspace, special: place.special, in: wallpapers) {
                guard FileManager.default.fileExists(atPath: path) else {
                    if missing.insert(path).inserted { Log.write(.warn, "no picture at \(path)", source: "wallpaper") }
                    continue
                }
                wanted = URL(fileURLWithPath: path)
            } else {
                wanted = original[id]
            }
            guard let url = wanted, applied[id] != url else { continue }
            if original[id] == nil, let current = NSWorkspace.shared.desktopImageURL(for: screen) {
                original[id] = current
                saveOriginals()
            }
            applied[id] = url
            // One turn later, so the layout pass that caused the switch is not held up. The call takes a moment and the picture may flash.
            let scheduled = generation
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard self?.generation == scheduled else { return }
                    do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) } catch {
                        Log.write(.warn, "cannot set \(url.path): \(error.localizedDescription)", source: "wallpaper")
                    }
                }
            }
        }
    }

    /// Puts the original pictures back, at once. For the end of the daemon and for a config without pictures.
    func restore() {
        generation += 1
        for (id, url) in original {
            guard let screen = Self.screen(id) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        original = [:]
        applied = [:]
        try? FileManager.default.removeItem(at: Self.originalsURL)
    }

    private static func screen(_ id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }

    private func saveOriginals() {
        let saved = Dictionary(uniqueKeysWithValues: original.map { (String($0.key), $0.value.absoluteString) })
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: Self.originalsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.originalsURL, options: .atomic)
    }

    /// A previous daemon changed the pictures and did not put them back: do it now.
    private func restoreAfterCrash() {
        guard let data = try? Data(contentsOf: Self.originalsURL),
              let saved = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (key, text) in saved {
            guard let id = UInt32(key), let url = URL(string: text), let screen = Self.screen(id) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        try? FileManager.default.removeItem(at: Self.originalsURL)
        Log.write(.info, "put back the pictures that an earlier daemon changed", source: "wallpaper")
    }
}
