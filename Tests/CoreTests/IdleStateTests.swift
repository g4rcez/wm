import Foundation
import Testing
@testable import Core

struct IdleStateTests {
    @Test func eachThresholdFiresOnceWhileTheIdleTimeGrows() {
        var state = IdleState(thresholds: [60, 300])
        let readings = [10.0, 40, 61, 100, 299, 301, 400].map { state.update(idleSeconds: $0) }
        #expect(readings == [[], [], [.idle(seconds: 60)], [], [], [.idle(seconds: 300)], []])
    }

    @Test func aReadingThatPassesTwoThresholdsFiresBoth() {
        var state = IdleState(thresholds: [300, 60])
        #expect(state.update(idleSeconds: 500) == [.idle(seconds: 60), .idle(seconds: 300)])
    }

    @Test func inputAfterAnIdleEventIsAResume() {
        var state = IdleState(thresholds: [60])
        _ = state.update(idleSeconds: 90)
        let back = state.update(idleSeconds: 2)
        #expect(back == [.resumed(idle: 90)])
    }

    @Test func inputWithoutAnIdleEventIsNotAResume() {
        var state = IdleState(thresholds: [60])
        _ = state.update(idleSeconds: 30)
        #expect(state.update(idleSeconds: 1).isEmpty)
    }

    @Test func theThresholdsFireAgainAfterAResume() {
        var state = IdleState(thresholds: [60])
        _ = state.update(idleSeconds: 70)
        _ = state.update(idleSeconds: 3)
        #expect(state.update(idleSeconds: 65) == [.idle(seconds: 60)])
    }

    @Test func aResumeAndANewIdleCanComeInOneReading() {
        var state = IdleState(thresholds: [10])
        _ = state.update(idleSeconds: 50)
        // Input at second 0, and then 12 seconds of quiet before the next reading.
        #expect(state.update(idleSeconds: 12) == [.resumed(idle: 50), .idle(seconds: 10)])
    }

    @Test func theIntervalIsAQuarterOfTheShortestThresholdBetweenOneAndFive() {
        #expect(IdleState(thresholds: [300, 60]).pollInterval == 5)
        #expect(IdleState(thresholds: [8]).pollInterval == 2)
        #expect(IdleState(thresholds: [2]).pollInterval == 1)
        #expect(IdleState(thresholds: []).pollInterval == nil)
    }

    @Test func repeatedAndInvalidThresholdsAreDropped() {
        #expect(IdleState(thresholds: [60, 60, 0, -5, 120]).thresholds == [60, 120])
    }
}
