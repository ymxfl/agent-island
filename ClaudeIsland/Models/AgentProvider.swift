import SwiftUI

/// 支持的 AI 编程代理
enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case claude = "Claude Code"
    case gemini = "Gemini CLI"
    case codex = "OpenAI Codex"
    case cursor = "Cursor"
    case opencode = "OpenCode"

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .claude: return "bolt.circle.fill"
        case .gemini: return "sparkle.magic.circle.fill"
        case .codex: return "keyboard.chevron.compact.down"
        case .cursor: return "cursorarrow.rays"
        case .opencode: return "terminal.app"
        }
    }

    /// 提供者主题色
    var tintColor: Color {
        switch self {
        case .claude: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .gemini: return Color(red: 0.3, green: 0.7, blue: 0.3)
        case .codex: return Color(red: 0.2, green: 0.4, blue: 0.8)
        case .cursor: return Color(red: 0.7, green: 0.3, blue: 0.8)
        case .opencode: return Color(red: 0.8, green: 0.5, blue: 0.2)
        }
    }

    /// Hook 脚本文件名
    var hookScriptName: String {
        switch self {
        case .claude: return "claude-island-state.py"
        case .gemini: return "gemini-island-state.py"
        case .codex: return "codex-island-state.py"
        case .cursor: return "cursor-island-state.py"
        case .opencode: return "opencode-island-state.py"
        }
    }

    /// 配置目录位置
    var configDirectory: String {
        switch self {
        case .claude: return "~/.claude"
        case .gemini: return "~/.gemini"
        case .codex: return "~/.codex"
        case .cursor: return "~/.cursor"
        case .opencode: return "~/.opencode"
        }
    }
}
