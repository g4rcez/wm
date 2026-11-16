import Testing
@testable import Common

struct TableTests {
    @Test func columnsAlignUnderTheHeader() {
        let text = renderTable(["", "id", "app"], [["*", "7", "Safari"], ["", "1475", "Yab"]])
        #expect(text == """
           ID    APP
        *  7     Safari
           1475  Yab

        """)
    }

    @Test func noRowsGiveNoOutput() {
        #expect(renderTable(["id", "app"], []) == "")
    }

    @Test func theLastColumnHasNoTrailingBlanks() {
        #expect(renderTable(["id", "state"], [["7", ""]]) == "ID  STATE\n7\n")
    }

    @Test func longTextIsCutWithAnEllipsis() {
        #expect(truncated("abcdefghij", to: 5) == "abcd…")
        #expect(truncated("abc", to: 5) == "abc")
    }
}
