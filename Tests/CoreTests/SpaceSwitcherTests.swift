import Testing
@testable import Core

@MainActor
struct SpaceSwitcherTests {
    @MainActor private final class Fake {
        var spaces: [UInt64] = [10, 11, 12, 13]
        var current: UInt64 = 10
        var swipes: [(Int32, Int32)] = []
        var now: UInt64 = 0
        var accept = true
        var dock: Int32? = 1

        func switcher(batch: Bool) -> SpaceSwitcher {
            SpaceSwitcher(
                currentSpace: { _ in self.current }, spaceIDs: { _ in self.spaces },
                swipe: { from, to, _ in
                    self.swipes.append((from, to))
                    return self.accept
                }, clock: { self.now }, pollAutomatically: false, batchMovement: batch, dockProcess: { self.dock })
        }
    }

    @Test func aRequestOnTheCurrentSpaceDoesNothing() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        #expect(!switcher.request(10, on: "d"))
        #expect(fake.swipes.isEmpty)
    }

    @Test func batchedMovementGoesToTheTargetInOneSwipe() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        var landed = false
        #expect(switcher.request(13, on: "d") { landed = true })
        #expect(fake.swipes.count == 1)
        #expect(fake.swipes[0] == (1, 4))
        fake.current = 13
        switcher.poll()
        #expect(landed)
        #expect(!switcher.switching)
    }

    @Test func legacyMovementGoesOneDesktopAtATime() {
        let fake = Fake()
        let switcher = fake.switcher(batch: false)
        var landed = false
        switcher.request(12, on: "d") { landed = true }
        #expect(fake.swipes.map(\.1) == [2])
        fake.current = 11
        switcher.poll()
        #expect(fake.swipes.map(\.1) == [2, 3])
        #expect(!landed)
        fake.current = 12
        switcher.poll()
        #expect(landed)
    }

    @Test func aNewRequestRetargetsWithoutPostingAgainWhileOneIsInFlight() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        switcher.request(12, on: "d")
        switcher.request(11, on: "d")
        #expect(fake.swipes.count == 1)
        #expect(switcher.target(on: "d") == 11)
        fake.current = 12
        switcher.poll()
        #expect(fake.swipes.count == 2)
        #expect(fake.swipes[1] == (3, 2))
    }

    @Test func aFailedSwipeEndsTheRequest() {
        let fake = Fake()
        fake.accept = false
        let switcher = fake.switcher(batch: true)
        var settled = false
        switcher.onSettled = { _ in settled = true }
        switcher.request(12, on: "d")
        #expect(settled)
        #expect(!switcher.switching)
    }

    @Test func aRequestThatNeverLandsIsGivenUpButStaysOwned() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        var settled = false
        switcher.onSettled = { _ in settled = true }
        switcher.request(12, on: "d")
        fake.now = 3_000_000_000
        switcher.poll()
        #expect(settled)
        #expect(switcher.target(on: "d") == nil)
        #expect(switcher.destination(on: "d") == 12)
        #expect(switcher.switching)
        fake.current = 12
        switcher.poll()
        #expect(!switcher.switching)
    }

    @Test func aNewDockVoidsTheFlight() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        var settled = false
        switcher.onSettled = { _ in settled = true }
        switcher.request(12, on: "d")
        fake.dock = 2
        switcher.poll()
        #expect(settled)
        #expect(!switcher.switching)
    }

    @Test func aSpaceThatIsNotOnTheDisplayFails() {
        let fake = Fake()
        let switcher = fake.switcher(batch: true)
        var settled = false
        switcher.onSettled = { _ in settled = true }
        switcher.request(99, on: "d")
        #expect(settled)
        #expect(fake.swipes.isEmpty)
    }
}
