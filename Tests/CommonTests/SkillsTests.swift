import Testing
@testable import Common

struct SkillsTests {
    @Test func theSkillHasTheFrontmatterOfASkillFile() {
        let lines = renderSkill().split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "---")
        #expect(lines.contains("name: wm"))
        #expect(lines.contains { $0.hasPrefix("description: ") })
        #expect(lines.dropFirst().contains("---"))
    }

    @Test func everyCommandIsListedWithItsUsage() {
        let text = renderSkill()
        for spec in commandSpecs { #expect(text.contains("`\(spec.usage)`"), "missing \(spec.path)") }
    }
}
