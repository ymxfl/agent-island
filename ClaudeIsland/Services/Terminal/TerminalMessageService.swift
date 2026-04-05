import AppKit
import Foundation

actor TerminalMessageService {
    static let shared = TerminalMessageService()

    private init() {}

    func sendText(_ text: String, to tty: String, terminal: TerminalApp) async -> Bool {
        switch terminal {
        case .iTerm2:
            return sendViaITermAppleScript(text, tty: tty)
        case .terminal:
            return sendViaTerminalAppAppleScript(text, tty: tty)
        case .kitty:
            return await sendViaKittyRemoteControl(text)
        case .ghostty, .warp, .alacritty, .vsCode, .cursor:
            return false
        }
    }

    nonisolated func supportsMessaging(_ terminal: TerminalApp) -> Bool {
        switch terminal {
        case .iTerm2, .terminal, .kitty:
            return true
        case .ghostty, .warp, .alacritty, .vsCode, .cursor:
            return false
        }
    }

    // MARK: - iTerm2

    private func sendViaITermAppleScript(_ text: String, tty: String) -> Bool {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set paneTty to tty of s
                        if paneTty is "\(tty)" or paneTty is "/dev/\(tty)" then
                            tell s to write text "\(escapedText)"
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Terminal.app

    private func sendViaTerminalAppAppleScript(_ text: String, tty: String) -> Bool {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabTty to tty of t
                    if tabTty is "\(tty)" or tabTty is "/dev/\(tty)" then
                        do script "\(escapedText)" in t
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
    }

    // MARK: - Kitty

    private func sendViaKittyRemoteControl(_ text: String) async -> Bool {
        let candidates = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"]
        let path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/kitty"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["@", "send-text", "--", text + "\n"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            print("AppleScript error: \(error)")
            return false
        }
        return result?.booleanValue ?? false
    }
}
