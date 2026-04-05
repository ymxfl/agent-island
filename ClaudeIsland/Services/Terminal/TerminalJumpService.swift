import Foundation
import AppKit

class TerminalJumpService: Sendable {
    static let shared = TerminalJumpService()

    private init() {}

    func jumpToTTY(_ tty: String, terminal: TerminalApp) {
        switch terminal {
        case .iTerm2:
            jumpToITerm(tty: tty)
        case .terminal:
            jumpToTerminal(tty: tty)
        case .ghostty, .warp, .alacritty, .kitty, .vsCode, .cursor:
            activateTerminal(terminal)
            // For other terminals, at least activate the app
        }
    }

    private func jumpToITerm(tty: String) {
        // Use AppleScript to activate iTerm and focus the correct session
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select s
                            set current window to w
                            return
                        end if
                    end repeat

                end repeat
            end repeat
        end tell
        """

        runAppleScript(script)
    }

    private func jumpToTerminal(tty: String) {
        // Terminal.app doesn't expose TTY info, just activate
        let script = """
        tell application "Terminal"
            activate
        end tell
        """
        runAppleScript(script)
    }

    private func activateTerminal(_ terminal: TerminalApp) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: [:])
        }
    }

    private func runAppleScript(_ source: String) {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}
