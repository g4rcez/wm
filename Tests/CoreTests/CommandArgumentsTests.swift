import CoreGraphics
import Testing
@testable import Core

struct CommandArgumentsTests {
    @Test func resizeTakesADimensionASideOrADirection() throws {
        #expect(try CommandArguments.resize(["width", "+50"]).get() == .dimension(.width, 50))
        #expect(try CommandArguments.resize(["smart", "-20"]).get() == .dimension(.smart, -20))
        #expect(try CommandArguments.resize(["left", "+40"]).get() == .side(.left, 40))
        #expect(try CommandArguments.resize(["dir", "down", "30"]).get() == .direction(.down, 30))
    }

    @Test(arguments: [
        ["width"], ["width", "abc"], ["width", "nan"], ["width", "inf"], ["left", "-inf"], ["dir", "down", "-5"], ["dir", "down", "0"],
        ["dir", "down"], ["dir", "sideways", "5"], ["depth", "5"], ["width", "5", "6"], [],
    ])
    func resizeRefuses(words: [String]) {
        #expect(throws: UsageError.self) { try CommandArguments.resize(words).get() }
    }

    @Test func moveHasADefaultStep() throws {
        let plain = try CommandArguments.move(["left"]).get()
        #expect(plain.direction == .left && plain.step == 40)
        let far = try CommandArguments.move(["up", "120"]).get()
        #expect(far.direction == .up && far.step == 120)
    }

    @Test(arguments: [[], ["nowhere"], ["left", "0"], ["left", "-40"], ["left", "nan"], ["left", "1e999"], ["left", "1", "2"]])
    func moveRefuses(words: [String]) {
        #expect(throws: UsageError.self) { try CommandArguments.move(words).get() }
    }

    @Test func aRatioIsSetInItsRangeOrChanged() {
        #expect(CommandArguments.ratio("0.6", in: 0.1...0.9)! == (0.6, false))
        #expect(CommandArguments.ratio("+0.05", in: 0.1...0.9)! == (0.05, true))
        #expect(CommandArguments.ratio("-0.05", in: 0.1...0.9)! == (-0.05, true))
        #expect(CommandArguments.ratio("5", in: 0.1...0.9) == nil)
        #expect(CommandArguments.ratio("0", in: 0.1...0.9) == nil)
        #expect(CommandArguments.ratio("nan", in: 0.1...0.9) == nil)
        #expect(CommandArguments.ratio(nil, in: 0.1...0.9) == nil)
    }

    @Test func aFractionIsMoreThanZeroAndAtMostOne() {
        #expect(CommandArguments.fraction("0.5") == 0.5)
        #expect(CommandArguments.fraction("1") == 1)
        for text in ["0", "-0.5", "1.5", "nan", "inf", "x", ""] { #expect(CommandArguments.fraction(text) == nil) }
        #expect(CommandArguments.fraction(nil) == nil)
    }
}
