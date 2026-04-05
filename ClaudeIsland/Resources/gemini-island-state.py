#!/usr/bin/env python3
"""
Gemini CLI Island Hook
- 通过 Unix socket 发送会话状态到 ClaudeIsland.app
- 权限请求时，等待应用的用户决策
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300  # 5 分钟等待权限决策


def get_tty():
    """获取 Gemini 进程的 TTY"""
    import subprocess

    # 获取父 PID (Gemini 进程)
    ppid = os.getppid()

    # 尝试从 ps 命令获取父进程的 TTY
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps 返回 "ttys001"，我们需要 "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # 后备方案：尝试当前进程的 stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def send_event(state):
    """发送事件到应用，如果需要返回响应"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        # 权限请求需要等待响应
        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # 获取进程信息
    gemini_pid = os.getppid()
    tty = get_tty()

    # 构建状态对象
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": gemini_pid,
        "tty": tty,
        "provider": "gemini",
    }

    # 映射事件到状态
    if event == "UserPromptSubmit":
        # 用户刚发送消息 - Gemini 正在处理中
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # 发送 tool_use_id 到 Swift 缓存
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionRequest":
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input

        # 发送到应用等待决策
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via ClaudeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        if notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "SubagentStop":
        state["status"] = "waiting_for_input"

    elif event == "SessionStart":
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        state["status"] = "compacting"

    else:
        state["status"] = "unknown"

    # 发送到 socket（非权限事件即发即忘）
    send_event(state)


if __name__ == "__main__":
    main()
