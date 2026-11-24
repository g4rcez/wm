import CoreGraphics
import Testing
@testable import Core

struct FrameDriftTests {
    private let sent = CGRect(x: 0, y: 0, width: 600, height: 900)

    @Test func aFrameWithinTheToleranceNeedsNoResend() {
        var drift = FrameDrift()
        let close = CGRect(x: 2, y: 1, width: 598, height: 902)
        let r1 = drift.shouldResend(1, actual: close, sent: sent)
        #expect(!r1)
    }

    @Test func aShortWindowIsSentAgainButOnlyMaxRetriesTimes() {
        var drift = FrameDrift()
        let short = CGRect(x: 0, y: 0, width: 600, height: 800)
        let r2 = drift.shouldResend(1, actual: short, sent: sent)
        #expect(r2)
        let r3 = drift.shouldResend(1, actual: short, sent: sent)
        #expect(r3)
        let r4 = drift.shouldResend(1, actual: short, sent: sent)
        #expect(!r4)
    }

    @Test func aNewTargetStartsTheCountAgain() {
        var drift = FrameDrift()
        let short = CGRect(x: 0, y: 0, width: 600, height: 800)
        for _ in 0..<3 { _ = drift.shouldResend(1, actual: short, sent: sent) }
        let other = CGRect(x: 0, y: 0, width: 500, height: 900)
        let r5 = drift.shouldResend(1, actual: short, sent: other)
        #expect(r5)
    }

    @Test func arrivingAtTheTargetResetsTheCount() {
        var drift = FrameDrift()
        let short = CGRect(x: 0, y: 0, width: 600, height: 800)
        _ = drift.shouldResend(1, actual: short, sent: sent)
        _ = drift.shouldResend(1, actual: short, sent: sent)
        let r6 = drift.shouldResend(1, actual: sent, sent: sent)
        #expect(!r6)
        let r7 = drift.shouldResend(1, actual: short, sent: sent)
        #expect(r7)
    }

    @Test func eachWindowCountsOnItsOwn() {
        var drift = FrameDrift()
        let short = CGRect(x: 0, y: 0, width: 600, height: 800)
        for _ in 0..<3 { _ = drift.shouldResend(1, actual: short, sent: sent) }
        let r8 = drift.shouldResend(2, actual: short, sent: sent)
        #expect(r8)
    }
}
