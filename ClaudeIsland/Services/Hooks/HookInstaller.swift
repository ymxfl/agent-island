//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation

struct HookInstaller {

    /// Install hook script and update settings/hooks config on app launch
    static func installIfNeeded() {
        installHooks(for: .claude)

        for provider in AgentProvider.allCases where provider != .claude {
            let providerDir = provider.configDirectory.expandingTildeInURL
            if FileManager.default.fileExists(atPath: providerDir.path) {
                installHooks(for: provider)
            }
        }

        cleanupLegacyCursorSettings()
    }

    /// Remove hooks that were previously (incorrectly) written to
    /// ``~/.cursor/settings.json`` in Claude Code format.  Cursor reads
    /// its hooks from ``hooks.json``, so the settings.json entries are dead weight.
    private static func cleanupLegacyCursorSettings() {
        let cursorSettingsURL = "~/.cursor".expandingTildeInURL
            .appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: cursorSettingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        var changed = false
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                let before = entries.count
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("cursor-island-state.py")
                        }
                    }
                    return false
                }
                if entries.count != before {
                    changed = true
                    if entries.isEmpty {
                        hooks.removeValue(forKey: event)
                    } else {
                        hooks[event] = entries
                    }
                }
            }
        }

        guard changed else { return }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if json.isEmpty {
            try? FileManager.default.removeItem(at: cursorSettingsURL)
        } else if let newData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? newData.write(to: cursorSettingsURL)
        }
    }

    internal static func installHooks(for provider: AgentProvider) {
        let configDir = provider.configDirectory.expandingTildeInURL
        let hooksDir = configDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(provider.hookScriptName)

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(
            forResource: String(provider.hookScriptName.dropLast(3)),
            withExtension: "py"
        ) {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        let configFile = configDir.appendingPathComponent(provider.hooksConfigFilename)
        if provider.usesNativeHooksJson {
            updateNativeHooksJson(at: configFile, provider: provider)
        } else {
            updateSettings(at: configFile, provider: provider)
        }
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

    // MARK: - Native hooks.json (Cursor-style)

    /// Install hooks into a Cursor-style hooks.json with ``version: 1`` format.
    private static func updateNativeHooksJson(at url: URL, provider: AgentProvider) {
        var json: [String: Any] = ["version": 1]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let hookDirPath = provider.configDirectory.replacingOccurrences(
            of: "~",
            with: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let command = "\(python) \(hookDirPath)/hooks/\(provider.hookScriptName)"

        let cursorEvents = [
            "beforeSubmitPrompt",
            "beforeShellExecution",
            "beforeMCPExecution",
            "afterFileEdit",
            "beforeReadFile",
            "stop",
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        for event in cursorEvents {
            let hookEntry: [String: Any] = ["command": command]
            if var existingEntries = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEntries.contains { entry in
                    (entry["command"] as? String)?.contains(provider.hookScriptName) == true
                }
                if !hasOurHook {
                    existingEntries.append(hookEntry)
                    hooks[event] = existingEntries
                }
            } else {
                hooks[event] = [hookEntry]
            }
        }

        json["hooks"] = hooks
        json["version"] = 1

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: url)
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
        let configFile = configDir.appendingPathComponent(provider.hooksConfigFilename)

        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        if provider.usesNativeHooksJson {
            for (_, value) in hooks {
                if let entries = value as? [[String: Any]] {
                    for entry in entries {
                        if let cmd = entry["command"] as? String,
                           cmd.contains(provider.hookScriptName) {
                            return true
                        }
                    }
                }
            }
        } else {
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
        let configFile = configDir.appendingPathComponent(provider.hooksConfigFilename)

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: configFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        if provider.usesNativeHooksJson {
            for (event, value) in hooks {
                if var entries = value as? [[String: Any]] {
                    entries.removeAll { entry in
                        let cmd = entry["command"] as? String ?? ""
                        return cmd.contains(provider.hookScriptName)
                    }
                    if entries.isEmpty {
                        hooks.removeValue(forKey: event)
                    } else {
                        hooks[event] = entries
                    }
                }
            }
        } else {
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
            try? data.write(to: configFile)
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
