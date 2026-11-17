import Testing
@testable import Core

struct RestoreMatchTests {
    private let candidates = [
        RestoreCandidate(key: 0, bundleID: "com.apple.Terminal", title: "build", order: 4),
        RestoreCandidate(key: 1, bundleID: "com.apple.Terminal", title: "logs", order: 2),
        RestoreCandidate(key: 2, bundleID: "com.apple.Notes", title: "Todo", order: 1),
    ]

    @Test func aWindowTakesTheCandidateOfItsAppWithTheSameTitle() {
        #expect(bestRestoreMatch(bundleID: "com.apple.Terminal", title: "build", among: candidates)?.key == 0)
        #expect(bestRestoreMatch(bundleID: "com.apple.Terminal", title: "logs", among: candidates)?.key == 1)
    }

    @Test func withoutAMatchingTitleTheEarliestOfTheAppGoesFirst() {
        #expect(bestRestoreMatch(bundleID: "com.apple.Terminal", title: "zsh", among: candidates)?.key == 1)
        #expect(bestRestoreMatch(bundleID: "com.apple.Terminal", title: "", among: candidates)?.key == 1)
    }

    @Test func anAppWithoutCandidatesGetsNone() {
        #expect(bestRestoreMatch(bundleID: "com.apple.Safari", title: "Todo", among: candidates) == nil)
        #expect(bestRestoreMatch(bundleID: "com.apple.Notes", title: "Todo", among: []) == nil)
    }

    @Test func theSameTitleOnTwoCandidatesGoesToTheEarlierOne() {
        let twins = [
            RestoreCandidate(key: 5, bundleID: "a", title: "zsh", order: 9),
            RestoreCandidate(key: 6, bundleID: "a", title: "zsh", order: 3),
        ]
        #expect(bestRestoreMatch(bundleID: "a", title: "zsh", among: twins)?.key == 6)
    }

    @Test func aPlaceholderLiesAboveEveryRealWindowId() {
        #expect(Placeholder.id(for: 7) == 0xF000_0007)
        #expect(Placeholder.isPlaceholder(Placeholder.id(for: 7)))
        #expect(!Placeholder.isPlaceholder(4_000_000))
    }
}
