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
        #expect(EnglishLemmatizer.lemma(for: "family") == "family")
    }

    @Test func lyAdverbsRestoreBaseAdjective() {
        // Regression: bare strip of "ly" turned "humbly" into "humb".
        #expect(EnglishLemmatizer.lemma(for: "humbly") == "humble")
        #expect(EnglishLemmatizer.lemma(for: "simply") == "simple")
        #expect(EnglishLemmatizer.lemma(for: "happily") == "happy")
        #expect(EnglishLemmatizer.lemma(for: "possibly") == "possible")
        #expect(EnglishLemmatizer.lemma(for: "truly") == "true")
        #expect(EnglishLemmatizer.lemma(for: "quickly") == "quick")
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

struct YoudaoDictionaryParsingTests {
    @Test func parseJSONAPIEnglishChinese() throws {
        let json = """
        {"input":"apple","ec":{"word":[{"usphone":"ˈæp(ə)l","ukphone":"ˈæp(ə)l","trs":[{"tr":[{"l":{"i":["n. 苹果；苹果树"]}}]}]}]}}
        """.data(using: .utf8)!
        let parsed = try YoudaoDictionaryService.parseJSONAPI(data: json)
        #expect(parsed.chinese.contains("苹果"))
        #expect(parsed.phonetic.contains("æp"))
    }

    @Test func parseSuggest() throws {
        let json = """
        {"result":{"msg":"success","code":200},"data":{"entries":[{"explain":"n. 苹果","entry":"apple"}],"query":"apple"}}
        """.data(using: .utf8)!
        let parsed = try YoudaoDictionaryService.parseSuggest(data: json)
        #expect(parsed.chinese == "n. 苹果")
    }

    @Test func mockResultContainsKnownWord() {
        let result = YoudaoDictionaryService.mockResult(for: "memory")
        #expect(result.source == "mock")
        #expect(result.chinese.contains("记忆"))
        #expect(!result.phonetic.isEmpty)
    }
}
