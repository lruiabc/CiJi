import SwiftUI

/// Checkbox list for picking zero or more groups.
struct GroupMultiPicker: View {
    @Binding var selection: GroupSelection
    let groups: [WordGroup]
    var showCapacityWarnings: Bool = true

    var body: some View {
        if groups.isEmpty {
            Text("还没有分组。可先在侧栏新建，或保存为未分组。")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.uuid) { group in
                    Toggle(isOn: binding(for: group.uuid)) {
                        HStack {
                            Text(group.name)
                            Spacer(minLength: 8)
                            Text("\(group.wordCount)/\(group.capacity)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(group.isOverCapacity ? .orange : .secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                if showCapacityWarnings {
                    let over = selection.resolve(from: groups).filter { $0.wordCount >= $0.capacity }
                    if !over.isEmpty {
                        Text("已满：\(over.map(\.name).joined(separator: "、"))。仍可加入，建议提高容量。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text(selection.isEmpty ? "当前：未分组（可多选）" : "已选：\(selection.summary(from: groups))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for uuid: UUID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(uuid) },
            set: { isOn in
                if isOn {
                    selection.ids.insert(uuid)
                } else {
                    selection.ids.remove(uuid)
                }
            }
        )
    }
}
