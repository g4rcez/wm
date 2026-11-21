import Cheatsheet
import Darwin
import Foundation

/// The size of the terminal on stdout, or 100 by 30 when it cannot be read.
private func terminalSize() -> (columns: Int, rows: Int) {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 { return (Int(size.ws_col), Int(size.ws_row)) }
    let columns = ProcessInfo.processInfo.environment["COLUMNS"].flatMap { Int($0) } ?? 100
    return (columns, 30)
}

/// The terminal as it was before the sheet took it, so that every way out can put it back.
nonisolated(unsafe) private var savedTerminal = termios()
nonisolated(unsafe) private var terminalTaken = false

private func giveTerminalBack() {
    guard terminalTaken else { return }
    terminalTaken = false
    // Show the cursor, leave the alternate screen.
    let text = "\u{1B}[?25h\u{1B}[?1049l"
    _ = text.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTerminal)
}

private func takeTerminal() {
    tcgetattr(STDIN_FILENO, &savedTerminal)
    var raw = savedTerminal
    cfmakeraw(&raw)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    terminalTaken = true
    let text = "\u{1B}[?1049h\u{1B}[?25l"
    _ = text.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    atexit { giveTerminalBack() }
    for signalNumber in [SIGTERM, SIGHUP, SIGQUIT] {
        signal(signalNumber) { code in
            giveTerminalBack()
            _exit(128 + code)
        }
    }
}

private enum Key: Equatable {
    case text(String), backspace, escape, left, right, up, down, pageUp, pageDown, tab, backTab, clear, quit, other
}

/// What the bytes of one read mean. A terminal sends an arrow as `ESC [ A`, so a lone ESC byte is the Escape key.
private func decodeKeys(_ bytes: [UInt8]) -> [Key] {
    var keys: [Key] = []
    var index = 0
    var text: [UInt8] = []
    func flush() {
        if !text.isEmpty { keys.append(.text(String(decoding: text, as: UTF8.self))) }
        text = []
    }
    while index < bytes.count {
        let byte = bytes[index]
        switch byte {
        case 0x1B:
            flush()
            guard index + 1 < bytes.count else {
                keys.append(.escape)
                index += 1
                continue
            }
            // Escape followed by a letter is Alt+letter: it is not a key of the sheet.
            guard bytes[index + 1] == 0x5B || bytes[index + 1] == 0x4F else {
                keys.append(.other)
                index += 2
                continue
            }
            var end = index + 2
            while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
            let final = end < bytes.count ? bytes[end] : 0
            let parameters = String(decoding: bytes[(index + 2)..<min(end, bytes.count)], as: UTF8.self)
            switch (final, parameters) {
            case (0x41, _): keys.append(.up)
            case (0x42, _): keys.append(.down)
            case (0x43, _): keys.append(.right)
            case (0x44, _): keys.append(.left)
            case (0x5A, _): keys.append(.backTab)
            case (0x7E, "5"): keys.append(.pageUp)
            case (0x7E, "6"): keys.append(.pageDown)
            default: keys.append(.other)
            }
            index = end + 1
        case 0x7F, 0x08: flush(); keys.append(.backspace); index += 1
        case 0x03, 0x04, 0x11: flush(); keys.append(.quit); index += 1
        case 0x15: flush(); keys.append(.clear); index += 1
        case 0x09: flush(); keys.append(.tab); index += 1
        case 0x0E: flush(); keys.append(.down); index += 1
        case 0x10: flush(); keys.append(.up); index += 1
        case 0x00..<0x20: flush(); keys.append(.other); index += 1
        default: text.append(byte); index += 1
        }
    }
    flush()
    return keys
}

/// The sheet in the terminal: it takes the screen, redraws on every key and when the window changes size, and leaves on Escape.
/// Typing filters, ← and → change the mode, ↑ and ↓ scroll.
func runCheatsheetScreen(_ sheet: Cheatsheet, mode: String?, color: Bool) {
    var page = sheet.pageIndex(of: mode)
    var query = ""
    var scroll = 0
    var maxScroll = 0
    var drawn: (columns: Int, rows: Int, text: String)?
    let palette = CheatPalette(enabled: color)
    takeTerminal()

    func draw(force: Bool = false) {
        let size = terminalSize()
        let screen = renderScreen(sheet, page: page, query: query, scroll: scroll, width: size.columns, height: size.rows, palette: palette)
        maxScroll = screen.maxScroll
        scroll = min(scroll, maxScroll)
        let text = screen.lines.joined(separator: "\u{1B}[K\r\n")
        if !force, let drawn, drawn.columns == size.columns, drawn.rows == size.rows, drawn.text == text { return }
        drawn = (size.columns, size.rows, text)
        let frame = "\u{1B}[H" + text + "\u{1B}[K\u{1B}[J"
        _ = frame.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    }

    func move(_ delta: Int) {
        guard sheet.pages.count > 1 else { return }
        page = (page + delta + sheet.pages.count) % sheet.pages.count
        scroll = 0
    }

    draw(force: true)
    var buffer = [UInt8](repeating: 0, count: 64)
    while true {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        // A timeout lets the sheet follow a window that changes size.
        guard poll(&descriptor, 1, 200) != 0 else { draw(); continue }
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count <= 0 { break }
        for key in decodeKeys(Array(buffer[0..<count])) {
            switch key {
            case .quit: giveTerminalBack(); return
            case .escape:
                if query.isEmpty { giveTerminalBack(); return }
                query = ""
                scroll = 0
            case .text(let text): query += text.filter { !$0.isNewline }; scroll = 0
            case .backspace: if !query.isEmpty { query.removeLast() }; scroll = 0
            case .clear: query = ""; scroll = 0
            case .left, .backTab: move(-1)
            case .right, .tab: move(1)
            case .up: scroll = max(0, scroll - 1)
            case .down: scroll = min(maxScroll, scroll + 1)
            case .pageUp: scroll = max(0, scroll - max(1, terminalSize().rows - 8))
            case .pageDown: scroll = min(maxScroll, scroll + max(1, terminalSize().rows - 8))
            case .other: break
            }
        }
        draw()
    }
    giveTerminalBack()
}

/// The sheet as text on stdout: for a pipe, or a terminal that has no keyboard to read.
func printCheatsheet(_ sheet: Cheatsheet, color: Bool) {
    let columns = isatty(STDOUT_FILENO) == 1 ? terminalSize().columns : (ProcessInfo.processInfo.environment["COLUMNS"].flatMap { Int($0) } ?? 100)
    print(renderStatic(sheet, width: max(60, columns), palette: CheatPalette(enabled: color)), terminator: "")
}
