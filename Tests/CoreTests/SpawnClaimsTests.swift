import Foundation
import Testing
@testable import Core

struct SpawnClaimsTests {
    /// Process 10 is a child of 1, and 20 a child of 10. Nothing else is related.
    private let tree: [Int32: Int32] = [20: 10, 10: 1]

    private func isDescendant(_ pid: Int32, of ancestor: Int32) -> Bool {
        var current = pid
        while true {
            if current == ancestor { return true }
            guard let parent = tree[current] else { return false }
            current = parent
        }
    }

    private func take(_ claims: inout SpawnClaims<String>, pid: Int32, app: String = "com.example.app", name: String = "Example", at now: TimeInterval = 0) -> String? {
        claims.take(pid: pid, bundleID: app, appName: name, now: now, isDescendant: isDescendant)
    }

    @Test func aWindowOfAChildProcessTakesTheClaim() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 10, app: nil, value: "float", timeout: 15, now: 0)
        let first = take(&claims, pid: 20)
        let second = take(&claims, pid: 20)
        #expect(first == "float")
        #expect(second == nil)
    }

    @Test func aWindowOfAnotherProcessDoesNot() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 10, app: nil, value: "float", timeout: 15, now: 0)
        let taken = take(&claims, pid: 99)
        #expect(taken == nil)
        #expect(claims.count == 1)
    }

    @Test func aClaimThatNamesAnAppIsTakenByAWindowOfThatApp() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 10, app: "Notes", value: "center", timeout: 15, now: 0)
        let other = take(&claims, pid: 99, name: "Mail")
        let same = take(&claims, pid: 99, name: "notes")
        #expect(other == nil)
        #expect(same == "center")
    }

    @Test func theAppMayBeABundleId() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 10, app: "com.apple.Notes", value: "center", timeout: 15, now: 0)
        let taken = take(&claims, pid: 99, app: "COM.APPLE.NOTES")
        #expect(taken == "center")
    }

    @Test func aClaimByProcessBeatsAnOlderClaimByApp() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 50, app: "Example", value: "by app", timeout: 15, now: 0)
        claims.add(pid: 10, app: nil, value: "by process", timeout: 15, now: 0)
        let first = take(&claims, pid: 20)
        let second = take(&claims, pid: 20)
        #expect(first == "by process")
        #expect(second == "by app")
    }

    @Test func aClaimExpires() {
        var claims = SpawnClaims<String>()
        claims.add(pid: 10, app: nil, value: "float", timeout: 5, now: 100)
        let taken = take(&claims, pid: 20, at: 105.5)
        #expect(taken == nil)
        #expect(claims.count == 0)
    }

    @Test func expireByIdDropsOnlyAClaimThatIsStillWaiting() {
        var claims = SpawnClaims<String>()
        let first = claims.add(pid: 10, app: nil, value: "a", timeout: 15, now: 0)
        let second = claims.add(pid: 11, app: nil, value: "b", timeout: 15, now: 0)
        let dropped = claims.expire(id: first)
        let droppedAgain = claims.expire(id: first)
        #expect(dropped)
        #expect(!droppedAgain)
        #expect(claims.count == 1)
        let taken = take(&claims, pid: 11)
        let late = claims.expire(id: second)
        #expect(taken == "b")
        #expect(!late)
    }
}
