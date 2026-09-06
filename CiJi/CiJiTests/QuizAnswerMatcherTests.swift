import Foundation
import Testing
@testable import CiJi

struct QuizAnswerMatcherTests {
    @Test func exactMatch() {
        #expect(QuizAnswerMatcher.isCorrect(answer: "苹果", expected: "n. 苹果"))
    }

    @Test func stripsPartOfSpeechAndPunctuation() {
        #expect(QuizAnswerMatcher.isCorrect(answer: "优雅的", expected: "adj. 优雅的；高雅的"))
    }

    @Test func acceptsAnySense() {
        #expect(QuizAnswerMatcher.isCorrect(answer: "高雅的", expected: "adj. 优雅的；高雅的"))
        #expect(QuizAnswerMatcher.isCorrect(answer: "优雅的", expected: "adj. 优雅的；高雅的"))
    }

    @Test func acceptsPartialCoreMeaning() {
        #expect(QuizAnswerMatcher.isCorrect(answer: "弹性", expected: "adj. 有弹性的；能复原的"))
    }

    @Test func rejectsWrongAnswer() {
        #expect(!QuizAnswerMatcher.isCorrect(answer: "香蕉", expected: "n. 苹果"))
    }

    @Test func emptyAnswerIsWrong() {
        #expect(!QuizAnswerMatcher.isCorrect(answer: "  ", expected: "苹果"))
    }

    @Test func sensesSplit() {
        let senses = QuizAnswerMatcher.senses(from: "n. 焦点；v. 集中")
        #expect(senses.contains("焦点"))
        #expect(senses.contains("集中"))
    }
}
