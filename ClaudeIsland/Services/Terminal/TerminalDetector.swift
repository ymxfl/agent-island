import AppKit
import Foundation

enum TerminalApp: String, CaseIterable {
    case iTerm2 = "iTerm2"
    case terminal = "Terminal.app"
    case ghostty = "Ghostty"
    case warp = "Warp"
    case alacritty = "Alacritty"
    case kitty = "Kitty"
    case vsCode = "VS Code"
    case cursor = "Cursor"

    var bundleId: String {
        switch self {
        case .iTerm2: return "com.googlecode.iterm2"
        case .terminal: return "com.apple.Terminal"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .alacritty: return "io.alacritty"
        case .kitty: return "net.kovidgoyal.kitty"
        case .vsCode: return "com.visualstudio.code"
        case .cursor: return "com.todesktop.230313mzl4w4b9f"
        }
    }

    var running: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleId
        }
    }

    /// 短标签名（用于灵动岛紧凑显示）
    var shortName: String {
        switch self {
        case .iTerm2: return "iTerm"
        case .terminal: return "Terminal"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .alacritty: return "Alacritty"
        case .kitty: return "Kitty"
        case .vsCode: return "VS Code"
        case .cursor: return "Cursor"
        }
    }
}

class TerminalDetector: Sendable {
    static let shared = TerminalDetector()

    private init() {}

    func detectRunningTerminal(for tty: String) -> TerminalApp? {
        // Find which terminal app owns this TTY
        for terminal in TerminalApp.allCases where terminal.running {
            if ownsTty(terminal, tty: tty) {
                return terminal
            }
        }
        return nil
    }

    private func ownsTty(_ terminal: TerminalApp, tty: String) -> Bool {
        // Use lsof to check which process owns this TTY
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-t", tty]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check if output contains any PID that belongs to the terminal app
            // This is a simplified check - full implementation would verify PIDs belong to the terminal
            return !output.isEmpty
        } catch {
            return false
        }
    }
}
