import Foundation
import Testing
@testable import CiJi

struct YoudaoSignTests {
    @Test func inputForSignUsesFullQueryWhenShort() {
        #expect(YoudaoDictionaryService.inputForSign("apple") == "apple")
    }

    @Test func inputForSignTruncatesLongQuery() {
        let q = String(repeating: "a", count: 25)
        let input = YoudaoDictionaryService.inputForSign(q)
        #expect(input == "aaaaaaaaaa25aaaaaaaaaa")
    }

    @Test func signIsStableSHA256Hex() {
        let sign = YoudaoDictionaryService.sign(
            appKey: "key",
            query: "hello",
            salt: "salt",
            curtime: "123",
            appSecret: "secret"
        )
        #expect(sign.count == 64)
        #expect(
            sign == YoudaoDictionaryService.sign(
                appKey: "key",
                query: "hello",
                salt: "salt",
                curtime: "123",
                appSecret: "secret"
            )
        )
    }
}

struct YoudaoFieldParsingTests {
    @Test func pickChinesePrefersExplainsOverTranslation() {
        let response = YoudaoAPIResponse(
            errorCode: "0",
            translation: ["好"],
            basic: YoudaoBasic(
                phonetic: "gʊd",
                usPhonetic: "ɡʊd",
                ukPhonetic: "gʊd",
                explains: ["adj. 好的；优良的", "n. 好处"]
            ),
            query: "good",
            web: nil
        )
        let chinese = YoudaoDictionaryService.pickChinese(from: response)
        #expect(chinese == "adj. 好的；优良的；n. 好处")
    }

    @Test func pickChineseFallsBackToTranslation() {
        let response = YoudaoAPIResponse(
            errorCode: "0",
            translation: ["你好", "您好"],
            basic: nil,
            query: "hello",
            web: nil
        )
        let chinese = YoudaoDictionaryService.pickChinese(from: response)
        #expect(chinese == "你好；您好")
    }

    @Test func pickPhoneticPrefersPrimaryThenUS() {
        let basic = YoudaoBasic(phonetic: nil, usPhonetic: "ˈæpl", ukPhonetic: "ˈæpl", explains: nil)
        let phonetic = YoudaoDictionaryService.pickPhonetic(from: basic)
        #expect(phonetic == "/ˈæpl/")
    }

    @Test func decodeYoudaoJSONUsesCorrectFieldNames() throws {
        let json = """
        {
          "errorCode": "0",
          "query": "memory",
          "translation": ["记忆"],
          "basic": {
            "phonetic": "ˈmeməri",
            "uk-phonetic": "ˈmeməri",
            "us-phonetic": "ˈmeməri",
            "explains": ["n. 记忆；回忆", "n. 内存"]
          },
          "web": [
            { "key": "memory", "value": ["内存", "记忆", "存储器"] }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(YoudaoAPIResponse.self, from: json)
        #expect(decoded.errorCode == "0")
        #expect(decoded.basic?.explains?.count == 2)
        #expect(YoudaoDictionaryService.pickChinese(from: decoded) == "n. 记忆；回忆；n. 内存")
        #expect(YoudaoDictionaryService.pickPhonetic(from: decoded.basic) == "/ˈmeməri/")
    }
}
