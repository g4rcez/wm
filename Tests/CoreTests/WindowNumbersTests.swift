import CoreGraphics
import XCTest

@testable import Core

final class WindowNumbersTests: XCTestCase {
    private func frames(_ count: Int) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        for index in 0..<count { result[WindowID(100 + index)] = CGRect(x: 0, y: Double(index) * 10, width: 5, height: 5) }
        return result
    }

    func testNumbersGoLeftToRightOverDisplaysThenInReadingOrder() {
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let numbers = WindowNumbers(
            frames: [
                1: CGRect(x: 1100, y: 0, width: 100, height: 100),
                2: CGRect(x: 600, y: 400, width: 100, height: 100),
                3: CGRect(x: 100, y: 0, width: 100, height: 100),
                4: CGRect(x: 100, y: 400, width: 100, height: 100),
            ], displays: [right, left])
        XCTAssertEqual(numbers.numbers, [3: 1, 4: 2, 2: 3, 1: 4])
    }

    func testOneDigitPicksAtOnceWithNineWindows() {
        var numbers = WindowNumbers(frames: frames(9), displays: [])
        XCTAssertEqual(numbers.press("1"), .pick(100))
        XCTAssertEqual(numbers.press("9"), .pick(108))
    }

    func testAPrefixWaitsForTheNextDigit() {
        var numbers = WindowNumbers(frames: frames(11), displays: [])
        XCTAssertEqual(numbers.press("1"), .pending)
        XCTAssertEqual(numbers.press("0"), .pick(109))
    }

    func testReturnPicksTheShorterNumber() {
        var numbers = WindowNumbers(frames: frames(11), displays: [])
        XCTAssertEqual(numbers.press("1"), .pending)
        XCTAssertEqual(numbers.confirm(), .pick(100))
        XCTAssertEqual(numbers.typed, "")
    }

    func testBackspaceUndoesADigit() {
        var numbers = WindowNumbers(frames: frames(11), displays: [])
        _ = numbers.press("1")
        numbers.deleteLast()
        XCTAssertEqual(numbers.typed, "")
        XCTAssertEqual(numbers.press("2"), .pick(101))
    }

    func testZeroAndLettersAreNotNumbers() {
        var numbers = WindowNumbers(frames: frames(11), displays: [])
        XCTAssertEqual(numbers.press("0"), .ignored)
        XCTAssertEqual(numbers.press("a"), .ignored)
    }

    func testANumberOfNoWindowDoesNothing() {
        var numbers = WindowNumbers(frames: frames(3), displays: [])
        XCTAssertEqual(numbers.press("7"), .pending)
        XCTAssertEqual(numbers.typed, "")
    }
}
