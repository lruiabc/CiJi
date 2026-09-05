import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            Form {
                Section("有道智云词典 API") {
                    TextField("App Key", text: $settings.youdaoAppKey)
                    SecureField("App Secret", text: $settings.youdaoAppSecret)
                    Toggle("未配置 Key 时使用本地示例释义", isOn: $settings.useMockWhenNoKey)
                    Text("在 https://ai.youdao.com 创建应用后，将密钥填入此处。发音功能使用有道公开语音接口，无需单独密钥。")
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
        .frame(width: 460, height: 300)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
