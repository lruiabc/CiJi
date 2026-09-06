import Foundation
import SwiftData

@Model
final class Word {
    var uuid: UUID
    var english: String
    var phonetic: String
    var chinese: String
    var createdAt: Date
    var sortOrder: Int
    var source: String
    /// Cumulative times this word was answered incorrectly in practice.
    var wrongAnswerCount: Int

    /// A word may belong to zero or more groups.
    @Relationship(inverse: \WordGroup.words)
    var groups: [WordGroup]

    init(
        english: String,
        phonetic: String = "",
        chinese: String = "",
        sortOrder: Int = 0,
        source: String = "google",
        groups: [WordGroup] = [],
        wrongAnswerCount: Int = 0
    ) {
        self.uuid = UUID()
        self.english = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.phonetic = phonetic
        self.chinese = chinese
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.source = source
        self.groups = groups
        self.wrongAnswerCount = max(0, wrongAnswerCount)
    }

    var isUngrouped: Bool { groups.isEmpty }

    var groupNamesText: String {
        let names = groups.map(\.name).sorted()
        return names.isEmpty ? "未分组" : names.joined(separator: "、")
    }

    func belongs(to group: WordGroup) -> Bool {
        groups.contains(where: { $0.uuid == group.uuid })
    }

    func addToGroup(_ group: WordGroup) {
        guard !belongs(to: group) else { return }
        groups.append(group)
    }

    func removeFromGroup(_ group: WordGroup) {
        groups.removeAll { $0.uuid == group.uuid }
    }

    func setGroups(_ newGroups: [WordGroup]) {
        groups = newGroups
    }
}
