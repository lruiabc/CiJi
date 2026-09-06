import Foundation

/// Multi-group selection for pickers — empty means ungrouped.
struct GroupSelection: Hashable, Equatable {
    var ids: Set<UUID>

    static var none: GroupSelection { GroupSelection(ids: []) }

    var isEmpty: Bool { ids.isEmpty }

    init(ids: Set<UUID> = []) {
        self.ids = ids
    }

    init(uuid: UUID?) {
        if let uuid {
            self.ids = [uuid]
        } else {
            self.ids = []
        }
    }

    init(preferred: WordGroup?) {
        self.init(uuid: preferred?.uuid)
    }

    mutating func toggle(_ uuid: UUID) {
        if ids.contains(uuid) {
            ids.remove(uuid)
        } else {
            ids.insert(uuid)
        }
    }

    func contains(_ uuid: UUID) -> Bool {
        ids.contains(uuid)
    }

    func resolve(from groups: [WordGroup]) -> [WordGroup] {
        groups.filter { ids.contains($0.uuid) }
    }

    func summary(from groups: [WordGroup]) -> String {
        let names = resolve(from: groups).map(\.name)
        if names.isEmpty { return "未分组" }
        if names.count == 1 { return names[0] }
        return "\(names.count) 个分组"
    }
}
