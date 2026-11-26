import CoreGraphics

/// The arguments of the commands that take numbers, parsed without a window manager so that they can be tested. A number is
/// finite: `Double("nan")` and `Double("inf")` are numbers to Swift, but no size, ratio or step can be one.
public enum CommandArguments {
    public static func number<S: StringProtocol>(_ text: S) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// `resize`: a dimension and a change, a side and a change, or `dir`, a direction and a positive amount.
    public enum Resize: Equatable, Sendable {
        case dimension(ResizeDimension, CGFloat)
        case side(Direction, CGFloat)
        case direction(Direction, CGFloat)
    }

    public static func resize(_ words: [String]) -> Result<Resize, UsageError> {
        if words.first == "dir" {
            guard words.count == 3, let direction = Direction(rawValue: words[1]), let points = number(words[2]), points > 0 else {
                return .failure(UsageError("resize dir needs a direction and a positive amount"))
            }
            return .success(.direction(direction, CGFloat(points)))
        }
        if words.count == 2, let side = Direction(rawValue: words[0]), let delta = number(words[1]) {
            return .success(.side(side, CGFloat(delta)))
        }
        guard words.count == 2, let dimension = ResizeDimension(rawValue: words[0]), let delta = number(words[1]) else {
            return .failure(UsageError("resize needs a dimension or a side, and an amount"))
        }
        return .success(.dimension(dimension, CGFloat(delta)))
    }

    /// `move <dir> [points]`: the points are positive, 40 when not given.
    public static func move(_ words: [String]) -> Result<(direction: Direction, step: CGFloat), UsageError> {
        guard let direction = words.first.flatMap(Direction.init(rawValue:)) else { return .failure(UsageError("move needs a direction")) }
        let wrong = UsageError("move takes a direction and an optional positive number of points")
        guard words.count <= 2 else { return .failure(wrong) }
        guard let text = words.dropFirst().first else { return .success((direction, 40)) }
        guard let points = number(text), points > 0 else { return .failure(wrong) }
        return .success((direction, CGFloat(points)))
    }

    /// A ratio: `+n` or `-n` changes it, a plain number sets it and has to be in `range`.
    public static func ratio(_ text: String?, in range: ClosedRange<Double>) -> (value: Double, relative: Bool)? {
        guard let text, let value = number(text) else { return nil }
        let relative = text.hasPrefix("+") || text.hasPrefix("-")
        guard relative || range.contains(value) else { return nil }
        return (value, relative)
    }

    /// A share of the screen, more than 0 and at most 1.
    public static func fraction(_ text: String?) -> Double? {
        guard let text, let value = number(text), value > 0, value <= 1 else { return nil }
        return value
    }
}

/// A command that was written wrong: the message says how to write it.
public struct UsageError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
