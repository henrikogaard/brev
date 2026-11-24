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

import BrevBackend
import BrevDesign
import BrevSettings
import BrevThemes
import Foundation
import Observation
import SwiftUI
#if os(macOS)
import Darwin
#endif

// MARK: - Approval Coordinator (ADR-0026 & ADR-0095)

/// Decision returned by `MCPApprovalCoordinator` for one change-tool request.
public enum MCPApprovalDecision: Equatable, Sendable {
    case approved
    case denied
    case timedOut
    case rateLimited
}

/// Preview metadata shown in Brev's in-app approval dialog before an external MCP
/// agent archives, moves/labels messages, or saves a draft.
public struct MCPApprovalRequest: Identifiable, Equatable, Sendable {
    public struct MessagePreview: Identifiable, Equatable, Sendable {
        public let id: String
        public let sender: String
        public let subject: String

        public init(id: String, sender: String, subject: String) {
            self.id = id
            self.sender = sender
            self.subject = subject
        }
    }

    /// Redacted preview metadata shown before saving an agent-created draft.
    public struct DraftPreview: Equatable, Sendable {
        public let to: [String]
        public let cc: [String]
        public let bcc: [String]
        public let subject: String
        public let bodyPreview: String
        public let isBodyTruncated: Bool
        public let inReplyToSubject: String?

        /// Creates a draft preview for the MCP approval sheet.
        public init(
            to: [String],
            cc: [String] = [],
            bcc: [String] = [],
            subject: String,
            bodyPreview: String,
            isBodyTruncated: Bool = false,
            inReplyToSubject: String? = nil
        ) {
            self.to = to
            self.cc = cc
            self.bcc = bcc
            self.subject = subject
            self.bodyPreview = bodyPreview
            self.isBodyTruncated = isBodyTruncated
            self.inReplyToSubject = inReplyToSubject
        }
    }

    public let id: UUID
    public let clientName: String
    public let clientPID: Int32?
    public let toolName: String
    public let accountID: String
    public let accountLabel: String
    public let targetFolderName: String?
    public let messageCount: Int
    public let previews: [MessagePreview]
    public let draftPreview: DraftPreview?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        clientName: String,
        clientPID: Int32? = nil,
        toolName: String,
        accountID: String,
        accountLabel: String,
        targetFolderName: String? = nil,
        messageCount: Int,
        previews: [MessagePreview],
        draftPreview: DraftPreview? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clientName = clientName
        self.clientPID = clientPID
        self.toolName = toolName
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.targetFolderName = targetFolderName
        self.messageCount = messageCount
        self.previews = previews
        self.draftPreview = draftPreview
        self.createdAt = createdAt
    }
}

/// Manages single-active-prompt per-call in-app approval for MCP change tools (ADR-0095).
///
/// Enforces:
/// - At most one active prompt at a time (concurrent requests fail closed with `.rateLimited`).
/// - Mandatory per-call user click (no "Approve all" or session-wide auto-approval).
/// - Fail-closed timeout (default 60 seconds) and fail-closed when UI cannot be displayed.
@MainActor
@Observable
public final class MCPApprovalCoordinator {
    /// Currently presented approval prompt, if any.
    public private(set) var activeRequest: MCPApprovalRequest?

    /// Whether Brev can currently display an in-app approval modal.
    public var canDisplayUI: Bool

    private var activeContinuation: CheckedContinuation<MCPApprovalDecision, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init(canDisplayUI: Bool = true) {
        self.canDisplayUI = canDisplayUI
    }

    /// Presents `request` for explicit user approval, failing closed on denial, timeout,
    /// rate-limit contention, or unavailable UI.
    public func requestApproval(
        _ request: MCPApprovalRequest,
        timeoutSeconds: TimeInterval = 60
    ) async -> MCPApprovalDecision {
        guard canDisplayUI else { return .denied }
        guard activeRequest == nil, activeContinuation == nil else {
            return .rateLimited
        }

        activeRequest = request
        return await withCheckedContinuation { continuation in
            activeContinuation = continuation
            let requestID = request.id
            timeoutTask = Task { [weak self] in
                let nanos = UInt64(max(0.01, timeoutSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                self?.resolve(requestID: requestID, decision: .timedOut)
            }
        }
    }

    /// Approves the currently active change request (single call only).
    public func approveActiveRequest() {
        guard let request = activeRequest else { return }
        resolve(requestID: request.id, decision: .approved)
    }

    /// Denies the currently active change request.
    public func denyActiveRequest() {
        guard let request = activeRequest else { return }
        resolve(requestID: request.id, decision: .denied)
    }

    private func resolve(requestID: UUID, decision: MCPApprovalDecision) {
        guard activeRequest?.id == requestID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = activeContinuation
        activeContinuation = nil
        activeRequest = nil
        continuation?.resume(returning: decision)
    }
}

/// In-app approval sheet shown when a local MCP client requests `archive_messages`,
/// `label_messages`, or `create_draft`.
public struct MCPApprovalSheetView: View {
    @Environment(\.brevTheme) private var theme
    let request: MCPApprovalRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    public init(
        request: MCPApprovalRequest,
        onApprove: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.request = request
        self.onApprove = onApprove
        self.onDeny = onDeny
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            HStack(spacing: BrevSpacing.sm) {
                Image(systemName: request.toolName == "create_draft" ? "square.and.pencil" : "hand.raised.fill")
                    .foregroundStyle(theme.accent.color)
                Text(actionTitle)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
            }

            Text(requestSummary)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)

            if let draft = request.draftPreview {
                ViewThatFits(in: .vertical) {
                    draftPreviewCard(draft)
                    ScrollView {
                        draftPreviewCard(draft)
                    }
                }
                .frame(maxHeight: 260)
            } else {
                VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                    ForEach(request.previews.prefix(5)) { preview in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.subject.isEmpty ? String(localized: "(No subject)", bundle: .module) : preview.subject)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(1)
                            Text(preview.sender)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textSecondary.color)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BrevSpacing.xs)
                        .background(theme.bgSecondary.color)
                        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
                    }
                    let shownPreviewCount = min(request.previews.count, 5)
                    if request.messageCount > shownPreviewCount {
                        Text(
                            String(
                                format: String(localized: "and %d more messages", bundle: .module),
                                request.messageCount - shownPreviewCount
                            )
                        )
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                    }
                }
            }

            if request.toolName == "create_draft" {
                Text(
                    "This only saves a draft for your manual review. External agents can never send or delete mail.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            } else {
                Text(
                    "Every change requires your explicit approval. Brev never exposes send or delete tools to external agents.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }

            HStack {
                Spacer()
                Button(String(localized: "Deny", bundle: .module), role: .cancel, action: onDeny)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Approve", bundle: .module), action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent.color)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(BrevSpacing.lg)
        .frame(width: 440)
        .background(theme.bgPrimary.color)
        .brevSheetAppearance(theme)
    }

    private func draftPreviewCard(_ draft: MCPApprovalRequest.DraftPreview) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            draftFieldRow(
                label: String(localized: "Account", bundle: .module),
                value: request.accountLabel
            )
            draftFieldRow(
                label: String(localized: "To", bundle: .module),
                value: draft.to.joined(separator: ", ")
            )
            if !draft.cc.isEmpty {
                draftFieldRow(
                    label: String(localized: "Cc", bundle: .module),
                    value: draft.cc.joined(separator: ", ")
                )
            }
            if !draft.bcc.isEmpty {
                draftFieldRow(
                    label: String(localized: "Bcc", bundle: .module),
                    value: draft.bcc.joined(separator: ", ")
                )
            }
            draftFieldRow(
                label: String(localized: "Subject", bundle: .module),
                value: draft.subject.isEmpty ? String(localized: "(No subject)", bundle: .module) : draft.subject
            )
            if let inReplyToSubject = draft.inReplyToSubject {
                draftFieldRow(
                    label: String(localized: "In reply to", bundle: .module),
                    value: inReplyToSubject.isEmpty ? String(localized: "(No subject)", bundle: .module) : inReplyToSubject
                )
            }
            Divider()
            Text(draft.bodyPreview)
                .brevFont(.footnote)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if draft.isBodyTruncated {
                Text("Draft preview truncated", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }

    private func draftFieldRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BrevSpacing.xs) {
            Text(label)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .frame(minWidth: 62, alignment: .leading)
            Text(value)
                .brevFont(.caption)
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionTitle: String {
        switch request.toolName {
        case "archive_messages":
            return String(localized: "Approve agent archive request?", bundle: .module)
        case "create_draft":
            return String(localized: "Create draft", bundle: .module)
        default:
            return String(localized: "Approve agent folder move?", bundle: .module)
        }
    }

    private var requestSummary: String {
        if request.toolName == "create_draft" {
            return String(
                format: String(localized: "%@ wants to save a draft in %@.", bundle: .module),
                request.clientName,
                request.accountLabel
            )
        }
        if let folder = request.targetFolderName {
            return String(
                format: String(localized: "%@ wants to move %d message(s) in %@ to %@.", bundle: .module),
                request.clientName,
                request.messageCount,
                request.accountLabel,
                folder
            )
        }
        return String(
            format: String(localized: "%@ wants to archive %d message(s) in %@.", bundle: .module),
            request.clientName,
            request.messageCount,
            request.accountLabel
        )
    }
}

// MARK: - Local MCP Broker (JSON-RPC 2.0)

/// Caller metadata attached to one local MCP request from a verified same-UID peer.
public struct MCPClientContext: Equatable, Sendable {
    public let processName: String
    public let pid: Int32?
    public let clientInfoName: String?

    public init(processName: String, pid: Int32? = nil, clientInfoName: String? = nil) {
        self.processName = processName
        self.pid = pid
        self.clientInfoName = clientInfoName
    }

    /// Display label recorded in the audit log and approval sheet.
    public var displayName: String {
        if let info = clientInfoName?.trimmingCharacters(in: .whitespacesAndNewlines), !info.isEmpty {
            if let pid {
                return "\(info) (\(processName) #\(pid))"
            }
            return "\(info) (\(processName))"
        }
        if let pid {
            return "\(processName) #\(pid)"
        }
        return processName
    }
}

/// In-process local MCP broker enforcing ADR-0095 consent, cache-only reads,
/// ADR-0088 sign-in code redaction, per-call approval prompts, and local audit logging.
@MainActor
public final class LocalMCPBroker {
    /// Hard page cap for `search_messages` (ADR-0095 §3).
    public static let maxSearchResults = 50
    /// Hard batch cap for `archive_messages` and `label_messages` (ADR-0095 §3).
    public static let maxChangeBatchSize = 25
    /// Hard UTF-8 byte cap for `create_draft` plain-text bodies (64 KiB).
    public static let maxDraftBodyBytes = 64 * 1024
    /// Hard character cap for `create_draft` trimmed subjects.
    public static let maxDraftSubjectLength = 500
    /// Hard total recipient cap across `to`, `cc`, and `bcc` for `create_draft`.
    public static let maxDraftRecipients = 50
    /// Character cap for the body preview displayed in the in-app draft approval sheet.
    private static let maxDraftPreviewCharacters = 400
    /// Line cap for the body preview displayed in the in-app draft approval sheet.
    private static let maxDraftPreviewLines = 6
    /// Allowed argument keys for `create_draft` (enforces schema `additionalProperties: false`).
    private static let createDraftAllowedArgumentKeys: Set<String> = [
        "account_id",
        "to",
        "cc",
        "bcc",
        "subject",
        "body_text",
        "in_reply_to_message_id"
    ]
    /// MCP protocol version advertised during `initialize`.
    public static let protocolVersion = "2024-11-05"

    private let backendsProvider: @MainActor () -> [any MailBackend]
    private let settingsProvider: @MainActor () -> AgentAccessSettings
    private let auditStore: AgentAccessAuditLogStore
    private let approvalCoordinator: MCPApprovalCoordinator
    private let approvalTimeoutSeconds: TimeInterval
    private let now: @Sendable () -> Date

    /// Creates a local MCP broker operating strictly on Brev's in-memory `MailBackend` instances.
    @MainActor
    public init(
        backendsProvider: @escaping @MainActor () -> [any MailBackend],
        settingsProvider: @escaping @MainActor () -> AgentAccessSettings = { AgentAccessSettings.load() },
        auditStore: AgentAccessAuditLogStore = .shared,
        approvalCoordinator: MCPApprovalCoordinator? = nil,
        approvalTimeoutSeconds: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backendsProvider = backendsProvider
        self.settingsProvider = settingsProvider
        self.auditStore = auditStore
        self.approvalCoordinator = approvalCoordinator ?? MCPApprovalCoordinator()
        self.approvalTimeoutSeconds = approvalTimeoutSeconds
        self.now = now
    }

    /// Handles one JSON-RPC 2.0 MCP payload and returns the serialized JSON-RPC response,
    /// or `nil` for JSON-RPC notifications with no `id`.
    public func handleJSONRPCData(_ data: Data, client: MCPClientContext) async -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encodeJSON(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
        }

        let id = object["id"]
        guard let method = object["method"] as? String else {
            guard let id else { return nil }
            return encodeJSON(errorResponse(id: id, code: -32600, message: "Invalid Request"))
        }

        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let clientInfo = (params["clientInfo"] as? [String: Any])?["name"] as? String
            _ = clientInfo
            guard let id else { return nil }
            let result: [String: Any] = [
                "protocolVersion": Self.protocolVersion,
                "capabilities": [
                    "tools": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "brev-local-mcp",
                    "version": "1.0.0"
                ]
            ]
            return encodeJSON(successResponse(id: id, result: result))

        case "notifications/initialized":
            return nil

        case "ping":
            guard let id else { return nil }
            return encodeJSON(successResponse(id: id, result: [:]))

        case "tools/list":
            guard let id else { return nil }
            return encodeJSON(successResponse(id: id, result: ["tools": Self.toolDefinitions()]))

        case "tools/call":
            guard let id else { return nil }
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let response = await handleToolCall(
                id: id,
                toolName: toolName,
                arguments: arguments,
                client: client
            )
            return encodeJSON(response)

        default:
            guard let id else { return nil }
            return encodeJSON(errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    private func handleToolCall(
        id: Any,
        toolName: String,
        arguments: [String: Any],
        client: MCPClientContext
    ) async -> [String: Any] {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            recordAudit(
                client: client,
                toolName: toolName.isEmpty ? "unknown" : toolName,
                accountID: "none",
                parameterSummary: "master_disabled",
                outcome: .blockedDisabled
            )
            return errorResponse(
                id: id,
                code: -32001,
                message: "Agent access is disabled in Brev Settings → Agent access."
            )
        }

        switch toolName {
        case "list_accounts":
            return handleListAccounts(id: id, settings: settings, client: client)
        case "list_folders":
            return await handleListFolders(id: id, arguments: arguments, settings: settings, client: client)
        case "search_messages":
            return await handleSearchMessages(id: id, arguments: arguments, settings: settings, client: client)
        case "read_message":
            return await handleReadMessage(id: id, arguments: arguments, settings: settings, client: client)
        case "archive_messages":
            return await handleChangeMessages(
                id: id,
                toolName: "archive_messages",
                arguments: arguments,
                settings: settings,
                client: client
            )
        case "label_messages":
            return await handleChangeMessages(
                id: id,
                toolName: "label_messages",
                arguments: arguments,
                settings: settings,
                client: client
            )
        case "create_draft":
            return await handleCreateDraft(
                id: id,
                arguments: arguments,
                settings: settings,
                client: client
            )
        default:
            recordAudit(
                client: client,
                toolName: toolName.isEmpty ? "unknown" : toolName,
                accountID: "none",
                parameterSummary: "excluded_or_unknown_tool",
                outcome: .denied
            )
            return errorResponse(
                id: id,
                code: -32601,
                message: "Tool '\(toolName)' is not exposed by Brev."
            )
        }
    }

    private func handleListAccounts(
        id: Any,
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) -> [String: Any] {
        let optedIn = backendsProvider()
            .filter { settings.isAccountEnabled($0.account.id) }
            .map { backend -> [String: Any] in
                [
                    "account_id": backend.account.id,
                    "label": backend.account.displayName.isEmpty
                        ? backend.account.emailAddress
                        : backend.account.displayName
                ]
            }
        recordAudit(
            client: client,
            toolName: "list_accounts",
            accountID: "none",
            parameterSummary: "returned=\(optedIn.count)",
            outcome: .allowed
        )
        return toolSuccessResponse(id: id, payload: ["accounts": optedIn])
    }

    private func handleListFolders(
        id: Any,
        arguments: [String: Any],
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) async -> [String: Any] {
        guard let accountID = arguments["account_id"] as? String, !accountID.isEmpty else {
            return errorResponse(id: id, code: -32602, message: "Missing required argument 'account_id'.")
        }
        guard let backend = resolveOptedInBackend(accountID: accountID, settings: settings) else {
            recordAudit(
                client: client,
                toolName: "list_folders",
                accountID: "none",
                parameterSummary: "account_unavailable",
                outcome: .blockedAccount
            )
            return errorResponse(id: id, code: -32002, message: "Account not found.")
        }

        do {
            let folders = try await backend.folders()
            let serialized = folders.map { folder -> [String: Any] in
                [
                    "folder_id": folder.id,
                    "name": folder.name,
                    "role": folder.role.rawValue,
                    "unread_count": folder.unreadCount
                ]
            }
            recordAudit(
                client: client,
                toolName: "list_folders",
                accountID: accountID,
                parameterSummary: "folders=\(serialized.count)",
                outcome: .allowed
            )
            return toolSuccessResponse(id: id, payload: ["folders": serialized])
        } catch {
            return errorResponse(id: id, code: -32003, message: "Couldn't read local folders.")
        }
    }

    private func handleSearchMessages(
        id: Any,
        arguments: [String: Any],
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) async -> [String: Any] {
        guard let accountID = arguments["account_id"] as? String, !accountID.isEmpty else {
            recordAudit(
                client: client,
                toolName: "search_messages",
                accountID: "none",
                parameterSummary: "missing_account_id",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required argument 'account_id'.")
        }
        guard let backend = resolveOptedInBackend(accountID: accountID, settings: settings) else {
            recordAudit(
                client: client,
                toolName: "search_messages",
                accountID: "none",
                parameterSummary: "account_unavailable",
                outcome: .blockedAccount
            )
            return errorResponse(id: id, code: -32002, message: "Account not found.")
        }

        let rawQuery = (arguments["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let folderID = (arguments["folder_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedLimit = arguments["limit"] as? Int ?? 20
        let limit = min(max(1, requestedLimit), Self.maxSearchResults)

        let query = SearchQuery(
            text: rawQuery,
            folderID: folderID?.isEmpty == false ? folderID : nil,
            execution: .cacheOnly
        )

        do {
            let folders = try await backend.folders()
            let excludedFolderIDs = Set(folders.filter { $0.role == .trash || $0.role == .spam }.map(\.id))
            if let folderID, !folderID.isEmpty, excludedFolderIDs.contains(folderID) {
                recordAudit(
                    client: client,
                    toolName: "search_messages",
                    accountID: accountID,
                    parameterSummary: "blocked_trash_or_spam folder=\(folderID)",
                    outcome: .denied
                )
                return errorResponse(
                    id: id,
                    code: -32602,
                    message: "Searching Trash or Spam is permanently excluded from MCP."
                )
            }
            let excludedMessageIDs = await excludedMessageIDs(in: folders, backend: backend)
            let headers = try await backend.search(query)
            guard settingsProvider().isAccountEnabled(accountID) else {
                recordAudit(
                    client: client,
                    toolName: "search_messages",
                    accountID: "none",
                    parameterSummary: "consent_revoked",
                    outcome: .blockedDisabled
                )
                return errorResponse(id: id, code: -32001, message: "Agent access was disabled before completion.")
            }
            let allowedHeaders = headers.filter {
                !excludedFolderIDs.contains($0.folderID) && !excludedMessageIDs.contains($0.id)
            }
            let formatter = ISO8601DateFormatter()
            let boundedHeaders = Array(allowedHeaders.prefix(limit))
            let results = boundedHeaders.map { header -> [String: Any] in
                let safeSubject = Self.redactedForSignInCodes(header.subject)
                let safeSnippet = Self.redactedForSignInCodes(header.snippet)
                return [
                    "message_id": header.id,
                    "folder_id": header.folderID,
                    "from": Self.formatCorrespondent(header.from),
                    "subject": safeSubject,
                    "date": formatter.string(from: header.date),
                    "snippet": safeSnippet,
                    "is_read": header.isRead,
                    "is_flagged": header.isFlagged
                ]
            }
            recordAudit(
                client: client,
                toolName: "search_messages",
                accountID: accountID,
                parameterSummary: "query_len=\(rawQuery.count) limit=\(limit) results=\(results.count)",
                outcome: .allowed
            )
            return toolSuccessResponse(id: id, payload: [
                "messages": results,
                "truncated": allowedHeaders.count > limit
            ])
        } catch {
            recordAudit(
                client: client,
                toolName: "search_messages",
                accountID: accountID,
                parameterSummary: "search_failed",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32003, message: "Local search failed.")
        }
    }

    private func handleReadMessage(
        id: Any,
        arguments: [String: Any],
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) async -> [String: Any] {
        guard let accountID = arguments["account_id"] as? String, !accountID.isEmpty,
              let messageID = arguments["message_id"] as? String, !messageID.isEmpty
        else {
            recordAudit(
                client: client,
                toolName: "read_message",
                accountID: "none",
                parameterSummary: "missing_arguments",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required arguments 'account_id' and 'message_id'.")
        }
        guard let backend = resolveOptedInBackend(accountID: accountID, settings: settings) else {
            recordAudit(
                client: client,
                toolName: "read_message",
                accountID: "none",
                parameterSummary: "account_unavailable",
                outcome: .blockedAccount
            )
            return errorResponse(id: id, code: -32002, message: "Account not found.")
        }

        do {
            let folders = try await backend.folders()
            let excludedFolderIDs = Set(folders.filter { $0.role == .trash || $0.role == .spam }.map(\.id))
            let excludedMessageIDs = await excludedMessageIDs(in: folders, backend: backend)
            if excludedMessageIDs.contains(messageID) {
                recordAudit(
                    client: client,
                    toolName: "read_message",
                    accountID: accountID,
                    parameterSummary: "blocked_trash_or_spam",
                    outcome: .denied
                )
                return errorResponse(
                    id: id,
                    code: -32602,
                    message: "Reading messages in Trash or Spam is permanently excluded from MCP."
                )
            }
            let matchedHeaders = try await findHeaders(
                messageIDs: [messageID],
                in: backend,
                folders: folders,
                excludedFolderIDs: excludedFolderIDs,
                excludedMessageIDs: excludedMessageIDs
            )
            guard let header = matchedHeaders[messageID] else {
                // Never log unresolved caller-supplied `message_id` values so an
                // agent cannot inject sign-in codes into the local audit log.
                recordAudit(
                    client: client,
                    toolName: "read_message",
                    accountID: accountID,
                    parameterSummary: "header_cache_miss",
                    outcome: .denied
                )
                return errorResponse(
                    id: id,
                    code: -32004,
                    message: "Message not found in local cache."
                )
            }
            // ADR-0095 §2: read_message must stay strictly cache-only and never trigger
            // provider network fetches on a cache miss.
            guard let cacheProvider = backend.extensionService(CachedMessageBodyProviding.self),
                  let body = await cacheProvider.cachedBody(for: messageID, sourceID: nil)
            else {
                recordAudit(
                    client: client,
                    toolName: "read_message",
                    accountID: accountID,
                    parameterSummary: "cache_miss message_id=\(messageID)",
                    outcome: .denied
                )
                return errorResponse(
                    id: id,
                    code: -32004,
                    message: "Message body is not in Brev's local cache."
                )
            }
            guard settingsProvider().isAccountEnabled(accountID) else {
                recordAudit(
                    client: client,
                    toolName: "read_message",
                    accountID: "none",
                    parameterSummary: "consent_revoked message_id=\(messageID)",
                    outcome: .blockedDisabled
                )
                return errorResponse(id: id, code: -32001, message: "Agent access was disabled before completion.")
            }
            let rawText = Self.sanitizedPlainText(from: body)
            let safeBody = Self.redactedForSignInCodes(rawText)
            let attachments = body.attachments.map { attachment -> [String: Any] in
                [
                    "name": attachment.name,
                    "mime_type": attachment.mimeType,
                    "size_bytes": attachment.sizeBytes
                ]
            }
            let formatter = ISO8601DateFormatter()
            let payload: [String: Any] = [
                "message_id": messageID,
                "body_text": safeBody,
                "attachments": attachments,
                "from": Self.formatCorrespondent(header.from),
                "to": header.to.map(Self.formatCorrespondent),
                "cc": header.cc.map(Self.formatCorrespondent),
                "subject": Self.redactedForSignInCodes(header.subject),
                "date": formatter.string(from: header.date),
                "folder_id": header.folderID
            ]
            recordAudit(
                client: client,
                toolName: "read_message",
                accountID: accountID,
                parameterSummary: "message_id=\(messageID)",
                outcome: .allowed
            )
            return toolSuccessResponse(id: id, payload: payload)
        } catch {
            recordAudit(
                client: client,
                toolName: "read_message",
                accountID: accountID,
                parameterSummary: "read_failed",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32004, message: "Message not found in local cache.")
        }
    }

    private func handleChangeMessages(
        id: Any,
        toolName: String,
        arguments: [String: Any],
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) async -> [String: Any] {
        guard let accountID = arguments["account_id"] as? String, !accountID.isEmpty,
              let rawIDs = arguments["message_ids"] as? [String]
        else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: "none",
                parameterSummary: "missing_arguments",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required arguments 'account_id' and 'message_ids'.")
        }
        let messageIDs = Array(NSOrderedSet(array: rawIDs.filter { !$0.isEmpty })) as? [String] ?? []
        guard !messageIDs.isEmpty else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: settings.isAccountEnabled(accountID) ? accountID : "none",
                parameterSummary: "empty_message_ids",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "'message_ids' must contain at least one message ID.")
        }
        guard messageIDs.count <= Self.maxChangeBatchSize else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: settings.isAccountEnabled(accountID) ? accountID : "none",
                parameterSummary: "batch_too_large count=\(messageIDs.count)",
                outcome: .denied
            )
            return errorResponse(
                id: id,
                code: -32602,
                message: "Batch size exceeds the maximum of \(Self.maxChangeBatchSize) messages."
            )
        }
        guard let backend = resolveOptedInBackend(accountID: accountID, settings: settings) else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: "none",
                parameterSummary: "account_unavailable",
                outcome: .blockedAccount
            )
            return errorResponse(id: id, code: -32002, message: "Account not found.")
        }

        let folders: [Folder]
        let targetFolder: Folder
        do {
            folders = try await backend.folders()
            if toolName == "archive_messages" {
                guard let archive = NotificationActionExecutor.archiveDestinationFolder(in: folders) else {
                    recordAudit(
                        client: client,
                        toolName: toolName,
                        accountID: accountID,
                        parameterSummary: "no_archive_folder",
                        outcome: .denied
                    )
                    return errorResponse(id: id, code: -32005, message: "No Archive folder available on this account.")
                }
                targetFolder = archive
            } else {
                guard let folderID = arguments["folder_id"] as? String, !folderID.isEmpty else {
                    recordAudit(
                        client: client,
                        toolName: toolName,
                        accountID: accountID,
                        parameterSummary: "missing_folder_id",
                        outcome: .denied
                    )
                    return errorResponse(id: id, code: -32602, message: "Missing required argument 'folder_id'.")
                }
                guard let matched = folders.first(where: { $0.id == folderID }) else {
                    recordAudit(
                        client: client,
                        toolName: toolName,
                        accountID: accountID,
                        parameterSummary: "folder_not_found folder=\(Self.redactedForSignInCodes(folderID))",
                        outcome: .denied
                    )
                    return errorResponse(id: id, code: -32005, message: "Target folder not found.")
                }
                // ADR-0095 §3: permanently exclude Trash and Spam moves over MCP.
                guard matched.role != .trash && matched.role != .spam else {
                    recordAudit(
                        client: client,
                        toolName: toolName,
                        accountID: accountID,
                        parameterSummary: "blocked_trash_or_spam folder=\(Self.redactedForSignInCodes(folderID))",
                        outcome: .denied
                    )
                    return errorResponse(
                        id: id,
                        code: -32602,
                        message: "Moving messages to Trash or Spam is permanently excluded from MCP."
                    )
                }
                targetFolder = matched
            }
        } catch {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "folders_load_failed",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32003, message: "Couldn't inspect account folders.")
        }

        let excludedFolderIDs = Set(folders.filter { $0.role == .trash || $0.role == .spam }.map(\.id))
        let previewIDs = Array(messageIDs.prefix(5))
        let previewHeaders = await (try? findHeaders(
            messageIDs: Set(previewIDs),
            in: backend,
            folders: folders,
            excludedFolderIDs: excludedFolderIDs,
            excludedMessageIDs: nil
        )) ?? [:]
        let previews: [MCPApprovalRequest.MessagePreview] = previewIDs.map { messageID in
            if let header = previewHeaders[messageID] {
                return MCPApprovalRequest.MessagePreview(
                    id: messageID,
                    sender: Self.formatCorrespondent(header.from),
                    subject: Self.redactedForSignInCodes(header.subject)
                )
            }
            return MCPApprovalRequest.MessagePreview(
                id: messageID,
                sender: accountID,
                subject: messageID
            )
        }

        let accountLabel = backend.account.displayName.isEmpty
            ? backend.account.emailAddress
            : backend.account.displayName
        let approvalRequest = MCPApprovalRequest(
            clientName: client.displayName,
            clientPID: client.pid,
            toolName: toolName,
            accountID: accountID,
            accountLabel: accountLabel,
            targetFolderName: toolName == "label_messages" ? targetFolder.name : nil,
            messageCount: messageIDs.count,
            previews: previews,
            createdAt: now()
        )

        let decision = await approvalCoordinator.requestApproval(
            approvalRequest,
            timeoutSeconds: approvalTimeoutSeconds
        )
        let paramSummary = "count=\(messageIDs.count) folder=\(targetFolder.id) ids=\(messageIDs.prefix(3).joined(separator: ","))"

        switch decision {
        case .approved:
            // Re-verify opt-in before mutating in case Settings changed while waiting.
            guard settingsProvider().isAccountEnabled(accountID) else {
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: "none",
                    parameterSummary: "consent_revoked",
                    outcome: .blockedDisabled
                )
                return errorResponse(id: id, code: -32001, message: "Agent access was disabled before execution.")
            }
            do {
                try await backend.move(messageIDs: messageIDs, to: targetFolder)
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: accountID,
                    parameterSummary: paramSummary,
                    outcome: .approved
                )
                return toolSuccessResponse(id: id, payload: [
                    "status": "approved",
                    "moved_count": messageIDs.count,
                    "target_folder_id": targetFolder.id
                ])
            } catch {
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: accountID,
                    parameterSummary: "move_failed \(paramSummary)",
                    outcome: .denied
                )
                return errorResponse(id: id, code: -32006, message: "Failed to apply approved mailbox change.")
            }

        case .denied:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: paramSummary,
                outcome: .denied
            )
            return errorResponse(id: id, code: -32010, message: "User denied the request in Brev.")

        case .timedOut:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: paramSummary,
                outcome: .timedOut
            )
            return errorResponse(id: id, code: -32011, message: "Approval request timed out in Brev.")

        case .rateLimited:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "concurrent_approval_rejected \(paramSummary)",
                outcome: .rateLimited
            )
            return errorResponse(
                id: id,
                code: -32012,
                message: "Another approval prompt is already active in Brev. Wait and retry."
            )
        }
    }

    private func handleCreateDraft(
        id: Any,
        arguments: [String: Any],
        settings: AgentAccessSettings,
        client: MCPClientContext
    ) async -> [String: Any] {
        let toolName = "create_draft"
        guard let accountID = arguments["account_id"] as? String, !accountID.isEmpty else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: "none",
                parameterSummary: "missing_account_id",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required argument 'account_id'.")
        }
        guard let backend = resolveOptedInBackend(accountID: accountID, settings: settings) else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: "none",
                parameterSummary: "account_unavailable",
                outcome: .blockedAccount
            )
            return errorResponse(id: id, code: -32002, message: "Account not found.")
        }

        let unknownKeys = Set(arguments.keys).subtracting(Self.createDraftAllowedArgumentKeys)
        guard unknownKeys.isEmpty else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "unknown_arguments count=\(unknownKeys.count)",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Unsupported argument(s) for 'create_draft'.")
        }

        let toAddresses: [String]
        let ccAddresses: [String]
        let bccAddresses: [String]
        do {
            toAddresses = try Self.validatedDraftRecipients(from: arguments["to"], required: true)
            ccAddresses = try Self.validatedDraftRecipients(from: arguments["cc"], required: false)
            bccAddresses = try Self.validatedDraftRecipients(from: arguments["bcc"], required: false)
        } catch let validationError as DraftArgumentValidationError {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: validationError.auditReason,
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: validationError.message)
        } catch {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "invalid_recipients",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Invalid recipient email address.")
        }

        let totalRecipients = toAddresses.count + ccAddresses.count + bccAddresses.count
        guard totalRecipients <= Self.maxDraftRecipients else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "too_many_recipients count=\(totalRecipients)",
                outcome: .denied
            )
            return errorResponse(
                id: id,
                code: -32602,
                message: "Total recipients exceed the maximum of \(Self.maxDraftRecipients)."
            )
        }

        guard let rawSubject = arguments["subject"] as? String else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "missing_subject",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required argument 'subject'.")
        }
        let subject = rawSubject
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard subject.count <= Self.maxDraftSubjectLength else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "subject_too_long len=\(subject.count)",
                outcome: .denied
            )
            return errorResponse(
                id: id,
                code: -32602,
                message: "Draft subject exceeds the maximum of \(Self.maxDraftSubjectLength) characters."
            )
        }

        guard let bodyText = arguments["body_text"] as? String else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "missing_body_text",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32602, message: "Missing required argument 'body_text'.")
        }
        let bodyBytes = bodyText.utf8.count
        guard bodyBytes <= Self.maxDraftBodyBytes else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "body_too_large bytes=\(bodyBytes)",
                outcome: .denied
            )
            return errorResponse(
                id: id,
                code: -32602,
                message: "Draft body exceeds the maximum size of 64 KiB."
            )
        }

        let folders: [Folder]
        do {
            folders = try await backend.folders()
        } catch {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "folders_load_failed",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32003, message: "Couldn't inspect account folders.")
        }
        guard folders.contains(where: { $0.role == .drafts }) else {
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "no_drafts_folder",
                outcome: .denied
            )
            return errorResponse(id: id, code: -32005, message: "No Drafts folder available on this account.")
        }

        var replyHeader: MessageHeader?
        if let rawReplyArg = arguments["in_reply_to_message_id"], !(rawReplyArg is NSNull) {
            guard let rawReplyID = rawReplyArg as? String else {
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: accountID,
                    parameterSummary: "invalid_in_reply_to",
                    outcome: .denied
                )
                return errorResponse(id: id, code: -32602, message: "'in_reply_to_message_id' must be a string.")
            }
            let replyID = rawReplyID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !replyID.isEmpty {
                do {
                    let excludedFolderIDs = Set(folders.filter { $0.role == .trash || $0.role == .spam }.map(\.id))
                    let excludedIDs = await excludedMessageIDs(in: folders, backend: backend)
                    if excludedIDs.contains(replyID) {
                        recordAudit(
                            client: client,
                            toolName: toolName,
                            accountID: accountID,
                            parameterSummary: "in_reply_to_unavailable",
                            outcome: .denied
                        )
                        return errorResponse(id: id, code: -32004, message: "Referenced message not found in local cache.")
                    }
                    let matched = try await findHeaders(
                        messageIDs: [replyID],
                        in: backend,
                        folders: folders,
                        excludedFolderIDs: excludedFolderIDs,
                        excludedMessageIDs: excludedIDs
                    )
                    guard let resolved = matched[replyID] else {
                        // Never log unresolved caller-supplied message IDs.
                        recordAudit(
                            client: client,
                            toolName: toolName,
                            accountID: accountID,
                            parameterSummary: "in_reply_to_not_found",
                            outcome: .denied
                        )
                        return errorResponse(id: id, code: -32004, message: "Referenced message not found in local cache.")
                    }
                    replyHeader = resolved
                } catch {
                    recordAudit(
                        client: client,
                        toolName: toolName,
                        accountID: accountID,
                        parameterSummary: "in_reply_to_lookup_failed",
                        outcome: .denied
                    )
                    return errorResponse(id: id, code: -32004, message: "Referenced message not found in local cache.")
                }
            }
        }

        let safeSubject = Self.redactedForSignInCodes(subject)
        let (bodyPreview, isBodyTruncated) = Self.draftBodyPreview(from: bodyText)
        let safeReplySubject = replyHeader.map { Self.redactedForSignInCodes($0.subject) }

        let accountLabel = backend.account.displayName.isEmpty
            ? backend.account.emailAddress
            : backend.account.displayName
        let approvalRequest = MCPApprovalRequest(
            clientName: client.displayName,
            clientPID: client.pid,
            toolName: toolName,
            accountID: accountID,
            accountLabel: accountLabel,
            targetFolderName: nil,
            messageCount: 0,
            previews: [],
            draftPreview: MCPApprovalRequest.DraftPreview(
                to: toAddresses,
                cc: ccAddresses,
                bcc: bccAddresses,
                subject: safeSubject,
                bodyPreview: bodyPreview,
                isBodyTruncated: isBodyTruncated,
                inReplyToSubject: safeReplySubject
            ),
            createdAt: now()
        )

        let replyTag = replyHeader != nil ? " reply=true" : ""
        // Never store caller-supplied subject or raw draft body text in audit logs so
        // bare sign-in codes or private draft content can never hit disk.
        let paramSummary =
            "to=\(toAddresses.count) cc=\(ccAddresses.count) bcc=\(bccAddresses.count) subject_len=\(subject.count) body_bytes=\(bodyBytes)\(replyTag)"

        let decision = await approvalCoordinator.requestApproval(
            approvalRequest,
            timeoutSeconds: approvalTimeoutSeconds
        )

        switch decision {
        case .approved:
            // Re-verify opt-in before saving in case Settings changed while waiting.
            guard settingsProvider().isAccountEnabled(accountID) else {
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: "none",
                    parameterSummary: "consent_revoked",
                    outcome: .blockedDisabled
                )
                return errorResponse(id: id, code: -32001, message: "Agent access was disabled before execution.")
            }
            let draft = Draft(
                id: UUID().uuidString,
                threadID: replyHeader?.threadID,
                inReplyToMessageID: replyHeader?.rfcMessageID,
                to: toAddresses.map { Correspondent(email: $0) },
                cc: ccAddresses.map { Correspondent(email: $0) },
                bcc: bccAddresses.map { Correspondent(email: $0) },
                subject: subject,
                htmlBody: ComposeHTMLBodyPolicy.html(fromEditorText: bodyText)
            )
            do {
                let saved = try await backend.save(draft: draft)
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: accountID,
                    parameterSummary: paramSummary,
                    outcome: .approved
                )
                return toolSuccessResponse(id: id, payload: [
                    "draft_id": saved.id,
                    "account_id": accountID,
                    "subject": Self.redactedForSignInCodes(saved.subject),
                    "recipient_count": totalRecipients,
                    "status": "saved_as_draft"
                ])
            } catch {
                recordAudit(
                    client: client,
                    toolName: toolName,
                    accountID: accountID,
                    parameterSummary: "save_failed \(paramSummary)",
                    outcome: .denied
                )
                return errorResponse(id: id, code: -32006, message: "Failed to save approved draft.")
            }

        case .denied:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: paramSummary,
                outcome: .denied
            )
            return errorResponse(id: id, code: -32010, message: "User denied the request in Brev.")

        case .timedOut:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: paramSummary,
                outcome: .timedOut
            )
            return errorResponse(id: id, code: -32011, message: "Approval request timed out in Brev.")

        case .rateLimited:
            recordAudit(
                client: client,
                toolName: toolName,
                accountID: accountID,
                parameterSummary: "concurrent_approval_rejected \(paramSummary)",
                outcome: .rateLimited
            )
            return errorResponse(
                id: id,
                code: -32012,
                message: "Another approval prompt is already active in Brev. Wait and retry."
            )
        }
    }

    private struct DraftArgumentValidationError: Error {
        let auditReason: String
        let message: String
    }

    private static func validatedDraftRecipients(from rawValue: Any?, required: Bool) throws -> [String] {
        if rawValue == nil || rawValue is NSNull {
            if required {
                throw DraftArgumentValidationError(
                    auditReason: "missing_to_recipients",
                    message: "Missing required argument 'to' (non-empty array of valid email addresses)."
                )
            }
            return []
        }
        guard let values = rawValue as? [String] else {
            throw DraftArgumentValidationError(
                auditReason: "invalid_recipient_type",
                message: "Recipient fields must be arrays of email address strings."
            )
        }
        if required && values.isEmpty {
            throw DraftArgumentValidationError(
                auditReason: "empty_to_recipients",
                message: "'to' must contain at least one valid email address."
            )
        }
        var validated: [String] = []
        validated.reserveCapacity(values.count)
        for raw in values {
            guard !raw.contains("\r"), !raw.contains("\n") else {
                throw DraftArgumentValidationError(
                    auditReason: "invalid_recipient_address",
                    message: "Recipient email address contains invalid characters."
                )
            }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard isValidDraftEmail(trimmed) else {
                throw DraftArgumentValidationError(
                    auditReason: "invalid_recipient_address",
                    message: "One or more recipient email addresses are invalid."
                )
            }
            validated.append(trimmed)
        }
        return validated
    }

    private static let dotAtomAllowedBytes: Set<UInt8> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~".utf8
    )

    private static func isValidDraftEmail(_ address: String) -> Bool {
        guard !address.isEmpty, address.utf8.count <= 254 else { return false }
        let parts = address.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.isEmpty,
              local.utf8.count <= 64,
              !local.hasPrefix("."),
              !local.hasSuffix("."),
              !local.contains("..")
        else { return false }
        for segment in local.split(separator: ".", omittingEmptySubsequences: false) {
            guard !segment.isEmpty,
                  segment.utf8.allSatisfy({ dotAtomAllowedBytes.contains($0) })
            else { return false }
        }
        return MailAccountAutodiscovery.isValidServerHost(domain)
    }

    private static func draftBodyPreview(from bodyText: String) -> (preview: String, isTruncated: Bool) {
        let redacted = redactedForSignInCodes(bodyText)
        if redacted != bodyText {
            return (redacted, false)
        }
        let normalized = bodyText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var truncated = false
        let lineBounded: String
        if lines.count > maxDraftPreviewLines {
            lineBounded = lines.prefix(maxDraftPreviewLines).joined(separator: "\n")
            truncated = true
        } else {
            lineBounded = normalized
        }
        if lineBounded.count > maxDraftPreviewCharacters {
            return (String(lineBounded.prefix(maxDraftPreviewCharacters)) + "…", true)
        }
        return (truncated ? lineBounded + "…" : lineBounded, truncated)
    }

    private func resolveOptedInBackend(
        accountID: String,
        settings: AgentAccessSettings
    ) -> (any MailBackend)? {
        guard settings.isAccountEnabled(accountID) else { return nil }
        return backendsProvider().first { $0.account.id == accountID }
    }

    private func excludedMessageIDs(
        in folders: [Folder],
        backend: any MailBackend
    ) async -> Set<MessageHeader.ID> {
        var excluded: Set<MessageHeader.ID> = []
        for folder in folders where folder.role == .trash || folder.role == .spam {
            if let matches = try? await backend.search(SearchQuery(
                text: "",
                folderID: folder.id,
                execution: .cacheOnly
            )) {
                for header in matches {
                    excluded.insert(header.id)
                }
            }
        }
        return excluded
    }

    private func findHeaders(
        messageIDs: Set<String>,
        in backend: any MailBackend,
        folders: [Folder],
        excludedFolderIDs: Set<Folder.ID>,
        excludedMessageIDs: Set<MessageHeader.ID>?
    ) async throws -> [String: MessageHeader] {
        guard !messageIDs.isEmpty else { return [:] }
        var remaining = messageIDs
        var resolved: [String: MessageHeader] = [:]
        for folder in folders where folder.role != .trash && folder.role != .spam {
            let matches = try await backend.search(SearchQuery(
                text: "",
                folderID: folder.id,
                execution: .cacheOnly
            ))
            for header in matches where remaining.contains(header.id) {
                resolved[header.id] = header
                remaining.remove(header.id)
            }
            if remaining.isEmpty { break }
        }
        // Fallback for archived messages without a catalog folder (e.g., unlabeled Gmail
        // mail mapped to synthetic `ALL_MAIL`): query the local cache unscoped while
        // still enforcing Trash/Spam exclusion.
        if !remaining.isEmpty {
            let excludedIDs: Set<MessageHeader.ID>
            if let excludedMessageIDs {
                excludedIDs = excludedMessageIDs
            } else {
                excludedIDs = await self.excludedMessageIDs(in: folders, backend: backend)
            }
            let unscoped = try await backend.search(SearchQuery(
                text: "",
                folderID: nil,
                execution: .cacheOnly
            ))
            for header in unscoped where remaining.contains(header.id)
                && !excludedFolderIDs.contains(header.folderID)
                && !excludedIDs.contains(header.id) {
                resolved[header.id] = header
                remaining.remove(header.id)
            }
        }
        return resolved
    }

    private func recordAudit(
        client: MCPClientContext,
        toolName: String,
        accountID: String,
        parameterSummary: String,
        outcome: AgentAccessAuditOutcome
    ) {
        auditStore.record(AgentAccessAuditEntry(
            timestamp: now(),
            clientName: client.displayName,
            clientPID: client.pid,
            toolName: toolName,
            accountID: accountID,
            parameterSummary: parameterSummary,
            outcome: outcome
        ))
    }

    /// ADR-0088 / ADR-0095 fail-closed credential guard: redact text matching `SignInCodeDetector`
    /// OR conservative OTP / magic-link patterns (including messages with unsubscribe footers,
    /// multiple candidates, markup, or > 64 KB payloads that the UI extractor intentionally skips).
    static func redactedForSignInCodes(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if SignInCodeDetector.detect(in: text) != nil || containsPotentialSignInCredential(text) {
            return "[Redacted: sign-in code or verification link hidden per ADR-0088]"
        }
        return text
    }

    private static let fallbackCredentialPatterns: [String] = [
        #"(?i)\b(?:verification|verify|sign[- ]?in|log[- ]?in|one[- ]?time|passcode|otp|2fa|two[- ]factor|security|auth(?:entication)?|bekreftelses|engangs|innloggings)\s*(?:code|pin|token|kode)\b.{0,48}\b[A-Z0-9]{4,8}\b"#,
        #"(?i)\b\d{4,8}\b.{0,32}\b(?:verification|verify|sign[- ]?in|log[- ]?in|one[- ]?time|passcode|otp|bekreftelseskode|engangskode)\b"#,
        #"(?i)https?://\S*(?:magic[-_]?link|sign[-_]?in|log[-_]?in|verify|verification|auth|token=|code=|otp=|reset[-_]?password)\S*"#
    ]

    private static func containsPotentialSignInCredential(_ text: String) -> Bool {
        fallbackCredentialPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func sanitizedPlainText(from body: MessageBody) -> String {
        if let plain = body.plainText?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }
        guard let html = body.html else { return "" }
        let withoutScripts = html
            .replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutScripts
    }

    private static func formatCorrespondent(_ correspondent: Correspondent) -> String {
        if let name = correspondent.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name) <\(correspondent.email)>"
        }
        return correspondent.email
    }

    private static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "list_accounts",
                "description": "List opaque account IDs and labels for accounts opted in to local agent access.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]
            ],
            [
                "name": "list_folders",
                "description": "List folders, roles, and unread counts for an opted-in account from local state.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["account_id": ["type": "string"]],
                    "required": ["account_id"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "search_messages",
                "description": "Search locally cached messages on an opted-in account (cache-only, max 50 results).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string"],
                        "query": ["type": "string"],
                        "folder_id": ["type": "string"],
                        "limit": ["type": "integer", "minimum": 1, "maximum": maxSearchResults]
                    ],
                    "required": ["account_id"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "read_message",
                "description": "Read sanitized plain text, basic headers, and attachment names for one cached message.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string"],
                        "message_id": ["type": "string"]
                    ],
                    "required": ["account_id", "message_id"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "archive_messages",
                "description": "Archive up to 25 messages after explicit in-app user approval in Brev.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string"],
                        "message_ids": ["type": "array", "items": ["type": "string"], "maxItems": maxChangeBatchSize]
                    ],
                    "required": ["account_id", "message_ids"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "label_messages",
                "description": "Move up to 25 messages to a non-Trash, non-Spam folder after explicit in-app user approval in Brev.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string"],
                        "message_ids": ["type": "array", "items": ["type": "string"], "maxItems": maxChangeBatchSize],
                        "folder_id": ["type": "string"]
                    ],
                    "required": ["account_id", "message_ids", "folder_id"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "create_draft",
                "description": "Save a plain-text draft for manual review after explicit in-app user approval in Brev. Never sends mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string"],
                        "to": [
                            "type": "array",
                            "items": ["type": "string"],
                            "minItems": 1,
                            "maxItems": maxDraftRecipients
                        ],
                        "cc": [
                            "type": "array",
                            "items": ["type": "string"],
                            "maxItems": maxDraftRecipients
                        ],
                        "bcc": [
                            "type": "array",
                            "items": ["type": "string"],
                            "maxItems": maxDraftRecipients
                        ],
                        "subject": ["type": "string", "maxLength": maxDraftSubjectLength],
                        "body_text": [
                            "type": "string",
                            "description": "Plain text draft body. Must not exceed 65,536 bytes when encoded as UTF-8."
                        ],
                        "in_reply_to_message_id": ["type": "string"]
                    ],
                    "required": ["account_id", "to", "subject", "body_text"],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private func toolSuccessResponse(id: Any, payload: [String: Any]) -> [String: Any] {
        let text: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let serialized = String(data: jsonData, encoding: .utf8) {
            text = serialized
        } else {
            text = "{}"
        }
        return successResponse(id: id, result: [
            "content": [
                ["type": "text", "text": text]
            ]
        ])
    }

    private func successResponse(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private func encodeJSON(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

#if os(macOS)

// MARK: - User-private Unix domain socket listener (zero TCP/UDP ports, ADR-0095 §1)

/// Listens on a `0600` user-private `AF_UNIX` stream socket and enforces same-UID peer credentials.
/// Never opens any TCP or UDP socket.
public final class LocalMCPUnixSocketServer: @unchecked Sendable {
    /// Serializes client descriptor registration, shutdown, and closing under a single lock so
    /// `stop()` can never shut down a descriptor number after it has been closed and recycled.
    private final class ClientRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var isAccepting = false
        private var activeClients: [UUID: Int32] = [:]

        func open() {
            lock.lock()
            isAccepting = true
            lock.unlock()
        }

        func register(_ fd: Int32) -> UUID? {
            lock.lock()
            defer { lock.unlock() }
            guard isAccepting else { return nil }
            let token = UUID()
            activeClients[token] = fd
            return token
        }

        func closeClient(token: UUID) {
            lock.lock()
            let fd = activeClients.removeValue(forKey: token)
            if let fd {
                close(fd)
            }
            lock.unlock()
        }

        func shutdownAllAndCloseAccepting() {
            lock.lock()
            isAccepting = false
            for fd in activeClients.values {
                _ = shutdown(fd, SHUT_RDWR)
            }
            lock.unlock()
        }
    }

    public let socketURL: URL
    private let broker: LocalMCPBroker
    private let queue = DispatchQueue(label: "eu.brevmail.local-mcp-socket", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private let clientRegistry = ClientRegistry()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var ownsSocketFile = false

    public init(socketURL: URL = AgentAccessSocketConfiguration.defaultSocketURL(), broker: LocalMCPBroker) {
        self.socketURL = socketURL
        self.broker = broker
    }

    deinit {
        stop()
    }

    /// Whether the Unix domain socket is currently listening.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listenFD >= 0
    }

    /// Starts listening on the user-private `0600` Unix domain socket.
    /// Refuses to unlink a socket owned by another live listener (`EADDRINUSE`),
    /// while cleaning up stale/abandoned socket files left by a prior crash.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD < 0 else { return }

        let parentDir = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        var dirStat = stat()
        guard lstat(parentDir.path, &dirStat) == 0,
              (dirStat.st_mode & S_IFMT) == S_IFDIR,
              dirStat.st_uid == geteuid()
        else {
            throw POSIXError(.EACCES)
        }
        guard chmod(parentDir.path, mode_t(0o700)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }

        let pathBytes = Array(socketURL.path.utf8)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < maxPathLen else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = byte
            }
        }

        if Self.isLiveUnixSocket(addr: addr) {
            throw POSIXError(.EADDRINUSE)
        }
        // Only remove an abandoned socket file after confirming no live listener owns it.
        var st = stat()
        if lstat(socketURL.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFSOCK {
            unlink(socketURL.path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EADDRINUSE)
        }

        // Enforce 0600 user-private permissions immediately after bind (ADR-0095 §1).
        guard chmod(socketURL.path, mode_t(0o600)) == 0 else {
            let err = errno
            close(fd)
            unlink(socketURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EACCES)
        }

        guard listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            unlink(socketURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        listenFD = fd
        ownsSocketFile = true
        clientRegistry.open()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptNextConnection()
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
    }

    /// Stops listening, terminates any active client sockets, and unlinks the Unix domain socket
    /// file only if this server instance bound it.
    public func stop() {
        lock.lock()
        let source = acceptSource
        acceptSource = nil
        listenFD = -1
        let shouldUnlink = ownsSocketFile
        ownsSocketFile = false
        lock.unlock()

        clientRegistry.shutdownAllAndCloseAccepting()
        source?.cancel()
        if shouldUnlink {
            unlink(socketURL.path)
        }
    }

    private static func isLiveUnixSocket(addr: sockaddr_un) -> Bool {
        let probeFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probeFD >= 0 else { return false }
        defer { close(probeFD) }
        var mutableAddr = addr
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &mutableAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(probeFD, sockPtr, addrLen)
            }
        }
        return connected == 0
    }

    private func acceptNextConnection() {
        lock.lock()
        let fd = listenFD
        lock.unlock()
        guard fd >= 0 else { return }

        let clientFD = accept(fd, nil, nil)
        guard clientFD >= 0 else { return }

        // Prevent SIGPIPE from terminating Brev if an agent disconnects while awaiting approval.
        var noSigPipe: Int32 = 1
        _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        // Verify peer UID matches current macOS user (ADR-0095 §1).
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
            close(clientFD)
            return
        }

        var peerPID: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        _ = getsockopt(clientFD, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &pidLen)
        let processName = Self.resolveProcessName(pid: peerPID)
        let clientContext = MCPClientContext(
            processName: processName,
            pid: peerPID > 0 ? peerPID : nil
        )

        guard let token = clientRegistry.register(clientFD) else {
            close(clientFD)
            return
        }

        let registry = clientRegistry
        queue.async { [broker] in
            defer { registry.closeClient(token: token) }
            Self.serveClient(fd: clientFD, client: clientContext, broker: broker)
        }
    }

    private static func serveClient(fd: Int32, client: MCPClientContext, broker: LocalMCPBroker) {
        var sessionClient = client
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(fd, &chunk, chunk.count)
            if bytesRead <= 0 { break }
            buffer.append(contentsOf: chunk[0 ..< bytesRead])

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0 ..< newlineIndex)
                buffer.removeSubrange(0 ... newlineIndex)
                guard !lineData.isEmpty else { continue }

                if let declaredName = Self.initializedClientName(from: lineData) {
                    let attributed = declaredName == client.processName
                        ? declaredName
                        : "\(declaredName) (via \(client.processName))"
                    sessionClient = MCPClientContext(processName: attributed, pid: client.pid)
                }

                let currentClient = sessionClient
                let semaphore = DispatchSemaphore(value: 0)
                var responseData: Data?
                Task { @MainActor in
                    responseData = await broker.handleJSONRPCData(lineData, client: currentClient)
                    semaphore.signal()
                }
                semaphore.wait()

                if var output = responseData {
                    output.append(0x0A)
                    let wroteAll = output.withUnsafeBytes { rawPtr -> Bool in
                        guard let base = rawPtr.baseAddress else { return false }
                        var totalWritten = 0
                        while totalWritten < output.count {
                            let written = write(fd, base.advanced(by: totalWritten), output.count - totalWritten)
                            if written <= 0 { return false }
                            totalWritten += written
                        }
                        return true
                    }
                    if !wroteAll { return }
                }
            }
        }
    }

    private static func initializedClientName(from lineData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              (object["method"] as? String) == "initialize",
              let params = object["params"] as? [String: Any],
              let clientInfo = params["clientInfo"] as? [String: Any],
              let rawName = clientInfo["name"] as? String
        else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    private static func resolveProcessName(pid: pid_t) -> String {
        guard pid > 0 else { return "local-agent" }
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let count = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if count > 0 {
            let name = String(cString: nameBuffer)
            if !name.isEmpty { return name }
        }
        return "local-agent"
    }
}
#endif
