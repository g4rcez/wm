import AppKit
import ApplicationServices
import Core
import PrivateApi

/// What `ElementReader.text` finds on a display.
public struct ScreenText: Sendable {
    /// The words that the Accessibility API gives. `window` of a word is an index into `windows`.
    public var words: [TextWord]
    /// The part of each window that is on the display, the window in front first.
    public var windows: [CGRect]
}

/// The text of the windows of a display, word by word, for the select mode.
extension ElementReader {
    private static let textRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea"]
    /// The most words that one read gives: each word is a call to its app.
    private static let maxWords = 3000
    /// A window that shows less than this on the display is not read.
    private static let minWindowSide: CGFloat = 40

    /// The words of every window that shows on `display` (a frame in screen coordinates).
    public func text(on display: CGRect) async -> ScreenText {
        await thread.run { [self] in readText(on: display) }
    }

    private func readText(on display: CGRect) -> ScreenText {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // The list is in order, the window in front first.
        let shown = list.compactMap { entry -> (id: CGWindowID, pid: pid_t, frame: CGRect)? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0, let pid = entry[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != own,
                  let id = entry[kCGWindowNumber as String] as? Int, let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let visible = frame.intersection(display)
            guard visible.width >= Self.minWindowSide, visible.height >= Self.minWindowSide else { return nil }
            return (CGWindowID(id), pid_t(pid), visible)
        }
        // Only a window that the Accessibility API knows counts: an app can have a clear window over the whole display.
        var elements: [CGWindowID: AXUIElement] = [:]
        for pid in Set(shown.map(\.pid)) {
            let windows: [AXUIElement] = attribute(application(pid), kAXWindowsAttribute) ?? []
            for window in windows {
                var id: CGWindowID = 0
                if _AXUIElementGetWindow(window, &id) == .success { elements[id] = window }
            }
        }
        var words: [TextWord] = []
        var frames: [CGRect] = []
        for window in shown {
            // A window that is all behind another one has nothing to read.
            guard let element = elements[window.id], !frames.contains(where: { $0.contains(window.frame) }) else { continue }
            let index = frames.count
            frames.append(window.frame)
            let count = words.count
            func walk() {
                budget = Self.maxNodes
                sawEmptyWebArea = false
                visitText(element, clip: window.frame, depth: 0, window: index, into: &words)
            }
            walk()
            if sawEmptyWebArea, enableWebContent(application(window.pid), pid: window.pid) {
                words.removeSubrange(count...)
                walk()
            }
        }
        return ScreenText(words: words, windows: frames)
    }

    private func visitText(_ element: AXUIElement, clip: CGRect, depth: Int, window: Int, into words: inout [TextWord]) {
        guard budget > 0, depth <= Self.maxDepth, words.count < Self.maxWords else { return }
        budget -= 1
        let node = read(element)
        // The text of a password field is not for the screen.
        if node.role == "AXMenu" || node.subrole == "AXSecureTextField" { return }
        if node.role == "AXWebArea", node.children.isEmpty { sawEmptyWebArea = true }
        var childClip = clip
        if let frame = node.frame, !frame.isEmpty {
            if !frame.intersects(clip) { return }
            if Self.scrollRoles.contains(node.role) { childClip = clip.intersection(frame) }
        }
        // The children of a text element repeat its text (the lines of a paragraph in Chromium), so the walk stops here.
        if Self.textRoles.contains(node.role), !node.value.isEmpty {
            addWords(of: node.value, in: element, node: node, measured: true, clip: clip, window: window, into: &words)
            return
        }
        if node.children.isEmpty, !node.title.isEmpty {
            addWords(of: node.title, in: element, node: node, measured: false, clip: clip, window: window, into: &words)
        }
        for child in node.children { visitText(child, clip: childClip, depth: depth + 1, window: window, into: &words) }
    }

    /// The words of an element that show in `clip`. `measured`: the app is asked for the frame of each word. When it does not
    /// answer, or for a title, the frame of the element is cut in proportion to the letters: right for one line of text only.
    private func addWords(
        of text: String, in element: AXUIElement, node: Node, measured: Bool, clip: CGRect, window: Int, into words: inout [TextWord]
    ) {
        let string = text as NSString
        var range = NSRange(location: 0, length: string.length)
        // A text area can hold a whole file: only the part that shows is read.
        if node.role == "AXTextArea", let visible = visibleRange(of: element) { range = NSIntersectionRange(range, visible) }
        guard range.length > 0 else { return }
        var measured = measured
        for (index, part) in Self.wordRanges(of: string, in: range, limit: Self.maxWords - words.count).enumerated() {
            var frame = measured ? bounds(of: part, in: element) : nil
            if frame == nil {
                // Only the first word decides: a later word without a frame is off the screen.
                if measured, index > 0 { continue }
                measured = false
                guard let whole = node.frame else { return }
                frame = CGRect(
                    x: whole.minX + whole.width * CGFloat(part.location - range.location) / CGFloat(range.length), y: whole.minY,
                    width: whole.width * CGFloat(part.length) / CGFloat(range.length), height: whole.height)
            }
            guard let frame, frame.width >= 1, frame.height >= 1, clip.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            words.append(TextWord(string.substring(with: part), frame: frame, window: window))
        }
    }

    private func visibleRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.length > 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// The frame of a range of the text of an element on the screen, or `nil` when the app does not give it.
    private func bounds(of range: NSRange, in element: AXUIElement) -> CGRect? {
        var wanted = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &wanted) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), !rect.isEmpty else { return nil }
        return rect
    }

    /// The ranges of the words of a text, in UTF-16 units as the Accessibility API counts them. At most `limit` words.
    private static func wordRanges(of string: NSString, in range: NSRange, limit: Int) -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        for index in range.location..<NSMaxRange(range) where ranges.count < limit {
            let isSpace = Unicode.Scalar(string.character(at: index)).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
            if !isSpace {
                if start == nil { start = index }
            } else if let from = start {
                ranges.append(NSRange(location: from, length: index - from))
                start = nil
            }
        }
        if let from = start, ranges.count < limit { ranges.append(NSRange(location: from, length: NSMaxRange(range) - from)) }
        return ranges
    }
}
