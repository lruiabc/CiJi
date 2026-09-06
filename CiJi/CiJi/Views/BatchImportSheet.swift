import SwiftUI
import SwiftData
import os

private let batchLog = Logger(subsystem: "app.ciji.mac", category: "BatchImport")

private struct ImportDraft: Identifiable, Equatable {
    let id = UUID()
    var english: String
    var phonetic: String = ""
    var chinese: String = ""
    var source: String = ""
    var groupChoice: GroupChoice = .none
    var status: Status = .pending
    var message: String?

    enum Status: Equatable {
        case pending, loading, ready, failed, skipped
    }
}

struct BatchImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pronunciation: PronunciationService

    @Query(sort: \WordGroup.sortOrder) private var groups: [WordGroup]
    @Query private var existingWords: [Word]

    var preferredGroup: WordGroup?

    @State private var rawText = ""
    @State private var drafts: [ImportDraft] = []
    @State private var defaultGroupChoice: GroupChoice = .none
    @State private var isLookingUp = false
    @State private var progressDone = 0
    @State private var progressTotal = 0
    @State private var statusMessage: String?
    @State private var didSave = false
    @State private var lookupTask: Task<Void, Never>?

    private let maxConcurrentLookups = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if drafts.isEmpty {
                    inputPhase
                } else {
                    previewPhase
                }
            }
            .navigationTitle("批量导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isLookingUp ? "停止" : "取消") {
                        if isLookingUp {
                            cancelLookup()
                        } else {
                            dismiss()
                        }
                    }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("写入词库") { commit() }
                            .disabled(isLookingUp || readyCount == 0)
                    }
                }
            }
            .onAppear {
                defaultGroupChoice = GroupChoice(uuid: preferredGroup?.uuid)
            }
            .onDisappear { cancelLookup() }
            .alert("导入完成", isPresented: $didSave) {
                Button("好") { dismiss() }
            } message: {
                Text(statusMessage ?? "单词已加入词库。")
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var inputPhase: some View {
        Form {
            Section {
                Text("每行一个英文单词。可先选定默认分组；预览阶段还能给个别单词改组。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("单词列表") {
                TextEditor(text: $rawText)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
            }

            Section("默认分组") {
                Picker("放入", selection: $defaultGroupChoice) {
                    Text("未分组").tag(GroupChoice.none)
                    ForEach(groups, id: \.uuid) { group in
                        Text("\(group.name)（\(group.wordCount)/\(group.capacity)）")
                            .tag(GroupChoice.group(group.uuid))
                    }
                }
            }

            Section {
                Button {
                    lookupTask = Task { await prepareAndLookup() }
                } label: {
                    Label("解析并查询释义", systemImage: "magnifyingglass")
                }
                .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var previewPhase: some View {
        VStack(spacing: 0) {
            HStack {
                if isLookingUp {
                    ProgressView(value: Double(progressDone), total: max(Double(progressTotal), 1))
                        .frame(maxWidth: 220)
                    Text("查询中 \(progressDone)/\(progressTotal)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("停止") { cancelLookup() }
                } else {
                    Text("可保存 \(readyCount) 个 · 跳过 \(skippedCount) · 失败 \(failedCount)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新编辑文本") {
                    cancelLookup()
                    drafts = []
                }
                .disabled(isLookingUp)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Table(drafts) {
                TableColumn("发音") { draft in
                    SpeakButton(word: draft.english, size: 12)
                        .disabled(draft.status != .ready)
                }
                .width(44)

                TableColumn("英文") { draft in
                    Text(draft.english)
                }
                .width(min: 90, ideal: 120)

                TableColumn("音标") { draft in
                    Text(draft.phonetic.isEmpty ? "—" : draft.phonetic)
                        .foregroundStyle(.secondary)
                        .font(.caption.monospaced())
                }
                .width(min: 90, ideal: 130)

                TableColumn("中文") { draft in
                    Text(draft.chinese.isEmpty ? (draft.message ?? "—") : draft.chinese)
                        .lineLimit(2)
                        .foregroundStyle(draft.status == .failed ? .red : .primary)
                }
                .width(min: 140, ideal: 220)

                TableColumn("分组") { draft in
                    Picker("", selection: bindingGroup(for: draft.id)) {
                        Text("未分组").tag(GroupChoice.none)
                        ForEach(groups, id: \.uuid) { group in
                            Text(group.name).tag(GroupChoice.group(group.uuid))
                        }
                    }
                    .labelsHidden()
                    .disabled(draft.status == .skipped || isLookingUp)
                }
                .width(min: 110, ideal: 150)

                TableColumn("状态") { draft in
                    statusLabel(draft.status)
                }
                .width(64)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func bindingGroup(for id: UUID) -> Binding<GroupChoice> {
        Binding(
            get: { drafts.first(where: { $0.id == id })?.groupChoice ?? .none },
            set: { newValue in
                if let idx = drafts.firstIndex(where: { $0.id == id }) {
                    drafts[idx].groupChoice = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func statusLabel(_ status: ImportDraft.Status) -> some View {
        switch status {
        case .pending: Text("等待").foregroundStyle(.secondary)
        case .loading: ProgressView().controlSize(.small)
        case .ready: Text("就绪").foregroundStyle(.green)
        case .failed: Text("失败").foregroundStyle(.red)
        case .skipped: Text("跳过").foregroundStyle(.orange)
        }
    }

    private var readyCount: Int { drafts.filter { $0.status == .ready }.count }
    private var failedCount: Int { drafts.filter { $0.status == .failed }.count }
    private var skippedCount: Int { drafts.filter { $0.status == .skipped }.count }

    private func cancelLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        if isLookingUp {
            isLookingUp = false
            batchLog.info("Batch lookup cancelled")
            AppLog.console("批量查询已取消", category: "BatchImport")
        }
    }

    @MainActor
    private func prepareAndLookup() async {
        let existing = Set(existingWords.map(\.english))
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var built: [ImportDraft] = []
        for line in lines {
            let token = line.split(whereSeparator: { $0 == "," || $0 == "\t" || $0 == " " }).first.map(String.init) ?? line
            let english = token.lowercased()
            guard !english.isEmpty else { continue }
            if seen.contains(english) { continue }
            seen.insert(english)

            var draft = ImportDraft(english: english, groupChoice: defaultGroupChoice)
            if existing.contains(english) {
                draft.status = .skipped
                draft.message = "词库已存在"
            }
            built.append(draft)
        }

        drafts = built
        let fetchIndices = built.indices.filter { built[$0].status != .skipped }
        progressTotal = fetchIndices.count
        progressDone = 0
        isLookingUp = true

        batchLog.info("Batch start: \(built.count) drafts, \(fetchIndices.count) to fetch")
        AppLog.console(
            "开始批量查询 \(fetchIndices.count) 个单词（并发 \(maxConcurrentLookups)）",
            category: "BatchImport"
        )

        let service = YoudaoDictionaryService(
            appKey: settings.youdaoAppKey,
            appSecret: settings.youdaoAppSecret,
            allowMockFallback: settings.useMockWhenNoKey
        )

        var offset = 0
        while offset < fetchIndices.count {
            if Task.isCancelled { break }
            let end = min(offset + maxConcurrentLookups, fetchIndices.count)
            let chunk = Array(fetchIndices[offset..<end])

            for index in chunk {
                drafts[index].status = .loading
            }

            await withTaskGroup(of: (Int, Result<DictionaryLookupResult, Error>).self) { group in
                for index in chunk {
                    let word = drafts[index].english
                    group.addTask {
                        do {
                            let result = try await service.lookup(word: word)
                            return (index, .success(result))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }

                for await (index, result) in group {
                    if Task.isCancelled { break }
                    switch result {
                    case .success(let lookup):
                        drafts[index].phonetic = lookup.phonetic
                        drafts[index].chinese = lookup.chinese
                        drafts[index].source = lookup.source
                        drafts[index].status = .ready
                    case .failure(let error):
                        drafts[index].status = .failed
                        drafts[index].message = error.localizedDescription
                        batchLog.error(
                            "Fail \(drafts[index].english, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    progressDone += 1
                }
            }

            offset = end
        }

        isLookingUp = false
        lookupTask = nil
        batchLog.info("Batch finished: ready=\(self.readyCount) failed=\(self.failedCount)")
        AppLog.console(
            "批量查询结束：就绪 \(readyCount)，失败 \(failedCount)",
            category: "BatchImport"
        )
    }

    private func commit() {
        var saved = 0
        for draft in drafts where draft.status == .ready {
            let group = groups.first { $0.uuid == draft.groupChoice.uuid }
            let word = Word(
                english: draft.english,
                phonetic: draft.phonetic,
                chinese: draft.chinese,
                source: draft.source.isEmpty ? "youdao" : draft.source,
                group: group
            )
            modelContext.insert(word)
            word.group = group
            saved += 1
            AppLog.console(
                "写入 \(draft.english) → 组 \(group?.name ?? "未分组")，中文=\(draft.chinese)",
                category: "BatchImport"
            )
        }
        try? modelContext.save()
        statusMessage = "成功写入 \(saved) 个单词。"
        didSave = true
    }
}
