import CoreGraphics

/// Short key labels for the windows of the overview: type a label to focus that window.
/// All labels have the same length, so no label is the start of another one.
public struct WindowHints: Sendable, Equatable {
    /// `h j k l` are left out because they move the selection. The home row comes first.
    public static let alphabet = Array("asdfgqwertyuiopzxcvbnm")

    public let labels: [WindowID: String]
    /// The keys pressed so far for a label of more than one letter.
    public private(set) var typed = ""

    public enum Result: Sendable, Equatable {
        /// The key is not a label key; the caller decides what it does.
        case ignored
        /// The key is used up, and the label is not complete.
        case pending
        case focus(WindowID)
    }

    /// Labels go in reading order: top to bottom, then left to right.
    public init(frames: [WindowID: CGRect]) {
        let base = Self.alphabet.count
        var length = 1
        var capacity = base
        while capacity < frames.count {
            length += 1
            capacity *= base
        }
        let ordered = frames.sorted { ($0.value.minY, $0.value.minX, $0.key) < ($1.value.minY, $1.value.minX, $1.key) }
        var labels: [WindowID: String] = [:]
        for (index, entry) in ordered.enumerated() {
            var rest = index
            var label = ""
            for _ in 0..<length {
                label = String(Self.alphabet[rest % base]) + label
                rest /= base
            }
            labels[entry.key] = label
        }
        self.labels = labels
    }

    public mutating func press(_ key: String) -> Result {
        guard key.count == 1, Self.alphabet.contains(Character(key)) else { return .ignored }
        let next = typed + key
        if let match = labels.first(where: { $0.value == next }) {
            typed = ""
            return .focus(match.key)
        }
        // A key that continues no label starts over.
        typed = labels.values.contains { $0.hasPrefix(next) } ? next : ""
        return .pending
    }

    public mutating func deleteLast() {
        typed = String(typed.dropLast())
    }
}
