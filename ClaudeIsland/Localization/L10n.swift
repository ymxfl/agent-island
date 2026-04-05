//
//  L10n.swift
//  ClaudeIsland
//
//  Localized strings driven by AppSettings.language (English / Simplified Chinese).
//

import Foundation

enum L10n {
    // MARK: - Menu
    static var back: String { localized("Back", zh: "返回") }
    static var screen: String { localized("Screen", zh: "显示器") }
    static var notificationSound: String { localized("Notification Sound", zh: "通知声音") }
    static var launchAtLogin: String { localized("Launch at Login", zh: "登录时启动") }
    static var hooks: String { localized("Hooks", zh: "Hooks") }
    static var accessibility: String { localized("Accessibility", zh: "辅助功能") }
    static var enabledAgents: String { localized("Enabled Agents", zh: "已启用代理") }
    static var checkForUpdates: String { localized("Check for Updates", zh: "检查更新") }
    static var starOnGithub: String { localized("Star on GitHub", zh: "在 GitHub 上加星") }
    static var quit: String { localized("Quit", zh: "退出") }
    static var language: String { localized("Language", zh: "语言") }
    static var on: String { localized("On", zh: "开") }
    static var off: String { localized("Off", zh: "关") }
    static var enable: String { localized("Enable", zh: "启用") }
    static var auto: String { localized("Auto", zh: "自动") }

    // MARK: - Instances
    static var noSessions: String { localized("No sessions", zh: "暂无会话") }
    static var runInTerminal: String { localized("Run claude in terminal", zh: "在终端中运行 claude") }
    static var needsYourInput: String { localized("Needs your input", zh: "需要你的输入") }
    static var you: String { localized("You:", zh: "你:") }

    // MARK: - Approval
    static var allow: String { localized("Allow", zh: "允许") }
    static var allowOnce: String { localized("Allow Once", zh: "允许一次") }
    static var allowAll: String { localized("Allow All", zh: "全部允许") }
    static var autoApprove: String { localized("Auto Approve", zh: "自动批准") }
    static var deny: String { localized("Deny", zh: "拒绝") }
    static var approve: String { localized("Approve", zh: "批准") }

    // MARK: - Chat
    static var typeMessage: String { localized("Type a message...", zh: "输入消息...") }
    static var tmuxRequired: String { localized("tmux session required to send messages", zh: "需要 tmux 会话才能发送消息") }

    // MARK: - Update
    static var checking: String { localized("Checking...", zh: "检查中...") }
    static var upToDate: String { localized("Up to date", zh: "已是最新") }
    static var downloadUpdate: String { localized("Download Update", zh: "下载更新") }
    static var downloading: String { localized("Downloading...", zh: "下载中...") }
    static var extracting: String { localized("Extracting...", zh: "解压中...") }
    static var installAndRelaunch: String { localized("Install & Relaunch", zh: "安装并重启") }
    static var installing: String { localized("Installing...", zh: "安装中...") }
    static var updateFailed: String { localized("Update failed", zh: "更新失败") }
    static var retry: String { localized("Retry", zh: "重试") }

    // MARK: - Terminal
    static var goToTerminal: String { localized("Go to Terminal", zh: "跳转终端") }
    static var terminal: String { localized("Terminal", zh: "终端") }

    // MARK: - Helpers

    private static func localized(_ en: String, zh: String) -> String {
        AppSettings.language == .chinese ? zh : en
    }
}
