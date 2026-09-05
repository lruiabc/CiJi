import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let youdaoAppKey = "youdaoAppKey"
        static let youdaoAppSecret = "youdaoAppSecret"
        static let defaultGroupCapacity = "defaultGroupCapacity"
        static let preferUSAccent = "preferUSAccent"
        static let useMockWhenNoKey = "useMockWhenNoKey"
    }

    @Published var youdaoAppKey: String {
        didSet { UserDefaults.standard.set(youdaoAppKey, forKey: Keys.youdaoAppKey) }
    }

    @Published var youdaoAppSecret: String {
        didSet { UserDefaults.standard.set(youdaoAppSecret, forKey: Keys.youdaoAppSecret) }
    }

    @Published var defaultGroupCapacity: Int {
        didSet { UserDefaults.standard.set(defaultGroupCapacity, forKey: Keys.defaultGroupCapacity) }
    }

    /// true = 美音 (type=1), false = 英音 (type=2)
    @Published var preferUSAccent: Bool {
        didSet { UserDefaults.standard.set(preferUSAccent, forKey: Keys.preferUSAccent) }
    }

    @Published var useMockWhenNoKey: Bool {
        didSet { UserDefaults.standard.set(useMockWhenNoKey, forKey: Keys.useMockWhenNoKey) }
    }

    var hasYoudaoCredentials: Bool {
        !youdaoAppKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !youdaoAppSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let defaults = UserDefaults.standard
        self.youdaoAppKey = defaults.string(forKey: Keys.youdaoAppKey) ?? ""
        self.youdaoAppSecret = defaults.string(forKey: Keys.youdaoAppSecret) ?? ""
        let capacity = defaults.object(forKey: Keys.defaultGroupCapacity) as? Int
        self.defaultGroupCapacity = capacity ?? 20
        self.preferUSAccent = defaults.object(forKey: Keys.preferUSAccent) as? Bool ?? true
        self.useMockWhenNoKey = defaults.object(forKey: Keys.useMockWhenNoKey) as? Bool ?? true
    }
}
