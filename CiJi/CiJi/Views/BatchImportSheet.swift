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
    var groupSelection: GroupSelection = .none
    var status: Status = .pending
    var message: String?
    /// Already in the library — commit merges selected groups onto the existing word.
    var alreadyExists: Bool = false

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
    @State private var defaultGroupSelection = GroupSelection.none
    @State private var bulkSelection = GroupSelection.none
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
            #if os(macOS)
            .navigationSubtitle(AppTheme.brandName)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isLookingUp ? "停止" : "取消") {
                        if isLookingUp { cancelLookup() } else { dismiss() }
                    }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("写入词库") { commit() }
                            .disabled(isLookingUp || savableCount == 0)
                    }
                }
            }
            .onAppear {
                defaultGroupSelection = GroupSelection(preferred: preferredGroup)
                bulkSelection = defaultGroupSelection
            }
            .onDisappear { cancelLookup() }
            .alert("导入完成", isPresented: $didSave) {
                Button("好") { dismiss() }
            } message: {
                Text(statusMessage ?? "单词已加入词库。")
            }
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    // MARK: - Input

    private var inputPhase: some View {
        Form {
            Section {
                Text("每行一个英文单词或短语（如 look forward to）。同一行也可用逗号/制表符分隔多个词条。可多选默认分组；预览阶段还能批量改组或逐条调整。词库已有的词条会直接复用音标与中文，不再联网查询。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("词条列表") {
                TextEditor(text: $rawText)
                    .font(.body.monospaced())
                    .frame(minHeight: 200)
            }

            Section("默认分组（可多选）") {
                GroupMultiPicker(selection: $defaultGroupSelection, groups: groups)
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

    // MARK: - Preview

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
                    Text("可写入 \(savableCount) · 新建 \(newReadyCount) · 追加 \(existingReadyCount) · 跳过 \(skippedCount) · 失败 \(failedCount)")
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

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("批量修改分组")
                        .font(.headline)
                    Text("应用到所有「新建 / 追加」项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .leading)

                GroupMultiPicker(
                    selection: $bulkSelection,
                    groups: groups,
                    showCapacityWarnings: false
                )
                .frame(maxWidth: 320)

                VStack(spacing: 8) {
                    Button("应用到全部可写入项") { applyBulkGroups() }
                        .disabled(isLookingUp || savableCount == 0)
                    Button("清空全部分组") {
                        bulkSelection = .none
                        applyBulkGroups()
                    }
                    .disabled(isLookingUp || savableCount == 0)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Table(drafts) {
                TableColumn("发音") { draft in
                    SpeakButton(word: draft.english, size: 12, pronunciation: pronunciation, settings: settings)
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
                .width(min: 140, ideal: 200)

                TableColumn("分组") { draft in
                    Menu {
                        Button("未分组") {
                            setGroups(for: draft.id, selection: .none)
                        }
                        ForEach(groups, id: \.uuid) { group in
                            Button {
                                toggleGroup(for: draft.id, uuid: group.uuid)
                            } label: {
                                HStack {
                                    Text(group.name)
                                    if draft.groupSelection.contains(group.uuid) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(draft.groupSelection.summary(from: groups))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(draft.status == .skipped || isLookingUp)
                }
                .width(min: 120, ideal: 160)

                TableColumn("状态") { draft in
                    statusLabel(draft)
                }
                .width(min: 72, ideal: 88)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func statusLabel(_ draft: ImportDraft) -> some View {
        switch draft.status {
        case .pending:
            Text("等待").foregroundStyle(.secondary)
        case .loading:
            ProgressView().controlSize(.small)
        case .ready:
            Text(draft.alreadyExists ? "追加" : "新建")
                .foregroundStyle(draft.alreadyExists ? .blue : .green)
        case .failed:
            Text("失败").foregroundStyle(.red)
        case .skipped:
            Text("跳过").foregroundStyle(.orange)
        }
    }

    private var savableCount: Int { drafts.filter { $0.status == .ready }.count }
    private var newReadyCount: Int { drafts.filter { $0.status == .ready && !$0.alreadyExists }.count }
    private var existingReadyCount: Int { drafts.filter { $0.status == .ready && $0.alreadyExists }.count }
    private var failedCount: Int { drafts.filter { $0.status == .failed }.count }
    private var skippedCount: Int { drafts.filter { $0.status == .skipped }.count }

    private func setGroups(for id: UUID, selection: GroupSelection) {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].groupSelection = selection
    }

    private func toggleGroup(for id: UUID, uuid: UUID) {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].groupSelection.toggle(uuid)
    }

    private func applyBulkGroups() {
        for index in drafts.indices where drafts[index].status == .ready {
            drafts[index].groupSelection = bulkSelection
        }
        AppLog.console(
            "批量改组 → \(bulkSelection.summary(from: groups))，影响 \(savableCount) 项",
            category: "BatchImport"
        )
    }

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
        let existingByEnglish = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.english, $0) })
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var built: [ImportDraft] = []
        for line in lines {
            // Keep spaces so phrases like "look forward to" stay intact.
            // Only comma / tab start a new entry on the same line.
            let entries = line
                .split(whereSeparator: { $0 == "," || $0 == "\t" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for token in entries {
                let raw = token.lowercased()
                guard !raw.isEmpty else { continue }
                let lemma = EnglishLemmatizer.lemma(for: raw)
                if seen.contains(lemma) { continue }
                seen.insert(lemma)

                var draft = ImportDraft(english: raw, groupSelection: defaultGroupSelection)
                if let existing = existingByEnglish[lemma] ?? existingByEnglish[raw] {
                    // Reuse library gloss — do not call the dictionary API again.
                    draft.alreadyExists = true
                    draft.english = existing.english
                    draft.phonetic = existing.phonetic
                    draft.chinese = existing.chinese
                    draft.source = existing.source.isEmpty ? "library" : existing.source
                    draft.status = .ready
                    draft.message = "词库已有，已填入音标与中文"
                }
                built.append(draft)
            }
        }

        drafts = built
        bulkSelection = defaultGroupSelection
        let fetchIndices = built.indices.filter { !built[$0].alreadyExists } // skip library hits
        progressTotal = fetchIndices.count
        progressDone = 0
        isLookingUp = true

        batchLog.info("Batch start: \(built.count) drafts")
        AppLog.console(
            "开始批量查询：联网 \(fetchIndices.count) 个，词库复用 \(built.filter(\.alreadyExists).count) 个（并发 \(maxConcurrentLookups)）",
            category: "BatchImport"
        )

        let service = YoudaoDictionaryService(allowMockFallback: settings.useMockOnFailure)

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
                        drafts[index].english = lookup.english
                        drafts[index].phonetic = lookup.phonetic
                        drafts[index].chinese = lookup.chinese
                        drafts[index].source = lookup.source
                        drafts[index].status = .ready
                        if drafts[index].alreadyExists {
                            drafts[index].message = "词库已有，将追加所选分组"
                        } else if lookup.wasLemmatized, let inputForm = lookup.inputForm {
                            drafts[index].message = "由 \(inputForm) 还原"
                        }
                    case .failure(let error):
                        if drafts[index].alreadyExists {
                            drafts[index].status = .ready
                            drafts[index].message = "词库已有（刷新释义失败）：仍可追加分组"
                        } else {
                            drafts[index].status = .failed
                            drafts[index].message = error.localizedDescription
                            batchLog.error(
                                "Fail \(drafts[index].english, privacy: .public): \(error.localizedDescription, privacy: .public)"
                            )
                        }
                    }
                    progressDone += 1
                }
            }

            offset = end
        }

        isLookingUp = false
        lookupTask = nil
        batchLog.info("Batch finished: ready=\(self.savableCount) failed=\(self.failedCount)")
        AppLog.console(
            "批量查询结束：可写入 \(savableCount)，失败 \(failedCount)",
            category: "BatchImport"
        )
    }

    private func commit() {
        var created = 0
        var merged = 0
        let existingByEnglish = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.english, $0) })
        // Preserve the user's input order via monotonic sortOrder.
        var nextOrder = (existingWords.map(\.sortOrder).max() ?? -1) + 1

        for draft in drafts where draft.status == .ready {
            let targetGroups = draft.groupSelection.resolve(from: groups)
            let key = draft.english.lowercased()
            if let existing = existingByEnglish[key] {
                for group in targetGroups {
                    existing.addToGroup(group)
                }
                if existing.phonetic.isEmpty, !draft.phonetic.isEmpty {
                    existing.phonetic = draft.phonetic
                }
                if existing.chinese.isEmpty, !draft.chinese.isEmpty {
                    existing.chinese = draft.chinese
                }
                merged += 1
                AppLog.console(
                    "追加 \(draft.english) → \(draft.groupSelection.summary(from: groups))",
                    category: "BatchImport"
                )
            } else {
                let word = Word(
                    english: draft.english,
                    phonetic: draft.phonetic,
                    chinese: draft.chinese,
                    sortOrder: nextOrder,
                    source: draft.source.isEmpty ? "youdao" : draft.source,
                    groups: targetGroups
                )
                nextOrder += 1
                modelContext.insert(word)
                created += 1
                AppLog.console(
                    "新建 \(draft.english) → \(draft.groupSelection.summary(from: groups))，中文=\(draft.chinese)",
                    category: "BatchImport"
                )
            }
        }
        try? modelContext.save()
        statusMessage = "新建 \(created) 个，追加分组 \(merged) 个。"
        didSave = true
    }
}