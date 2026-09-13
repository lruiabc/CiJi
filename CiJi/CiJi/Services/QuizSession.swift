import Foundation
import SwiftData

/// Live (pre-submit) correctness hint for practice rows.
enum QuizLiveStatus: Equatable {
    case idle
    case empty
    case correct
    case incorrect
}

/// In-memory multi-word quiz session (persists stats when a round finishes).
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

    enum OrderMode: String, CaseIterable, Identifiable {
        case sequential
        case shuffled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sequential: return "顺序"
            case .shuffled: return "乱序"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let english: String
        let phonetic: String
        let chinese: String
    }

    struct Prompt: Identifiable, Equatable {
        let item: Item
        var answer: String
        var feedback: Feedback?

        var id: UUID { item.id }

        enum Feedback: Equatable {
            case correct(matched: String?)
            case incorrect(expected: String)
        }
    }

    struct Result: Identifiable, Equatable {
        let id: UUID
        let item: Item
        let userAnswer: String
        let isCorrect: Bool
    }

    @Published var phase: Phase = .setup
    @Published var scope: Scope = .all
    @Published var orderMode: OrderMode = .shuffled
    /// Words shown per page; defaults to the selected scope’s eligible count.
    @Published var pageSize: Int = 1
    /// `0` = all eligible words.
    @Published var limit: Int = 0
    /// When on, answers are validated as the user types (no submit required to see correctness).
    @Published var liveCheckEnabled: Bool = true

    @Published private(set) var queue: [Item] = []
    @Published private(set) var pageIndex: Int = 0
    @Published var prompts: [Prompt] = []
    @Published private(set) var pageChecked: Bool = false
    @Published private(set) var results: [Result] = []
    @Published private(set) var didRecordCompletion: Bool = false

    var totalPages: Int {
        guard pageSize > 0, !queue.isEmpty else { return 0 }
        return (queue.count + pageSize - 1) / pageSize
    }

    var progressLabel: String {
        guard phase == .practicing, totalPages > 0 else { return "" }
        return "第 \(pageIndex + 1) / \(totalPages) 页 · 共 \(queue.count) 词"
    }

    var correctCount: Int { results.filter(\.isCorrect).count }
    var wrongCount: Int { results.filter { !$0.isCorrect }.count }
    var totalAnswered: Int { results.count }
    var totalCount: Int { results.count }
    var wrongItems: [Result] { results.filter { !$0.isCorrect } }
    var distinctWrongWordCount: Int {
        Set(wrongItems.map(\.item.id)).count
    }
    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(correctCount) / Double(totalAnswered)
    }
    var isLastPage: Bool { totalPages == 0 || pageIndex + 1 >= totalPages }

    /// Live (pre-submit) status for one answer field.
    static func liveStatus(answer: String, expectedChinese: String) -> QuizLiveStatus {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        return QuizAnswerMatcher.isCorrect(answer: trimmed, expected: expectedChinese)
            ? .correct
            : .incorrect
    }

    func availableCount(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> Int {
        eligibleItems(for: scope, allWords: allWords, groups: groups).count
    }

    /// Set page size to the eligible word count for the current scope (min 1).
    func syncPageSizeToScope(allWords: [Word], groups: [WordGroup]) {
        let count = availableCount(for: scope, allWords: allWords, groups: groups)
        pageSize = max(1, count)
    }

    func scopeLabel(groups: [WordGroup]) -> String {
        switch scope {
        case .all: return "全部单词"
        case .ungrouped: return "未分组"
        case .group(let id):
            return groups.first(where: { $0.uuid == id })?.name ?? "分组"
        }
    }

    @discardableResult
    func start(allWords: [Word], groups: [WordGroup]) -> String? {
        pageSize = max(1, pageSize)
        var items = eligibleItems(for: scope, allWords: allWords, groups: groups)
        guard !items.isEmpty else {
            return "所选范围没有带中文释义的单词，请先添加或编辑释义。"
        }

        switch orderMode {
        case .sequential:
            break
        case .shuffled:
            items.shuffle()
        }
        if limit > 0, items.count > limit {
            items = Array(items.prefix(limit))
        }

        queue = items
        pageIndex = 0
        results = []
        pageChecked = false
        didRecordCompletion = false
        loadCurrentPage()
        phase = .practicing
        AppLog.console(
            "开始练习 scope=\(scope.id) order=\(orderMode.rawValue) pageSize=\(pageSize) count=\(items.count)",
            category: "Quiz"
        )
        return nil
    }

    /// Grade all prompts on this page. Any one *complete* Chinese sense counts as correct (no partial fragments).
    func checkPage() {
        guard phase == .practicing, !pageChecked else { return }
        var graded: [Prompt] = []
        for prompt in prompts {
            let trimmed = prompt.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let judgment = QuizAnswerMatcher.judge(answer: trimmed, expected: prompt.item.chinese)
            var updated = prompt
            updated.answer = trimmed
            updated.feedback = judgment.isCorrect
                ? .correct(matched: judgment.matchedSense)
                : .incorrect(expected: prompt.item.chinese)
            graded.append(updated)
            results.append(
                Result(id: UUID(), item: prompt.item, userAnswer: trimmed, isCorrect: judgment.isCorrect)
            )
        }
        prompts = graded
        pageChecked = true
    }

    func revealPage() {
        guard phase == .practicing, !pageChecked else { return }
        checkPage()
    }

    func goNextPage(context: ModelContext? = nil, allWords: [Word] = [], groups: [WordGroup] = []) {
        guard pageChecked else { return }
        if isLastPage {
            if let context {
                recordCompletion(context: context, allWords: allWords, groups: groups)
            }
            phase = .summary
            prompts = []
            pageChecked = false
            AppLog.console(
                "练习结束 correct=\(correctCount)/\(totalAnswered) wrongWords=\(distinctWrongWordCount)",
                category: "Quiz"
            )
            return
        }
        pageIndex += 1
        pageChecked = false
        loadCurrentPage()
    }

    /// Persist session wrong-word tally and per-word incorrect counts.
    @discardableResult
    func recordCompletion(context: ModelContext, allWords: [Word], groups: [WordGroup]) -> PracticeRecord? {
        guard !didRecordCompletion else { return nil }
        didRecordCompletion = true

        var wrongTimesByID: [UUID: Int] = [:]
        for result in wrongItems {
            wrongTimesByID[result.item.id, default: 0] += 1
        }

        let wordsByID = Dictionary(uniqueKeysWithValues: allWords.map { ($0.uuid, $0) })
        for (id, times) in wrongTimesByID {
            guard let word = wordsByID[id] else { continue }
            word.wrongAnswerCount += times
        }

        let record = PracticeRecord(
            scopeID: scope.id,
            scopeLabel: scopeLabel(groups: groups),
            totalCount: totalAnswered,
            wrongWordCount: distinctWrongWordCount,
            correctCount: correctCount
        )
        context.insert(record)
        try? context.save()
        AppLog.console(
            "记录练习结果 wrongWords=\(record.wrongWordCount)/\(record.totalCount) perWordIncrements=\(wrongTimesByID.count)",
            category: "Quiz"
        )
        return record
    }

    @discardableResult
    func restartSameSettings(allWords: [Word], groups: [WordGroup]) -> String? {
        start(allWords: allWords, groups: groups)
    }

    func backToSetup() {
        phase = .setup
        queue = []
        pageIndex = 0
        prompts = []
        pageChecked = false
        results = []
        didRecordCompletion = false
    }

    private func loadCurrentPage() {
        let size = max(1, pageSize)
        let start = pageIndex * size
        guard start < queue.count else {
            prompts = []
            return
        }
        let end = min(start + size, queue.count)
        prompts = queue[start..<end].map { Prompt(item: $0, answer: "", feedback: nil) }
    }

    private func eligibleItems(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> [Item] {
        var words = sourceWords(for: scope, allWords: allWords, groups: groups)
            .filter { !$0.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        words.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.english < $1.english
        }
        return words.map {
            Item(id: $0.uuid, english: $0.english, phonetic: $0.phonetic, chinese: $0.chinese)
        }
    }

    private func sourceWords(for scope: Scope, allWords: [Word], groups: [WordGroup]) -> [Word] {
        switch scope {
        case .all: return allWords
        case .ungrouped: return allWords.filter(\.isUngrouped)
        case .group(let id): return groups.first(where: { $0.uuid == id })?.words ?? []
        }
    }
}
