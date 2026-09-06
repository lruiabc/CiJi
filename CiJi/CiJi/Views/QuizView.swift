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
    @FocusState private var answerFocused: Bool

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
        .frame(minWidth: 560, minHeight: 480)
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
                Text("看英文，默写中文释义。一词多义时，写出其中任一义项即可。")
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

            Section("选项") {
                Toggle("打乱顺序", isOn: $session.shuffle)
                Picker("题目数量", selection: $session.limit) {
                    Text("全部").tag(0)
                    Text("10 题").tag(10)
                    Text("20 题").tag(20)
                    Text("30 题").tag(30)
                }
            }

            if let setupError {
                Section {
                    Text(setupError).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    if let error = session.start(allWords: allWords, groups: groups) {
                        setupError = error
                    } else {
                        setupError = nil
                        focusAnswer()
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
                value: Double(min(session.index + (session.feedback == nil ? 0 : 1), session.queue.count)),
                total: Double(max(session.queue.count, 1))
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if let item = session.current {
                VStack(spacing: 20) {
                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        Text(item.english)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .textSelection(.enabled)
                        SpeakButton(
                            word: item.english,
                            size: 18,
                            helpText: "听发音",
                            pronunciation: pronunciation,
                            settings: settings
                        )
                    }

                    Text(item.phonetic.isEmpty ? " " : item.phonetic)
                        .font(.title3.monospaced())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("中文释义")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("输入中文意思", text: $session.answerText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .focused($answerFocused)
                            .disabled(session.feedback != nil)
                            .onSubmit(handlePrimaryAction)
                    }
                    .frame(maxWidth: 420)

                    if let feedback = session.feedback {
                        feedbackBanner(feedback, fullExpected: item.chinese)
                            .frame(maxWidth: 420)
                    }

                    HStack(spacing: 12) {
                        if session.feedback == nil {
                            Button("不会，看答案") {
                                session.answerText = ""
                                session.submitCurrent()
                            }
                            Button("提交") { session.submitCurrent() }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .keyboardShortcut(.defaultAction)
                        } else {
                            Button(session.index + 1 >= session.queue.count ? "查看结果" : "下一题") {
                                session.goNext()
                                focusAnswer()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        }
                    }

                    Spacer()

                    Text("已答对 \(session.correctCount) / \(session.totalAnswered)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("没有题目", systemImage: "questionmark.circle")
            }
        }
        .onAppear(perform: focusAnswer)
    }

    @ViewBuilder
    private func feedbackBanner(_ feedback: QuizSession.Feedback, fullExpected: String) -> some View {
        switch feedback {
        case .correct(let matched):
            VStack(alignment: .leading, spacing: 6) {
                Label("正确", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                if let matched, !matched.isEmpty {
                    Text("匹配义项：\(matched)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("完整释义：\(fullExpected)")
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

        case .incorrect(let expected):
            VStack(alignment: .leading, spacing: 6) {
                Label("不正确", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                let typed = session.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty {
                    Text("你的回答：\(typed)")
                        .font(.callout)
                }
                Text("参考释义：\(expected)")
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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
                            .foregroundStyle(result.isCorrect ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.item.english)
                                    .font(.body.weight(.semibold))
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
                    focusAnswer()
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

    private func handlePrimaryAction() {
        if session.feedback == nil {
            guard !session.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            session.submitCurrent()
        } else {
            session.goNext()
            focusAnswer()
        }
    }

    private func focusAnswer() {
        DispatchQueue.main.async { answerFocused = true }
    }
}
