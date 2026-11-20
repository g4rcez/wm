import Foundation
import Testing
@testable import Core

struct WallpaperPlanTests {
    private let wallpapers = ["1": "/w/one.jpg", "code": "/w/code.heic", "special:term": "/w/term.png"]

    @Test func aNormalWorkspaceUsesItsOwnWallpaper() {
        #expect(WallpaperPlan.path(workspace: "code", special: nil, in: wallpapers) == "/w/code.heic")
    }

    @Test func aSpecialWorkspaceWinsOverTheNormalOne() {
        #expect(WallpaperPlan.path(workspace: "1", special: "special:term", in: wallpapers) == "/w/term.png")
    }

    @Test func aSpecialWorkspaceWithoutOneLeavesTheNormalWallpaper() {
        #expect(WallpaperPlan.path(workspace: "1", special: "special:notes", in: wallpapers) == "/w/one.jpg")
    }

    @Test func aWorkspaceWithoutOneHasNone() {
        #expect(WallpaperPlan.path(workspace: "9", special: nil, in: wallpapers) == nil)
    }
}
