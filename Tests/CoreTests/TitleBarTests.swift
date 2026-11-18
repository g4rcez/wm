import CoreGraphics
import Testing
@testable import Core

struct TitleBarTests {
    private let window = CGRect(x: 100, y: 200, width: 800, height: 600)

    @Test func theTopStripOfTheWindowIsTheTitleBar() {
        #expect(titleBarContains(CGPoint(x: 300, y: 210), frame: window, height: 40))
        #expect(titleBarContains(CGPoint(x: 100, y: 200), frame: window, height: 40))
    }

    @Test func belowTheStripOrOutsideTheWindowIsNotTheTitleBar() {
        #expect(!titleBarContains(CGPoint(x: 300, y: 240), frame: window, height: 40))
        #expect(!titleBarContains(CGPoint(x: 300, y: 199), frame: window, height: 40))
        #expect(!titleBarContains(CGPoint(x: 900, y: 210), frame: window, height: 40))
    }

    @Test func aStripTallerThanTheWindowStopsAtTheWindow() {
        let small = CGRect(x: 0, y: 0, width: 100, height: 30)
        #expect(!titleBarContains(CGPoint(x: 10, y: 35), frame: small, height: 200))
    }
}
