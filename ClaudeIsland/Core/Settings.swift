//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Combine
import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let enabledProviders = "enabledProviders"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }
}

// MARK: - Agent enabled settings

extension AppSettings {
    static var enabledProviders: Set<AgentProvider> {
        get {
            guard let data = defaults.data(forKey: Keys.enabledProviders),
                  let decoded = try? JSONDecoder().decode(Set<AgentProvider>.self, from: data) else {
                // Default: all enabled
                return Set(AgentProvider.allCases)
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.enabledProviders)
            }
        }
    }

    static func isEnabled(_ provider: AgentProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    static func toggle(_ provider: AgentProvider) {
        var providers = enabledProviders
        if providers.contains(provider) {
            providers.remove(provider)
        } else {
            providers.insert(provider)
        }
        enabledProviders = providers
    }
}

// MARK: - Language settings

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

extension AppSettings {
    private static let languageKey = "appLanguage"

    static var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: languageKey),
                  let lang = AppLanguage(rawValue: raw) else {
                return .english
            }
            return lang
        }
        set {
            defaults.set(newValue.rawValue, forKey: languageKey)
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("com.agentisland.languageDidChange")
}

// MARK: - Auto-approve settings

extension AppSettings {
    private static let autoApproveKey = "autoApproveEnabled"

    static var isAutoApproveEnabled: Bool {
        get { defaults.bool(forKey: autoApproveKey) }
        set { defaults.set(newValue, forKey: autoApproveKey) }
    }
}

@MainActor
class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var enabledProviders: Set<AgentProvider> = AppSettings.enabledProviders {
        didSet { AppSettings.enabledProviders = enabledProviders }
    }

    @Published var isAutoApproveEnabled: Bool = AppSettings.isAutoApproveEnabled {
        didSet { AppSettings.isAutoApproveEnabled = isAutoApproveEnabled }
    }

    private init() {}

    func isEnabled(_ provider: AgentProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    func toggle(_ provider: AgentProvider) {
        if enabledProviders.contains(provider) {
            enabledProviders.remove(provider)
        } else {
            enabledProviders.insert(provider)
        }
    }
}
