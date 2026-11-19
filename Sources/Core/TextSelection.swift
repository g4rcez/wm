import CoreGraphics

/// A move of the cursor in the select mode.
public enum TextMotion: Sendable, Equatable {
    case left, right
    case nextWord, previousWord, wordEnd
    case down, up
    case lineStart, lineEnd
}

/// The selection of the select mode: the characters from `anchor` to `head`, both included. `head` is the cursor.
public struct TextSelection: Sendable, Equatable {
    public private(set) var anchor: TextPosition
    public private(set) var head: TextPosition
    /// When it is off, a move takes the whole selection to the cursor. When it is on, only the cursor moves.
    public private(set) var extend = false

    public init(_ match: TextMatch) {
        anchor = match.start
        head = match.end
    }

    /// A label was typed. The first one selects the match and starts to extend; the next ones make the selection reach the match.
    public mutating func jump(to match: TextMatch) {
        guard extend else {
            anchor = match.start
            head = match.end
            extend = true
            return
        }
        let low = min(anchor, head), high = max(anchor, head)
        if match.start < low {
            anchor = max(high, match.end)
            head = match.start
        } else {
            anchor = low
            head = max(high, match.end)
        }
    }

    public mutating func toggleExtend() {
        extend.toggle()
        if !extend { anchor = head }
    }

    public mutating func move(_ motion: TextMotion, in page: TextPage) {
        head = Self.destination(of: motion, from: head, in: page)
        if !extend { anchor = head }
    }

    public func text(in page: TextPage) -> String { page.text(from: anchor, to: head) }

    public func rects(in page: TextPage) -> [CGRect] { page.rects(from: anchor, to: head) }

    /// Where a click goes: the middle of the first word of the selection.
    public func clickPoint(in page: TextPage) -> CGPoint {
        let frame = page.words[min(anchor, head).word].frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func destination(of motion: TextMotion, from position: TextPosition, in page: TextPage) -> TextPosition {
        guard let lineIndex = page.line(of: position.word) else { return position }
        let line = page.lines[lineIndex]
        func last(_ word: Int) -> Int { page.words[word].text.count - 1 }
        switch motion {
        case .left:
            if position.offset > 0 { return TextPosition(word: position.word, offset: position.offset - 1) }
            if position.word > line.lowerBound { return TextPosition(word: position.word - 1, offset: last(position.word - 1)) }
        case .right:
            if position.offset < last(position.word) { return TextPosition(word: position.word, offset: position.offset + 1) }
            if position.word + 1 < line.upperBound { return TextPosition(word: position.word + 1, offset: 0) }
        case .nextWord:
            if position.word + 1 < page.words.count { return TextPosition(word: position.word + 1, offset: 0) }
        case .previousWord:
            if position.offset > 0 { return TextPosition(word: position.word, offset: 0) }
            if position.word > 0 { return TextPosition(word: position.word - 1, offset: 0) }
        case .wordEnd:
            if position.offset < last(position.word) { return TextPosition(word: position.word, offset: last(position.word)) }
            if position.word + 1 < page.words.count { return TextPosition(word: position.word + 1, offset: last(position.word + 1)) }
        case .down, .up:
            let target = lineIndex + (motion == .down ? 1 : -1)
            guard page.lines.indices.contains(target) else { return position }
            // The character of the other line that is nearest to the middle of this one.
            let x = (page.edge(of: position, trailing: false) + page.edge(of: position, trailing: true)) / 2
            func distance(_ word: Int) -> CGFloat { max(page.words[word].frame.minX - x, x - page.words[word].frame.maxX, 0) }
            guard let word = page.lines[target].min(by: { distance($0) < distance($1) }) else { return position }
            let frame = page.words[word].frame
            let offset = frame.width > 0 ? Int((x - frame.minX) / frame.width * CGFloat(last(word) + 1)) : 0
            return TextPosition(word: word, offset: min(max(offset, 0), last(word)))
        case .lineStart:
            return TextPosition(word: line.lowerBound, offset: 0)
        case .lineEnd:
            return TextPosition(word: line.upperBound - 1, offset: last(line.upperBound - 1))
        }
        return position
    }
}
