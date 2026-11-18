import CoreGraphics
import Foundation
import Testing
@testable import Core

struct CustomTemplatesTests {
    @Test func aDrawnRectangleBecomesAFrameInsideTheScreen() {
        let frame = CustomTemplates.gridFrame(columns: 8, rows: 6, column: 2, row: 1, spanColumns: 4, spanRows: 3)
        #expect(frame?.name == "frame-2-1-4x3-of-8x6")
        #expect(frame?.area == CGRect(x: 0.25, y: 1.0 / 6, width: 0.5, height: 0.5))
        #expect(frame?.cells == [CGRect(x: 0, y: 0, width: 1, height: 1)])
        #expect(frame?.isFrame == true)
    }

    @Test func aFrameThatCoversTheWholeGridOrLeavesItIsRefused() {
        #expect(CustomTemplates.gridFrame(columns: 8, rows: 6, column: 0, row: 0, spanColumns: 8, spanRows: 6) == nil)
        #expect(CustomTemplates.gridFrame(columns: 8, rows: 6, column: 6, row: 0, spanColumns: 3, spanRows: 2) == nil)
        #expect(CustomTemplates.gridFrame(columns: 8, rows: 6, column: 0, row: 0, spanColumns: 0, spanRows: 2) == nil)
    }

    @Test func aFullWidthStripIsAValidFrame() {
        let frame = CustomTemplates.gridFrame(columns: 8, rows: 6, column: 0, row: 2, spanColumns: 8, spanRows: 2)!
        #expect(SplitTemplate.shapeError(frame.cells, area: frame.area) == nil)
    }

    @Test func addingTheSameFrameAgainMovesItToTheEnd() {
        let first = CustomTemplates.gridFrame(columns: 8, rows: 6, column: 1, row: 1, spanColumns: 2, spanRows: 2)!
        let second = CustomTemplates.gridFrame(columns: 8, rows: 6, column: 3, row: 1, spanColumns: 2, spanRows: 2)!
        #expect(CustomTemplates.adding(first, to: [first, second]) == [second, first])
    }

    @Test func theListKeepsOnlyTheNewestFrames() {
        var list: [SplitTemplate] = []
        for column in 0..<7 { for row in 0..<5 {
            list = CustomTemplates.adding(CustomTemplates.gridFrame(columns: 8, rows: 6, column: column, row: row, spanColumns: 1, spanRows: 1)!, to: list)
        } }
        #expect(list.count == 24)
        #expect(list.last?.name == "frame-6-4-1x1-of-8x6")
    }

    @Test func framesSurviveAWriteAndALoadAndBadEntriesAreDropped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wm-\(UUID().uuidString)/custom-templates.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let frame = CustomTemplates.gridFrame(columns: 8, rows: 6, column: 1, row: 1, spanColumns: 6, spanRows: 4)!
        let bad = SplitTemplate(name: "a b", cells: [SplitTemplate.unit], area: CGRect(x: 0.1, y: 0, width: 0.5, height: 1))
        try CustomTemplates.write([frame, bad, .two], to: url)
        #expect(CustomTemplates.load(from: url) == [frame])
    }

    @Test func aMissingFileGivesNoFrames() {
        #expect(CustomTemplates.load(from: URL(fileURLWithPath: "/nonexistent/wm/custom-templates.json")).isEmpty)
    }
}
