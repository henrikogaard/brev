/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import Foundation

public extension Notification.Name {
    /// Posted when device-local MCP agent access settings change (ADR-0095).
    static let brevAgentAccessSettingsDidChange = Notification.Name("BrevAgentAccessSettingsDidChange")

    /// Posted when the local MCP audit log records or clears entries (ADR-0095).
    static let brevAgentAccessAuditLogDidChange = Notification.Name("BrevAgentAccessAuditLogDidChange")
}

/// Device-local consent settings for the macOS local MCP server (ADR-0095, #305).
///
/// Deliberately excluded from settings backups (ADR-0076) and iCloud preference
/// sync (ADR-0056) so agent access can never be silently enabled on another Mac.
public struct AgentAccessSettings: Equatable, Sendable {
    enum Key {
        static let isEnabled = "agentAccess.isEnabled.v1"
        static let enabledAccountIDs = "agentAccess.enabledAccountIDs.v1"
    }

    /// Master switch (off by default).
    public var isEnabled: Bool

    /// Explicit per-account opt-ins keyed by stable `BrevAccount.ID` (empty by default).
    public var enabledAccountIDs: Set<String>

    /// Default configuration: master switch off, zero accounts opted in.
    public static let defaults = AgentAccessSettings(
        isEnabled: false,
        enabledAccountIDs: []
    )

    /// Creates device-local agent access settings.
    public init(isEnabled: Bool = false, enabledAccountIDs: Set<String> = []) {
        self.isEnabled = isEnabled
        self.enabledAccountIDs = Set(enabledAccountIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    /// Returns whether both the master switch and the specific account opt-in are enabled.
    public func isAccountEnabled(_ accountID: String) -> Bool {
        isEnabled && enabledAccountIDs.contains(accountID)
    }

    /// Toggles per-account opt-in without altering the master switch.
    public mutating func setAccount(_ accountID: String, enabled: Bool) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if enabled {
            enabledAccountIDs.insert(trimmed)
        } else {
            enabledAccountIDs.remove(trimmed)
        }
    }

    /// Loads device-local agent access settings from `defaults`.
    public static func load(from defaults: UserDefaults = .standard) -> AgentAccessSettings {
        let isEnabled = defaults.bool(forKey: Key.isEnabled)
        let rawIDs = defaults.stringArray(forKey: Key.enabledAccountIDs) ?? []
        return AgentAccessSettings(
            isEnabled: isEnabled,
            enabledAccountIDs: Set(rawIDs)
        )
    }

    /// Persists device-local agent access settings to `defaults`.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Key.isEnabled)
        defaults.set(Array(enabledAccountIDs).sorted(), forKey: Key.enabledAccountIDs)
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .brevAgentAccessSettingsDidChange, object: nil)
        }
    }

    /// Revokes any stored agent-access grant for a removed account so re-adding the
    /// same email address later requires explicit opt-in again (ADR-0095).
    public static func removeAccount(_ accountID: String, from defaults: UserDefaults = .standard) {
        let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var settings = load(from: defaults)
        guard settings.enabledAccountIDs.remove(trimmed) != nil else { return }
        settings.save(to: defaults)
    }
}

/// Permission tier shown in Settings → Agent access for each MCP tool (ADR-0095).
public enum AgentAccessToolPermission: String, Equatable, Sendable {
    case read
    case approvalRequired

    /// Localized badge label displayed next to the tool.
    public var badgeTitle: String {
        switch self {
        case .read:
            String(localized: "Read", bundle: .module)
        case .approvalRequired:
            String(localized: "Approval required in Brev", bundle: .module)
        }
    }
}

/// Read-only specification of one tool exposed by the local MCP server (ADR-0095).
public struct AgentAccessToolSpec: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let permission: AgentAccessToolPermission
    public let summary: String

    public init(name: String, permission: AgentAccessToolPermission, summary: String) {
        self.name = name
        self.permission = permission
        self.summary = summary
    }

    /// Complete v1 tool inventory exposed over the local MCP bridge (ADR-0095 §3).
    public static var exposedTools: [AgentAccessToolSpec] {
        [
            AgentAccessToolSpec(
                name: "list_accounts",
                permission: .read,
                summary: String(localized: "Lists opaque IDs and labels for accounts you enabled above.", bundle: .module)
            ),
            AgentAccessToolSpec(
                name: "list_folders",
                permission: .read,
                summary: String(localized: "Lists folder names, roles, and unread counts from local state.", bundle: .module)
            ),
            AgentAccessToolSpec(
                name: "search_messages",
                permission: .read,
                summary: String(
                    localized: "Searches locally cached mail only (up to 50 headers per call; never hits the network).",
                    bundle: .module
                )
            ),
            AgentAccessToolSpec(
                name: "read_message",
                permission: .read,
                summary: String(
                    localized: "Reads sanitized plain text, basic headers, and attachment filenames for one cached message.",
                    bundle: .module
                )
            ),
            AgentAccessToolSpec(
                name: "archive_messages",
                permission: .approvalRequired,
                summary: String(localized: "Archives up to 25 messages after you click Approve in Brev.", bundle: .module)
            ),
            AgentAccessToolSpec(
                name: "label_messages",
                permission: .approvalRequired,
                summary: String(
                    localized: "Moves up to 25 messages to a non-Trash, non-Spam folder after you click Approve in Brev.",
                    bundle: .module
                )
            )
        ]
    }
}

/// Outcome recorded for every request received by the running MCP broker (ADR-0095 §4).
public enum AgentAccessAuditOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case allowed
    case approved
    case denied
    case timedOut = "timed_out"
    case blockedDisabled = "blocked_disabled"
    case blockedAccount = "blocked_account"
    case rateLimited = "rate_limited"

    /// Localized label shown in the Settings → Agent access audit log.
    public var displayTitle: String {
        switch self {
        case .allowed:
            String(localized: "Allowed", bundle: .module)
        case .approved:
            String(localized: "Approved", bundle: .module)
        case .denied:
            String(localized: "Denied", bundle: .module)
        case .timedOut:
            String(localized: "Timed out", bundle: .module)
        case .blockedDisabled:
            String(localized: "Blocked (disabled)", bundle: .module)
        case .blockedAccount:
            String(localized: "Blocked (account)", bundle: .module)
        case .rateLimited:
            String(localized: "Rate limited", bundle: .module)
        }
    }

    /// Whether this outcome represents a denied, timed-out, or blocked request.
    public var isRejected: Bool {
        switch self {
        case .allowed, .approved:
            false
        case .denied, .timedOut, .blockedDisabled, .blockedAccount, .rateLimited:
            true
        }
    }
}

/// Single structured audit entry stored locally without message bodies, snippets, or codes (ADR-0095 §4).
public struct AgentAccessAuditEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let clientName: String
    public let clientPID: Int32?
    public let toolName: String
    public let accountID: String
    public let parameterSummary: String
    public let outcome: AgentAccessAuditOutcome

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        clientName: String,
        clientPID: Int32? = nil,
        toolName: String,
        accountID: String = "none",
        parameterSummary: String,
        outcome: AgentAccessAuditOutcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.clientName = Self.bounded(clientName, limit: 80)
        self.clientPID = clientPID
        self.toolName = Self.bounded(toolName, limit: 64)
        self.accountID = accountID.isEmpty ? "none" : Self.bounded(accountID, limit: 80)
        self.parameterSummary = Self.bounded(parameterSummary, limit: 160)
        self.outcome = outcome
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.count > limit else { return sanitized }
        return String(sanitized.prefix(limit))
    }
}

/// Bounded local ring buffer (max 1,000 entries) storing MCP audit entries excluded from backups (ADR-0095 §4).
public final class AgentAccessAuditLogStore: @unchecked Sendable {
    /// Maximum number of retained entries in the ring buffer.
    public static let maxEntries = 1000

    /// Shared default audit store under `Application Support/Brev/agent-access-audit.json`.
    public static let shared = AgentAccessAuditLogStore(fileURL: defaultFileURL())

    private let lock = NSLock()
    private let fileURL: URL?
    private var cachedEntries: [AgentAccessAuditEntry]
    private let postsChangeNotification: Bool

    /// Creates an audit log store backed by `fileURL` (or memory-only when `nil`).
    public init(fileURL: URL?, postsChangeNotification: Bool = true) {
        self.fileURL = fileURL
        self.postsChangeNotification = postsChangeNotification
        cachedEntries = Self.loadFromDisk(fileURL: fileURL)
    }

    /// Default backup-excluded storage path inside Application Support.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("agent-access-audit.json", isDirectory: false)
    }

    /// Appends one entry, trimming oldest entries past `maxEntries`, and persists atomically.
    public func record(_ entry: AgentAccessAuditEntry) {
        lock.lock()
        cachedEntries.append(entry)
        if cachedEntries.count > Self.maxEntries {
            cachedEntries.removeFirst(cachedEntries.count - Self.maxEntries)
        }
        let snapshot = cachedEntries
        lock.unlock()

        persist(snapshot)
        if postsChangeNotification {
            NotificationCenter.default.post(name: .brevAgentAccessAuditLogDidChange, object: nil)
        }
    }

    /// Returns retained entries newest first.
    public func entries() -> [AgentAccessAuditEntry] {
        lock.lock()
        let snapshot = cachedEntries
        lock.unlock()
        return snapshot.reversed()
    }

    /// Clears all retained audit entries from memory and disk immediately.
    public func clear() {
        lock.lock()
        cachedEntries.removeAll()
        lock.unlock()

        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if postsChangeNotification {
            NotificationCenter.default.post(name: .brevAgentAccessAuditLogDidChange, object: nil)
        }
    }

    private static func loadFromDisk(fileURL: URL?) -> [AgentAccessAuditEntry] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([AgentAccessAuditEntry].self, from: data)) ?? []
        if decoded.count > maxEntries {
            return Array(decoded.suffix(maxEntries))
        }
        return decoded
    }

    private func persist(_ entries: [AgentAccessAuditEntry]) {
        guard let fileURL else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(resourceValues)
    }
}

/// Client configuration snippet format shown in Settings → Agent access.
public enum AgentAccessClientFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case codexTOML

    public var id: String { rawValue }

    /// Short picker label for this client format.
    public var title: String {
        switch self {
        case .json: String(localized: "Claude / Cursor (JSON)", bundle: .module)
        case .codexTOML: String(localized: "Codex CLI (TOML)", bundle: .module)
        }
    }
}

/// Socket path and stdio client configuration helper for `brev-mcp` (ADR-0095 §1).
public enum AgentAccessSocketConfiguration {
    /// Shared macOS App Group identifier used by sandboxed Brev builds and `brev-mcp`.
    public static let appGroupIdentifier = "group.eu.brevmail.brev"

    /// Maximum safe `sockaddr_un.sun_path` UTF-8 byte length on macOS (104 including NUL).
    private static let maxSocketPathUTF8Bytes = 100

    /// User-private Unix domain socket path reachable by both sandboxed Brev builds and
    /// the unsandboxed `brev-mcp` stdio helper without exceeding the 104-byte `sun_path` limit.
    public static func defaultSocketURL() -> URL {
        #if os(macOS)
        let fallbackBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
        #else
        let fallbackBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        let groupContainer = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? fallbackBase
        let candidate = groupContainer.appendingPathComponent("mcp.sock", isDirectory: false)
        if candidate.path.utf8.count <= maxSocketPathUTF8Bytes {
            return candidate
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brev-mcp-\(getuid()).sock", isDirectory: false)
    }

    /// Default path to the bundled `brev-mcp` stdio bridge executable.
    public static func defaultHelperPath(bundle: Bundle = .main) -> String {
        if let helper = bundle.url(forAuxiliaryExecutable: "brev-mcp")?.path {
            return helper
        }
        let helpersCandidate = bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("brev-mcp", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helpersCandidate.path) {
            return helpersCandidate.path
        }
        return "/Applications/Brev.app/Contents/Helpers/brev-mcp"
    }

    /// Copyable MCP client configuration snippet for Claude Desktop/Code/Cursor (JSON) or Codex CLI (TOML).
    public static func clientConfigSnippet(
        for format: AgentAccessClientFormat = .json,
        helperPath: String = defaultHelperPath()
    ) -> String {
        switch format {
        case .json:
            return """
            {
              "mcpServers": {
                "brev": {
                  "command": "\(helperPath)"
                }
              }
            }
            """
        case .codexTOML:
            let escaped = helperPath.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            [mcp_servers.brev]
            command = "\(escaped)"
            """
        }
    }
}
