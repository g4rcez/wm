import Core
import Foundation

/// The key list of the floating label, like a which-key plugin: the keys that can be pressed now, with what they do.
public enum WhichKey {
    /// The glyph that a key name is drawn as, so a chip stays narrow: `leftsquarebracket` is `[`, `left` is `←`. Letters,
    /// digits and the names that have no glyph (`esc`, `home`, `f5`) are drawn as they are.
    private static let glyphs: [String: String] = [
        "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/", "backslash": "\\", "semicolon": ";", "quote": "'",
        "backtick": "`", "leftsquarebracket": "[", "rightsquarebracket": "]",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "space": "␣", "tab": "⇥", "enter": "↩", "backspace": "⌫", "delete": "⌦", "pageup": "⇞", "pagedown": "⇟",
    ]

    /// A chord as it is drawn on its chip: modifiers as symbols, then the key as it was written (`⌥h`, `⇧y`) or its glyph
    /// (`⌘[`, `←`).
    public static func display(_ chord: Chord) -> String {
        chord.modifiers.symbols + (glyphs[chord.key] ?? chord.key)
    }

    /// The keys of `mode` (and the universal ones) that can be pressed after the `pending` steps of a sequence (none at
    /// the start). Only binds that run on press count, minus the hidden ones and the ones that swallow a key. A longer
    /// sequence under a key shows as one entry with `…`. The order is the same every time: letters and digits, then
    /// chords with modifiers, then other keys, then `esc`.
    public static func entries(mode: String, pending: [Chord], records: [BindRecord]) -> [LabelEntry] {
        var found: [Chord: (text: String, grouped: Bool)] = [:]
        // A hold bind (`repeating = true`) shows when its keys have no plain bind; with one, the plain bind shows.
        let plain = Set(records.filter { $0.trigger == .press }.map { "\($0.mode)\u{0}\($0.keys)" })
        for record in records
        where (record.mode == mode || record.mode == universalMode)
            && (record.trigger == .press || (record.trigger == .hold && !plain.contains("\(record.mode)\u{0}\(record.keys)")))
            && !record.options.hidden && record.action != "noop" {
            guard let chords = try? parseChordSequence(record.keys), chords.count > pending.count,
                  Array(chords.prefix(pending.count)) == pending else { continue }
            let next = chords[pending.count]
            if chords.count > pending.count + 1 {
                found[next] = ("…", true)
            } else if found[next]?.grouped != true {
                found[next] = (text(for: record), false)
            }
        }
        return found.sorted { rank($0.key) < rank($1.key) }.map { LabelEntry(key: display($0.key), text: $0.value.text) }
    }

    private static func text(for record: BindRecord) -> String {
        if let description = record.options.description, !description.isEmpty { return description }
        if record.action == "mode main" { return "exit" }
        return record.action.count <= 28 ? record.action : String(record.action.prefix(27)) + "…"
    }

    private static func rank(_ chord: Chord) -> (Int, String) {
        let group: Int
        if !chord.modifiers.isEmpty {
            group = 1
        } else if chord.key == "esc" {
            group = 3
        } else {
            group = chord.key.count == 1 ? 0 : 2
        }
        return (group, display(chord))
    }
}
