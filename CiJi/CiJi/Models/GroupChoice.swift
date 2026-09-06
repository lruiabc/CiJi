import Foundation

/// Shared group picker value — avoids SwiftUI Optional-UUID tag matching bugs on macOS.
enum GroupChoice: Hashable, Identifiable {
    case none
    case group(UUID)

    var id: String {
        switch self {
        case .none: return "none"
        case .group(let uuid): return uuid.uuidString
        }
    }

    var uuid: UUID? {
        switch self {
        case .none: return nil
        case .group(let uuid): return uuid
        }
    }

    init(uuid: UUID?) {
        if let uuid {
            self = .group(uuid)
        } else {
            self = .none
        }
    }
}
