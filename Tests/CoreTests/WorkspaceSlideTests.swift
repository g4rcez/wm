import CoreGraphics
import Foundation
import Testing
@testable import Core

struct WorkspaceSlideTests {
    private let viewport = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let target = CGRect(x: 100, y: 50, width: 400, height: 300)
    private let all: Set<Direction> = [.left, .right, .down]

    @Test func numbersAreComparedByValueAndNamesInFinderOrder() {
        #expect(WorkspaceSlide.isForward(from: "2", to: "10"))
        #expect(!WorkspaceSlide.isForward(from: "10", to: "2"))
        #expect(WorkspaceSlide.isForward(from: "web", to: "work"))
        #expect(!WorkspaceSlide.isForward(from: "work", to: "web"))
        #expect(WorkspaceSlide.isForward(from: "1", to: "a"))
    }

    @Test func aLaterWorkspaceSlidesInFromTheRight() {
        let start = WorkspaceSlide.start(of: target, viewport: viewport, style: .slide, forward: true, freeEdges: all)
        #expect(start == CGRect(x: 999, y: 50, width: 400, height: 300))
    }

    @Test func anEarlierWorkspaceSlidesInFromTheLeft() {
        let start = WorkspaceSlide.start(of: target, viewport: viewport, style: .slide, forward: false, freeEdges: all)
        #expect(start == CGRect(x: -399, y: 50, width: 400, height: 300))
    }

    @Test func aSideWithANeighbourMonitorIsNotUsed() {
        let noRight = WorkspaceSlide.start(of: target, viewport: viewport, style: .slide, forward: true, freeEdges: [.left, .down])
        #expect(noRight == CGRect(x: -399, y: 50, width: 400, height: 300))
        let neither = WorkspaceSlide.start(of: target, viewport: viewport, style: .slide, forward: true, freeEdges: [.down])
        #expect(neither == nil)
    }

    @Test func slidevertComesFromTheBottomWhenItIsFree() {
        let start = WorkspaceSlide.start(of: target, viewport: viewport, style: .slidevert, forward: false, freeEdges: all)
        #expect(start == CGRect(x: 100, y: 799, width: 400, height: 300))
        let blocked = WorkspaceSlide.start(of: target, viewport: viewport, style: .slidevert, forward: true, freeEdges: [.left, .right])
        #expect(blocked == nil)
    }

    @Test func noneNeverSlides() {
        #expect(WorkspaceSlide.start(of: target, viewport: viewport, style: .none, forward: true, freeEdges: all) == nil)
    }

    @Test func aWindowAlreadyAtTheStartJumps() {
        let atEdge = CGRect(x: 999, y: 0, width: 100, height: 100)
        #expect(WorkspaceSlide.start(of: atEdge, viewport: viewport, style: .slide, forward: true, freeEdges: all) == nil)
    }
}
