import CoreGraphics
import Testing
@testable import Core

struct SplitTemplateTests {
    @Test func windowCountsMatchTheNames() {
        #expect(SplitTemplate.allCases.map(\.count) == [2, 3, 4, 5, 6, 3, 3, 2, 2, 2])
    }

    @Test func stackLeftHasTwoStackedOnTheLeftAndOneTallOnTheRight() {
        #expect(SplitTemplate.stackLeft.cells == [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ])
    }

    @Test func stackRightHasOneTallOnTheLeftAndTwoStackedOnTheRight() {
        #expect(SplitTemplate.stackRight.cells == [
            CGRect(x: 0, y: 0, width: 0.5, height: 1),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    }

    @Test func fiveStretchesTheLastRowToFillTheWidth() {
        let cells = SplitTemplate.five.cells
        #expect(cells.count == 5)
        #expect(cells[3] == CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(cells[4] == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test func sixIsTwoRowsOfThree() {
        #expect(SplitTemplate.six.cells[2] == CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 0.5))
        #expect(SplitTemplate.six.cells[3] == CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5))
    }

    @Test func theFocusedWindowTakesTwoThirdsOrThreeQuartersAndTheNextTheRest() {
        #expect(SplitTemplate.twoThirds.cells == [
            CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        ])
        #expect(SplitTemplate.threeQuarters.cells == [
            CGRect(x: 0, y: 0, width: 0.75, height: 1), CGRect(x: 0.75, y: 0, width: 0.25, height: 1),
        ])
    }

    @Test func oneQuarterIsTheMirrorOfThreeQuarters() {
        #expect(SplitTemplate.oneQuarter.cells == [
            CGRect(x: 0, y: 0, width: 0.25, height: 1), CGRect(x: 0.25, y: 0, width: 0.75, height: 1),
        ])
    }

    @Test func everyTemplateHasAOneCharacterPickerKeyNumbersFirst() {
        #expect(SplitTemplate.allCases.map(\.key) == ["2", "3", "4", "5", "6", "l", "r", "t", "q", "w"])
    }

    @Test func everyTemplateFillsTheWholeAreaExactly() {
        for template in SplitTemplate.allCases {
            let area = template.cells.reduce(0.0) { $0 + Double($1.width * $1.height) }
            #expect(abs(area - 1) < 1e-9)
        }
    }

    @Test func namesRoundTrip() {
        #expect(SplitTemplate(rawValue: "2+1") == .stackLeft)
        #expect(SplitTemplate(rawValue: "1+2") == .stackRight)
        #expect(SplitTemplate(rawValue: "2/3") == .twoThirds)
        #expect(SplitTemplate(rawValue: "3/4") == .threeQuarters)
        #expect(SplitTemplate(rawValue: "1/4") == .oneQuarter)
        #expect(SplitTemplate(rawValue: "7") == nil)
    }
}
