import Foundation

/// The colors of the text that the CLI prints: `wm help` and error lines. A style that is off returns the text unchanged,
/// so a pipe, a file and a test see plain text.
public struct HelpStyle: Sendable, Equatable {
    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public static let plain = HelpStyle(enabled: false)

    /// Colors only on a terminal. `NO_COLOR` (any text) and `TERM=dumb` turn them off, and `NO_COLOR` wins over
    /// `CLICOLOR_FORCE` (anything but `0`), which turns them on, also in a pipe.
    public static func detect(isTerminal: Bool, environment: [String: String]) -> HelpStyle {
        if let off = environment["NO_COLOR"], !off.isEmpty { return .plain }
        if let force = environment["CLICOLOR_FORCE"], !force.isEmpty, force != "0" { return HelpStyle(enabled: true) }
        if environment["TERM"] == "dumb" { return .plain }
        return HelpStyle(enabled: isTerminal)
    }

    private func paint(_ code: String, _ text: String) -> String {
        enabled && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    /// A section title: `FOCUS AND MOVE`, `Options`.
    public func heading(_ text: String) -> String { paint("1;36", text) }
    /// The words of a command: `window send workspace`.
    public func command(_ text: String) -> String { paint("1", text) }
    /// An argument: `<name>`, `[on|off]`.
    public func argument(_ text: String) -> String { paint("36", text) }
    /// An option: `--stay`.
    public func option(_ text: String) -> String { paint("33", text) }
    /// An example line.
    public func example(_ text: String) -> String { paint("32", text) }
    /// Secondary text: the label of an error line, a note.
    public func dim(_ text: String) -> String { paint("2", text) }
    public func error(_ text: String) -> String { paint("1;31", text) }
    public func hint(_ text: String) -> String { paint("36", text) }
}
