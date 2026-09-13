import SwiftUI
import SwiftData

struct AddWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pronunciation: PronunciationService

    @Query(sort: \WordGroup.sortOrder) private var groups: [WordGroup]
    @Query private var existingWords: [Word]

    var preferredGroup: WordGroup?

    @State private var input = ""
    @State private var groupSelection = GroupSelection.none
    @State private var preview: DictionaryLookupResult?
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var saveSucceeded = false
    @State private var saveAlertMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("英文单词 / 短语") {
                    HStack(spacing: 10) {
                        TextField("例如：resilient 或 look forward to", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await lookup() } }

                        Button("查询") {
                            Task { await lookup() }
                        }
                        .disabled(isLookingUp || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }

                Section("查词结果") {
                    if isLookingUp {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在查询音标与中文…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let preview {
                        LabeledContent("英文") {
                            HStack(spacing: 8) {
                                Text(preview.english)
                                    .font(AppTheme.wordFont)
                                    .foregroundStyle(AppTheme.ink)
                                SpeakButton(word: preview.english, size: 14, helpText: "试听发音", pronunciation: pronunciation, settings: settings)
                            }
                        }
                        if preview.wasLemmatized, let inputForm = preview.inputForm {
                            Text("已还原为原型（输入：\(inputForm)）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("音标 (IPA)") {
                            Text(preview.phonetic.isEmpty ? "—" : preview.phonetic)
                                .font(.body.monospaced())
                        }
                        LabeledContent("中文") {
                            Text(preview.chinese.isEmpty ? "—" : preview.chinese)
                                .textSelection(.enabled)
                        }
                        LabeledContent("来源") {
                            Text(sourceLabel(preview.source))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("可输入单词或短语。单词会尝试还原为原型；短语按原样查询，并显示音标、中文与发音。")
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                    if let infoMessage {
                        Text(infoMessage)
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                Section("放入分组（可多选）") {
                    GroupMultiPicker(selection: $groupSelection, groups: groups)
                    Text("同一词条可同时属于多个分组。若词库已有该词条，将把所选分组追加进去。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("添加词条")
            #if os(macOS)
            .navigationSubtitle(AppTheme.brandName)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存到词库") { save() }
                        .disabled(preview == nil || isLookingUp)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
            }
            .onAppear {
                groupSelection = GroupSelection(preferred: preferredGroup)
            }
            .alert("已保存", isPresented: $saveSucceeded) {
                Button("继续添加") {
                    input = ""
                    preview = nil
                    infoMessage = nil
                    errorMessage = nil
                }
                Button("完成") { dismiss() }
            } message: {
                Text(saveAlertMessage)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "youdao": return "有道"
        case "mock": return "本地示例"
        case "google": return "Google（旧）"
        default: return source
        }
    }

    private func dictionaryService() -> YoudaoDictionaryService {
        YoudaoDictionaryService(allowMockFallback: settings.useMockOnFailure)
    }

    private func lookup() async {
        errorMessage = nil
        infoMessage = nil
        preview = nil
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            errorMessage = "请输入英文单词或短语"
            return
        }

        isLookingUp = true
        defer { isLookingUp = false }

        do {
            let result = try await dictionaryService().lookup(word: word)
            preview = result
            AppLog.console(
                "查词 输入=\(word) → 原型=\(result.english) | 音标=\(result.phonetic) | 中文=\(result.chinese) | 来源=\(result.source)",
                category: "AddWord"
            )
            if result.wasLemmatized, let inputForm = result.inputForm {
                infoMessage = "已将「\(inputForm)」还原为原型「\(result.english)」。"
            }
            if result.source == "mock" {
                let mockNote = "网络查询失败，已使用本地示例释义。可在设置中关闭该回退。"
                infoMessage = [infoMessage, mockNote].compactMap { $0 }.joined(separator: " ")
            }
            if result.phonetic.isEmpty {
                let phNote = "未找到 IPA 音标（词典源暂无该词读音）。"
                infoMessage = [infoMessage, phNote].compactMap { $0 }.joined(separator: " ")
            }
            if existingWords.contains(where: { $0.english == result.english.lowercased() }) {
                let existNote = "词库已有「\(result.english)」，保存时会追加所选分组。"
                infoMessage = [infoMessage, existNote].compactMap { $0 }.joined(separator: " ")
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.console("查词失败：\(error.localizedDescription)", category: "AddWord")
        }
    }

    private func save() {
        guard let preview else { return }
        let english = preview.english.lowercased()
        let targetGroups = groupSelection.resolve(from: groups)

        if let existing = existingWords.first(where: { $0.english == english }) {
            for group in targetGroups {
                existing.addToGroup(group)
            }
            // Optionally refresh gloss if empty
            if existing.phonetic.isEmpty, !preview.phonetic.isEmpty {
                existing.phonetic = preview.phonetic
            }
            if existing.chinese.isEmpty, !preview.chinese.isEmpty {
                existing.chinese = preview.chinese
            }
            try? modelContext.save()
            let names = targetGroups.map(\.name).joined(separator: "、")
            saveAlertMessage = targetGroups.isEmpty
                ? "词库已有「\(english)」。未选择分组，未改动其所属分组。"
                : "词库已有「\(english)」，已追加到：\(names)。"
            AppLog.console("追加分组 \(english) → \(names.isEmpty ? "无" : names)", category: "AddWord")
            saveSucceeded = true
            return
        }

        let word = Word(
            english: preview.english,
            phonetic: preview.phonetic,
            chinese: preview.chinese,
            source: preview.source,
            groups: targetGroups
        )
        modelContext.insert(word)
        try? modelContext.save()
        let names = targetGroups.map(\.name).joined(separator: "、")
        saveAlertMessage = targetGroups.isEmpty
            ? "「\(english)」已保存为未分组。"
            : "「\(english)」已加入：\(names)。"
        AppLog.console("保存 \(english) → \(names.isEmpty ? "未分组" : names)", category: "AddWord")
        saveSucceeded = true
    }
}
