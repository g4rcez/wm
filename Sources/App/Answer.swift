import Common

func ok(_ output: String = "") -> ServerAnswer { ServerAnswer(exitCode: 0, stdout: output) }

/// An error answer. The text has up to three lines: `wm: error: <message>`, the `usage:` of the command (from the
/// command table), and a `hint:`. Exit code 2 is for wrong use of a command, 1 for a command that cannot run now.
func fail(_ message: String, _ code: Int32 = 1, usage: String? = nil, hint: String? = nil) -> ServerAnswer {
    var text = "wm: error: \(message)\n"
    if let usage {
        let lines = usageLines(for: usage)
        if !lines.isEmpty { text += "usage: " + lines.map { String($0.dropFirst(3)) }.joined(separator: "\n       ") + "\n" }
    }
    if let hint { text += "hint: \(hint)\n" }
    return ServerAnswer(exitCode: code, stderr: text)
}

/// An error for the first option that the command does not have, or `nil` when all are known.
func unknownOption(_ flags: Set<String>, allowed: Set<String>, usage: String) -> ServerAnswer? {
    guard let bad = flags.subtracting(allowed).sorted().first else { return nil }
    return fail("unknown option \(bad)", 2, usage: usage, hint: bad == "--silent" ? "--silent is now --stay" : nil)
}
