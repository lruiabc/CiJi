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
    var group: WordGroup?

    init(
        english: String,
        phonetic: String = "",
        chinese: String = "",
        sortOrder: Int = 0,
        source: String = "youdao",
        group: WordGroup? = nil
    ) {
        self.uuid = UUID()
        self.english = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.phonetic = phonetic
        self.chinese = chinese
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.source = source
        self.group = group
    }
}
