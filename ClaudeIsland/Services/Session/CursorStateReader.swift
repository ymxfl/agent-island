//
//  CursorStateReader.swift
//  ClaudeIsland
//
//  Reads Cursor IDE's internal SQLite database to extract conversation
//  metadata and message content for Cursor Agent sessions.
//
//  Database location: ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
//  Tables: ItemTable (composerHeaders), cursorDiskKV (composerData, bubbles)
//

import Foundation
import SQLite3
import os.log

actor CursorStateReader {
    static let shared = CursorStateReader()
    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "CursorState")

    private let dbPath: String = {
        let home = NSHomeDirectory()
        return home + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    // MARK: - Public API

    /// Fetch conversation name and metadata for a given composerId (= conversation_id from hooks)
    func conversationInfo(for composerId: String) -> CursorComposerInfo? {
        guard let db = openDatabase() else { return nil }
        defer { sqlite3_close(db) }

        guard let headers = readComposerHeaders(db: db) else { return nil }

        return headers.first { $0.composerId == composerId }
    }

    /// Fetch chat messages (bubbles) for a given composerId
    func chatMessages(for composerId: String) -> [CursorBubble] {
        guard let db = openDatabase() else { return [] }
        defer { sqlite3_close(db) }

        guard let bubbleRefs = readBubbleReferences(db: db, composerId: composerId) else {
            return []
        }

        var bubbles: [CursorBubble] = []
        for ref in bubbleRefs {
            if let bubble = readBubble(db: db, composerId: composerId, bubbleId: ref.bubbleId) {
                bubbles.append(bubble)
            }
        }
        return bubbles
    }

    /// Load full conversation: metadata + messages, converting to Agent Island's format
    func loadConversation(composerId: String, into session: inout SessionState) {
        guard let db = openDatabase() else { return }
        defer { sqlite3_close(db) }

        // Load metadata (name, timestamps)
        if let headers = readComposerHeaders(db: db),
           let info = headers.first(where: { $0.composerId == composerId }) {
            if let name = info.name, !name.isEmpty {
                session.conversationInfo.summary = name
            }
        }

        // Load bubbles as chat items
        guard let bubbleRefs = readBubbleReferences(db: db, composerId: composerId) else { return }

        let existingIds = Set(session.chatItems.map { $0.id })
        var newItems: [ChatHistoryItem] = []

        for ref in bubbleRefs {
            let itemId = "cursor-bubble-\(ref.bubbleId)"
            guard !existingIds.contains(itemId) else { continue }

            guard let bubble = readBubble(db: db, composerId: composerId, bubbleId: ref.bubbleId),
                  !bubble.text.isEmpty else { continue }

            let itemType: ChatHistoryItemType
            switch bubble.type {
            case 1: // user
                itemType = .user(bubble.text)
            case 2: // assistant
                itemType = .assistant(bubble.text)
            default:
                continue
            }

            let item = ChatHistoryItem(
                id: itemId,
                type: itemType,
                timestamp: bubble.createdAt ?? Date()
            )
            newItems.append(item)
        }

        if !newItems.isEmpty {
            // Remove any hook-generated user messages that were placeholders
            session.chatItems.removeAll { item in
                if case .user = item.type, item.id.hasPrefix("hook-user-") { return true }
                return false
            }
            session.chatItems.append(contentsOf: newItems)
            session.chatItems.sort { $0.timestamp < $1.timestamp }

            // Update conversationInfo from loaded messages
            if let firstUser = newItems.first(where: { if case .user = $0.type { return true }; return false }),
               case .user(let text) = firstUser.type,
               session.conversationInfo.firstUserMessage == nil {
                session.conversationInfo.firstUserMessage = String(text.prefix(100))
            }
            if let lastItem = newItems.last {
                switch lastItem.type {
                case .user(let text):
                    session.conversationInfo.lastMessage = String(text.prefix(200))
                    session.conversationInfo.lastMessageRole = "user"
                case .assistant(let text):
                    session.conversationInfo.lastMessage = String(text.prefix(200))
                    session.conversationInfo.lastMessageRole = "assistant"
                default:
                    break
                }
            }
        }
    }

    // MARK: - Database Access

    private func openDatabase() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)
        if result != SQLITE_OK {
            Self.logger.debug("Failed to open Cursor state.vscdb: \(result)")
            if let db = db { sqlite3_close(db) }
            return nil
        }
        return db
    }

    private func readComposerHeaders(db: OpaquePointer) -> [CursorComposerInfo]? {
        let query = "SELECT value FROM ItemTable WHERE key = 'composer.composerHeaders'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        let jsonStr = String(cString: cStr)

        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let allComposers = root["allComposers"] as? [[String: Any]] else { return nil }

        return allComposers.compactMap { dict -> CursorComposerInfo? in
            guard let composerId = dict["composerId"] as? String else { return nil }
            let name = dict["name"] as? String
            let subtitle = dict["subtitle"] as? String
            let createdAt = (dict["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let lastUpdatedAt = (dict["lastUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let workspace = (dict["workspaceIdentifier"] as? [String: Any])
            let uri = (workspace?["uri"] as? [String: Any])
            let fsPath = uri?["fsPath"] as? String

            return CursorComposerInfo(
                composerId: composerId,
                name: name,
                subtitle: subtitle,
                createdAt: createdAt,
                lastUpdatedAt: lastUpdatedAt,
                workspacePath: fsPath
            )
        }
    }

    private func readBubbleReferences(db: OpaquePointer, composerId: String) -> [BubbleReference]? {
        let key = "composerData:\(composerId)"
        let query = "SELECT value FROM cursorDiskKV WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        let jsonStr = String(cString: cStr)

        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let headers = root["fullConversationHeadersOnly"] as? [[String: Any]] else { return nil }

        return headers.compactMap { dict -> BubbleReference? in
            guard let bubbleId = dict["bubbleId"] as? String,
                  let type = dict["type"] as? Int else { return nil }
            return BubbleReference(bubbleId: bubbleId, type: type)
        }
    }

    private func readBubble(db: OpaquePointer, composerId: String, bubbleId: String) -> CursorBubble? {
        let key = "bubbleId:\(composerId):\(bubbleId)"
        let query = "SELECT value FROM cursorDiskKV WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        let jsonStr = String(cString: cStr)

        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let type = root["type"] as? Int ?? 0
        let text = root["text"] as? String ?? ""
        let createdAtStr = root["createdAt"] as? String

        var createdAt: Date?
        if let str = createdAtStr {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: str)
        }

        return CursorBubble(
            bubbleId: bubbleId,
            type: type,
            text: text,
            createdAt: createdAt
        )
    }
}

// MARK: - Models

struct CursorComposerInfo: Sendable {
    let composerId: String
    let name: String?
    let subtitle: String?
    let createdAt: Date?
    let lastUpdatedAt: Date?
    let workspacePath: String?
}

struct BubbleReference: Sendable {
    let bubbleId: String
    let type: Int  // 1 = user, 2 = assistant
}

struct CursorBubble: Sendable {
    let bubbleId: String
    let type: Int  // 1 = user, 2 = assistant
    let text: String
    let createdAt: Date?
}
