import Foundation
import SwiftData

/// One completed practice round (persisted).
@Model
final class PracticeRecord {
    var uuid: UUID
    var completedAt: Date
    /// Scope id: `all` / `ungrouped` / group UUID string.
    var scopeID: String
    var scopeLabel: String
    var totalCount: Int
    /// Number of distinct words answered incorrectly this round.
    var wrongWordCount: Int
    var correctCount: Int

    init(
        scopeID: String,
        scopeLabel: String,
        totalCount: Int,
        wrongWordCount: Int,
        correctCount: Int,
        completedAt: Date = Date()
    ) {
        self.uuid = UUID()
        self.completedAt = completedAt
        self.scopeID = scopeID
        self.scopeLabel = scopeLabel
        self.totalCount = totalCount
        self.wrongWordCount = wrongWordCount
        self.correctCount = correctCount
    }
}
