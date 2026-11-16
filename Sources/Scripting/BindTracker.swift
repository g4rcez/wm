import Foundation

/// What the binds say about one chord right now (the current mode and the universal binds together).
public struct BindLookup: Sendable, Equatable {
    public var press: BindAction?
    public var release: BindAction?
    public var longPress: BindAction?
    /// The press bind does not repeat while the key is held.
    public var noRepeat: Bool

    public init(press: BindAction? = nil, release: BindAction? = nil, longPress: BindAction? = nil, noRepeat: Bool = false) {
        self.press = press
        self.release = release
        self.longPress = longPress
        self.noRepeat = noRepeat
    }

    public var isEmpty: Bool { press == nil && release == nil && longPress == nil }
}

/// The rules for the triggers of a bind, apart from the event tap, so they can be tested.
///
/// - A press bind runs when the key goes down, and again for each repeat of the held key, unless it does not repeat.
/// - A release bind runs when the key comes up.
/// - A long-press bind runs when the key has been held for the timeout. A chord that has one waits: its press bind runs
///   when the key comes up before the timeout (a short press), and not when the long press fires.
/// - A key whose down event was used is also used when it comes up, so apps do not see half a key press.
public struct BindTracker: Sendable {
    public enum Effect: Sendable, Equatable {
        case run(BindAction)
        case startLongPress(keyCode: Int)
        case cancelLongPress(keyCode: Int)
    }

    private struct Held {
        var lookup: BindLookup
        var longPressFired = false
    }

    private var held: [Int: Held] = [:]

    public init() {}

    /// `swallow` says whether the key event is used up.
    public mutating func keyDown(keyCode: Int, isRepeat: Bool, lookup: BindLookup) -> (swallow: Bool, effects: [Effect]) {
        guard !lookup.isEmpty else { return (false, []) }
        if isRepeat, held[keyCode] != nil {
            // The key is held. Only a plain press bind runs again (unless it does not repeat).
            guard lookup.longPress == nil, !lookup.noRepeat, let press = lookup.press else { return (true, []) }
            return (true, [.run(press)])
        }
        let needsKeyUp = lookup.release != nil || lookup.longPress != nil
        if needsKeyUp { held[keyCode] = Held(lookup: lookup) }
        if lookup.longPress != nil { return (true, [.startLongPress(keyCode: keyCode)]) }
        if isRepeat, lookup.noRepeat { return (true, []) }
        return (true, lookup.press.map { [.run($0)] } ?? [])
    }

    public mutating func keyUp(keyCode: Int) -> (swallow: Bool, effects: [Effect]) {
        guard let state = held.removeValue(forKey: keyCode) else { return (false, []) }
        var effects: [Effect] = []
        if state.lookup.longPress != nil {
            effects.append(.cancelLongPress(keyCode: keyCode))
            if !state.longPressFired, let press = state.lookup.press { effects.append(.run(press)) }
        }
        if let release = state.lookup.release { effects.append(.run(release)) }
        return (true, effects)
    }

    /// The timer of `startLongPress` ran out while the key is still down.
    public mutating func longPressElapsed(keyCode: Int) -> [Effect] {
        guard var state = held[keyCode], !state.longPressFired, let action = state.lookup.longPress else { return [] }
        state.longPressFired = true
        held[keyCode] = state
        return [.run(action)]
    }
}
