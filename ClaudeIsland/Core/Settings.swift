//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

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
