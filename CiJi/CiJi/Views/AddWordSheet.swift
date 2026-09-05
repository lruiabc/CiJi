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
    @State private var selectedGroupID: UUID?
    @State private var preview: DictionaryLookupResult?
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var saveSucceeded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("英文单词") {
                    HStack(spacing: 10) {
                        TextField("例如：resilient", text: $input)
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
                                    .font(.body.weight(.semibold))
                                SpeakButton(word: preview.english, size: 14, helpText: "试听发音")
                            }
                        }
                        LabeledContent("音标") {
                            Text(preview.phonetic.isEmpty ? "—" : preview.phonetic)
                                .font(.body.monospaced())
                        }
                        LabeledContent("中文") {
                            Text(preview.chinese.isEmpty ? "—" : preview.chinese)
                                .textSelection(.enabled)
                        }
                        LabeledContent("来源") {
                            Text(preview.source == "youdao" ? "有道词典" : "本地示例")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("输入单词后点击「查询」，将显示音标、中文与发音按钮。")
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

                Section("放入分组") {
                    Picker("目标分组", selection: $selectedGroupID) {
                        Text("未分组").tag(UUID?.none)
                        ForEach(groups, id: \.uuid) { group in
                            Text("\(group.name)（\(group.wordCount)/\(group.capacity)）")
                                .tag(Optional(group.uuid))
                        }
                    }

                    if let group = selectedGroup {
                        if group.wordCount >= group.capacity {
                            Text("该组已满（\(group.capacity)）。仍可强制加入，建议新建分组或提高容量。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("添加单词")
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
                selectedGroupID = preferredGroup?.uuid
            }
            .alert("已加入词库", isPresented: $saveSucceeded) {
                Button("继续添加") {
                    input = ""
                    preview = nil
                    infoMessage = nil
                    errorMessage = nil
                }
                Button("完成") { dismiss() }
            } message: {
                Text("单词已保存。列表中可随时点击发音按钮听读音。")
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private var selectedGroup: WordGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first { $0.uuid == selectedGroupID }
    }

    private func dictionaryService() -> YoudaoDictionaryService {
        YoudaoDictionaryService(
            appKey: settings.youdaoAppKey,
            appSecret: settings.youdaoAppSecret,
            allowMockFallback: settings.useMockWhenNoKey
        )
    }

    private func lookup() async {
        errorMessage = nil
        infoMessage = nil
        preview = nil
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            errorMessage = "请输入英文单词"
            return
        }

        isLookingUp = true
        defer { isLookingUp = false }

        do {
            let result = try await dictionaryService().lookup(word: word)
            preview = result
            if result.source == "mock" {
                infoMessage = DictionaryServiceError.missingCredentials.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let preview else { return }
        let english = preview.english.lowercased()
        if existingWords.contains(where: { $0.english == english }) {
            errorMessage = "词库中已有「\(english)」，请勿重复添加。"
            return
        }

        let word = Word(
            english: preview.english,
            phonetic: preview.phonetic,
            chinese: preview.chinese,
            source: preview.source,
            group: selectedGroup
        )
        modelContext.insert(word)
        try? modelContext.save()
        saveSucceeded = true
    }
}
