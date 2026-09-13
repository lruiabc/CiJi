import SwiftUI
import SwiftData

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pronunciation: PronunciationService

    @Query(sort: \WordGroup.sortOrder) private var groups: [WordGroup]
    @Query(sort: [SortDescriptor(\Word.sortOrder), SortDescriptor(\Word.createdAt)]) private var allWords: [Word]

    @StateObject private var session = QuizSession()
    @State private var setupError: String?
    @FocusState private var focusedPromptID: UUID?

    let preferredScope: QuizSession.Scope

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .setup:
                    setupForm
                case .practicing:
                    practicingView
                case .summary:
                    summaryView
                }
            }
            .navigationTitle(navigationTitle)
            #if os(macOS)
            .navigationSubtitle(session.phase == .setup ? "英译中练习" : session.progressLabel)
            #endif
            .toolbar { toolbarContent }
            .onAppear {
                if session.phase == .setup {
                    session.scope = preferredScope
                    session.syncPageSizeToScope(allWords: allWords, groups: groups)
                }
            }
            .onChange(of: session.scope) { _, _ in
                guard session.phase == .setup else { return }
                session.syncPageSizeToScope(allWords: allWords, groups: groups)
            }
        }
        .background(AppAtmosphereBackground())
        .frame(minWidth: 760, minHeight: 560)
    }

    private var navigationTitle: String {
        switch session.phase {
        case .setup: "练习"
        case .practicing: session.pageChecked ? "本页对照" : "答题"
        case .summary: "本轮结果"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { dismiss() }
        }

        if session.phase == .practicing, !session.pageChecked {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $session.liveCheckEnabled) {
                    Text("实时校验")
                }
                .toggleStyle(.checkbox)
                .help("开启后，输入释义时可即时对照，无需先点提交")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("提交本页") { session.revealPage() }
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }

        if session.phase == .practicing, session.pageChecked {
            ToolbarItem(placement: .confirmationAction) {
                Button(session.isLastPage ? "查看结果" : "下一页") {
                    session.goNextPage(context: modelContext, allWords: allWords, groups: groups)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }

        if session.phase == .summary {
            ToolbarItem(placement: .confirmationAction) {
                Button("再练一轮") {
                    setupError = session.restartSameSettings(allWords: allWords, groups: groups)
                }
            }
        }
    }

    // MARK: - Setup

    private var setupForm: some View {
        Form {
            Section("练习范围") {
                Picker("范围", selection: $session.scope) {
                    Text("全部单词（\(session.availableCount(for: .all, allWords: allWords, groups: groups))）")
                        .tag(QuizSession.Scope.all)
                    Text("未分组（\(session.availableCount(for: .ungrouped, allWords: allWords, groups: groups))）")
                        .tag(QuizSession.Scope.ungrouped)
                    ForEach(groups) { group in
                        Text("\(group.name)（\(session.availableCount(for: .group(group.uuid), allWords: allWords, groups: groups))）")
                            .tag(QuizSession.Scope.group(group.uuid))
                    }
                }

                Picker("出题顺序", selection: $session.orderMode) {
                    ForEach(QuizSession.OrderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                HStack {
                    Text("每页题数")
                    Spacer()
                    TextField("题数", value: $session.pageSize, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: session.pageSize) { _, newValue in
                            if newValue < 1 { session.pageSize = 1 }
                            if newValue > 500 { session.pageSize = 500 }
                        }
                }
                Text("默认为当前范围的单词总数（可手动修改）。当前范围共 \(session.availableCount(for: session.scope, allWords: allWords, groups: groups)) 个可练习词。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(value: $session.limit, in: 0...500) {
                    Text(session.limit == 0 ? "本轮题数：全部" : "本轮最多：\(session.limit) 词")
                }
            }

            Section("校验方式") {
                Toggle("实时校验（输入时即可对照，不必先提交）", isOn: $session.liveCheckEnabled)
                Text(
                    session.liveCheckEnabled
                        ? "右侧会随输入显示对/错提示；仍可随时点「提交本页」写入成绩并看完整对照。"
                        : "关闭后先专心作答，点「提交本页」后再显示对错。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let setupError {
                Section {
                    Text(setupError)
                        .foregroundStyle(AppTheme.coral)
                }
            }

            Section {
                Button("开始练习") {
                    setupError = session.start(allWords: allWords, groups: groups)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Practicing

    private var practicingView: some View {
        VStack(spacing: 0) {
            compactPracticeChrome
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(session.prompts.enumerated()), id: \.element.id) { index, prompt in
                        if session.pageChecked {
                            revealedRow(prompt: prompt)
                        } else {
                            answerRow(index: index, prompt: prompt)
                        }
                        Divider()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            if !session.pageChecked {
                Divider()
                footerHint
            }
        }
    }

    /// Single slim chrome strip: progress + optional live-check + column labels.
    private var compactPracticeChrome: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(session.progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                Spacer(minLength: 8)
                if session.liveCheckEnabled, !session.pageChecked {
                    Label("实时校验已开", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.jade)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.jade.opacity(0.12)))
                        .labelStyle(.titleAndIcon)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                Text("英文")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.jade.opacity(0.55))
                    .frame(width: 20)
                Text("中文释义")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 28)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answerRow(index: Int, prompt: QuizSession.Prompt) -> some View {
        let live: QuizLiveStatus = session.liveCheckEnabled
            ? QuizSession.liveStatus(answer: prompt.answer, expectedChinese: prompt.item.chinese)
            : .idle

        return HStack(alignment: .center, spacing: 16) {
            englishColumn(item: prompt.item)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            HStack(spacing: 8) {
                TextField("输入中文释义", text: answerBinding(at: index))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedPromptID, equals: prompt.id)
                    .onSubmit { session.revealPage() }

                liveBadge(live)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func revealedRow(prompt: QuizSession.Prompt) -> some View {
        let correct = prompt.feedback.map { feedback in
            if case .correct = feedback { return true }
            return false
        } ?? false

        return HStack(alignment: .top, spacing: 16) {
            englishColumn(item: prompt.item)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(correct ? AppTheme.jade : AppTheme.coral)
                    Text(prompt.answer.isEmpty ? "（未作答）" : prompt.answer)
                        .font(.body)
                        .foregroundStyle(correct ? AppTheme.ink : AppTheme.coral)
                }

                if !correct {
                    Text("参考：\(prompt.item.chinese)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if case .correct(let matched)? = prompt.feedback, let matched, !matched.isEmpty {
                    Text("匹配：\(matched)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func englishColumn(item: QuizSession.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.english)
                    .font(AppTheme.wordFont)
                    .foregroundStyle(AppTheme.ink)
                    .textSelection(.enabled)
                SpeakButton(word: item.english, pronunciation: pronunciation, settings: settings)
            }
            if !item.phonetic.isEmpty {
                Text(item.phonetic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func liveBadge(_ status: QuizLiveStatus) -> some View {
        Group {
            switch status {
            case .idle:
                Color.clear.frame(width: 28, height: 28)
            case .empty:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
                    .help("尚未输入")
            case .correct:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.jade)
                    .help("已匹配某一义项")
            case .incorrect:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(AppTheme.coral.opacity(0.85))
                    .help("尚未匹配，可继续改")
            }
        }
        .font(.title3)
        .frame(width: 28, height: 28)
        .accessibilityLabel(status.accessibilityLabel)
    }

    private var footerHint: some View {
        Text(
            session.liveCheckEnabled
                ? "左侧英文 · 右侧中文。实时校验已开 · ⌘↩ 提交本页"
                : "左侧英文 · 右侧中文。提交后显示对错 · ⌘↩ 提交本页"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: - Summary

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                scoreChip(title: "正确", value: session.correctCount, tint: AppTheme.jade)
                scoreChip(title: "答错词数", value: session.distinctWrongWordCount, tint: AppTheme.coral)
                scoreChip(
                    title: "正确率",
                    valueText: "\(Int((session.accuracy * 100).rounded()))%",
                    tint: AppTheme.jade
                )
            }

            Text("本轮答错 \(session.distinctWrongWordCount) 个单词（已记入各词累计错次）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if session.wrongItems.isEmpty {
                ContentUnavailableView(
                    "全部正确",
                    systemImage: "checkmark.seal.fill",
                    description: Text("本轮 \(session.totalCount) 词全部答对。")
                )
                .frame(maxHeight: .infinity)
            } else {
                Text("错题回顾")
                    .font(.headline)

                List(session.wrongItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.item.english).font(.headline)
                            SpeakButton(
                                word: item.item.english,
                                pronunciation: pronunciation,
                                settings: settings
                            )
                            Spacer()
                            Text("你的答案：\(item.userAnswer.isEmpty ? "（空）" : item.userAnswer)")
                                .foregroundStyle(AppTheme.coral)
                        }
                        if let total = cumulativeWrongCount(for: item.item.id), total > 0 {
                            Text("累计错 \(total) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("参考：\(item.item.chinese)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Button("调整设置") { session.backToSetup() }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func scoreChip(title: String, value: Int, tint: Color) -> some View {
        scoreChip(title: title, valueText: "\(value)", tint: tint)
    }

    private func scoreChip(title: String, valueText: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.title.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.mist.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.jade.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func cumulativeWrongCount(for wordID: UUID) -> Int? {
        allWords.first(where: { $0.uuid == wordID })?.wrongAnswerCount
    }

    private func answerBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard session.prompts.indices.contains(index) else { return "" }
                return session.prompts[index].answer
            },
            set: { newValue in
                guard session.prompts.indices.contains(index) else { return }
                var prompt = session.prompts[index]
                prompt.answer = newValue
                session.prompts[index] = prompt
            }
        )
    }
}

private extension QuizLiveStatus {
    var accessibilityLabel: String {
        switch self {
        case .idle: "未启用实时校验"
        case .empty: "尚未输入"
        case .correct: "正确"
        case .incorrect: "尚未匹配"
        }
    }
}
