import Foundation

/// The chords that the Shortcuts window collects while the user presses keys to record a shortcut.
public struct ChordRecording: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The chord is in the recording, and more can follow.
        case added
        /// The chord is in the recording, and it has all the steps that it can have.
        case finished
        /// A bare Esc: the user stops, and the Esc is not part of the shortcut.
        case cancelled
    }

    /// 1 for a single key (the key that a remap types), more for a sequence such as `ctrl-p>h`.
    public let maxSteps: Int
    public private(set) var chords: [Chord] = []

    public init(maxSteps: Int) { self.maxSteps = maxSteps }

    /// The recording as `parseChordSequence` reads it: `ctrl-p>h`.
    public var text: String { chords.map(\.description).joined(separator: ">") }

    public mutating func add(_ chord: Chord) -> Outcome {
        if chord.key == "esc", chord.modifiers.isEmpty { return .cancelled }
        chords.append(chord)
        return chords.count >= maxSteps ? .finished : .added
    }
}
