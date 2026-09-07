import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            Form {
                Section("词典与发音") {
                    LabeledContent("数据来源") {
                        Text("有道词典（免费网页接口）")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("网络失败时使用本地示例释义", isOn: $settings.useMockOnFailure)
                    Text("查词与发音使用有道公开词典接口，用户无需申请或填写 API Key。失败时可回退本地示例 / 系统朗读。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("词典", systemImage: "character.book.closed") }

            Form {
                Section("分组与发音") {
                    Stepper(value: $settings.defaultGroupCapacity, in: 5...200, step: 5) {
                        Text("新建分组默认容量：\(settings.defaultGroupCapacity)")
                    }
                    Picker("默认发音口音", selection: $settings.preferUSAccent) {
                        Text("美音").tag(true)
                        Text("英音").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("偏好", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 460, height: 280)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
