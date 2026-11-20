import CoreGraphics
import Foundation
import Testing
@testable import Core

struct BorderGradientTests {
    private func near(_ a: CGPoint, _ x: Double, _ y: Double) -> Bool { abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9 }

    @Test(arguments: [
        (0.0, (0.5, 0.0), (0.5, 1.0)),
        (90.0, (0.0, 0.5), (1.0, 0.5)),
        (180.0, (0.5, 1.0), (0.5, 0.0)),
        (270.0, (1.0, 0.5), (0.0, 0.5)),
        (45.0, (0.0, 0.0), (1.0, 1.0)),
        (225.0, (1.0, 1.0), (0.0, 0.0)),
        (-90.0, (1.0, 0.5), (0.0, 0.5)),
        (360.0, (0.5, 0.0), (0.5, 1.0)),
    ])
    func theLineRunsClockwiseFromUp(angle: Double, start: (Double, Double), end: (Double, Double)) {
        let points = BorderGradient.points(angle: angle)
        #expect(near(points.start, start.0, start.1))
        #expect(near(points.end, end.0, end.1))
    }

    @Test func theCornersGetTheFirstAndTheLastColor() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        for angle in stride(from: 0.0, through: 360.0, by: 15.0) {
            let (start, end) = BorderGradient.points(angle: angle)
            let line = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let length = line.x * line.x + line.y * line.y
            // Where each corner falls along the line: 0 at the start, 1 at the end.
            let along = corners.map { ((($0.x - start.x) * line.x) + (($0.y - start.y) * line.y)) / length }
            #expect(abs(along.min()! - 0) < 1e-9, "angle \(angle)")
            #expect(abs(along.max()! - 1) < 1e-9, "angle \(angle)")
        }
    }
}
