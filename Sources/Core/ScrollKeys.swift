import CoreGraphics

/// What a key does in scroll mode. A positive `dy` scrolls down and a positive `dx` scrolls right.
public enum ScrollAction: Sendable, Equatable {
    /// The key is not a scroll key; the caller decides what it does.
    case ignored
    /// The key is used up and waits for the next one: the first `g` of `gg`.
    case pending
    case by(dx: Double, dy: Double)
    /// `1` is half a page down, `-1` half a page up.
    case halfPage(Int)
    case top
    case bottom
    case nextArea
    case previousArea
    case area(Int)
    case exit
}

/// The vim keys of scroll mode.
public struct ScrollKeys: Sendable, Equatable {
    /// How far `h j k l` scroll, in points. Shift multiplies it by `dashFactor`.
    public static let step = 60.0
    public static let dashFactor = 5.0

    private var pendingG = false

    public init() {}

    public mutating func press(_ key: String, shift: Bool = false, control: Bool = false) -> ScrollAction {
        let wasPending = pendingG
        pendingG = false
        let distance = shift ? Self.step * Self.dashFactor : Self.step
        switch key {
        case "h" where !control: return .by(dx: -distance, dy: 0)
        case "l" where !control: return .by(dx: distance, dy: 0)
        case "j" where !control: return .by(dx: 0, dy: distance)
        case "k" where !control: return .by(dx: 0, dy: -distance)
        case "d" where !control: return .halfPage(1)
        case "u" where !control: return .halfPage(-1)
        case "g" where !control:
            if shift { return .bottom }
            if wasPending { return .top }
            pendingG = true
            return .pending
        case "tab": return shift ? .previousArea : .nextArea
        case "down": return .nextArea
        case "up": return .previousArea
        case "n" where control: return .nextArea
        case "p" where control: return .previousArea
        case "esc": return .exit
        default:
            if !control, !shift, key.count == 1, let digit = Int(key) { return .area(digit) }
            return .ignored
        }
    }
}

/// The scroll areas of a window, without duplicates, numbered in reading order. At most ten, so a digit key reaches each one.
public struct ScrollAreas: Sendable, Equatable {
    public static let limit = 10

    public let frames: [CGRect]
    public private(set) var active: Int

    /// The largest area is active first. With no area, `fallback` (the window) is the only one.
    public init(frames: [CGRect], fallback: CGRect) {
        var distinct: [CGRect] = []
        for frame in frames.sorted(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) where !distinct.contains(where: { $0.isSameFrame(as: frame) }) {
            distinct.append(frame)
        }
        self.frames = distinct.isEmpty ? [fallback] : Array(distinct.prefix(Self.limit))
        let areas = self.frames.map { $0.width * $0.height }
        active = areas.firstIndex(of: areas.max() ?? 0) ?? 0
    }

    public var current: CGRect { frames[active] }

    /// Goes to the area of this number. A number with no area changes nothing.
    public mutating func select(_ index: Int) {
        if frames.indices.contains(index) { active = index }
    }

    /// Goes to the next (`1`) or the previous (`-1`) area, and wraps at the ends.
    public mutating func step(_ direction: Int) {
        active = (active + direction + frames.count) % frames.count
    }
}
