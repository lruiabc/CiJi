import Foundation
import Testing
@testable import CiJi

struct EnglishLemmatizerTests {
    @Test func irregularVerbs() {
        #expect(EnglishLemmatizer.lemma(for: "went") == "go")
        #expect(EnglishLemmatizer.lemma(for: "running") == "run")
        #expect(EnglishLemmatizer.lemma(for: "better") == "good")
        #expect(EnglishLemmatizer.lemma(for: "children") == "child")
        #expect(EnglishLemmatizer.lemma(for: "leaves") == "leaf")
        #expect(EnglishLemmatizer.lemma(for: "left") == "leave")
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

struct IPAPhoneticServiceTests {
    @Test func arpabetIntentionalToDJIPA() {
        let ipa = IPAPhoneticService.arpabetToDJIPA("IH0 N T EH1 N SH AH0 N AH0 L")
        #expect(ipa == "/ɪnˈtenʃənəl/")
    }

    @Test func arpabetApple() {
        #expect(IPAPhoneticService.arpabetToDJIPA("AE1 P AH0 L") == "/ˈæpəl/")
    }

    @Test func arpabetRun() {
        #expect(IPAPhoneticService.arpabetToDJIPA("R AH1 N") == "/ˈrʌn/")
    }

    @Test func rejectsGoogleRomanization() {
        #expect(IPAPhoneticService.isPlausibleIPA("/ten(t)SH(ə)nəl/") == false)
        #expect(IPAPhoneticService.isPlausibleIPA("/ɪnˈtenʃənəl/") == true)
    }

    @Test func extractFreeDictionaryIPA() {
        let json = """
        [{"word":"apple","phonetic":"/ˈæp.əl/","phonetics":[{"text":"/ˈæp.əl/","audio":""}]}]
        """.data(using: .utf8)!
        #expect(IPAPhoneticService.extractFreeDictionaryIPA(from: json) == "/ˈæp.əl/")
    }

    @Test func extractDatamuseARPABET() {
        let json = """
        [{"word":"intentional","score":1,"tags":["pron:IH0 N T EH1 N SH AH0 N AH0 L "]}]
        """.data(using: .utf8)!
        let ipa = IPAPhoneticService.extractDatamuseARPABET(from: json, word: "intentional")
        #expect(ipa == "/ɪnˈtenʃənəl/")
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

    @Test func mockResultContainsKnownWord() {
        let result = GoogleTranslateService.mockResult(for: "memory")
        #expect(result.source == "mock")
        #expect(result.chinese.contains("记忆"))
        #expect(!result.phonetic.isEmpty)
    }
}
