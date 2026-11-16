import CoreGraphics
import Testing
@testable import Core

private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

/// Windows 1...count, each opened beside the previous one.
private func make<E: LayoutEngine>(_ type: E.Type, _ count: Int) -> E {
    var engine = E(settings: Settings())
    for window in 0..<count { engine.insert(WindowID(window + 1), after: window == 0 ? nil : WindowID(window)) }
    return engine
}

private func rotate<E: LayoutEngine>(_ engine: inout E, clockwise: Bool = true) -> Bool {
    engine.perform(.rotate(clockwise: clockwise), focused: 1, in: context)
}

private func checkSameSlots<E: LayoutEngine>(_ type: E.Type, _ count: Int) {
    var engine = make(type, count)
    let before = engine.frames(in: context, focused: 1)
    #expect(rotate(&engine) == true)
    let after = engine.frames(in: context, focused: 1)
    #expect(after.count == count)
    #expect(before.values.allSatisfy { frame in after.values.contains(frame) })
}

private func checkMovesToNextSlot<E: LayoutEngine>(_ type: E.Type, _ count: Int, clockwise: Bool) {
    var engine = make(type, count)
    let before = engine.frames(in: context, focused: 1)
    let ring = clockwiseRing(before)
    #expect(rotate(&engine, clockwise: clockwise) == true)
    let after = engine.frames(in: context, focused: 1)
    for index in ring.indices {
        let next = ring[(index + 1) % count]
        // The window in slot `index` moves to slot `index + 1` (clockwise), or the window in slot `index + 1` to slot `index`.
        #expect(clockwise ? after[ring[index]] == before[next] : after[next] == before[ring[index]])
    }
}

private func checkOppositeCancel<E: LayoutEngine>(_ type: E.Type, _ count: Int) {
    var engine = make(type, count)
    let before = engine.frames(in: context, focused: 1)
    #expect(rotate(&engine, clockwise: true) == true)
    #expect(rotate(&engine, clockwise: false) == true)
    #expect(engine.frames(in: context, focused: 1) == before)
}

private func checkFullTurn<E: LayoutEngine>(_ type: E.Type, _ count: Int) {
    var engine = make(type, count)
    let before = engine.frames(in: context, focused: 1)
    for _ in 0..<count { #expect(rotate(&engine) == true) }
    #expect(engine.frames(in: context, focused: 1) == before)
}

private func checkNothingToRotate<E: LayoutEngine>(_ type: E.Type, _ count: Int) {
    var engine = make(type, count)
    let before = engine.frames(in: context, focused: 1)
    #expect(rotate(&engine) == false)
    #expect(rotate(&engine, clockwise: false) == false)
    #expect(engine.frames(in: context, focused: 1) == before)
}

struct RotateDwindleTests {
    @Test(arguments: [2, 3, 4]) func slotsStayTheSame(count: Int) { checkSameSlots(DwindleEngine.self, count) }
    @Test(arguments: [2, 3, 4], [true, false]) func windowsMoveToTheNextSlot(count: Int, clockwise: Bool) {
        checkMovesToNextSlot(DwindleEngine.self, count, clockwise: clockwise)
    }
    @Test(arguments: [2, 3, 4]) func oppositeRotationsCancel(count: Int) { checkOppositeCancel(DwindleEngine.self, count) }
    @Test(arguments: [2, 3, 4]) func aFullTurnIsTheIdentity(count: Int) { checkFullTurn(DwindleEngine.self, count) }
    @Test(arguments: [0, 1]) func fewerThanTwoWindowsDoNotRotate(count: Int) { checkNothingToRotate(DwindleEngine.self, count) }

    // 1 | 2
    //   | 3
    @Test func aSpiralOfThreeTurnsClockwise() {
        var engine = make(DwindleEngine.self, 3)
        #expect(rotate(&engine) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 500, y: 0, width: 500, height: 300),
            2: CGRect(x: 500, y: 300, width: 500, height: 300),
            3: CGRect(x: 0, y: 0, width: 500, height: 600),
        ])
    }

    @Test func rotatingKeepsTheSplitRatios() {
        var engine = make(DwindleEngine.self, 3)
        #expect(engine.perform(.resize(.width, 100), focused: 1, in: context) == true)
        let before = engine.frames(in: context, focused: 1)
        #expect(rotate(&engine) == true)
        #expect(engine.frames(in: context, focused: 1)[3] == before[1])
    }
}
