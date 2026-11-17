import AppKit
import Core
import Platform
import Scripting

/// Turns key presses, scrolls and pointer moves into commands.
@MainActor
final class InputRouter {
    let tap = EventTap()
    var binds: [String: [Chord: BindAction]] = [:]
    /// Key sequences such as `ctrl-p>h`, per mode (two or more steps).
    var sequences: [String: [[Chord]: BindAction]] = [:]
    /// Binds that run when the key comes up or when it is held, and the press binds that do not repeat, per mode. The
    /// mode `*` (`universalMode`) holds the binds that work in every mode.
    var releaseBinds: [String: [Chord: BindAction]] = [:]
    var longPressBinds: [String: [Chord: BindAction]] = [:]
    /// Binds that run for each repeat of a held key (`repeating = true`).
    var holdBinds: [String: [Chord: BindAction]] = [:]
    var noRepeat: [String: Set<Chord>] = [:]
    /// Swipes with a modifier (`wm.gesture`).
    var gestures: [Gesture] = []
    private var gestureTracker = GestureTracker()
    private var tracker = BindTracker()
    private var longPressTimers: [Int: Timer] = [:]
    /// Called with the steps pressed so far while a sequence waits for its next key (`ctrl-p`), and with `nil` when it ends.
    var onPending: (([Chord]?) -> Void)?
    /// The steps pressed so far of a sequence that is waiting for its next key.
    private var pending: [Chord] = []
    private var pendingMode = "main"
    /// Set by the app: the switcher takes over the keys while it is open.
    var switcher: SwitcherController?
    /// Key codes of remaps that a panel used up, until their key comes up.
    private var overlayHeld: Set<Int> = []
    /// While the palette is open its text field gets every key, so no bind runs; remaps still do, and the panel gets their target
    /// (`hyper-j` → `down`). The `--cmdtab` palette takes Tab and the arrow keys itself, so that macOS does not see its Cmd+Tab.
    var palette: PaletteController?
    /// Set by the app: the template picker takes over the keys while it is open.
    var picker: TemplatePicker?
    /// The modifiers of the key press being handled (empty outside a key press), for commands that depend on them.
    private(set) var currentFlags: CGEventFlags = []
    /// CapsLock as the hyper key (`binds.capslock = "hyper"`): `hyperDown` while it is held. A tap that no other key used is Esc.
    private var hyperDown = false
    private var hyperUsed = false
    private var hyperDownAt = Date.distantPast
    private var hyperEnabled: Bool { manager.settings.binds.capsLockHyper }
    private let manager: WindowManager
    private let run: (_ command: String) -> Void
    private let call: (_ function: Int) -> Void

    init(manager: WindowManager, run: @escaping (String) -> Void, call: @escaping (Int) -> Void) {
        self.manager = manager
        self.run = run
        self.call = call
    }

    /// Returns `false` while Accessibility permission is missing.
    func start() -> Bool {
        tap.onKey = { [unowned self] code, flags, isRepeat in handleKey(code, flags, isRepeat: isRepeat) }
        tap.onKeyUp = { [unowned self] code, flags in
            if hyperEnabled, code == KeyboardRemap.hyperKeyCode { return hyperKeyUp() }
            // A remap that a panel used up: the app never saw the key down, so it does not see the key up.
            if overlayHeld.remove(code) != nil { return true }
            let outcome = tracker.keyUp(keyCode: code)
            apply(outcome.effects, flags: flags)
            return outcome.swallow
        }
        tap.onScroll = { [unowned self] dx, dy, flags, phase in handleScroll(dx, dy, flags, phase) }
        tap.onPointer = { [unowned self] location in manager.pointerMoved(to: location) }
        tap.onFlags = { [unowned self] flags in
            switcher?.flagsChanged(flags)
            palette?.flagsChanged(flags)
        }
        // The key ups of the hyper key are lost while the tap is off, and a hyper key that stays down would eat every key.
        tap.onReenabled = { [unowned self] in
            hyperDown = false
            overlayHeld = []
        }
        tap.onButton = { [unowned self] isDown in manager.mouseButton(isDown: isDown) }
        tap.onMouse = { [unowned self] event in
            if event.kind == .down { switcher?.pointerPressed(at: event.location) }
            return manager.handleMouse(event)
        }
        return tap.start()
    }

    private func handleKey(_ code: Int, _ flags: CGEventFlags, isRepeat: Bool) -> Bool {
        if hyperEnabled, code == KeyboardRemap.hyperKeyCode { return hyperKeyDown(isRepeat: isRepeat) }
        guard let key = KeyCodes.name(for: code) else { return false }
        if hyperDown { hyperUsed = true }
        var modifiers = Self.modifiers(of: flags)
        if hyperDown { modifiers.insert(.hyper) }
        let chord = Chord(modifiers: modifiers, key: key)
        let mode = manager.mode

        // A remap comes first: the key is its target everywhere, in the panels of wm too. A panel that is open gets the target.
        if pending.isEmpty, let (remap, target) = remap(for: chord, mode: mode) {
            if overlayKey(target.key, flags: KeyOutput.flags(of: target.modifiers)) == true {
                overlayHeld.insert(code)
                return true
            }
            let outcome = tracker.keyDown(keyCode: code, isRepeat: isRepeat, lookup: remap)
            apply(outcome.effects, flags: flags)
            return outcome.swallow
        }
        // The panels take every other key. A hyper chord is not text, so the keys are not typed.
        if let handled = overlayKey(key, flags: flags) { return handled || chord.modifiers.contains(.hyper) }

        if !pending.isEmpty {
            // A key held down after the prefix must not count as the second key.
            if isRepeat { return true }
            return continueSequence(with: chord, flags: flags)
        }
        let lookup = lookup(for: chord, mode: mode)
        if !lookup.isEmpty {
            let outcome = tracker.keyDown(keyCode: code, isRepeat: isRepeat, lookup: lookup)
            apply(outcome.effects, flags: flags)
            return outcome.swallow
        }
        if hasSequence(in: mode, startingWith: [chord]) {
            beginSequence(chord, mode: mode)
            return true
        }
        // A hyper chord that nothing uses is not typed: the keys are not for the app.
        return chord.modifiers.contains(.hyper)
    }

    /// The open panel (palette, switcher, template picker) takes the key. `nil` when no panel is open.
    private func overlayKey(_ key: String, flags: CGEventFlags) -> Bool? {
        if let palette, palette.isOpen { return palette.handleKey(key, flags: flags) }
        if let switcher, switcher.isOpen { return switcher.handleKey(key, flags: flags) }
        if let picker, picker.isOpen { return picker.handleKey(key) }
        return nil
    }

    /// The remap that a chord fires, with the key lookup to run it. An exact bind of the chord wins, and so does a sequence
    /// that starts with it; then the remap with fewer modifiers than the chord (`remapLookup`).
    private func remap(for chord: Chord, mode: String) -> (lookup: BindLookup, target: Chord)? {
        let exact = lookup(for: chord, mode: mode)
        if !exact.isEmpty {
            guard case .remap(let target)? = exact.press, exact.release == nil, exact.longPress == nil, exact.hold == nil else { return nil }
            return (exact, target)
        }
        guard !hasSequence(in: mode, startingWith: [chord]), let loose = remapLookup(for: chord, mode: mode),
              case .remap(let target)? = loose.press else { return nil }
        return (loose, target)
    }

    private func hyperKeyDown(isRepeat: Bool) -> Bool {
        if !isRepeat, !hyperDown {
            hyperDown = true
            hyperUsed = false
            hyperDownAt = Date()
        }
        return true
    }

    /// A hyper key that was pressed and released alone, and quickly, is Esc. The router gets the Esc first, so that it closes
    /// what Esc closes (the keys of a prefix, the palette, a mode with `esc = "mode main"`); only an Esc that the router does
    /// not use goes on to the app. A key that wm types carries its own tag and never comes back to this tap.
    private func hyperKeyUp() -> Bool {
        guard hyperDown else { return true }
        hyperDown = false
        guard !hyperUsed, Date().timeIntervalSince(hyperDownAt) < manager.settings.binds.longPressTimeout,
              let code = KeyCodes.code(for: "esc") else { return true }
        if !handleKey(code, [], isRepeat: false) { KeyOutput.tap(Chord(modifiers: [], key: "esc")) }
        // A bind of Esc that waits for the key up (`release`, `long_press`) has its key up now.
        apply(tracker.keyUp(keyCode: code).effects, flags: [])
        return true
    }

    /// A remap that holds for a chord with more modifiers than it names: `hyper-h` → `left` also takes `hyper-shift-h`, and
    /// types `shift-left`. The remap with the most modifiers wins.
    private func remapLookup(for chord: Chord, mode: String) -> BindLookup? {
        guard !chord.modifiers.isEmpty else { return nil }
        var best: (source: Chord, target: Chord)?
        for name in [mode, universalMode] {
            for (source, action) in binds[name] ?? [:] {
                guard case let .remap(target) = action, source.key == chord.key, chord.modifiers.isSuperset(of: source.modifiers) else { continue }
                if let current = best {
                    let (count, currentCount) = (source.modifiers.rawValue.nonzeroBitCount, current.source.modifiers.rawValue.nonzeroBitCount)
                    guard count > currentCount || (count == currentCount && source.description < current.source.description) else { continue }
                }
                best = (source, target)
            }
        }
        guard let (source, target) = best else { return nil }
        let extra = chord.modifiers.subtracting(source.modifiers).subtracting(.hyper)
        return BindLookup(press: .remap(Chord(modifiers: target.modifiers.union(extra), key: target.key)))
    }

    /// What the binds of `mode` and the universal binds say about a chord.
    private func lookup(for chord: Chord, mode: String) -> BindLookup {
        BindLookup(
            press: binds[mode]?[chord] ?? binds[universalMode]?[chord],
            release: releaseBinds[mode]?[chord] ?? releaseBinds[universalMode]?[chord],
            longPress: longPressBinds[mode]?[chord] ?? longPressBinds[universalMode]?[chord],
            hold: holdBinds[mode]?[chord] ?? holdBinds[universalMode]?[chord],
            noRepeat: (noRepeat[mode]?.contains(chord) ?? false) || (noRepeat[universalMode]?.contains(chord) ?? false))
    }

    private func apply(_ effects: [BindTracker.Effect], flags: CGEventFlags) {
        for effect in effects {
            switch effect {
            case .run(let action):
                perform(action, flags: flags)
            case .startLongPress(let code):
                longPressTimers[code]?.invalidate()
                longPressTimers[code] = Timer.scheduledTimer(withTimeInterval: manager.settings.binds.longPressTimeout, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.longPressTimers[code] = nil
                        self.apply(self.tracker.longPressElapsed(keyCode: code), flags: EventTap.currentFlags())
                    }
                }
            case .cancelLongPress(let code):
                longPressTimers.removeValue(forKey: code)?.invalidate()
            case .remapDown(let chord, let isRepeat):
                KeyOutput.post(chord, down: true, isRepeat: isRepeat)
            case .remapUp(let chord):
                KeyOutput.post(chord, down: false)
            }
        }
    }

    private static func modifiers(of flags: CGEventFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers
    }

    private func perform(_ action: BindAction, flags: CGEventFlags) {
        currentFlags = flags
        defer { currentFlags = [] }
        switch action {
        case let .command(command): run(command)
        case let .function(id): call(id)
        case let .remap(chord): KeyOutput.tap(chord)
        }
    }

    // MARK: Trackpad swipes with 3 or 4 fingers

    /// A swipe moves the strip by this many points per width of the pad (times `trackpad.speed`).
    private static let pointsPerPad = 1500.0

    private var fingerGestures = GestureTracker()
    private var swipeFingers: Int?
    /// A `wm.gesture` took the swipe: the strip does not scroll.
    private var swipeClaimed = false

    /// The events of `FingerTracker`. A gesture for the number of fingers claims the swipe on its axis; the rest of the
    /// swipes scroll the strip when their number is `trackpad.scroll_fingers`, with momentum at the end.
    func handleFinger(_ events: [FingerTracker.Event]) {
        let settings = manager.settings.trackpad
        let modifiers = Self.modifiers(of: EventTap.currentFlags())
        let time = ProcessInfo.processInfo.systemUptime
        for event in events {
            switch event {
            case .began(let fingers):
                swipeFingers = fingers
                swipeClaimed = false
                _ = fingerGestures.scroll(dx: 0, dy: 0, modifiers: modifiers, phase: .began, time: time, gestures: gestures, fingers: fingers)
            case .moved(let dx, let dy):
                guard let fingers = swipeFingers else { continue }
                let x = dx * Self.pointsPerPad * settings.speed, y = dy * Self.pointsPerPad * settings.speed
                switch fingerGestures.scroll(dx: x, dy: y, modifiers: modifiers, phase: .changed, time: time, gestures: gestures, fingers: fingers) {
                case .consumed: swipeClaimed = true
                case .fire(let action):
                    swipeClaimed = true
                    perform(action, flags: EventTap.currentFlags())
                case .ignored:
                    if !swipeClaimed, fingers == settings.scrollFingers, manager.focusedWorkspace?.kind == .scrolling {
                        scrollStrip(x, y)
                    }
                }
            case .ended(let vx, let vy):
                defer { swipeFingers = nil }
                guard let fingers = swipeFingers, !swipeClaimed, fingers == settings.scrollFingers,
                      manager.focusedWorkspace?.kind == .scrolling else { continue }
                // The swipe goes on a little after the fingers lift, then the strip settles on a column.
                scrollStrip(vx * Self.pointsPerPad * settings.speed * 0.12, vy * Self.pointsPerPad * settings.speed * 0.12)
                manager.settleScroll()
            }
        }
    }

    private func scrollStrip(_ x: Double, _ y: Double) {
        let delta = manager.focusedStrip == .vertical ? y : x
        if delta != 0 { manager.scrollBy(-delta) }
    }

    // MARK: Key sequences

    private func hasSequence(in mode: String, startingWith steps: [Chord]) -> Bool {
        [mode, universalMode].contains { name in
            sequences[name]?.keys.contains { $0.count > steps.count && $0.starts(with: steps) } ?? false
        }
    }

    private func beginSequence(_ first: Chord, mode: String) {
        pending = [first]
        pendingMode = mode
        updatePending()
    }

    /// The next key of a sequence. A key that continues no sequence ends it and is eaten, as in tmux; Escape cancels. A sequence waits without a timeout.
    private func continueSequence(with chord: Chord, flags: CGEventFlags) -> Bool {
        if chord.key == "esc", chord.modifiers.subtracting(.hyper).isEmpty {
            cancelSequence()
            return true
        }
        // The hyper key may still be down for the next step: `hyper-w>1` takes `hyper-1` as well as `1`.
        var candidates = [chord]
        if chord.modifiers.contains(.hyper) { candidates.append(Chord(modifiers: chord.modifiers.subtracting(.hyper), key: chord.key)) }
        for candidate in candidates {
            let steps = pending + [candidate]
            if let action = sequences[pendingMode]?[steps] ?? sequences[universalMode]?[steps] {
                cancelSequence()
                perform(action, flags: flags)
                return true
            }
            if hasSequence(in: pendingMode, startingWith: steps) {
                pending = steps
                updatePending()
                return true
            }
        }
        if chord.isScreenshotShortcut {
            // A screenshot of the key hints: macOS takes the keys, and the hints and the prefix stay as they are.
            return false
        }
        cancelSequence()
        return true
    }

    func cancelSequence() {
        guard !pending.isEmpty else { return }
        pending = []
        onPending?(nil)
    }

    private func updatePending() {
        onPending?(pending)
    }

    /// Option + two-finger swipe scrolls a scrolling workspace; the strip settles on a column when the fingers lift.
    /// The focused window's strip decides the axis: sideways swipes move a strip that runs sideways, up and down swipes a
    /// strip that runs down the screen.
    private func handleScroll(_ dx: CGFloat, _ dy: CGFloat, _ flags: CGEventFlags, _ phase: ScrollPhase) -> Bool {
        // A swipe that a gesture claims is the gesture's. The rest goes on to the scrolling of the strip.
        if !gestures.isEmpty {
            let gesturePhase: GesturePhase = switch phase {
            case .began: .began
            case .changed: .changed
            case .ended: .ended
            case .none: .none
            }
            switch gestureTracker.scroll(
                dx: Double(dx), dy: Double(dy), modifiers: Self.modifiers(of: flags), phase: gesturePhase,
                time: ProcessInfo.processInfo.systemUptime, gestures: gestures
            ) {
            case .consumed: return true
            case .fire(let action):
                perform(action, flags: flags)
                return true
            case .ignored: break
            }
        }
        guard flags.contains(.maskAlternate), manager.focusedWorkspace?.kind == .scrolling else { return false }
        if phase == .ended {
            manager.settleScroll()
        } else {
            let delta = manager.focusedStrip == .vertical ? dy : dx
            if delta != 0 { manager.scrollBy(-delta) }
        }
        return true
    }
}

extension WindowManager {
    /// The screen axis along which the strip of the focused window scrolls: sideways on a normal screen, up and down for a
    /// strip that runs down a portrait monitor, and the other way round for the side strip.
    var focusedStrip: Orientation? {
        guard let id = focused, let workspace = focusedWorkspace, let scrolling = workspace.engine as? ScrollingEngine else { return nil }
        return scrolling.screenAxis(of: id, in: layoutContext(forWorkspace: workspace.name))
    }

    func pointerMoved(to location: CGPoint) {
        guard settings.focusFollowsMouse.enabled, let id = window(at: location), id != focused else { return }
        if settings.focusFollowsMouse.onlyFullyVisible, !isFullyOnScreen(id) { return }
        focus(id, warpMouse: false)
    }

    /// Whether the window lies inside the work area of the monitor that shows its workspace (1 point of slack).
    private func isFullyOnScreen(_ id: WindowID) -> Bool {
        guard let managed = windows[id], let monitor = monitor(showing: managed.workspace), let frame = currentFrame(of: id) else { return false }
        return monitor.workArea.insetBy(dx: -1, dy: -1).contains(frame)
    }

    func scrollBy(_ delta: CGFloat) {
        guard let workspace = focusedWorkspace, let id = focused ?? workspace.engine.windows.first else { return }
        let context = layoutContext(forWorkspace: workspace.name)
        _ = workspace.engine.perform(.scroll(delta), focused: id, in: context)
        relayout(snapAll: true)
    }

    func settleScroll() {
        guard let workspace = focusedWorkspace, var engine = workspace.engine as? ScrollingEngine else { return }
        let context = layoutContext(forWorkspace: workspace.name)
        let target = engine.settle(in: context)
        workspace.engine = engine
        if let target { focus(target) } else { relayout() }
    }
}
