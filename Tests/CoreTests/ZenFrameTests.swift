import CoreGraphics
import Testing
@testable import Core

struct ZenFrameTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func theWindowIsCenteredWithTheWidthAndTheWholeHeight() {
        #expect(zenFrame(in: area, width: 0.7) == CGRect(x: 150, y: 0, width: 700, height: 800))
    }

    @Test func theAreaCanStartAnywhere() {
        #expect(zenFrame(in: CGRect(x: 100, y: 50, width: 1000, height: 800), width: 0.5) == CGRect(x: 350, y: 50, width: 500, height: 800))
    }

    @Test func theWidthStaysBetweenAThirdAndTheWholeArea() {
        #expect(zenFrame(in: area, width: 0.1) == CGRect(x: 350, y: 0, width: 300, height: 800))
        #expect(zenFrame(in: area, width: 2) == area)
    }
}
