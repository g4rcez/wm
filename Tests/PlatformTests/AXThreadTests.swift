import Foundation
import Testing
@testable import Platform

struct AXThreadTests {
    @Test func runAnswersWithTheBody() async {
        let thread = AXThread(name: "test-run")
        let value = await thread.run(orElse: -1) { 42 }
        #expect(value == 42)
        thread.stop()
    }

    /// The race behind a frozen wm: an app quits (its thread stops) while the refresh still waits for its windows. The loop may
    /// still run a block queued at that moment, or end first: either way the call answers, and never waits for ever.
    @Test(arguments: 0..<50)
    func aCallQueuedAroundStopAlwaysAnswers(round: Int) async {
        let thread = AXThread(name: "test-stop-\(round)")
        let release = DispatchSemaphore(value: 0)
        thread.async { release.wait() }
        thread.stop()
        // Not a task group: it would wait for a call that never answers, and the test would hang instead of failing.
        let box = AnswerBox()
        Task.detached { box.set(await thread.run(orElse: "gone") { "ran" }) }
        release.signal()
        var answer: String?
        for _ in 0..<200 {
            answer = box.value
            if answer != nil { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(answer == "gone" || answer == "ran", "the call did not answer within 2 seconds")
    }

    @Test func aCallAfterTheThreadEndedAnswersAtOnce() async throws {
        let thread = AXThread(name: "test-ended")
        thread.stop()
        // Give the loop time to end.
        try await Task.sleep(nanoseconds: 100_000_000)
        let answer = await thread.run(orElse: 0) { 1 }
        #expect(answer == 0)
    }
}

final class AnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: String?
    func set(_ value: String) { lock.withLock { answer = value } }
    var value: String? { lock.withLock { answer } }
}
