import CoreGraphics
import Platform
import Scripting

/// Types keys for the user: remaps, `wm.press`, `key press`, and the Esc of a lone hyper key.
enum KeyOutput {
    static func flags(of modifiers: Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    /// One half of a key press of `chord`. A media key has no modifiers and no repeat.
    static func post(_ chord: Chord, down: Bool, isRepeat: Bool = false) {
        if let media = KeyCodes.mediaKey(for: chord.key) {
            EventTap.postMedia(key: media, down: down)
        } else if let code = KeyCodes.code(for: chord.key) {
            EventTap.post(keyCode: code, flags: flags(of: chord.modifiers), down: down, isRepeat: isRepeat)
        }
    }

    /// A press and a release.
    static func tap(_ chord: Chord) {
        post(chord, down: true)
        post(chord, down: false)
    }
}
