import Testing
@testable import Scripting

@Suite("ChordRecording")
struct ChordRecordingTests {
    @Test func aSingleKeyFinishesAtOnce() throws {
        var recording = ChordRecording(maxSteps: 1)

        #expect(recording.add(try parseChord("cmd-right")) == .finished)
        #expect(recording.text == "cmd-right")
    }

    @Test func aSequenceGrowsUntilItIsFull() throws {
        var recording = ChordRecording(maxSteps: 3)

        #expect(recording.add(try parseChord("ctrl-p")) == .added)
        #expect(recording.add(try parseChord("h")) == .added)
        #expect(recording.text == "ctrl-p>h")
        #expect(recording.add(try parseChord("j")) == .finished)
        #expect(recording.text == "ctrl-p>h>j")
    }

    @Test func theTextIsReadBackAsTheSameSequence() throws {
        var recording = ChordRecording(maxSteps: 4)
        _ = recording.add(try parseChord("hyper-k"))
        _ = recording.add(try parseChord("shift+alt-l"))

        #expect(recording.text == "hyper-k>alt-shift-l")
        #expect(try parseChordSequence(recording.text) == recording.chords)
    }

    @Test func aBareEscapeStopsAndIsNotRecorded() throws {
        var recording = ChordRecording(maxSteps: 4)
        _ = recording.add(try parseChord("alt-h"))

        #expect(recording.add(try parseChord("esc")) == .cancelled)
        #expect(recording.text == "alt-h")
    }

    @Test func anEscapeWithAModifierIsAKey() throws {
        var recording = ChordRecording(maxSteps: 1)

        #expect(recording.add(try parseChord("cmd-esc")) == .finished)
        #expect(recording.text == "cmd-esc")
    }

    @Test func nothingRecordedIsEmptyText() {
        #expect(ChordRecording(maxSteps: 4).text == "")
    }
}
