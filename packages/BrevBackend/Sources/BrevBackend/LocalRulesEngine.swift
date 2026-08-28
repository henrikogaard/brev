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

public struct LocalRulesExecutionContext: Sendable, Equatable {
    public enum DestructiveActionPolicy: Sendable, Equatable {
        /// Automatic execution mode: destructive actions are skipped and
        /// surfaced for explicit user confirmation.
        case requireExplicitApproval
        /// Manual safe run: destructive delete is converted to a recoverable
        /// move into the configured folder.
        case recoverDelete(toFolderID: Folder.ID)
        /// Manual forced run: destructive actions execute as-is.
        case allow
    }

    public var capabilities: BackendCapabilities
    public var destructiveActionPolicy: DestructiveActionPolicy
    public var archiveFolderID: Folder.ID?

    public init(
        capabilities: BackendCapabilities = [],
        destructiveActionPolicy: DestructiveActionPolicy = .requireExplicitApproval,
        archiveFolderID: Folder.ID? = nil
    ) {
        self.capabilities = capabilities
        self.destructiveActionPolicy = destructiveActionPolicy
        self.archiveFolderID = archiveFolderID
    }
}

public struct LocalRulesExecutionResult: Sendable, Equatable {
    public enum SkippedActionReason: Sendable, Equatable {
        case missingCapability(BackendCapabilities)
        case requiresExplicitDestructiveApproval
    }

    public struct AppliedAction: Sendable, Equatable {
        public let ruleID: ServerRule.ID
        public let messageID: MessageHeader.ID
        /// Action after local safety/capability resolution.
        public let action: ServerRuleAction
        /// Original action stored in the rule.
        public let originalAction: ServerRuleAction

        public init(
            ruleID: ServerRule.ID,
            messageID: MessageHeader.ID,
            action: ServerRuleAction,
            originalAction: ServerRuleAction
        ) {
            self.ruleID = ruleID
            self.messageID = messageID
            self.action = action
            self.originalAction = originalAction
        }
    }

    public struct SkippedAction: Sendable, Equatable {
        public let ruleID: ServerRule.ID
        public let messageID: MessageHeader.ID
        public let action: ServerRuleAction
        public let reason: SkippedActionReason

        public init(
            ruleID: ServerRule.ID,
            messageID: MessageHeader.ID,
            action: ServerRuleAction,
            reason: SkippedActionReason
        ) {
            self.ruleID = ruleID
            self.messageID = messageID
            self.action = action
            self.reason = reason
        }
    }

    public let appliedActions: [AppliedAction]
    public let skippedActions: [SkippedAction]
    /// Remaining headers after execution. Permanently deleted messages are
    /// removed. Ordering is deterministic (newest first, then id).
    public let headers: [MessageHeader]

    public init(
        appliedActions: [AppliedAction],
        skippedActions: [SkippedAction],
        headers: [MessageHeader]
    ) {
        self.appliedActions = appliedActions
        self.skippedActions = skippedActions
        self.headers = headers
    }
}

public enum LocalRulesEngine {
    public static func execute(
        rules: [ServerRule],
        on inputHeaders: [MessageHeader],
        context: LocalRulesExecutionContext = .init()
    ) -> LocalRulesExecutionResult {
        let orderedRules = rules.filter(\.isEnabled)
        let orderedHeaders = deterministicOrder(for: inputHeaders)
        let orderedMessageIDs = orderedHeaders.map(\.id)
        // Failable-merge: a server can emit two messages with the same UID
        // (duplicate header id), which would trap Dictionary(uniqueKeysWithValues:).
        var states = Dictionary(
            orderedHeaders.map { ($0.id, MessageState(header: $0)) },
            uniquingKeysWith: { _, newer in newer }
        )

        var appliedActions: [LocalRulesExecutionResult.AppliedAction] = []
        var skippedActions: [LocalRulesExecutionResult.SkippedAction] = []

        for rule in orderedRules {
            for messageID in orderedMessageIDs {
                guard var state = states[messageID], !state.halted else { continue }
                guard rule.matches(header: state.header, capabilities: context.capabilities) else { continue }

                actionLoop: for action in rule.actions {
                    switch resolve(
                        action: action,
                        capabilities: context.capabilities,
                        destructiveActionPolicy: context.destructiveActionPolicy,
                        archiveFolderID: context.archiveFolderID
                    ) {
                    case .skip(let reason):
                        skippedActions.append(
                            .init(
                                ruleID: rule.id,
                                messageID: state.header.id,
                                action: action,
                                reason: reason
                            )
                        )
                    case .apply(let resolvedAction, let isDestructive):
                        state.apply(resolvedAction)
                        appliedActions.append(
                            .init(
                                ruleID: rule.id,
                                messageID: state.header.id,
                                action: resolvedAction,
                                originalAction: action
                            )
                        )
                        if isDestructive {
                            state.halted = true
                            break actionLoop
                        }
                    }
                }

                states[state.header.id] = state
            }
        }

        let headers = orderedMessageIDs.compactMap { messageID -> MessageHeader? in
            guard let state = states[messageID], !state.deleted else { return nil }
            return state.header
        }
        return LocalRulesExecutionResult(
            appliedActions: appliedActions,
            skippedActions: skippedActions,
            headers: headers
        )
    }
}

private struct MessageState {
    var header: MessageHeader
    var halted = false
    var deleted = false

    mutating func apply(_ action: ServerRuleAction) {
        switch action {
        case .moveToFolder(let id):
            header = MessageHeader(
                id: header.id,
                threadID: header.threadID,
                folderID: id,
                from: header.from,
                to: header.to,
                cc: header.cc,
                bcc: header.bcc,
                subject: header.subject,
                snippet: header.snippet,
                date: header.date,
                isRead: header.isRead,
                isFlagged: header.isFlagged,
                isAnswered: header.isAnswered,
                isForwarded: header.isForwarded,
                hasAttachments: header.hasAttachments,
                flagColor: header.flagColor,
                messageID: header.messageID,
                inReplyTo: header.inReplyTo,
                labels: header.labels
            )
        case .archive:
            break
        case .markRead:
            header.isRead = true
        case .markUnread:
            header.isRead = false
        case .flag:
            header.isFlagged = true
        case .delete:
            deleted = true
        case .forward, .providerAction:
            break
        }
    }
}

private extension ServerRule {
    func matches(
        header: MessageHeader,
        capabilities: BackendCapabilities
    ) -> Bool {
        conditions.allSatisfy { condition in
            switch condition {
            case .senderContains(let value):
                let needle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return false }
                return header.from.email.lowercased().contains(needle)
                    || (header.from.name?.lowercased().contains(needle) ?? false)

            case .recipientContains(let value):
                let needle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return false }
                let recipients = header.to + header.cc + header.bcc
                return recipients.contains {
                    $0.email.lowercased().contains(needle)
                        || ($0.name?.lowercased().contains(needle) ?? false)
                }

            case .subjectContains(let value):
                let needle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return false }
                return header.subject.lowercased().contains(needle)

            case .hasAttachment:
                return header.hasAttachments

            case .isUnread:
                return !header.isRead

            case .providerPredicate:
                return capabilities.contains(.providerAPI)
            }
        }
    }
}

private enum LocalRuleResolvedAction {
    case apply(ServerRuleAction, isDestructive: Bool)
    case skip(LocalRulesExecutionResult.SkippedActionReason)
}

private func resolve(
    action: ServerRuleAction,
    capabilities: BackendCapabilities,
    destructiveActionPolicy: LocalRulesExecutionContext.DestructiveActionPolicy,
    archiveFolderID: Folder.ID?
) -> LocalRuleResolvedAction {
    if case .providerAction = action, !capabilities.contains(.providerAPI) {
        return .skip(.missingCapability(.providerAPI))
    }
    if case .forward = action, !capabilities.contains(.providerAPI) {
        return .skip(.missingCapability(.providerAPI))
    }

    switch action {
    case .archive:
        if let archiveFolderID {
            return .apply(.moveToFolder(id: archiveFolderID), isDestructive: false)
        }
        return .apply(action, isDestructive: false)

    case .delete:
        switch destructiveActionPolicy {
        case .requireExplicitApproval:
            return .skip(.requiresExplicitDestructiveApproval)
        case .recoverDelete(let folderID):
            return .apply(.moveToFolder(id: folderID), isDestructive: true)
        case .allow:
            return .apply(.delete, isDestructive: true)
        }

    case .forward:
        switch destructiveActionPolicy {
        case .requireExplicitApproval:
            return .skip(.requiresExplicitDestructiveApproval)
        case .recoverDelete, .allow:
            return .apply(action, isDestructive: true)
        }

    case .moveToFolder, .markRead, .markUnread, .flag, .providerAction:
        return .apply(action, isDestructive: false)
    }
}

private func deterministicOrder(for headers: [MessageHeader]) -> [MessageHeader] {
    headers.sorted { lhs, rhs in
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id < rhs.id
    }
}
