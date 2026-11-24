import CoreGraphics
import Foundation
import Testing
@testable import Core

struct SplitTemplateTests {
    @Test func windowCountsMatchTheNames() {
        #expect(SplitTemplate.allCases.map(\.count) == [2, 3, 4, 5, 6, 3, 3, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3])
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
        #expect(SplitTemplate.allCases.map(\.key) == ["2", "3", "4", "5", "6", "l", "r", "t", "q", "w", "v", "h", "y", "n", "j", "m", "u", "o"])
    }

    @Test func everyTemplateFillsTheWholeAreaExactly() {
        for template in SplitTemplate.allCases {
            let area = template.cells.reduce(0.0) { $0 + Double($1.width * $1.height) }
            #expect(abs(area - 1) < 1e-9)
        }
    }

    @Test func builtInTemplatesAreFoundByName() {
        #expect(SplitTemplate.builtIn(named: "2+1") == .stackLeft)
        #expect(SplitTemplate.builtIn(named: "1+2") == .stackRight)
        #expect(SplitTemplate.builtIn(named: "2/3") == .twoThirds)
        #expect(SplitTemplate.builtIn(named: "3/4") == .threeQuarters)
        #expect(SplitTemplate.builtIn(named: "1/4") == .oneQuarter)
        #expect(SplitTemplate.builtIn(named: "7") == nil)
    }

    @Test func everyBuiltInTemplateHasAValidShape() {
        for template in SplitTemplate.allCases {
            #expect(SplitTemplate.shapeError(template.cells) == nil)
        }
    }

    @Test func theCenteredFrameHasAValidShapeAndIsBuiltInForTiling() {
        #expect(SplitTemplate.shapeError(SplitTemplate.centered.cells, area: SplitTemplate.centered.area) == nil)
        #expect(SplitTemplate.centered.isFrame)
        #expect(SplitTemplate.builtIn(named: "center") == .centered)
        #expect(SplitTemplate.tilingCases.last == .centered)
        #expect(!SplitTemplate.allCases.contains(.centered))
    }

    @Test func aFrameNeedsOneUnitCellAndASmallerArea() {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let middle = CGRect(x: 0.2, y: 0, width: 0.6, height: 1)
        #expect(SplitTemplate.shapeError([unit], area: middle) == nil)
        #expect(SplitTemplate.shapeError([unit]) == "a template needs at least two cells")
        #expect(SplitTemplate.shapeError([CGRect(x: 0, y: 0, width: 0.5, height: 1)], area: middle)
            == "a template with one cell and an area needs the cell { 0, 0, 1, 1 }")
        #expect(SplitTemplate.shapeError([unit], area: CGRect(x: 0.5, y: 0, width: 0.8, height: 1))
            == "the area needs a positive size and must stay inside 0 to 1")
    }

    @Test func aTemplateKeepsItsAreaThroughJSONAndAnOldOneHasNone() throws {
        let data = try JSONEncoder().encode(SplitTemplate.centered)
        #expect(try JSONDecoder().decode(SplitTemplate.self, from: data) == .centered)
        var object = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(SplitTemplate.two)) as? [String: Any])
        object["area"] = nil
        let old = try JSONDecoder().decode(SplitTemplate.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.area == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func shapeErrorsNameTheProblem() {
        let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        #expect(SplitTemplate.shapeError([left]) == "a template needs at least two cells")
        #expect(SplitTemplate.shapeError([left, CGRect(x: 0.5, y: 0, width: 0.6, height: 1)])
            == "every cell needs a positive size and must stay inside 0 to 1")
        // A gap in the middle.
        #expect(SplitTemplate.shapeError([left, CGRect(x: 0.6, y: 0, width: 0.4, height: 1)])
            == "the cells must fill the screen with straight cuts and no overlap")
        // An overlap that makes up for a gap, so the areas add up to 1.
        #expect(SplitTemplate.shapeError([CGRect(x: 0, y: 0, width: 0.6, height: 1), CGRect(x: 0.5, y: 0, width: 0.4, height: 1), CGRect(x: 0.9, y: 0, width: 0.1, height: 0.5)])
            == "the cells must fill the screen with straight cuts and no overlap")
        // A pinwheel has no straight cut through the whole area.
        #expect(SplitTemplate.shapeError([
            CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1.0 / 3), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 2.0 / 3),
            CGRect(x: 1.0 / 3, y: 2.0 / 3, width: 2.0 / 3, height: 1.0 / 3), CGRect(x: 0, y: 1.0 / 3, width: 1.0 / 3, height: 2.0 / 3),
            CGRect(x: 1.0 / 3, y: 1.0 / 3, width: 1.0 / 3, height: 1.0 / 3),
        ]) == "the cells must fill the screen with straight cuts and no overlap")
    }

    @Test func aCustomTemplateRoundTripsThroughJSON() throws {
        let template = SplitTemplate(
            name: "70/30", key: "s", title: "Focus 70%",
            cells: [CGRect(x: 0, y: 0, width: 0.7, height: 1), CGRect(x: 0.7, y: 0, width: 0.3, height: 1)])

        let decoded = try JSONDecoder().decode(SplitTemplate.self, from: JSONEncoder().encode(template))

        #expect(decoded == template)
    }

    @Test func aSavedStateWithTheOldNameOfABuiltInTemplateStillLoads() throws {
        #expect(try JSONDecoder().decode(SplitTemplate.self, from: Data("\"2+1\"".utf8)) == .stackLeft)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SplitTemplate.self, from: Data("\"9\"".utf8)) }
    }

    @Test func fitFindsTheTiledPartForFewerWindows() {
        let four = SplitTemplate.four.fit(2)
        #expect(four?.cells == [0, 1])
        #expect(four?.bounds == CGRect(x: 0, y: 0, width: 1, height: 0.5))
        let left = SplitTemplate.stackLeft.fit(2)
        #expect(left?.cells == [0, 1])
        #expect(left?.bounds == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(SplitTemplate.six.fit(3)?.bounds == CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(SplitTemplate.twoThirds.fit(1)?.cells == [0])
        #expect(SplitTemplate.stackRight.fit(2) == nil)
        #expect(SplitTemplate.two.fit(2) == nil)
        #expect(SplitTemplate.centered.fit(1) == nil)
    }
}
