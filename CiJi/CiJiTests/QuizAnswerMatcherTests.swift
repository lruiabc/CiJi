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

    @Test func acceptsAnyCompleteSense() {
        #expect(QuizAnswerMatcher.isCorrect(answer: "高雅的", expected: "adj. 优雅的；高雅的"))
        #expect(QuizAnswerMatcher.isCorrect(answer: "优雅的", expected: "adj. 优雅的；高雅的"))
    }

    @Test func rejectsPartialFragmentOfSense() {
        // "使" / "尴尬" / "使尴" must NOT count when the sense is the full "使尴尬"
        #expect(!QuizAnswerMatcher.isCorrect(answer: "使", expected: "v. 使尴尬"))
        #expect(!QuizAnswerMatcher.isCorrect(answer: "尴尬", expected: "v. 使尴尬"))
        #expect(!QuizAnswerMatcher.isCorrect(answer: "使尴", expected: "v. 使尴尬"))
        #expect(QuizAnswerMatcher.isCorrect(answer: "使尴尬", expected: "v. 使尴尬"))
    }

    @Test func rejectsPartialCoreMeaning() {
        #expect(!QuizAnswerMatcher.isCorrect(answer: "弹性", expected: "adj. 有弹性的；能复原的"))
        #expect(QuizAnswerMatcher.isCorrect(answer: "有弹性的", expected: "adj. 有弹性的；能复原的"))
        #expect(QuizAnswerMatcher.isCorrect(answer: "能复原的", expected: "adj. 有弹性的；能复原的"))
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
