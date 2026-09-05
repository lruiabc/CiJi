import Foundation
import SwiftData

@Model
final class WordGroup {
    var uuid: UUID
    var name: String
    var capacity: Int
    var sortOrder: Int
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Word.group)
    var words: [Word]

    init(name: String, capacity: Int = 20, sortOrder: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.capacity = max(1, capacity)
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.words = []
    }

    var wordCount: Int { words.count }

    var isOverCapacity: Bool { words.count > capacity }
}
