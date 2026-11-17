/// US-layout (ANSI) virtual key codes by canonical key name. Key codes are positions, so bindings do not depend
/// on the active input source.
public enum KeyCodes {
    public static func code(for name: String) -> Int? { byName[name] }
    public static func name(for code: Int) -> String? { byCode[code] }
    /// The `NX_KEYTYPE_*` number of a media key (`volume_up`, `play`), for `EventTap.postMedia`.
    public static func mediaKey(for name: String) -> Int? { media[name] }

    private static let media: [String: Int] = [
        "volume_up": 0, "volume_down": 1, "brightness_up": 2, "brightness_down": 3, "mute": 7, "play": 16,
        // The fast-forward and rewind keys of F9 and F7 (NX_KEYTYPE_FAST, NX_KEYTYPE_REWIND): a tap skips the track.
        "next": 19, "previous": 20,
    ]

    private static let byName: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24,
        "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "rightsquarebracket": 30, "o": 31, "u": 32,
        "leftsquarebracket": 33, "i": 34, "p": 35, "enter": 36, "l": 37, "j": 38, "quote": 39, "k": 40,
        "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48,
        "space": 49, "backtick": 50, "backspace": 51, "esc": 53, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103, "f13": 105, "f16": 106,
        "f14": 107, "f10": 109, "f12": 111, "f15": 113, "home": 115, "pageup": 116, "delete": 117, "f4": 118,
        "end": 119, "f2": 120, "pagedown": 121, "f1": 122, "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    private static let byCode: [Int: String] = Dictionary(uniqueKeysWithValues: byName.map { ($1, $0) })
}
