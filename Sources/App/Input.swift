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
    private var pendingTimer: Timer?
    /// Set by the app: the switcher takes over the keys while it is open.
    var switcher: SwitcherController?
    /// Set by the app: the template picker takes over the keys while it is open.
    var picker: TemplatePicker?
    /// The modifiers of the key press being handled (empty outside a key press), for commands that depend on them.
    private(set) var currentFlags: CGEventFlags = []
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
            let outcome = tracker.keyUp(keyCode: code)
            apply(outcome.effects, flags: flags)
            return outcome.swallow
        }
        tap.onScroll = { [unowned self] dx, dy, flags, phase in handleScroll(dx, dy, flags, phase) }
        tap.onPointer = { [unowned self] location in manager.pointerMoved(to: location) }
        tap.onFlags = { [unowned self] flags in switcher?.flagsChanged(flags) }
        tap.onButton = { [unowned self] isDown in manager.mouseButton(isDown: isDown) }
        return tap.start()
    }

    private func handleKey(_ code: Int, _ flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard let key = KeyCodes.name(for: code) else { return false }
        if let switcher, switcher.isOpen { return switcher.handleKey(key, flags: flags) }
        if let picker, picker.isOpen { return picker.handleKey(key) }
        let chord = Chord(modifiers: Self.modifiers(of: flags), key: key)

        if !pending.isEmpty {
            // A key held down after the prefix must not count as the second key.
            if isRepeat { return true }
            return continueSequence(with: chord, flags: flags)
        }
        let mode = manager.mode
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
        return false
    }

    /// What the binds of `mode` and the universal binds say about a chord.
    private func lookup(for chord: Chord, mode: String) -> BindLookup {
        BindLookup(
            press: binds[mode]?[chord] ?? binds[universalMode]?[chord],
            release: releaseBinds[mode]?[chord] ?? releaseBinds[universalMode]?[chord],
            longPress: longPressBinds[mode]?[chord] ?? longPressBinds[universalMode]?[chord],
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
        }
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

    /// The next key of a sequence. A key that continues no sequence ends it and is eaten, as in tmux; Escape cancels.
    private func continueSequence(with chord: Chord, flags: CGEventFlags) -> Bool {
        if chord.key == "esc", chord.modifiers.isEmpty {
            cancelSequence()
            return true
        }
        let steps = pending + [chord]
        if let action = sequences[pendingMode]?[steps] ?? sequences[universalMode]?[steps] {
            cancelSequence()
            perform(action, flags: flags)
        } else if hasSequence(in: pendingMode, startingWith: steps) {
            pending = steps
            updatePending()
        } else {
            cancelSequence()
        }
        return true
    }

    func cancelSequence() {
        pendingTimer?.invalidate()
        pendingTimer = nil
        guard !pending.isEmpty else { return }
        pending = []
        onPending?(nil)
    }

    private func updatePending() {
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: manager.settings.prefix.timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelSequence() }
        }
        onPending?(pending)
    }

    /// Option + two-finger swipe scrolls a scrolling workspace; the strip settles on a column when the fingers lift.
    /// The focused window's strip decides the axis: sideways swipes move the horizontal strip, up and down swipes the
    /// vertical strip.
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
    /// The strip of the focused window on a scrolling workspace.
    var focusedStrip: Orientation? {
        guard let id = focused, let workspace = focusedWorkspace, let scrolling = workspace.engine as? ScrollingEngine else { return nil }
        return scrolling.strip(of: id)
    }

    func pointerMoved(to location: CGPoint) {
        guard settings.focusFollowsMouse, let id = window(at: location), id != focused else { return }
        focus(id, warpMouse: false)
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
