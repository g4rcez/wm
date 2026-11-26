import Testing
@testable import Core

struct AnimationStatsTests {
    @Test func ticksGiveCountMeanMaximumAndSlowCount() {
        var stats = AnimationStats()
        stats.tick(interval: 0.016)
        stats.tick(interval: 0.018)
        stats.tick(interval: 0.030)

        #expect(stats.summary.contains("ticks=3 mean=21.3ms max=30.0ms slow=1"))
    }

    @Test func framesAreCounted() {
        var stats = AnimationStats()
        stats.offered()
        stats.offered()
        stats.offered()
        stats.written()
        stats.written()
        stats.replaced()

        #expect(stats.summary.contains("offered=3 written=2 replaced=1"))
    }

    @Test func writeTimesAreGroupedByApp() {
        var stats = AnimationStats()
        stats.write(app: "Finder", seconds: 0.002)
        stats.write(app: "Finder", seconds: 0.004)
        stats.write(app: "Spotify", seconds: 0.020)

        #expect(stats.summary.contains("Finder n=2 avg=3.0ms max=4.0ms"))
        #expect(stats.summary.contains("Spotify n=1 avg=20.0ms max=20.0ms"))
    }

    @Test func mainThreadWorkAndRelayoutsAreTimed() {
        var stats = AnimationStats()
        #expect(!stats.summary.contains("work"))
        stats.work(seconds: 0.001)
        stats.work(seconds: 0.003)
        stats.relayout(seconds: 0.004)
        #expect(stats.summary.contains("work avg=2.0ms max=3.0ms"))
        #expect(stats.summary.contains("relayouts=1 avg=4.0ms max=4.0ms"))
    }

    @Test func resetClearsEverything() {
        var stats = AnimationStats()
        stats.tick(interval: 0.5)
        stats.offered()
        stats.write(app: "Finder", seconds: 0.002)
        stats.reset()

        #expect(stats == AnimationStats())
    }

    @Test func emptyStatsHaveZeroValues() {
        #expect(AnimationStats().summary == "ticks=0 mean=0.0ms max=0.0ms slow=0 offered=0 written=0 replaced=0")
    }
}
