import Foundation
import Testing

@testable import Common

struct VersionTests {
    @Test func theVersionIsThreeNumbers() {
        #expect(wmVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil, "\(wmVersion)")
    }
}
