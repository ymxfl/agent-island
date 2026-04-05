//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation

struct HookInstaller {

    /// Install hook script and update settings.json on app launch
    static func installIfNeeded() {
        // 安装 Claude Code hooks
        installHooks(for: .claude)

        // 为其他代理安装 hook，如果配置目录存在
        for provider in AgentProvider.allCases where provider != .claude {
            let providerDir = provider.configDirectory.expandingTildeInURL
            if FileManager.default.fileExists(atPath: providerDir.path) {
                installHooks(for: provider)
            }
        }
    }

    internal static func installHooks(for provider: AgentProvider) {
        let configDir = provider.configDirectory.expandingTildeInURL
        let hooksDir = configDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(provider.hookScriptName)
        let settings = configDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(
            forResource: provider.hookScriptName.dropLast(3),
            withExtension: "py"
        ) {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        updateSettings(at: settings, provider: provider)
    }

    private static func updateSettings(at settingsURL: URL, provider: AgentProvider) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let hookDirPath = provider.configDirectory.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        let command = "\(python) \(hookDirPath)/hooks/\(provider.hookScriptName)"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains(provider.hookScriptName)
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        for provider in AgentProvider.allCases {
            if isInstalled(for: provider) {
                return true
            }
        }
        return false
    }

    private static func isInstalled(for provider: AgentProvider) -> Bool {
        let configDir = provider.configDirectory.expandingTildeInURL
        let settings = configDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains(provider.hookScriptName) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        for provider in AgentProvider.allCases {
            uninstallHooks(for: provider)
        }
    }

    internal static func uninstallHooks(for provider: AgentProvider) {
        let configDir = provider.configDirectory.expandingTildeInURL
        let hooksDir = configDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(provider.hookScriptName)
        let settings = configDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains(provider.hookScriptName)
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }
}

private extension String {
    var expandingTildeInURL: URL {
        URL(fileURLWithPath: (self as NSString).expandingTildeInPath)
    }
}
