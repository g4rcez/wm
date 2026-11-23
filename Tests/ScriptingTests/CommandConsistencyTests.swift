import Common
import Core
import Foundation
import Testing

/// The command table (`CommandSpec`), the places that run the commands and the shell completion each keep their own list of words.
/// These tests fail when the lists drift apart.
struct CommandConsistencyTests {
    private func repositoryFile(_ path: String) throws -> String {
        // Tests/ScriptingTests/CommandConsistencyTests.swift -> the repository root.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func completed(_ words: [String]) -> Set<String> {
        guard case let .candidates(list) = complete(words) else { return [] }
        return Set(list.map(\.word))
    }

    /// Textual on purpose: `App` has no test target. It catches a command in the table that nothing runs, not a wrong handler.
    @Test func everyCommandInTheTableHasAHandler() throws {
        let daemon = try repositoryFile("Sources/App/Controller.swift") + (try repositoryFile("Sources/App/Commands.swift"))
        let cli = try repositoryFile("Sources/Cli/main.swift")
        // A word is handled when a `case` line of the daemon names it (`case "hints", "scroll":`), or the CLI runs it itself.
        let caseLines = daemon.split(separator: "\n").filter { $0.contains("case \"") }
        let missing = commandNames.sorted().filter { word in
            !caseLines.contains { $0.contains("\"\(word)\"") } && !cli.contains("arguments.first == \"\(word)\"")
                && !cli.contains("[\"\(word)\"")
        }
        #expect(missing.isEmpty, "no handler found for: \(missing)")
    }

    @Test func layoutNamesAreCompletedFromTheLayoutKinds() {
        let layouts = Set(LayoutKind.allCases.map(\.rawValue))
        #expect(completed(["layout", "set", ""]) == layouts)
        #expect(completed(["workspace", "all", ""]) == layouts)
    }

    @Test func snapPlacesAreCompletedFromTheSnapPlaces() {
        #expect(completed(["window", "snap", ""]) == Set(SnapPlace.allCases.map(\.rawValue)))
    }

    @Test func directionsAreCompletedFromTheDirections() {
        let directions = Set(Direction.allCases.map(\.rawValue))
        #expect(directions.isSubset(of: completed(["focus", ""])))
        #expect(directions.isSubset(of: completed(["swap", ""])))
    }
}
