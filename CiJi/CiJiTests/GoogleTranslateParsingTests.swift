import Foundation
import Testing
@testable import CiJi

struct GoogleTranslateParsingTests {
    @Test func parseSimpleTranslationArray() throws {
        let json = """
        [[["苹果","apple",null,null,10]],null,"en"]
        """.data(using: .utf8)!

        let parsed = try GoogleTranslateService.parseResponse(data: json, query: "apple")
        #expect(parsed.chinese == "苹果")
    }

    @Test func parseDictionaryCombinedWithTranslation() throws {
        let json = """
        [
          [[["苹果","apple",null,null,10]]],
          [
            ["noun",["苹果","苹"],null,"apple",1]
          ],
          "en"
        ]
        """.data(using: .utf8)!

        let parsed = try GoogleTranslateService.parseResponse(data: json, query: "apple")
        #expect(parsed.chinese.contains("苹果"))
        #expect(parsed.chinese.contains("noun"))
    }

    @Test func mockResultContainsKnownWord() {
        let result = GoogleTranslateService.mockResult(for: "memory")
        #expect(result.source == "mock")
        #expect(result.chinese.contains("记忆"))
        #expect(!result.phonetic.isEmpty)
    }
}
