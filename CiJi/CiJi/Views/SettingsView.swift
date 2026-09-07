import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            Form {
                Section("有道智云词典") {
                    TextField("AppKey（应用 ID）", text: $settings.youdaoAppKey)
                        .textFieldStyle(.roundedBorder)
                    SecureField("应用密钥", text: $settings.youdaoAppSecret)
                        .textFieldStyle(.roundedBorder)

                    if settings.hasYoudaoCredentials {
                        Label("已配置密钥，将调用有道官方 API", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("尚未配置密钥：查词将使用本地示例（若开启回退）", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    Toggle("网络失败或未配置时使用本地示例释义", isOn: $settings.useMockOnFailure)

                    Text("在 ai.youdao.com 注册并创建「文本翻译」应用，将 AppKey 与密钥填到此处。音标仍优先使用 Free Dictionary / Datamuse。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("打开有道智云控制台", destination: URL(string: "https://ai.youdao.com/")!)
                        .font(.caption)
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
                    Text("发音仍优先 Google TTS，失败时回退系统朗读。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("偏好", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 360)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}
