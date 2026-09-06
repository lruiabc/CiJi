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
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var selectedWordIDs: Set<Word.ID> = []
    @State private var renameTarget: WordGroup?
    @State private var renameText = ""

    private var visibleWords: [Word] {
        let base: [Word]
        switch selection {
        case .all:
            base = allWords
        case .ungrouped:
            base = allWords.filter { $0.group == nil }
        case .group(let id):
            base = allWords.filter { $0.group?.uuid == id }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.english.localizedCaseInsensitiveContains(q)
                || $0.chinese.localizedCaseInsensitiveContains(q)
                || $0.phonetic.localizedCaseInsensitiveContains(q)
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
        }
        .sheet(isPresented: $showBatchSheet) {
            BatchImportSheet(preferredGroup: currentGroup)
        }
        .alert("新建分组", isPresented: $showNewGroupAlert) {
            TextField("分组名称，例如：第一组", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") { createGroup() }
        } message: {
            Text("每组默认容量为 \(settings.defaultGroupCapacity) 个单词，可在设置中修改。")
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
                Label("全部单词", systemImage: "books.vertical")
                    .badge(allWords.count)
                    .tag(SidebarSelection.all)

                Label("未分组", systemImage: "tray")
                    .badge(allWords.filter { $0.group == nil }.count)
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
                        Button("删除分组", role: .destructive) {
                            deleteGroup(group)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("词记")
        .safeAreaInset(edge: .bottom) {
            Button {
                newGroupName = nextDefaultGroupName()
                showNewGroupAlert = true
            } label: {
                Label("新建分组", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if visibleWords.isEmpty {
                emptyState
            } else {
                wordTable
            }
        }
        .navigationTitle(detailTitle)
        .searchable(text: $searchText, prompt: "搜索英文 / 中文 / 音标")
    }

    private var detailTitle: String {
        switch selection {
        case .all: return "全部单词"
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
                Label("添加单词", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button {
                showBatchSheet = true
            } label: {
                Label("批量导入", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            if !selectedWordIDs.isEmpty {
                Menu {
                    Button("移到「未分组」") {
                        moveSelected(to: nil)
                    }
                    ForEach(groups, id: \.uuid) { group in
                        Button(group.name) {
                            moveSelected(to: group)
                        }
                    }
                } label: {
                    Label("移动到组 (\(selectedWordIDs.count))", systemImage: "arrow.right.doc.on.clipboard")
                }

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }

            Spacer()

            Text("\(visibleWords.count) 个单词")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "text.book.closed")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("添加单词") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
            Button("批量导入") { showBatchSheet = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "没有匹配的单词" }
        switch selection {
        case .all: return "词库还是空的"
        case .ungrouped: return "没有未分组单词"
        case .group: return "这个分组还没有单词"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "试试其他关键词，或清空搜索。" }
        return "先添加几个英文单词。系统会自动查询音标与中文，并可一键听发音。"
    }

    private var wordTable: some View {
        Table(visibleWords, selection: $selectedWordIDs) {
            TableColumn("发音") { word in
                SpeakButton(word: word.english, size: 13)
            }
            .width(min: 44, ideal: 52, max: 64)

            TableColumn("英文") { word in
                Text(word.english)
                    .font(.body.weight(.medium))
            }
            .width(min: 100, ideal: 140)

            TableColumn("音标") { word in
                Text(word.phonetic.isEmpty ? "—" : word.phonetic)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
            .width(min: 100, ideal: 150)

            TableColumn("中文") { word in
                Text(word.chinese.isEmpty ? "—" : word.chinese)
                    .lineLimit(2)
            }
            .width(min: 160, ideal: 280)

            TableColumn("分组") { word in
                Text(word.group?.name ?? "未分组")
                    .foregroundStyle(word.group == nil ? .tertiary : .secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("来源") { word in
                Text(word.source == "google" ? "Google" : (word.source == "mock" ? "示例" : word.source))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(min: 48, ideal: 56)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Word.ID.self) { ids in
            if !ids.isEmpty {
                Menu("移动到组") {
                    Button("未分组") { move(ids: ids, to: nil) }
                    ForEach(groups, id: \.uuid) { group in
                        Button(group.name) { move(ids: ids, to: group) }
                    }
                }
                Button("删除", role: .destructive) {
                    selectedWordIDs = ids
                    deleteSelected()
                }
            }
        }
    }

    // MARK: - Actions

    private func nextDefaultGroupName() -> String {
        let index = groups.count + 1
        return "第\(index)组"
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
        for word in group.words {
            word.group = nil
        }
        if case .group(let id) = selection, id == group.uuid {
            selection = .all
        }
        modelContext.delete(group)
        try? modelContext.save()
    }

    private func moveSelected(to group: WordGroup?) {
        move(ids: selectedWordIDs, to: group)
    }

    private func move(ids: Set<Word.ID>, to group: WordGroup?) {
        for word in allWords where ids.contains(word.persistentModelID) {
            word.group = group
        }
        try? modelContext.save()
        AppLog.console("移动 \(ids.count) 个单词 → \(group?.name ?? "未分组")", category: "Groups")
    }

    private func deleteSelected() {
        for word in allWords where selectedWordIDs.contains(word.persistentModelID) {
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
        .modelContainer(for: [Word.self, WordGroup.self], inMemory: true)
}
