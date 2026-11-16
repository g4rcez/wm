import Core
import Foundation

/// The key list of the floating label, like a which-key plugin: the keys that can be pressed now, with what they do.
public enum WhichKey {
    /// A chord as it is drawn on its chip: modifiers as symbols, a letter in capitals (`⌥H`), other names as they are.
    public static func display(_ chord: Chord) -> String {
        var text = ""
        if chord.modifiers.contains(.control) { text += "⌃" }
        if chord.modifiers.contains(.option) { text += "⌥" }
        if chord.modifiers.contains(.shift) { text += "⇧" }
        if chord.modifiers.contains(.command) { text += "⌘" }
        return text + (chord.key.count == 1 ? chord.key.uppercased() : chord.key)
    }

    /// The keys of `mode` (and the universal ones) that can be pressed after the `pending` steps of a sequence (none at
    /// the start). Only binds that run on press count, minus the hidden ones and the ones that swallow a key. A longer
    /// sequence under a key shows as one entry with `…`. The order is the same every time: letters and digits, then
    /// chords with modifiers, then other keys, then `esc`.
    public static func entries(mode: String, pending: [Chord], records: [BindRecord]) -> [LabelEntry] {
        var found: [Chord: (text: String, grouped: Bool)] = [:]
        for record in records
        where (record.mode == mode || record.mode == universalMode) && record.trigger == .press
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
