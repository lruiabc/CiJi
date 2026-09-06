import Foundation
import Testing
@testable import CiJi

struct EnglishLemmatizerTests {
    @Test func irregularVerbs() {
        #expect(EnglishLemmatizer.lemma(for: "went") == "go")
        #expect(EnglishLemmatizer.lemma(for: "running") == "run")
        #expect(EnglishLemmatizer.lemma(for: "better") == "good")
        #expect(EnglishLemmatizer.lemma(for: "children") == "child")
    }

    @Test func regularInflections() {
        #expect(EnglishLemmatizer.lemma(for: "apples") == "apple")
        #expect(EnglishLemmatizer.lemma(for: "studied") == "study")
        #expect(EnglishLemmatizer.lemma(for: "cities") == "city")
        #expect(EnglishLemmatizer.lemma(for: "cats") == "cat")
    }

    @Test func alreadyLemmaUnchanged() {
        #expect(EnglishLemmatizer.lemma(for: "apple") == "apple")
        #expect(EnglishLemmatizer.lemma(for: "vocabulary") == "vocabulary")
    }
}

struct GoogleTranslateParsingTests {
    @Test func parseSimpleTranslationArray() throws {
        let json = """
        [[["苹果","apple",null,null,10]],null,"en"]
        """.data(using: .utf8)!

        let parsed = try GoogleTranslateService.parseResponse(data: json, query: "apple")
        #expect(parsed.chinese == "苹果")
    }

    @Test func extractPhoneticFromEnEnResponse() {
        // Shape observed from Google en→en + dt=rm
        let json = """
        [[["apple","apple",null,null,5],[null,null,null,"ˈap(ə)l"]],null,"en"]
        """.data(using: .utf8)!

        let phonetic = GoogleTranslateService.extractPhonetic(from: json, query: "apple")
        #expect(phonetic == "/ˈap(ə)l/")
    }

    @Test func mockResultContainsKnownWord() {
        let result = GoogleTranslateService.mockResult(for: "memory")
        #expect(result.source == "mock")
        #expect(result.chinese.contains("记忆"))
        #expect(!result.phonetic.isEmpty)
    }
}
