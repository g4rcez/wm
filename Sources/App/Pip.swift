import Common
import Core
import Foundation
import Platform

/// The pictures of `window pip`: which windows have one, and where each picture is.
@MainActor
final class PipController {
    static let limit = 4

    private struct Item {
        var window: WindowID
        var corner: PipCorner
        var monitor: UInt32
        var shape: CGSize
        var panel: PipPanel
        var capture: LiveCapture
        var pixels = CGSize.zero
    }

    private unowned let manager: WindowManager
    private var items: [Item] = []
    private var timer: Timer?

    init(manager: WindowManager) { self.manager = manager }

    func command(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        let cornerFlag = flags.first { $0.hasPrefix("--corner=") }
        if let bad = unknownOption(flags.filter { $0 != cornerFlag }, allowed: ["--all"], usage: "window pip") { return bad }
        let action = words.first ?? "toggle"
        guard words.count <= 1, ["on", "off", "toggle"].contains(action) else {
            return fail("window pip takes on, off or toggle", 2, usage: "window pip")
        }
        var corner: PipCorner?
        if let cornerFlag {
            corner = PipCorner(rawValue: String(cornerFlag.dropFirst("--corner=".count)))
            guard corner != nil else {
                return fail("--corner takes " + PipCorner.allCases.map(\.rawValue).joined(separator: ", "), 2, usage: "window pip")
            }
        }
        if flags.contains("--all") {
            guard action == "off" else { return fail("--all goes with off", 2, usage: "window pip") }
            for item in items { close(item.window) }
            return ok()
        }
        guard let id else { return fail("there is no focused window") }
        let shown = items.contains { $0.window == id }
        if action == "off" || (action == "toggle" && shown && corner == nil) {
            guard shown else { return fail("this window has no picture", 1, hint: "`wm window pip off --all` closes every picture") }
            close(id)
            return ok()
        }
        if shown {
            if let corner, let index = items.firstIndex(where: { $0.window == id }) { items[index].corner = corner }
            update()
            return ok()
        }
        return open(id, corner: corner)
    }

    private func open(_ id: WindowID, corner: PipCorner?) -> ServerAnswer {
        guard let managed = manager.windows[id], !managed.minimized else { return fail("wm has no such window, or it is minimized") }
        guard items.count < Self.limit else { return fail("there are \(Self.limit) pictures already", 1, hint: "close one with `wm window pip off`") }
        guard ThumbnailService.hasPermission else {
            ThumbnailService.requestOnce()
            return fail("window pip needs the Screen Recording permission", 1, hint: "allow wm in System Settings > Privacy & Security > Screen Recording")
        }
        guard let monitor = manager.focusedMonitor else { return fail("there is no monitor") }
        let panel = PipPanel(
            clicked: { [weak self] in self?.manager.focus(id) },
            dragged: { [weak self] in self?.drop(id, at: $0) },
            closed: { [weak self] in self?.close(id) })
        let capture = LiveCapture(
            window: id, onFrame: { panel.draw($0) },
            onStop: { [weak self] in
                Log.write(.debug, "picture of window \(id) stopped by macOS", source: "pip")
                self?.close(id)
            })
        items.append(Item(
            window: id, corner: corner ?? manager.settings.pip.corner, monitor: monitor.id, shape: managed.info.frame.size,
            panel: panel, capture: capture))
        update()
        guard let item = items.first(where: { $0.window == id }) else { return fail("cannot show the picture") }
        let pixels = item.pixels, fps = manager.settings.pip.fps
        Task { @MainActor in
            let started = await capture.start(pixels: pixels, fps: fps)
            guard let current = items.first(where: { $0.capture === capture }) else { return }
            if !started {
                Log.write(.error, "cannot capture window \(id)", source: "pip")
                close(id)
            } else if current.pixels != pixels {
                // The picture took another size while the capture started.
                capture.resize(pixels: current.pixels, fps: fps)
            }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        let hidden = manager.settings.pip.hideWhenVisible && manager.isOnScreen(id)
        return ok(hidden ? "the picture shows while the window is out of sight\n" : "")
    }

    func close(_ id: WindowID) {
        guard let index = items.firstIndex(where: { $0.window == id }) else { return }
        let item = items.remove(at: index)
        item.capture.stop()
        item.panel.hide()
        if items.isEmpty {
            timer?.invalidate()
            timer = nil
        } else {
            update()
        }
    }

    private func drop(_ id: WindowID, at point: CGPoint) {
        guard let index = items.firstIndex(where: { $0.window == id }),
              let monitor = manager.monitors.first(where: { $0.frame.contains(point) }) ?? manager.focusedMonitor else { return }
        items[index].monitor = monitor.id
        items[index].corner = nearestCorner(to: point, in: monitor.workArea)
        update()
    }

    /// Closes the pictures of windows that are gone, and puts the others where they belong.
    private func update() {
        for item in items where manager.windows[item.window] == nil { close(item.window) }
        let settings = manager.settings.pip
        var stacks: [String: [Int]] = [:]
        for index in items.indices {
            guard let managed = manager.windows[items[index].window] else { continue }
            // A parked window keeps its size, so the shape follows a resize wherever the window is.
            items[index].shape = managed.info.frame.size
            if settings.hideWhenVisible, manager.isOnScreen(items[index].window) {
                items[index].panel.hide()
                continue
            }
            if !manager.monitors.contains(where: { $0.id == items[index].monitor }) { items[index].monitor = manager.focusedMonitorID }
            stacks["\(items[index].monitor) \(items[index].corner.rawValue)", default: []].append(index)
        }
        for indices in stacks.values {
            guard let first = indices.first, let monitor = manager.monitors.first(where: { $0.id == items[first].monitor }) else { continue }
            let frames = pipFrames(indices.map { items[$0].shape }, corner: items[first].corner, widthFraction: settings.size, in: monitor.workArea)
            for (index, frame) in zip(indices, frames) {
                items[index].panel.show(at: frame)
                resize(index, to: frame.size, fps: settings.fps)
            }
        }
        // A picture that has not been on screen yet still needs a size to start with.
        for index in items.indices where items[index].pixels == .zero {
            guard let monitor = manager.monitors.first(where: { $0.id == items[index].monitor }) else { continue }
            let frame = pipFrames([items[index].shape], corner: items[index].corner, widthFraction: settings.size, in: monitor.workArea)[0]
            resize(index, to: frame.size, fps: settings.fps)
        }
    }

    private func resize(_ index: Int, to size: CGSize, fps: Int) {
        let scale = items[index].panel.scale
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixels != items[index].pixels else { return }
        items[index].pixels = pixels
        items[index].capture.resize(pixels: pixels, fps: fps)
    }
}
