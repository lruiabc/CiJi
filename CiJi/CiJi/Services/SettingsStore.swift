import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let defaultGroupCapacity = "defaultGroupCapacity"
        static let preferUSAccent = "preferUSAccent"
        static let useMockOnFailure = "useMockOnFailure"
    }

    @Published var defaultGroupCapacity: Int {
        didSet { UserDefaults.standard.set(defaultGroupCapacity, forKey: Keys.defaultGroupCapacity) }
    }

    /// true = 美音, false = 英音
    @Published var preferUSAccent: Bool {
        didSet { UserDefaults.standard.set(preferUSAccent, forKey: Keys.preferUSAccent) }
    }

    /// 网络失败时回退到本地示例释义
    @Published var useMockOnFailure: Bool {
        didSet { UserDefaults.standard.set(useMockOnFailure, forKey: Keys.useMockOnFailure) }
    }

    init() {
        let defaults = UserDefaults.standard
        let capacity = defaults.object(forKey: Keys.defaultGroupCapacity) as? Int
        self.defaultGroupCapacity = capacity ?? 20
        self.preferUSAccent = defaults.object(forKey: Keys.preferUSAccent) as? Bool ?? true
        if defaults.object(forKey: Keys.useMockOnFailure) == nil,
           let old = defaults.object(forKey: "useMockWhenNoKey") as? Bool {
            self.useMockOnFailure = old
        } else {
            self.useMockOnFailure = defaults.object(forKey: Keys.useMockOnFailure) as? Bool ?? true
        }
    }
}
