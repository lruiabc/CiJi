import Foundation

/// In-memory quiz session (not persisted).
@MainActor
final class QuizSession: ObservableObject {
    enum Phase: Equatable {
        case setup
        case practicing
        case summary
    }

    enum Scope: Equatable, Hashable, Identifiable {
        case all
        case ungrouped
        case group(UUID)

        var id: String {
            switch self {
            case .all: return "all"
            case .ungrouped: return "ungrouped"
            case .group(let id): return id.uuidString
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let english: String
        let phonetic: String
        let chinese: String
    }

    struct Result: Identifiable, Equatable {
        let id: UUID
        let item: Item
        let userAnswer: String
        let isCorrect: Bool
    }

    enum Feedback: Equatable {
        case correct(matched: String?)
        case incorrect(expected: String)
    }

    @Published var phase: Phase = .setup
    @Published var scope: Scope = .all
    @Published var shuffle = true
    /// `0` means use all eligible words.
    @Published var limit = 0

    @Published private(set) var queue: [Item] = []
    @Published private(set) var index = 0
    @Published var answerText = ""
    @Published var feedback: Feedback?
    @Published private(set) var results: [Result] = []

    var current: Item? {
        guard phase == .practicing, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    var progressLabel: String {
        guard phase == .practicing, !queue.isEmpty else { return "" }
        return "\(index + 1) / \(queue.count)"
    }

    var correctCount: Int { results.filter(\.isCorrect).count }
    var totalAnswered: Int { results.count }

    func availableCount(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> Int {
        eligibleItems(for: scope, allWords: allWords, groups: groups).count
    }

    @discardableResult
    func start(allWords: [Word], groups: [WordGroup]) -> String? {
        var items = eligibleItems(for: scope, allWords: allWords, groups: groups)
        guard !items.isEmpty else {
            return "所选范围没有带中文释义的单词，请先添加或编辑释义。"
        }
        if shuffle { items.shuffle() }
        if limit > 0, items.count > limit {
            items = Array(items.prefix(limit))
        }
        queue = items
        index = 0
        answerText = ""
        feedback = nil
        results = []
        phase = .practicing
        AppLog.console("开始练习 scope=\(scope.id) count=\(items.count)", category: "Quiz")
        return nil
    }

    /// Empty answer is graded wrong (used by “不会，看答案”).
    func submitCurrent() {
        guard let item = current, feedback == nil else { return }
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let judgment = QuizAnswerMatcher.judge(answer: trimmed, expected: item.chinese)
        feedback = judgment.isCorrect
            ? .correct(matched: judgment.matchedSense)
            : .incorrect(expected: item.chinese)
        results.append(
            Result(id: UUID(), item: item, userAnswer: trimmed, isCorrect: judgment.isCorrect)
        )
    }

    func goNext() {
        guard feedback != nil else { return }
        if index + 1 >= queue.count {
            phase = .summary
            feedback = nil
            answerText = ""
            AppLog.console("练习结束 correct=\(correctCount)/\(totalAnswered)", category: "Quiz")
            return
        }
        index += 1
        answerText = ""
        feedback = nil
    }

    @discardableResult
    func restartSameSettings(allWords: [Word], groups: [WordGroup]) -> String? {
        start(allWords: allWords, groups: groups)
    }

    func backToSetup() {
        phase = .setup
        queue = []
        index = 0
        answerText = ""
        feedback = nil
        results = []
    }

    private func eligibleItems(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> [Item] {
        sourceWords(for: scope, allWords: allWords, groups: groups)
            .filter { !$0.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { Item(id: $0.uuid, english: $0.english, phonetic: $0.phonetic, chinese: $0.chinese) }
    }

    private func sourceWords(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> [Word] {
        switch scope {
        case .all: return allWords
        case .ungrouped: return allWords.filter(\.isUngrouped)
        case .group(let id): return groups.first(where: { $0.uuid == id })?.words ?? []
        }
    }
}
