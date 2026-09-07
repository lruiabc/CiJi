import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let defaultGroupCapacity = "defaultGroupCapacity"
        static let preferUSAccent = "preferUSAccent"
        static let useMockOnFailure = "useMockOnFailure"
        static let youdaoAppKey = "youdaoAppKey"
        static let youdaoAppSecret = "youdaoAppSecret"
    }

    @Published var defaultGroupCapacity: Int {
        didSet { UserDefaults.standard.set(defaultGroupCapacity, forKey: Keys.defaultGroupCapacity) }
    }

    /// true = 美音, false = 英音
    @Published var preferUSAccent: Bool {
        didSet { UserDefaults.standard.set(preferUSAccent, forKey: Keys.preferUSAccent) }
    }

    /// 网络失败 / 未配置密钥时回退到本地示例释义
    @Published var useMockOnFailure: Bool {
        didSet { UserDefaults.standard.set(useMockOnFailure, forKey: Keys.useMockOnFailure) }
    }

    /// 有道智云应用 ID（AppKey）
    @Published var youdaoAppKey: String {
        didSet { UserDefaults.standard.set(youdaoAppKey, forKey: Keys.youdaoAppKey) }
    }

    /// 有道智云应用密钥
    @Published var youdaoAppSecret: String {
        didSet { UserDefaults.standard.set(youdaoAppSecret, forKey: Keys.youdaoAppSecret) }
    }

    var hasYoudaoCredentials: Bool {
        !youdaoAppKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !youdaoAppSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let defaults = UserDefaults.standard
        let capacity = defaults.object(forKey: Keys.defaultGroupCapacity) as? Int
        self.defaultGroupCapacity = capacity ?? 20
        self.preferUSAccent = defaults.object(forKey: Keys.preferUSAccent) as? Bool ?? true
        // migrate old key if present
        if defaults.object(forKey: Keys.useMockOnFailure) == nil,
           let old = defaults.object(forKey: "useMockWhenNoKey") as? Bool {
            self.useMockOnFailure = old
        } else {
            self.useMockOnFailure = defaults.object(forKey: Keys.useMockOnFailure) as? Bool ?? true
        }
        self.youdaoAppKey = defaults.string(forKey: Keys.youdaoAppKey) ?? ""
        self.youdaoAppSecret = defaults.string(forKey: Keys.youdaoAppSecret) ?? ""
    }
}
