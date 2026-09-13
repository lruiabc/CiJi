import SwiftUI
import SwiftData
import AppKit

enum SidebarSelection: Hashable {
    case all
    case ungrouped
    case group(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pronunciation: PronunciationService

    @Query(sort: \WordGroup.sortOrder) private var groups: [WordGroup]
    @Query(sort: \Word.createdAt, order: .reverse) private var allWords: [Word]

    @State private var selection: SidebarSelection = .all
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showBatchSheet = false
    @State private var showQuizSheet = false
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var selectedWordIDs: Set<Word.ID> = []
    @State private var renameTarget: WordGroup?
    @State private var renameText = ""
    @State private var editingChineseWord: Word?
    @State private var editingChineseText = ""

    private var visibleWords: [Word] {
        let base: [Word]
        switch selection {
        case .all:
            base = allWords
        case .ungrouped:
            base = allWords.filter(\.isUngrouped)
        case .group(let id):
            base = allWords.filter { word in
                word.groups.contains(where: { $0.uuid == id })
            }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.english.localizedCaseInsensitiveContains(q)
                || $0.chinese.localizedCaseInsensitiveContains(q)
                || $0.phonetic.localizedCaseInsensitiveContains(q)
        }
    }

    private var quizPreferredScope: QuizSession.Scope {
        switch selection {
        case .all: return .all
        case .ungrouped: return .ungrouped
        case .group(let id): return .group(id)
        }
    }

    private var currentGroup: WordGroup? {
        if case .group(let id) = selection {
            return groups.first { $0.uuid == id }
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detail
        }
        .sheet(isPresented: $showAddSheet) {
            AddWordSheet(preferredGroup: currentGroup)
                .environmentObject(settings)
                .environmentObject(pronunciation)
        }
        .sheet(isPresented: $showBatchSheet) {
            BatchImportSheet(preferredGroup: currentGroup)
                .environmentObject(settings)
                .environmentObject(pronunciation)
        }
        .sheet(isPresented: $showQuizSheet) {
            QuizView(preferredScope: quizPreferredScope)
                .environmentObject(settings)
                .environmentObject(pronunciation)
        }
        .alert("新建分组", isPresented: $showNewGroupAlert) {
            TextField("分组名称，例如：第一组", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") { createGroup() }
        } message: {
            Text("每组默认容量为 \(settings.defaultGroupCapacity) 个词条，可在设置中修改。")
        }
        .alert(
            "重命名分组",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("分组名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let g = renameTarget {
                    g.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? modelContext.save()
                }
                renameTarget = nil
            }
        }
        
        .alert(
            "编辑中文释义",
            isPresented: Binding(
                get: { editingChineseWord != nil },
                set: { if !$0 { editingChineseWord = nil } }
            )
        ) {
            TextField("中文意思", text: $editingChineseText)
            Button("取消", role: .cancel) { editingChineseWord = nil }
            Button("保存") { saveChineseEdit() }
        } message: {
            if let word = editingChineseWord {
                Text("修改「\(word.english)」的中文释义。")
            }
        }

        .overlay(alignment: .bottom) {
            if let err = pronunciation.lastError {
                Text(err)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { pronunciation.lastError = nil }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("词库") {
                Label("全部词条", systemImage: "books.vertical")
                    .badge(allWords.count)
                    .tag(SidebarSelection.all)

                Label("未分组", systemImage: "tray")
                    .badge(allWords.filter(\.isUngrouped).count)
                    .tag(SidebarSelection.ungrouped)
            }

            Section("分组") {
                if groups.isEmpty {
                    Text("暂无分组")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(groups, id: \.uuid) { group in
                    Label {
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(group.wordCount)/\(group.capacity)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(group.isOverCapacity ? .orange : .secondary)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .tag(SidebarSelection.group(group.uuid))
                    .contextMenu {
                        Button("重命名…") {
                            renameTarget = group
                            renameText = group.name
                        }
                        Button("容量设为 \(settings.defaultGroupCapacity)") {
                            group.capacity = settings.defaultGroupCapacity
                            try? modelContext.save()
                        }
                        Divider()
                        Button("练习此组") {
                            selection = .group(group.uuid)
                            showQuizSheet = true
                        }
                        Divider()
                        Button("删除分组", role: .destructive) {
                            deleteGroup(group)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppTheme.brandName)
        .safeAreaInset(edge: .top) {
            BrandMark(compact: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                newGroupName = nextDefaultGroupName()
                showNewGroupAlert = true
            } label: {
                Label("新建分组", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.jade.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.ink)
            .padding(12)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack {
            AppAtmosphereBackground()
            VStack(spacing: 0) {
                toolbar
                Divider().opacity(0.5)
                if visibleWords.isEmpty {
                    emptyState
                } else {
                    wordTable
                }
            }
        }
        .navigationTitle(detailTitle)
        .searchable(text: $searchText, prompt: "搜索英文 / 中文 / 音标")
    }

    private var detailTitle: String {
        switch selection {
        case .all: return "全部词条"
        case .ungrouped: return "未分组"
        case .group(let id):
            return groups.first { $0.uuid == id }?.name ?? "分组"
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                showAddSheet = true
            } label: {
                Label("添加词条", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button {
                showBatchSheet = true
            } label: {
                Label("批量导入", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                showQuizSheet = true
            } label: {
                Label("练习", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            .keyboardShortcut("p", modifiers: [.command])
            .help("按分组练习：看英文，默写中文")

            if !selectedWordIDs.isEmpty {
                if selectedWordIDs.count == 1, let word = selectedWords(from: selectedWordIDs).first {
                    Button {
                        beginChineseEdit(word)
                    } label: {
                        Label("编辑中文", systemImage: "pencil")
                    }
                }

                Menu {
                    Menu("加入分组") {
                        ForEach(groups, id: \.uuid) { group in
                            Button(group.name) {
                                addSelected(to: group)
                            }
                        }
                    }
                    Menu("仅保留此组") {
                        ForEach(groups, id: \.uuid) { group in
                            Button(group.name) {
                                replaceSelected(with: group)
                            }
                        }
                    }
                    if let currentGroup {
                        Button("移出「\(currentGroup.name)」") {
                            removeSelected(from: currentGroup)
                        }
                    }
                    Button("清空全部分组") {
                        clearSelectedGroups()
                    }
                } label: {
                    Label("分组 (\(selectedWordIDs.count))", systemImage: "folder.badge.gearshape")
                }

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }

            Spacer()

            Text("\(visibleWords.count) 个词条")
                .foregroundStyle(.secondary)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.mist.opacity(0.9)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.jade.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(AppTheme.jade)
            }
            Text(emptyTitle)
                .font(AppTheme.brandTitleFont)
                .foregroundStyle(AppTheme.ink)
            Text(emptyDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("添加词条") { showAddSheet = true }
                    .buttonStyle(PrimaryActionButtonStyle())
                Button("批量导入") { showBatchSheet = true }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "没有匹配的词条" }
        switch selection {
        case .all: return "词库还是空的"
        case .ungrouped: return "没有未分组词条"
        case .group: return "这个分组还没有词条"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "试试其他关键词，或清空搜索。" }
        return "先添加几个英文单词或短语。系统会自动查询音标与中文，并可一键听发音。同一词条可加入多个分组。"
    }

    private var wordTable: some View {
        Table(visibleWords, selection: $selectedWordIDs) {
            TableColumn("发音") { word in
                SpeakButton(word: word.english, size: 13, pronunciation: pronunciation, settings: settings)
            }
            .width(min: 44, ideal: 52, max: 64)

            TableColumn("英文") { word in
                Text(word.english)
                    .font(AppTheme.wordFont)
                    .foregroundStyle(AppTheme.ink)
            }
            .width(min: 100, ideal: 140)

            TableColumn("音标") { word in
                Text(word.phonetic.isEmpty ? "—" : word.phonetic)
                    .foregroundStyle(.secondary)
                    .font(AppTheme.phoneticFont)
            }
            .width(min: 100, ideal: 150)

            TableColumn("中文") { word in
                TextField("点击编辑中文", text: chineseBinding(for: word))
                    .textFieldStyle(.plain)
                    .help("直接修改中文释义，回车或失焦后自动保存")
            }
            .width(min: 160, ideal: 280)

            TableColumn("分组") { word in
                Text(word.groupNamesText)
                    .foregroundStyle(word.isUngrouped ? .tertiary : .secondary)
                    .lineLimit(2)
            }
            .width(min: 100, ideal: 160)

            TableColumn("错次") { word in
                Text(word.wrongAnswerCount == 0 ? "—" : "\(word.wrongAnswerCount)")
                    .foregroundStyle(word.wrongAnswerCount == 0 ? Color.secondary.opacity(0.5) : Color.orange)
                    .help("练习中累计答错次数")
            }
            .width(min: 44, ideal: 56, max: 72)

            TableColumn("来源") { word in
                Text({
                    switch word.source {
                    case "youdao": return "有道"
                    case "mock": return "示例"
                    case "google": return "Google"
                    default: return word.source
                    }
                }())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(min: 48, ideal: 56)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Word.ID.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1, let word = selectedWords(from: ids).first {
                    Button("编辑中文释义…") {
                        beginChineseEdit(word)
                    }
                    Divider()
                }
                Menu("加入分组") {
                    ForEach(groups, id: \.uuid) { group in
                        Button(group.name) { add(ids: ids, to: group) }
                    }
                }
                Menu("仅保留此组") {
                    ForEach(groups, id: \.uuid) { group in
                        Button(group.name) { replace(ids: ids, with: group) }
                    }
                }
                if let currentGroup {
                    Button("移出「\(currentGroup.name)」") {
                        remove(ids: ids, from: currentGroup)
                    }
                }
                Button("清空全部分组") {
                    clearGroups(ids: ids)
                }
                Divider()
                Button("删除", role: .destructive) {
                    selectedWordIDs = ids
                    deleteSelected()
                }
            }
        }
    }

    // MARK: - Actions

    private func nextDefaultGroupName() -> String {
        "第\(groups.count + 1)组"
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = WordGroup(
            name: name,
            capacity: settings.defaultGroupCapacity,
            sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(group)
        try? modelContext.save()
        selection = .group(group.uuid)
        newGroupName = ""
        AppLog.console("创建分组 \(name)", category: "Groups")
    }

    private func deleteGroup(_ group: WordGroup) {
        // Removing the group drops membership; words remain in the library.
        let members = Array(group.words)
        for word in members {
            word.removeFromGroup(group)
        }
        if case .group(let id) = selection, id == group.uuid {
            selection = .all
        }
        modelContext.delete(group)
        try? modelContext.save()
    }

    private func selectedWords(from ids: Set<Word.ID>) -> [Word] {
        allWords.filter { ids.contains($0.persistentModelID) }
    }

    private func addSelected(to group: WordGroup) {
        add(ids: selectedWordIDs, to: group)
    }

    private func add(ids: Set<Word.ID>, to group: WordGroup) {
        for word in selectedWords(from: ids) {
            word.addToGroup(group)
        }
        try? modelContext.save()
        AppLog.console("加入分组 \(ids.count) 个 → \(group.name)", category: "Groups")
    }

    private func replaceSelected(with group: WordGroup) {
        replace(ids: selectedWordIDs, with: group)
    }

    private func replace(ids: Set<Word.ID>, with group: WordGroup) {
        for word in selectedWords(from: ids) {
            word.setGroups([group])
        }
        try? modelContext.save()
        AppLog.console("仅保留分组 \(ids.count) 个 → \(group.name)", category: "Groups")
    }

    private func removeSelected(from group: WordGroup) {
        remove(ids: selectedWordIDs, from: group)
    }

    private func remove(ids: Set<Word.ID>, from group: WordGroup) {
        for word in selectedWords(from: ids) {
            word.removeFromGroup(group)
        }
        try? modelContext.save()
        AppLog.console("移出分组 \(ids.count) 个 ← \(group.name)", category: "Groups")
    }

    private func clearSelectedGroups() {
        clearGroups(ids: selectedWordIDs)
    }

    private func clearGroups(ids: Set<Word.ID>) {
        for word in selectedWords(from: ids) {
            word.setGroups([])
        }
        try? modelContext.save()
        AppLog.console("清空分组 \(ids.count) 个", category: "Groups")
    }


    private func chineseBinding(for word: Word) -> Binding<String> {
        Binding(
            get: { word.chinese },
            set: { newValue in
                guard word.chinese != newValue else { return }
                word.chinese = newValue
                try? modelContext.save()
            }
        )
    }

    private func beginChineseEdit(_ word: Word) {
        editingChineseWord = word
        editingChineseText = word.chinese
    }

    private func saveChineseEdit() {
        guard let word = editingChineseWord else { return }
        word.chinese = editingChineseText.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        AppLog.console("更新中文 \(word.english) → \(word.chinese)", category: "Words")
        editingChineseWord = nil
    }

    private func deleteSelected() {
        for word in selectedWords(from: selectedWordIDs) {
            modelContext.delete(word)
        }
        selectedWordIDs.removeAll()
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
        .environmentObject(PronunciationService())
        .modelContainer(for: [Word.self, WordGroup.self, PracticeRecord.self], inMemory: true)
}
