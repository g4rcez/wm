import CoreGraphics
import Foundation

/// A clickable element of the screen, as the Accessibility API reports it. `frame` is in screen coordinates, origin at the top left.
public struct HintElement: Sendable, Equatable {
    public var id: Int
    public var frame: CGRect
    public var role: String
    /// What the search looks at: title, description, value and help of the element.
    public var text: String

    public init(id: Int, frame: CGRect, role: String = "", text: String = "") {
        self.id = id
        self.frame = frame
        self.role = role
        self.text = text
    }
}

extension CGRect {
    /// Two frames this close are one target: a row and the button that fills it, a scroll area and its web view.
    public func isSameFrame(as other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

/// The state of the hint mode, which works like the flash plugin of Neovim.
///
/// Every element has a label of two letters, and typing the label picks the element. `/` starts a search, as in fzf: the text
/// is words separated by spaces, in any order, and each word matches when its letters are in the text of the element in that
/// order, with other letters between them (`sv as` finds "Save As"). Only the elements that match keep their labels. A letter
/// that could continue the last word in some match is never the first letter of a label, so a key is a label key or a search
/// key, never both. When the letters left for labels are too few for all the matches, the first matches get a label.
public struct ElementSearch: Sendable, Equatable {
    /// The home row comes first.
    public static let alphabet = Array("asdfghjklqwertyuiopzxcvbnm")
    public enum Outcome: Sendable, Equatable {
        /// The key does nothing here; the caller decides.
        case ignored
        /// The state changed: draw again.
        case updated
        /// A label is complete.
        case picked(HintElement)
    }

    /// Every element, without duplicates, in reading order.
    public let elements: [HintElement]
    public private(set) var searching = false
    public private(set) var query = ""
    public private(set) var matches: [HintElement]
    /// The labels of the matches. None while the last word of a search is empty: its first letter is not a label then.
    public private(set) var labels: [Int: String] = [:]
    /// The letters of a label that are typed so far.
    public private(set) var typed = ""
    public private(set) var focused: Int?
    /// The wait mode: every element keeps its label, and the text picks the target by label or by title.
    public let keepsLabels: Bool
    /// The letters of the labels, in the order that they are used (`hints.letters`).
    public let letters: [Character]

    public init(elements: [HintElement], keepsLabels: Bool = false, letters: [Character] = ElementSearch.alphabet) {
        self.keepsLabels = keepsLabels
        self.letters = letters
        let ordered = Self.deduplicated(elements).sorted { ($0.frame.minY, $0.frame.minX, $0.id) < ($1.frame.minY, $1.frame.minX, $1.id) }
        self.elements = ordered
        matches = ordered
        labels = Self.labels(for: ordered, avoiding: [], letters: letters)
    }

    /// The elements without the ones that sit on the frame of an element that is already kept. The first one stays.
    public static func deduplicated(_ elements: [HintElement]) -> [HintElement] {
        var kept: [HintElement] = []
        for element in elements where !kept.contains(where: { $0.frame.isSameFrame(as: element.frame) }) {
            kept.append(element)
        }
        return kept
    }

    /// The label of an element that matches.
    public func label(of id: Int) -> String? { labels[id] }

    /// The element that a click goes to: the focused one, or the only match.
    public var target: HintElement? {
        if let focused, let match = matches.first(where: { $0.id == focused }) { return match }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Starts a search: the labels go away until the first letter of the text.
    public mutating func beginSearch() {
        guard !searching else { return }
        searching = true
        refresh()
    }

    /// A character that the user typed: a letter, a digit or a sign.
    public mutating func press(_ character: String) -> Outcome {
        if keepsLabels {
            if character == " ", query.isEmpty || query.hasSuffix(" ") { return .ignored }
            query += character
            refresh()
            return .updated
        }
        let next = typed + character
        if let id = labels.first(where: { $0.value == next })?.key, let element = matches.first(where: { $0.id == id }) {
            typed = ""
            return .picked(element)
        }
        if labels.values.contains(where: { $0.hasPrefix(next) }) {
            typed = next
            return .updated
        }
        // A key that continues no label cancels the one that is typed.
        if !typed.isEmpty {
            typed = ""
            return .updated
        }
        guard searching else { return .ignored }
        // A word does not start with a space, and a space is not repeated.
        if character == " ", query.isEmpty || query.hasSuffix(" ") { return .ignored }
        query += character
        refresh()
        return .updated
    }

    /// Takes back a typed letter of a label; then a letter of the text; then the search itself.
    public mutating func backspace() {
        if !typed.isEmpty {
            typed.removeLast()
        } else if !query.isEmpty {
            query.removeLast()
            refresh()
        } else if searching {
            searching = false
            refresh()
        }
    }

    /// Focuses a match, for a mode that waits for the click. An element that is not a match is not focused.
    public mutating func focus(_ id: Int) {
        if matches.contains(where: { $0.id == id }) { focused = id }
    }

    /// Moves the focus to the next (`1`) or the previous (`-1`) match, and wraps at the ends.
    public mutating func step(_ direction: Int) {
        guard !matches.isEmpty else { return }
        guard let current = matches.firstIndex(where: { $0.id == focused }) else {
            focused = (direction > 0 ? matches[0] : matches[matches.count - 1]).id
            return
        }
        focused = matches[(current + direction + matches.count) % matches.count].id
    }

    private mutating func refresh() {
        typed = ""
        let words = Self.words(of: query)
        if keepsLabels {
            // The target is the element whose label is the text, else the first match of the words.
            let wanted = query.lowercased()
            let labeled = labels.first { $0.value == wanted }?.key
            matches = elements.filter { element in
                if element.id == labeled { return true }
                let text = Array(Self.normalized(element.text))
                return words.allSatisfy { Self.fuzzyEnd(of: $0, in: text) != nil }
            }
            focused = query.isEmpty ? nil : (labeled ?? matches.first?.id)
            return
        }
        matches = words.isEmpty ? elements : elements.filter { element in
            let text = Array(Self.normalized(element.text))
            return words.allSatisfy { Self.fuzzyEnd(of: $0, in: text) != nil }
        }
        if searching, words.isEmpty || query.hasSuffix(" ") {
            labels = [:]
        } else {
            labels = Self.labels(for: matches, avoiding: searching ? Self.continuations(of: words[words.count - 1], in: matches) : [], letters: letters)
        }
        if let focused, !matches.contains(where: { $0.id == focused }) { self.focused = nil }
    }

    private static func words(of query: String) -> [[Character]] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map { Array($0) }
    }

    /// Where a word ends in a text when its letters are found in order, as early as they can be. `nil` when they are not.
    private static func fuzzyEnd(of word: [Character], in text: [Character]) -> Int? {
        var next = 0
        for (index, letter) in text.enumerated() where next < word.count && letter == word[next] {
            next += 1
            if next == word.count { return index + 1 }
        }
        return word.isEmpty ? 0 : nil
    }

    /// The letters that could come next in the last word: the ones that are in a match after the place where the word ends.
    private static func continuations(of word: [Character], in matches: [HintElement]) -> Set<Character> {
        var letters: Set<Character> = []
        for element in matches {
            let text = Array(normalized(element.text))
            if let end = fuzzyEnd(of: word, in: text) { letters.formUnion(text[end...]) }
        }
        return letters
    }

    /// Two letters for each match, in reading order. The first letters change first, so that near elements differ in the letter
    /// that is typed first. No first letter is in `avoided`, so the matches that come after the last label have none.
    static func labels(for matches: [HintElement], avoiding avoided: Set<Character>, letters alphabet: [Character] = alphabet) -> [Int: String] {
        let firsts = alphabet.filter { !avoided.contains($0) }
        let base = alphabet.count
        var labels: [Int: String] = [:]
        for (index, element) in matches.prefix(firsts.count * base).enumerated() {
            labels[element.id] = String(firsts[index % firsts.count]) + String(alphabet[index / firsts.count])
        }
        return labels
    }

    /// Case does not count, and neither do the spaces of the text.
    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}
