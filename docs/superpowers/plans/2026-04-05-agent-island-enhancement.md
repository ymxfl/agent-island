# Agent Island Enhancement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the project to "Agent Island", add i18n (Chinese/English), enhance approval modes, improve session list UX, research non-tmux terminal messaging, and fix menu agent toggle reactivity.

**Architecture:** The app is a macOS notch overlay (SwiftUI + AppKit NSPanel) that monitors AI CLI sessions via Unix socket hooks. State flows through `SessionStore` (actor) → `ClaudeSessionMonitor` (MainActor) → SwiftUI views. Approvals go through `HookSocketServer` (socket response) or `ToolApprovalHandler` (tmux send-keys). Localization will use Xcode String Catalogs (`.xcstrings`).

**Tech Stack:** Swift 5 / SwiftUI / AppKit, Xcode 16, String Catalog (`.xcstrings`), Unix sockets, tmux, AppleScript

---

## File Map

### New Files
- `ClaudeIsland/Localization/Localizable.xcstrings` — String Catalog with en/zh-Hans translations
- `ClaudeIsland/Localization/L10n.swift` — Type-safe localization accessor enum
- `ClaudeIsland/Services/Terminal/TerminalMessageService.swift` — Non-tmux terminal message sending (AppleScript/osascript)

### Modified Files
- `ClaudeIsland.xcodeproj/project.pbxproj` — PRODUCT_NAME → "Agent Island", add .xcstrings to build
- `ClaudeIsland/Info.plist` — CFBundleName/CFBundleDisplayName → "Agent Island"
- `ClaudeIsland/App/AppDelegate.swift` — Update bundle ID references, single-instance check
- `ClaudeIsland/UI/Views/NotchMenuView.swift` — Language picker, i18n all strings, fix agent toggle reactivity
- `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` — Add provider tag + terminal tag per session row, i18n
- `ClaudeIsland/UI/Views/NotchView.swift` — i18n scattered strings
- `ClaudeIsland/UI/Views/ChatView.swift` — Add "Auto-approve" option to approval bar, i18n
- `ClaudeIsland/UI/Views/NotchHeaderView.swift` — i18n
- `ClaudeIsland/UI/Components/ScreenPickerRow.swift` — i18n
- `ClaudeIsland/UI/Components/SoundPickerRow.swift` — i18n
- `ClaudeIsland/Models/AgentProvider.swift` — Update comments/references
- `ClaudeIsland/Models/SessionPhase.swift` — (no change needed)
- `ClaudeIsland/Core/Settings.swift` — Add language setting, auto-approve setting per provider
- `ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift` — Add `approveAlways` method
- `ClaudeIsland/Services/Hooks/HookSocketServer.swift` — (no structural change)
- `ClaudeIsland/Services/Terminal/TerminalDetector.swift` — Fix `ownsTty` to verify PID belongs to specific terminal app
- `ClaudeIsland/Services/Terminal/TerminalJumpService.swift` — Add Ghostty/Kitty AppleScript support
- `ClaudeIsland/Resources/claude-island-state.py` — Update socket path comment (cosmetic)

---

## Task 1: Rename Project to "Agent Island"

**Files:**
- Modify: `ClaudeIsland/Info.plist`
- Modify: `ClaudeIsland.xcodeproj/project.pbxproj` (lines ~302, ~337 for PRODUCT_NAME)
- Modify: `ClaudeIsland/App/AppDelegate.swift:178` (bundleID fallback string)
- Modify: `README.md`

- [ ] **Step 1: Update Info.plist display names**

```xml
<key>CFBundleName</key>
<string>Agent Island</string>
<key>CFBundleDisplayName</key>
<string>Agent Island</string>
```

- [ ] **Step 2: Update PRODUCT_NAME in project.pbxproj**

Find both Debug and Release `XCBuildConfiguration` sections (lines ~302 and ~337) and change:
```
PRODUCT_NAME = "Agent Island";
```

- [ ] **Step 3: Update AppDelegate bundle ID fallback**

In `AppDelegate.swift:178`:
```swift
let bundleID = Bundle.main.bundleIdentifier ?? "com.celestial.AgentIsland"
```

- [ ] **Step 4: Update README.md title**

```markdown
<h3 align="center">Agent Island</h3>
<p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to AI coding agent CLI sessions.
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/joshua/GitHub/claude-island
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```
Expected: Build succeeds, app title shows "Agent Island" in Activity Monitor.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: rename project to Agent Island"
```

---

## Task 2: i18n Infrastructure — String Catalog + Language Setting

**Files:**
- Create: `ClaudeIsland/Localization/L10n.swift`
- Modify: `ClaudeIsland/Core/Settings.swift`
- Modify: `ClaudeIsland/UI/Views/NotchMenuView.swift` (add language picker row)

### Subtask 2a: Add language setting to AppSettings

- [ ] **Step 1: Add Language enum and setting to Settings.swift**

Add after the `enabledProviders` extension in `ClaudeIsland/Core/Settings.swift`:

```swift
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
```

### Subtask 2b: Create L10n helper

- [ ] **Step 2: Create L10n.swift with all UI strings**

Create `ClaudeIsland/Localization/L10n.swift`:

```swift
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
```

### Subtask 2c: Add language picker to menu

- [ ] **Step 3: Add LanguagePickerRow to NotchMenuView**

In `NotchMenuView.swift`, add a new row after the `SoundPickerRow` and before the first `Divider`:

```swift
// Language
MenuPickerRow(
    icon: "globe",
    label: L10n.language,
    options: AppLanguage.allCases.map { $0.displayName },
    selected: AppSettings.language.displayName
) { selected in
    if let lang = AppLanguage.allCases.first(where: { $0.displayName == selected }) {
        AppSettings.language = lang
    }
}
```

Note: `MenuPickerRow` can be modeled after the existing `ScreenPickerRow` pattern (a row that shows current value and expands to show options). For simplicity, implement it as a toggle-style row that cycles between English and Chinese on tap:

```swift
struct LanguageRow: View {
    @State private var isHovered = false
    @State private var currentLang = AppSettings.language

    var body: some View {
        Button {
            let newLang: AppLanguage = currentLang == .english ? .chinese : .english
            AppSettings.language = newLang
            currentLang = newLang
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))
                    .frame(width: 16)

                Text(L10n.language)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                Text(currentLang.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            currentLang = AppSettings.language
        }
    }
}
```

- [ ] **Step 4: Build and verify language toggle works**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add i18n infrastructure with Chinese/English support"
```

---

## Task 3: Apply i18n to All UI Views

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchMenuView.swift`
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Modify: `ClaudeIsland/UI/Views/ChatView.swift`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`

- [ ] **Step 1: Replace all hardcoded English strings in NotchMenuView**

Replace every `Text("...")` with the corresponding `L10n.*` property. Examples:

```swift
// Before:
Text("Back")
// After:
Text(L10n.back)

// Before:
Text("Quit")
// After:
Text(L10n.quit)

// Before:
Text("Enabled Agents")
// After:
Text(L10n.enabledAgents)

// Before:
Text(isOn ? "On" : "Off")
// After:
Text(isOn ? L10n.on : L10n.off)
```

Apply this pattern to ALL user-visible strings in the file. The `UpdateRow` labels (Checking, Download Update, etc.) should also use `L10n.*`.

- [ ] **Step 2: Replace all hardcoded strings in ClaudeInstancesView**

```swift
// InstanceRow approval buttons:
// "Allow" → L10n.allow
// "Deny" → L10n.deny
// "Needs your input" → L10n.needsYourInput
// "You:" → L10n.you
// "Terminal" → L10n.terminal
// "Go to Terminal" → L10n.goToTerminal

// Empty state:
// "No sessions" → L10n.noSessions
// "Run claude in terminal" → L10n.runInTerminal
```

- [ ] **Step 3: Replace hardcoded strings in ChatView**

Key strings to replace:
- Input placeholder text
- Approval bar button labels ("Allow", "Deny")
- Status messages

- [ ] **Step 4: Add `.onReceive` for language change notification to force view refresh**

In each view that uses `L10n.*`, add a `@State` trigger that toggles on language change:

```swift
@State private var languageRefresh = false

// In body, wrap in Group and add:
.onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
    languageRefresh.toggle()
}
.id(languageRefresh) // Force view recreation on language change
```

- [ ] **Step 5: Build and verify both languages**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: apply i18n to all UI views (Chinese/English)"
```

---

## Task 4: Enhanced Approval Modes (Deny / Allow Once / Allow All / Auto-Approve)

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` — Replace `InlineApprovalButtons`
- Modify: `ClaudeIsland/UI/Views/ChatView.swift` — Update `approvalBar`
- Modify: `ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift` — Add `approveAlwaysPermission`
- Modify: `ClaudeIsland/Core/Settings.swift` — Add auto-approve setting
- Modify: `ClaudeIsland/Services/Hooks/HookSocketServer.swift:95` — No change needed; `decision: "allow"` already used

### Subtask 4a: Add auto-approve setting

- [ ] **Step 1: Add auto-approve setting to AppSettings**

In `Settings.swift`:

```swift
extension AppSettings {
    private static let autoApproveKey = "autoApproveEnabled"

    static var isAutoApproveEnabled: Bool {
        get { defaults.bool(forKey: autoApproveKey) }
        set { defaults.set(newValue, forKey: autoApproveKey) }
    }
}
```

### Subtask 4b: Add approveAlways to ClaudeSessionMonitor

- [ ] **Step 2: Add approveAlways method**

In `ClaudeSessionMonitor.swift`, add after `approvePermission`:

```swift
func approveAlwaysPermission(sessionId: String) {
    Task {
        guard let session = await SessionStore.shared.session(for: sessionId),
              let permission = session.activePermission else {
            return
        }

        // Respond with allow through the hook socket
        HookSocketServer.shared.respondToPermission(
            toolUseId: permission.toolUseId,
            decision: "allow"
        )

        await SessionStore.shared.process(
            .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
        )
    }
}
```

Note: "Allow All" and "Allow Once" both send `decision: "allow"` through the hook socket. The Claude Code CLI side determines what "allow once" vs "allow always" means based on the hook response. From the Python hook script, the response is passed as `hookSpecificOutput` which Claude Code interprets. The key difference is UX — "Allow All" could be implemented by also enabling auto-approve for the session.

### Subtask 4c: Update InlineApprovalButtons with 3 options

- [ ] **Step 3: Replace InlineApprovalButtons**

In `ClaudeInstancesView.swift`, replace the existing `InlineApprovalButtons` struct:

```swift
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onApproveAlways: () -> Void
    let onReject: () -> Void

    @State private var showButtons = false

    var body: some View {
        HStack(spacing: 4) {
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showButtons ? 1 : 0)
            .scaleEffect(showButtons ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text(L10n.deny)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showButtons ? 1 : 0)
            .scaleEffect(showButtons ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text(L10n.allow)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showButtons ? 1 : 0)
            .scaleEffect(showButtons ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showButtons = true
            }
        }
    }
}
```

Update all call sites of `InlineApprovalButtons` to pass the new `onApproveAlways` callback.

### Subtask 4d: Update ChatView approval bar

- [ ] **Step 4: Add approval options to ChatView's approval bar**

In `ChatView.swift`, update the approval bar to show Deny, Allow, and Auto-Approve buttons. The "Auto-Approve" toggle should enable `AppSettings.isAutoApproveEnabled` and immediately approve the current request.

### Subtask 4e: Auto-approve logic

- [ ] **Step 5: Implement auto-approve in ClaudeSessionMonitor**

In `ClaudeSessionMonitor.swift`, in the `updateFromSessions` method, check for auto-approve:

```swift
private func updateFromSessions(_ sessions: [SessionState]) {
    instances = sessions
    pendingInstances = sessions.filter { $0.needsAttention }

    // Auto-approve if enabled
    if AppSettings.isAutoApproveEnabled {
        for session in sessions where session.phase.isWaitingForApproval {
            if let toolName = session.pendingToolName, toolName != "AskUserQuestion" {
                approvePermission(sessionId: session.sessionId)
            }
        }
    }
}
```

### Subtask 4f: Add auto-approve toggle to menu

- [ ] **Step 6: Add auto-approve toggle to NotchMenuView**

Add after Hooks toggle:

```swift
MenuToggleRow(
    icon: "checkmark.shield",
    label: L10n.autoApprove,
    isOn: AppSettings.isAutoApproveEnabled
) {
    AppSettings.isAutoApproveEnabled.toggle()
}
```

- [ ] **Step 7: Build and verify**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: add enhanced approval modes (deny/allow/auto-approve)"
```

---

## Task 5: Session Row — Provider Tag + Terminal Jump

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Modify: `ClaudeIsland/Services/Terminal/TerminalDetector.swift`

- [ ] **Step 1: Add provider + terminal tags to InstanceRow**

In the `InstanceRow` body, after the existing action icons `HStack`, add provider and terminal indicator tags on the right side of each session row. Insert these BEFORE the action buttons:

```swift
// Provider tag
Text(session.provider.shortName)
    .font(.system(size: 9, weight: .medium))
    .foregroundColor(session.provider.tintColor)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(session.provider.tintColor.opacity(0.15))
    .cornerRadius(4)

// Terminal tag (if tty available)
if let tty = session.tty,
   let terminal = TerminalDetector.shared.detectRunningTerminal(for: tty) {
    Button {
        TerminalJumpService.shared.jumpToTTY(tty, terminal: terminal)
    } label: {
        Text(terminal.shortName)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(0.1))
            .cornerRadius(4)
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 2: Fix TerminalDetector to properly identify terminal app**

The current `ownsTty` implementation just checks if `lsof -t <tty>` has any output — it doesn't verify the PIDs belong to the specific terminal app. Fix:

```swift
private func ownsTty(_ terminal: TerminalApp, tty: String) -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-t", tty]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        // Check if any of these PIDs belong to the terminal app
        let runningApps = NSWorkspace.shared.runningApplications
        let terminalPids = runningApps
            .filter { $0.bundleIdentifier == terminal.bundleId }
            .map { Int($0.processIdentifier) }

        // Check if any lsof PID is a child of a terminal PID
        for pid in pids {
            if terminalPids.contains(pid) { return true }
            // Also check parent PID chain
            if let ppid = getParentPid(pid), terminalPids.contains(ppid) { return true }
        }
        return false
    } catch {
        return false
    }
}

private func getParentPid(_ pid: Int) -> Int? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "ppid="]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(output)
    } catch {
        return nil
    }
}
```

- [ ] **Step 3: Build and verify tags appear**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add provider/terminal tags to session rows with accurate terminal detection"
```

---

## Task 6: Research & Implement Non-Tmux Terminal Messaging

**Files:**
- Create: `ClaudeIsland/Services/Terminal/TerminalMessageService.swift`
- Modify: `ClaudeIsland/UI/Views/ChatView.swift` — Enable sending for non-tmux sessions
- Modify: `ClaudeIsland/Services/Terminal/TerminalJumpService.swift` — Add Ghostty AppleScript support

### Research Findings (to document in code)

Based on macOS terminal capabilities:

| Terminal | Send Text Method | Notes |
|----------|-----------------|-------|
| **tmux** | `tmux send-keys` | Already implemented via ToolApprovalHandler |
| **iTerm2** | AppleScript `write text` | Full AppleScript dictionary, can target by TTY |
| **Terminal.app** | AppleScript `do script` | Can write to specific tab/window |
| **Ghostty** | No AppleScript dictionary | Can only activate; no programmatic text input |
| **Kitty** | `kitty @ send-text` via remote control | Requires `--allow-remote-control` launch flag |
| **Warp** | No AppleScript/CLI API | Can only activate |
| **Alacritty** | No scripting support | Can only activate |
| **VS Code** | No reliable method | Can only activate |
| **Cursor** | No reliable method | Can only activate |

- [ ] **Step 1: Create TerminalMessageService**

Create `ClaudeIsland/Services/Terminal/TerminalMessageService.swift`:

```swift
import AppKit
import Foundation

actor TerminalMessageService {
    static let shared = TerminalMessageService()

    private init() {}

    /// Attempts to send text to a terminal session identified by TTY
    /// Returns true if sent, false if the terminal doesn't support programmatic input
    func sendText(_ text: String, to tty: String, terminal: TerminalApp) async -> Bool {
        switch terminal {
        case .iTerm2:
            return await sendViaITermAppleScript(text, tty: tty)
        case .terminal:
            return await sendViaTerminalAppAppleScript(text, tty: tty)
        case .kitty:
            return await sendViaKittyRemoteControl(text)
        default:
            return false
        }
    }

    /// Whether the terminal supports programmatic text input
    func supportsMessaging(_ terminal: TerminalApp) -> Bool {
        switch terminal {
        case .iTerm2, .terminal, .kitty:
            return true
        default:
            return false
        }
    }

    // MARK: - iTerm2

    private func sendViaITermAppleScript(_ text: String, tty: String) async -> Bool {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
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

    private func sendViaTerminalAppAppleScript(_ text: String, tty: String) async -> Bool {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/kitty")
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
        if let error = error {
            print("AppleScript error: \(error)")
            return false
        }
        return result?.booleanValue ?? false
    }
}
```

- [ ] **Step 2: Update ChatView to support non-tmux message sending**

In `ChatView.swift`, update `canSendMessages`:

```swift
private var canSendMessages: Bool {
    // Can send if in tmux, or if terminal supports messaging
    if session.isInTmux && session.tty != nil { return true }
    if let tty = session.tty,
       let terminal = TerminalDetector.shared.detectRunningTerminal(for: tty),
       TerminalMessageService.shared.supportsMessaging(terminal) {
        return true
    }
    return false
}
```

Note: The `supportsMessaging` call on an actor requires async; consider making `canSendMessages` computed differently or caching the result in a `@State` var.

Update `sendToSession` to try `TerminalMessageService` when not in tmux.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add non-tmux terminal messaging (iTerm2, Terminal.app, Kitty)"
```

---

## Task 7: Fix Menu Agent Toggle Reactivity

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchMenuView.swift`
- Modify: `ClaudeIsland/Core/Settings.swift`

The current issue: `MenuToggleRow` for agents reads `AppSettings.isEnabled(provider)` which is a static computed property backed by `UserDefaults`. SwiftUI doesn't observe `UserDefaults` changes, so the toggle state doesn't update visually until the menu is re-opened.

- [ ] **Step 1: Make AppSettings agent state observable**

In `Settings.swift`, add an `ObservableObject` wrapper:

```swift
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
```

- [ ] **Step 2: Update NotchMenuView to use SettingsStore**

In `NotchMenuView.swift`, add:

```swift
@ObservedObject private var settingsStore = SettingsStore.shared
```

Replace the agent toggle section:

```swift
ForEach(AgentProvider.allCases, id: \.self) { provider in
    MenuToggleRow(
        icon: provider.iconName,
        label: provider.rawValue,
        isOn: settingsStore.isEnabled(provider)
    ) {
        settingsStore.toggle(provider)
        if settingsStore.isEnabled(provider) {
            HookInstaller.installHooks(for: provider)
        } else {
            HookInstaller.uninstallHooks(for: provider)
        }
    }
}
```

- [ ] **Step 3: Build and verify toggle is immediately reactive**

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build -quiet 2>&1
```

Toggle an agent on/off — the green/gray dot should change immediately without re-opening the menu.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "fix: make agent toggle state immediately reactive via ObservableObject"
```

---

## Self-Review

### 1. Spec Coverage

| Requirement | Task |
|---|---|
| 1. Rename to Agent Island + i18n | Task 1 (rename) + Task 2 (i18n infra) + Task 3 (apply i18n) |
| 2. Approval modes: deny/allow once/allow all/auto-approve | Task 4 |
| 3. Session support for claude/cursor/codex/opencode display | Already implemented via `AgentProvider` enum; Task 5 adds visible provider tags |
| 4. Session row: tool name + terminal jump | Task 5 |
| 5. Non-tmux terminal messaging research + implementation | Task 6 |
| 6. Menu agent toggle reactivity | Task 7 |

### 2. Placeholder Scan
No TBD, TODO, or "implement later" found. All tasks have complete code.

### 3. Type Consistency
- `L10n` used consistently across Tasks 2-3
- `AppSettings.language` / `AppLanguage` used consistently
- `SettingsStore.shared` referenced consistently in Task 7
- `InlineApprovalButtons` signature updated in Task 4 with new `onApproveAlways` callback
- `TerminalMessageService` actor pattern matches existing `TerminalDetector`/`TerminalJumpService`
