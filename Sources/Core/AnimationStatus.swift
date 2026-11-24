import Foundation

/// One kind of animation and whether it runs now, for `wm animations`.
public struct AnimationStatus: Sendable, Equatable {
    public let name: String
    public let enabled: Bool
    public let detail: String

    public static let kinds = ["windows", "workspaces", "special", "overlays"]
}

extension Settings {
    /// What the overlays draw with: the look of `appearance`, and the fade of `animations.overlays`. The fade is 0 (none) when the
    /// master switch or the overlays are off; else `animations.overlays.duration`, else `appearance.animation`, else 0.12.
    public func overlayStyle() -> ResolvedStyle {
        var style = appearance.resolved()
        style.animation = overlayDuration
        return style
    }

    public var overlayDuration: Double {
        guard animations.enabled, animations.overlays.enabled else { return 0 }
        return animations.overlays.duration ?? appearance.animation ?? 0.12
    }

    /// The four kinds of animation and their state, in the order of `AnimationStatus.kinds`.
    public func animationStatus() -> [AnimationStatus] {
        let all = animations
        func seconds(_ value: Double) -> String { String(format: "%g", value) + " s" }
        func spring(_ kind: AnimationKind) -> String { "rate " + String(format: "%g", kind.rate ?? all.rate) }
        func slide(_ kind: AnimationKind) -> AnimationStatus {
            AnimationStatus(
                name: "", enabled: all.enabled && kind.enabled && kind.style != .none,
                detail: kind.style == .none ? "style none (the windows jump)" : "style \(kind.style.rawValue), \(spring(kind))")
        }
        func named(_ name: String, _ status: AnimationStatus) -> AnimationStatus {
            AnimationStatus(name: name, enabled: status.enabled, detail: status.detail)
        }
        return [
            AnimationStatus(
                name: "windows", enabled: all.enabled && all.windows.enabled,
                detail: "\(spring(all.windows)), \(String(format: "%g", all.fps)) fps"),
            named("workspaces", slide(all.workspaces)),
            named("special", slide(all.special)),
            AnimationStatus(
                name: "overlays", enabled: overlayDuration > 0,
                detail: overlayDuration > 0 ? seconds(overlayDuration) : "no fade"),
        ]
    }
}
