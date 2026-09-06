import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            Form {
                Section("词典与翻译") {
                    LabeledContent("数据来源") {
                        Text("Google Translate（免费）")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("网络失败时使用本地示例释义", isOn: $settings.useMockOnFailure)
                    Text("查词使用 Google 免费翻译接口，无需 API Key。该接口非官方、可能限流。发音使用 Google TTS。")
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
