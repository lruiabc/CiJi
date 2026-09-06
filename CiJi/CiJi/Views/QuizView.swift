import SwiftUI
import SwiftData

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pronunciation: PronunciationService

    @Query(sort: \WordGroup.sortOrder) private var groups: [WordGroup]
    @Query(sort: \Word.createdAt, order: .reverse) private var allWords: [Word]

    var preferredScope: QuizSession.Scope = .all

    @StateObject private var session = QuizSession()
    @State private var setupError: String?
    @FocusState private var focusedPromptID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .setup: setupPhase
                case .practicing: practicePhase
                case .summary: summaryPhase
                }
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.phase == .setup ? "关闭" : "结束") {
                        switch session.phase {
                        case .setup: dismiss()
                        case .practicing, .summary: session.backToSetup()
                        }
                    }
                }
            }
            .onAppear {
                if session.phase == .setup {
                    session.scope = preferredScope
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private var navTitle: String {
        switch session.phase {
        case .setup: return "开始练习"
        case .practicing: return "练习中 \(session.progressLabel)"
        case .summary: return "本轮结果"
        }
    }

    // MARK: Setup

    private var setupPhase: some View {
        Form {
            Section {
                Text("每页同时出示多个英文单词。写出中文释义即可；一词多义时，答对其中任何一个意思就算正确。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("练习范围") {
                Picker("范围", selection: $session.scope) {
                    Text("全部单词（\(wordCount(for: .all))）").tag(QuizSession.Scope.all)
                    Text("未分组（\(wordCount(for: .ungrouped))）").tag(QuizSession.Scope.ungrouped)
                    ForEach(groups, id: \.uuid) { group in
                        Text("\(group.name)（\(wordCount(for: .group(group.uuid)))）")
                            .tag(QuizSession.Scope.group(group.uuid))
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            Section("出题方式") {
                Picker("顺序", selection: $session.orderMode) {
                    ForEach(QuizSession.OrderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("每页单词数", selection: $session.pageSize) {
                    Text("3 个").tag(3)
                    Text("5 个").tag(5)
                    Text("8 个").tag(8)
                    Text("10 个").tag(10)
                }

                Picker("本轮总题量", selection: $session.limit) {
                    Text("全部").tag(0)
                    Text("10 词").tag(10)
                    Text("20 词").tag(20)
                    Text("30 词").tag(30)
                }
            }

            if let setupError {
                Section { Text(setupError).foregroundStyle(.red) }
            }

            Section {
                Button {
                    if let error = session.start(allWords: allWords, groups: groups) {
                        setupError = error
                    } else {
                        setupError = nil
                        focusFirstEmpty()
                    }
                } label: {
                    Label("开始练习", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(wordCount(for: session.scope) == 0)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Practice

    private var practicePhase: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: Double(min(session.pageIndex + (session.pageChecked ? 1 : 0), max(session.totalPages, 1))),
                total: Double(max(session.totalPages, 1))
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack {
                Text(session.progressLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已答对 \(session.correctCount) / \(session.totalAnswered)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            if session.prompts.isEmpty {
                ContentUnavailableView("没有题目", systemImage: "questionmark.circle")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($session.prompts) { $prompt in
                            promptCard(prompt: $prompt)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                Divider()

                HStack(spacing: 12) {
                    if !session.pageChecked {
                        Button("不会，看本页答案") { session.revealPage() }
                        Button("提交本页") { session.checkPage() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(session.isLastPage ? "查看结果" : "下一页") {
                            session.goNextPage()
                            focusFirstEmpty()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
            }
        }
        .onAppear(perform: focusFirstEmpty)
    }

    private func promptCard(prompt: Binding<QuizSession.Prompt>) -> some View {
        let value = prompt.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value.item.english)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                SpeakButton(
                    word: value.item.english,
                    size: 14,
                    helpText: "听发音",
                    pronunciation: pronunciation,
                    settings: settings
                )
                if !value.item.phonetic.isEmpty {
                    Text(value.item.phonetic)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let feedback = value.feedback {
                    Image(systemName: isCorrect(feedback) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isCorrect(feedback) ? Color.green : Color.red)
                }
            }

            TextField("中文释义（任一义项即可）", text: prompt.answer)
                .textFieldStyle(.roundedBorder)
                .focused($focusedPromptID, equals: value.id)
                .disabled(session.pageChecked)
                .onSubmit { focusNext(after: value.id) }

            if let feedback = value.feedback {
                feedbackText(feedback, fullExpected: value.item.chinese, userAnswer: value.answer)
            }
        }
        .padding(12)
        .background(cardBackground(value.feedback), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func feedbackText(
        _ feedback: QuizSession.Prompt.Feedback,
        fullExpected: String,
        userAnswer: String
    ) -> some View {
        switch feedback {
        case .correct(let matched):
            Text(matched.map { "正确 · 匹配「\($0)」" } ?? "正确")
                .font(.caption)
                .foregroundStyle(.green)
            Text("完整释义：\(fullExpected)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .incorrect(let expected):
            if !userAnswer.isEmpty {
                Text("你的回答：\(userAnswer)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("参考释义：\(expected)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func isCorrect(_ feedback: QuizSession.Prompt.Feedback) -> Bool {
        if case .correct = feedback { return true }
        return false
    }

    private func cardBackground(_ feedback: QuizSession.Prompt.Feedback?) -> Color {
        switch feedback {
        case .correct: return Color.green.opacity(0.08)
        case .incorrect: return Color.red.opacity(0.08)
        case nil: return Color(nsColor: .controlBackgroundColor)
        }
    }

    // MARK: Summary

    private var summaryPhase: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            Image(systemName: summaryIcon)
                .font(.system(size: 48))
                .foregroundStyle(summaryColor)
            Text("\(session.correctCount) / \(session.totalAnswered)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(summaryMessage)
                .font(.title3)
                .foregroundStyle(.secondary)

            List {
                ForEach(session.results) { result in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.isCorrect ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.item.english).font(.body.weight(.semibold))
                                SpeakButton(
                                    word: result.item.english,
                                    size: 12,
                                    pronunciation: pronunciation,
                                    settings: settings
                                )
                            }
                            Text(result.item.chinese)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if !result.isCorrect, !result.userAnswer.isEmpty {
                                Text("你的回答：\(result.userAnswer)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: 280)

            HStack(spacing: 12) {
                Button("返回设置") { session.backToSetup() }
                Button("再练一轮") {
                    setupError = session.restartSameSettings(allWords: allWords, groups: groups)
                    focusFirstEmpty()
                }
                .buttonStyle(.borderedProminent)
                Button("完成") { dismiss() }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }

    private var summaryIcon: String {
        guard session.totalAnswered > 0 else { return "questionmark.circle" }
        let ratio = Double(session.correctCount) / Double(session.totalAnswered)
        if ratio >= 0.9 { return "star.circle.fill" }
        if ratio >= 0.6 { return "hand.thumbsup.circle.fill" }
        return "book.circle.fill"
    }

    private var summaryColor: Color {
        guard session.totalAnswered > 0 else { return .secondary }
        let ratio = Double(session.correctCount) / Double(session.totalAnswered)
        if ratio >= 0.9 { return .yellow }
        if ratio >= 0.6 { return .accentColor }
        return .orange
    }

    private var summaryMessage: String {
        guard session.totalAnswered > 0 else { return "本轮没有作答。" }
        let ratio = Double(session.correctCount) / Double(session.totalAnswered)
        if ratio == 1 { return "全部正确，太棒了！" }
        if ratio >= 0.8 { return "很扎实，继续保持。" }
        if ratio >= 0.5 { return "有进步空间，错题再看一眼会更熟。" }
        return "别着急，先回到词库把释义看熟再练。"
    }

    // MARK: Helpers

    private func wordCount(for scope: QuizSession.Scope) -> Int {
        session.availableCount(for: scope, allWords: allWords, groups: groups)
    }

    private func focusFirstEmpty() {
        DispatchQueue.main.async {
            focusedPromptID = session.prompts.first(where: {
                $0.feedback == nil && $0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })?.id ?? session.prompts.first?.id
        }
    }

    private func focusNext(after id: UUID) {
        guard let idx = session.prompts.firstIndex(where: { $0.id == id }) else { return }
        if idx + 1 < session.prompts.count {
            focusedPromptID = session.prompts[idx + 1].id
        } else if !session.pageChecked {
            session.checkPage()
        }
    }
}
