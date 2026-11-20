import Foundation

/// Tells when the dynamic rules of a window start or stop applying. A dynamic rule is looked at again when the title of a
/// window changes, so a window can start to match (a browser tab that becomes a picture-in-picture window) or stop matching.
/// Only a change is reported, so a rule never runs twice for a state that it has already put the window in.
///
/// `matching` is the indices of the dynamic rules that match the window now, in rule order; the same list means no change.
public struct DynamicRuleTracker: Sendable {
    public enum Change: Equatable, Sendable {
        /// The same rules match as before.
        case none
        /// The window matches other rules than before (or matches for the first time).
        case applied
        /// The window matched and does not match any rule now.
        case reverted
    }

    /// A window that changes this many times in `window` seconds is left alone until it calms down, so two rules that undo each
    /// other cannot make the window flicker for ever.
    public static let maxChanges = 4
    public static let window: TimeInterval = 1

    private var matched: [WindowID: [Int]] = [:]
    private var changes: [WindowID: [TimeInterval]] = [:]

    public init() {}

    /// The rules that matched `window` at the last change, or none.
    public func matching(_ window: WindowID) -> [Int] { matched[window] ?? [] }

    public mutating func update(window: WindowID, matching indices: [Int], now: TimeInterval) -> Change {
        let before = matched[window] ?? []
        guard indices != before else { return .none }
        let recent = (changes[window] ?? []).filter { now - $0 < Self.window }
        guard recent.count < Self.maxChanges else {
            changes[window] = recent
            return .none
        }
        changes[window] = recent + [now]
        matched[window] = indices.isEmpty ? nil : indices
        return indices.isEmpty ? .reverted : .applied
    }

    public mutating func forget(_ window: WindowID) {
        matched[window] = nil
        changes[window] = nil
    }
}
