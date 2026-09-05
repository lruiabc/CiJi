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
        #expect(sign == YoudaoDictionaryService.sign(
            appKey: "key",
            query: "hello",
            salt: "salt",
            curtime: "123",
            appSecret: "secret"
        ))
    }
}
