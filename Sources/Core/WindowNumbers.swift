import CoreGraphics

/// Numbers for the windows of `wm jump`: 1, 2, 3… left to right over the displays, then in reading order on each one.
/// Typing a number picks the window. With ten or more windows a number can be the start of another one (1 and 10): the
/// shorter one waits for more digits, and Return picks it.
public struct WindowNumbers: Sendable, Equatable {
    public let numbers: [WindowID: Int]
    /// The digits pressed so far.
    public private(set) var typed = ""

    public enum Result: Sendable, Equatable {
        /// The key is not a number key; the caller decides what it does.
        case ignored
        /// The key is used up, and the number is not complete.
        case pending
        case pick(WindowID)
    }

    /// `displays` are the frames of the displays, in any order. A window belongs to the display that holds its center.
    public init(frames: [WindowID: CGRect], displays: [CGRect]) {
        let columns = displays.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
        func column(_ frame: CGRect) -> Int {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return columns.firstIndex { $0.contains(center) } ?? columns.count
        }
        let ordered = frames.sorted {
            (column($0.value), $0.value.minY, $0.value.minX, $0.key) < (column($1.value), $1.value.minY, $1.value.minX, $1.key)
        }
        var numbers: [WindowID: Int] = [:]
        for (index, entry) in ordered.enumerated() { numbers[entry.key] = index + 1 }
        self.numbers = numbers
    }

    public func label(of id: WindowID) -> String? { numbers[id].map(String.init) }

    /// The windows whose number starts with the digits typed so far.
    public func matches(_ id: WindowID) -> Bool {
        typed.isEmpty || (numbers[id].map { String($0).hasPrefix(typed) } ?? false)
    }

    public mutating func press(_ key: String) -> Result {
        guard key.count == 1, Int(key) != nil else { return .ignored }
        let next = typed + key
        // A number never starts with 0.
        guard !next.hasPrefix("0") else { return .ignored }
        let labels = numbers.map { (id: $0.key, text: String($0.value)) }
        guard labels.contains(where: { $0.text.hasPrefix(next) }) else {
            // No window has this number: keep what was typed.
            return .pending
        }
        if let exact = labels.first(where: { $0.text == next }),
           !labels.contains(where: { $0.text != next && $0.text.hasPrefix(next) }) {
            typed = ""
            return .pick(exact.id)
        }
        typed = next
        return .pending
    }

    /// Return: picks the window of the digits typed so far, when there is one.
    public mutating func confirm() -> Result {
        guard let id = numbers.first(where: { String($0.value) == typed })?.key else { return .pending }
        typed = ""
        return .pick(id)
    }

    public mutating func deleteLast() {
        typed = String(typed.dropLast())
    }
}
