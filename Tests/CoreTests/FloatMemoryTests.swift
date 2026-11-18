import Foundation
import Testing
@testable import Core

struct FloatMemoryTests {
    private func place(_ app: String, _ title: String, x: Double = 0.1) -> LastFloatFrame {
        LastFloatFrame(app: app, title: title, frame: RelativeFrame(x: x, y: 0.2, width: 0.3, height: 0.4), monitor: "LG")
    }

    @Test func aWindowOpensWhereTheLastOneOfTheSameTitleClosed() {
        var memory = FloatMemory()
        memory.record(place("meet", "Meet - Class", x: 0.7))
        memory.record(place("meet", "Other", x: 0.2))
        #expect(memory.last(app: "meet", title: "Meet - Class")?.frame.x == 0.7)
    }

    @Test func aTitleThatWasNeverSeenGetsTheLastPlaceOfTheApp() {
        var memory = FloatMemory()
        memory.record(place("finder", "Recents", x: 0.1))
        memory.record(place("finder", "Downloads", x: 0.5))
        #expect(memory.last(app: "finder", title: "Documents")?.frame.x == 0.5)
    }

    @Test func anotherAppNeverMatches() {
        var memory = FloatMemory()
        memory.record(place("finder", "Recents"))
        #expect(memory.last(app: "preview", title: "Recents") == nil)
    }

    @Test func aNewPlaceReplacesTheOldOneOfTheSameWindow() {
        var memory = FloatMemory()
        memory.record(place("finder", "Recents", x: 0.1))
        memory.record(place("finder", "Recents", x: 0.6))
        #expect(memory.frames.count == 1)
        #expect(memory.last(app: "finder", title: "Recents")?.frame.x == 0.6)
    }

    @Test func theOldestPlacesAreDroppedAfterTheLimit() {
        var memory = FloatMemory()
        for index in 0..<(FloatMemory.limit + 5) { memory.record(place("app", "w\(index)")) }
        #expect(memory.frames.count == FloatMemory.limit)
        #expect(memory.frames.first?.title == "w5")
        #expect(memory.last(app: "app", title: "w0")?.title == "w204")
    }

    @Test func theMemoryComesBackFromItsFile() throws {
        var memory = FloatMemory()
        memory.record(place("finder", "Recents", x: 0.25))
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(FloatMemory.self, from: data) == memory)
    }
}
