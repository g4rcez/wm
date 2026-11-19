import CoreGraphics
import Foundation

/// Where a word of the screen comes from.
public enum TextSource: Sendable, Equatable {
    case accessibility
    case ocr
}

/// A word that is visible on the screen. `frame` is in screen coordinates, origin at the top left. `window` is the place of
/// its window in the list that the page gets, where the first window is the one in front.
public struct TextWord: Sendable, Equatable {
    public var text: String
    public var frame: CGRect
    public var window: Int
    public var source: TextSource

    public init(_ text: String, frame: CGRect, window: Int = 0, source: TextSource = .accessibility) {
        self.text = text
        self.frame = frame
        self.window = window
        self.source = source
    }
}

/// A character of the page: a word, and the place of the character in it.
public struct TextPosition: Sendable, Equatable, Comparable {
    public var word: Int
    public var offset: Int

    public init(word: Int, offset: Int) {
        self.word = word
        self.offset = offset
    }

    public static func < (left: TextPosition, right: TextPosition) -> Bool {
        (left.word, left.offset) < (right.word, right.offset)
    }
}

/// A place where the search text is on the page: from the character `start` to the character `end`, both included.
public struct TextMatch: Sendable, Equatable {
    public var id: Int
    public var start: TextPosition
    public var end: TextPosition
    public var frame: CGRect
}

/// The text of the screen for the select mode: the words that are not behind another window, in reading order, in lines.
public struct TextPage: Sendable {
    /// The first letters of these keys move the cursor in the select mode, so no label starts with them.
    public static let motionKeys: Set<Character> = ["h", "j", "k", "l", "w", "b", "e", "v", "y"]

    public let words: [TextWord]
    /// The words of each line, as indices into `words`.
    public let lines: [Range<Int>]
    private let folded: [FoldedLine]

    /// The text of a line as the search sees it, and the character of the page that each letter comes from. A space between
    /// two words comes from no character.
    private struct FoldedLine: Sendable {
        var characters: [Character] = []
        var positions: [TextPosition?] = []
    }

    public init(words: [TextWord], windows: [CGRect] = []) {
        let visible = words.filter { word in
            let center = CGPoint(x: word.frame.midX, y: word.frame.midY)
            return !word.text.isEmpty && !windows.prefix(max(0, word.window)).contains { $0.contains(center) }
        }
        func origin(_ window: Int) -> CGPoint { windows.indices.contains(window) ? windows[window].origin : .zero }
        let groups = Dictionary(grouping: visible, by: \.window).sorted {
            (origin($0.key).y, origin($0.key).x, $0.key) < (origin($1.key).y, origin($1.key).x, $1.key)
        }
        var ordered: [TextWord] = []
        var lines: [Range<Int>] = []
        for (_, group) in groups {
            for line in Self.lines(of: group) {
                lines.append(ordered.count..<ordered.count + line.count)
                ordered += line
            }
        }
        self.words = ordered
        self.lines = lines
        folded = lines.map { line in
            var result = FoldedLine()
            for index in line {
                if index > line.lowerBound {
                    result.characters.append(" ")
                    result.positions.append(nil)
                }
                for (offset, character) in ordered[index].text.enumerated() {
                    for letter in Self.fold(String(character)) {
                        result.characters.append(letter)
                        result.positions.append(TextPosition(word: index, offset: offset))
                    }
                }
            }
            return result
        }
    }

    /// A window with this few words from the Accessibility API has its text in pixels: the OCR reads it.
    public static func needsOCR(wordCount: Int) -> Bool { wordCount < 8 }

    /// A box of the Vision framework (0 to 1, origin at the bottom left) in the screen coordinates of the image it was read from.
    public static func screenRect(normalized box: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
            width: box.width * frame.width, height: box.height * frame.height)
    }

    /// The line of a word.
    public func line(of word: Int) -> Int? { lines.firstIndex { $0.contains(word) } }

    /// The places of a text on the page. Case and accents do not count, and the text can go over many words of one line. An
    /// empty text gives every word.
    public func matches(_ query: String) -> [TextMatch] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else {
            return words.indices.map { index in
                TextMatch(
                    id: index, start: TextPosition(word: index, offset: 0),
                    end: TextPosition(word: index, offset: words[index].text.count - 1), frame: words[index].frame)
            }
        }
        var found: [TextMatch] = []
        for line in folded {
            var index = 0
            while index + needle.count <= line.characters.count {
                let end = index + needle.count
                if line.characters[index..<end].elementsEqual(needle), let first = line.positions[index], let last = line.positions[end - 1] {
                    found.append(TextMatch(id: found.count, start: first, end: last, frame: rects(from: first, to: last)[0]))
                    index = end
                } else {
                    index += 1
                }
            }
        }
        return found
    }

    /// Two letters for each match, as the hints have. The matches after the last label have none.
    public func labels(for matches: [TextMatch], avoiding: Set<Character> = TextPage.motionKeys) -> [Int: String] {
        ElementSearch.labels(for: matches.map { HintElement(id: $0.id, frame: $0.frame) }, avoiding: avoiding)
    }

    /// The text between two characters, both included: a space between words, a new line between lines.
    public func text(from start: TextPosition, to end: TextPosition) -> String {
        let (low, high) = start <= end ? (start, end) : (end, start)
        return lines.compactMap { line -> String? in
            let first = max(line.lowerBound, low.word), last = min(line.upperBound - 1, high.word)
            guard first <= last else { return nil }
            return (first...last).map { index in
                let characters = Array(words[index].text)
                let from = index == low.word ? min(low.offset, characters.count - 1) : 0
                let to = index == high.word ? min(high.offset, characters.count - 1) : characters.count - 1
                return String(characters[from...max(from, to)])
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// One frame for each line between two characters, both included. A word that is cut is cut in proportion to its letters,
    /// so the edge is near the letter, not on it, when the letters have different widths.
    public func rects(from start: TextPosition, to end: TextPosition) -> [CGRect] {
        let (low, high) = start <= end ? (start, end) : (end, start)
        return lines.compactMap { line -> CGRect? in
            let first = max(line.lowerBound, low.word), last = min(line.upperBound - 1, high.word)
            guard first <= last else { return nil }
            let whole = words[first...last].reduce(CGRect.null) { $0.union($1.frame) }
            let left = first == low.word ? edge(of: low, trailing: false) : whole.minX
            let right = last == high.word ? edge(of: high, trailing: true) : whole.maxX
            return CGRect(x: left, y: whole.minY, width: right - left, height: whole.height)
        }
    }

    /// The left or the right side of a character.
    func edge(of position: TextPosition, trailing: Bool) -> CGFloat {
        let word = words[position.word]
        return word.frame.minX + word.frame.width * CGFloat(position.offset + (trailing ? 1 : 0)) / CGFloat(max(word.text.count, 1))
    }

    /// The words of one window in lines, top to bottom, each line left to right. Two words are on one line when they share
    /// half the height of the shorter one.
    private static func lines(of words: [TextWord]) -> [[TextWord]] {
        var lines: [[TextWord]] = []
        for word in words.sorted(by: { ($0.frame.midY, $0.frame.minX) < ($1.frame.midY, $1.frame.minX) }) {
            if let first = lines.last?.first {
                let overlap = min(first.frame.maxY, word.frame.maxY) - max(first.frame.minY, word.frame.minY)
                if overlap >= min(first.frame.height, word.frame.height) / 2 {
                    lines[lines.count - 1].append(word)
                    continue
                }
            }
            lines.append([word])
        }
        return lines.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func fold(_ text: String) -> [Character] {
        Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }
}
