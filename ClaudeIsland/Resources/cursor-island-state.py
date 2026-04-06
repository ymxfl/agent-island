#!/usr/bin/env python3
"""
Cursor Agent → Agent Island Bridge
- Reads Cursor hooks.json event payloads from stdin
- Maps Cursor events to the Agent Island socket protocol
- Supports permission decisions for beforeShellExecution / beforeMCPExecution

Cursor hook events (hooks.json, version 1):
  beforeSubmitPrompt  → user sends a prompt
  beforeShellExecution → before running a shell command (can allow/deny)
  beforeMCPExecution   → before calling an MCP tool (can allow/deny)
  afterFileEdit        → after a file was edited
  beforeReadFile       → before reading a file (can allow/deny)
  stop                 → agent finished (completed/aborted/error)
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-island.sock"
TIMEOUT_SECONDS = 300


def send_event(state):
    """Send event to Agent Island app, return response if any."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

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

    event = data.get("hook_event_name", "")
    conversation_id = data.get("conversation_id", "unknown")
    workspace_roots = data.get("workspace_roots", [])
    cwd = workspace_roots[0] if workspace_roots else os.getcwd()

    state = {
        "session_id": conversation_id,
        "cwd": cwd,
        "event": event,
        "pid": os.getpid(),
        "tty": None,
        "provider": "cursor",
    }

    if event == "beforeSubmitPrompt":
        state["event"] = "UserPromptSubmit"
        state["status"] = "processing"
        prompt = data.get("prompt", "")
        if prompt:
            state["message"] = prompt

    elif event == "beforeShellExecution":
        command = data.get("command", "")
        shell_cwd = data.get("cwd", cwd)
        state["event"] = "PreToolUse"
        state["status"] = "waiting_for_approval"
        state["tool"] = "Shell"
        state["tool_input"] = {"command": command, "cwd": shell_cwd}

        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            if decision == "allow":
                print(json.dumps({"permission": "allow"}))
                sys.exit(0)
            elif decision == "deny":
                reason = response.get("reason", "Denied by user via Agent Island")
                print(json.dumps({
                    "permission": "deny",
                    "agentMessage": reason,
                }))
                sys.exit(0)

        # Default: let Cursor show its own UI
        print(json.dumps({"permission": "ask"}))
        sys.exit(0)

    elif event == "beforeMCPExecution":
        tool_name = data.get("tool_name", "unknown")
        tool_input = data.get("tool_input", {})
        state["event"] = "PreToolUse"
        state["status"] = "waiting_for_approval"
        state["tool"] = tool_name
        state["tool_input"] = (
            tool_input if isinstance(tool_input, dict) else {"raw": str(tool_input)}
        )

        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            if decision == "allow":
                print(json.dumps({"permission": "allow"}))
                sys.exit(0)
            elif decision == "deny":
                reason = response.get("reason", "Denied by user via Agent Island")
                print(json.dumps({
                    "permission": "deny",
                    "agentMessage": reason,
                }))
                sys.exit(0)

        print(json.dumps({"permission": "ask"}))
        sys.exit(0)

    elif event == "afterFileEdit":
        state["event"] = "PostToolUse"
        state["status"] = "processing"
        state["tool"] = "FileEdit"
        file_path = data.get("file_path", "")
        state["tool_input"] = {"file_path": file_path}

    elif event == "beforeReadFile":
        state["event"] = "PreToolUse"
        state["status"] = "running_tool"
        state["tool"] = "Read"
        file_path = data.get("file_path", "")
        state["tool_input"] = {"file_path": file_path}
        send_event(state)
        print(json.dumps({"permission": "allow"}))
        sys.exit(0)

    elif event == "stop":
        stop_status = data.get("status", "completed")
        if stop_status == "completed":
            state["event"] = "Stop"
            state["status"] = "waiting_for_input"
        elif stop_status == "aborted":
            state["event"] = "Stop"
            state["status"] = "waiting_for_input"
        else:
            state["event"] = "Stop"
            state["status"] = "waiting_for_input"

    else:
        state["status"] = "unknown"

    send_event(state)


if __name__ == "__main__":
    main()
