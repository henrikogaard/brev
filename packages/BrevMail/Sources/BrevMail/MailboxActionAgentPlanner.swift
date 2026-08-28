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
import Foundation

enum MailboxActionAgentClarification: Equatable, Sendable {
    case unsupportedRequest
    case missingSender
    case missingMoveTarget
    case unknownFolder(String)
    case ambiguousFolder(String)
}

enum MailboxActionAgentPlanningResult: Equatable, Sendable {
    case planned(MailboxActionAgentPlan)
    case clarificationRequired(MailboxActionAgentClarification)
}

struct MailboxActionAgentSourceScope: Equatable, Sendable {
    let sourceID: MailSourceID?
    let accountName: String?
    let mailboxName: String?
    let mailboxAddress: String?

    static let currentMailbox = MailboxActionAgentSourceScope(
        sourceID: nil,
        accountName: nil,
        mailboxName: nil,
        mailboxAddress: nil
    )

    init(
        sourceID: MailSourceID?,
        accountName: String?,
        mailboxName: String?,
        mailboxAddress: String?
    ) {
        self.sourceID = sourceID
        self.accountName = Self.cleaned(accountName)
        self.mailboxName = Self.cleaned(mailboxName)
        self.mailboxAddress = Self.cleaned(mailboxAddress)
    }

    var displayText: String {
        var parts: [String] = []
        if let accountName {
            parts.append(accountName)
        }
        if let mailboxName, mailboxName != mailboxAddress {
            parts.append(mailboxName)
        }
        let base = parts.isEmpty ? mailboxAddress ?? "Current mailbox" : parts.joined(separator: " - ")
        guard let mailboxAddress, mailboxAddress != base else {
            return base
        }
        return "\(base) (\(mailboxAddress))"
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MailboxActionAgentStructuredIntentError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedFields([String])
    case missingAction
    case missingSender
    case unsupportedAction(String)
    case missingMoveTarget
    case invalidField(String)
}

enum MailboxActionAgentStructuredIntentAction: Equatable, Sendable {
    case delete
    case move
    case archive
    case markRead
    case markUnread
    case flag
    case unflag
}

struct MailboxActionAgentStructuredIntent: Equatable, Sendable {
    let action: MailboxActionAgentStructuredIntentAction
    let senderEmail: String
    let targetFolderName: String?
    let useFocusedFolder: Bool
    let sourceFolderName: String?
    let olderThanDays: Int?

    var requestText: String {
        var text: String
        switch action {
        case .delete:
            text = "delete all mails from sender \(senderEmail)"
        case .move:
            let target = useFocusedFolder
                ? "this folder here"
                : targetFolderName ?? ""
            text = "move all mails from sender \(senderEmail) to \(target)"
        case .archive:
            text = "archive all mails from sender \(senderEmail)"
        case .markRead:
            text = "mark all mails from sender \(senderEmail) as read"
        case .markUnread:
            text = "mark all mails from sender \(senderEmail) as unread"
        case .flag:
            text = "flag all mails from sender \(senderEmail)"
        case .unflag:
            text = "unflag all mails from sender \(senderEmail)"
        }
        if let sourceFolderName {
            text.append(" only in \(sourceFolderName)")
        }
        if let olderThanDays {
            text.append(" older than \(olderThanDays) \(olderThanDays == 1 ? "day" : "days")")
        }
        return text
    }
}

enum MailboxActionAgentStructuredIntentDecoder {
    private static let allowedFields: Set<String> = [
        "action",
        "senderEmail",
        "targetFolderName",
        "useFocusedFolder",
        "sourceFolderName",
        "olderThanDays"
    ]

    static func decode(_ data: Data) throws -> MailboxActionAgentStructuredIntent {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MailboxActionAgentStructuredIntentError.invalidJSON
        }

        guard let dictionary = object as? [String: Any] else {
            throw MailboxActionAgentStructuredIntentError.invalidJSON
        }

        let unsupportedFields = dictionary.keys
            .filter { !allowedFields.contains($0) }
            .sorted()
        guard unsupportedFields.isEmpty else {
            throw MailboxActionAgentStructuredIntentError.unsupportedFields(unsupportedFields)
        }

        let rawAction = try requiredString(
            for: "action",
            in: dictionary,
            missingError: .missingAction
        )
        let action: MailboxActionAgentStructuredIntentAction
        switch normalizedAction(rawAction) {
        case "delete":
            action = .delete
        case "move":
            action = .move
        case "archive":
            action = .archive
        case "markread":
            action = .markRead
        case "markunread":
            action = .markUnread
        case "flag":
            action = .flag
        case "unflag":
            action = .unflag
        case let unsupported:
            throw MailboxActionAgentStructuredIntentError.unsupportedAction(unsupported)
        }

        let senderEmail = try normalizedEmail(requiredString(
            for: "senderEmail",
            in: dictionary,
            missingError: .missingSender
        ))
        guard !senderEmail.isEmpty else {
            throw MailboxActionAgentStructuredIntentError.missingSender
        }

        let targetFolderName = try optionalString(for: "targetFolderName", in: dictionary)
        let useFocusedFolder = try optionalBool(for: "useFocusedFolder", in: dictionary) ?? false
        let sourceFolderName = try optionalString(for: "sourceFolderName", in: dictionary)
        let olderThanDays = try optionalPositiveInt(for: "olderThanDays", in: dictionary)

        if action == .move, targetFolderName == nil, !useFocusedFolder {
            throw MailboxActionAgentStructuredIntentError.missingMoveTarget
        }

        return MailboxActionAgentStructuredIntent(
            action: action,
            senderEmail: senderEmail,
            targetFolderName: targetFolderName,
            useFocusedFolder: useFocusedFolder,
            sourceFolderName: sourceFolderName,
            olderThanDays: olderThanDays
        )
    }

    private static func requiredString(
        for key: String,
        in dictionary: [String: Any],
        missingError: MailboxActionAgentStructuredIntentError
    ) throws -> String {
        guard let value = dictionary[key], !(value is NSNull) else {
            throw missingError
        }
        guard let string = value as? String else {
            throw MailboxActionAgentStructuredIntentError.invalidField(key)
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw missingError
        }
        return trimmed
    }

    private static func optionalString(
        for key: String,
        in dictionary: [String: Any]
    ) throws -> String? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            throw MailboxActionAgentStructuredIntentError.invalidField(key)
        }
        let trimmed = cleanedTarget(string)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalBool(
        for key: String,
        in dictionary: [String: Any]
    ) throws -> Bool? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        guard let bool = value as? Bool else {
            throw MailboxActionAgentStructuredIntentError.invalidField(key)
        }
        return bool
    }

    private static func optionalPositiveInt(
        for key: String,
        in dictionary: [String: Any]
    ) throws -> Int? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        guard !(value is Bool),
              let number = value as? NSNumber,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.intValue > 0
        else {
            throw MailboxActionAgentStructuredIntentError.invalidField(key)
        }
        return number.intValue
    }

    private static func normalizedAction(_ action: String) -> String {
        action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter(\.isLetter)
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func cleanedTarget(_ target: String) -> String {
        let trimmingCharacters = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: #""'.,!?:"#)
        )
        return target.trimmingCharacters(in: trimmingCharacters)
    }
}

enum MailboxActionAgentOperation: Equatable, Sendable {
    case delete
    case move(to: Folder)
    case archive(to: Folder)
    case markRead
    case markUnread
    case flag
    case unflag

    var isDestructive: Bool {
        switch self {
        case .delete:
            return true
        case .move, .archive, .markRead, .markUnread, .flag, .unflag:
            return false
        }
    }

    var confirmationVerb: String {
        switch self {
        case .delete:
            return "DELETE"
        case .move:
            return "MOVE"
        case .archive:
            return "ARCHIVE"
        case .markRead:
            return "MARK READ"
        case .markUnread:
            return "MARK UNREAD"
        case .flag:
            return "FLAG"
        case .unflag:
            return "UNFLAG"
        }
    }

    var promptVerb: String {
        switch self {
        case .delete:
            return "Delete"
        case .move:
            return "Move"
        case .archive:
            return "Archive"
        case .markRead:
            return "Mark Read"
        case .markUnread:
            return "Mark Unread"
        case .flag:
            return "Flag"
        case .unflag:
            return "Unflag"
        }
    }
}

struct MailboxActionAgentConfirmation: Equatable, Sendable {
    let planID: UUID
    let phrase: String
}

struct MailboxActionAgentConfirmationChallenge: Equatable, Sendable {
    let planID: UUID
    let prompt: String
    let requiredPhrase: String
}

enum MailboxActionAgentAuthorization: Equatable, Sendable {
    case authorized
    case requiresConfirmation(MailboxActionAgentConfirmationChallenge)
}

enum MailboxActionAgentExecutionResult: Equatable, Sendable {
    case enqueued(PendingMutation)
    case requiresConfirmation(MailboxActionAgentConfirmationChallenge)
    case noMatchingMessages
}

struct MailboxActionAgentMessageSample: Equatable, Identifiable, Sendable {
    let id: MessageHeader.ID
    let sender: String
    let subject: String
    let date: Date

    init(header: MessageHeader) {
        id = header.id
        sender = header.from.email
        subject = header.subject
        date = header.date
    }

    init(
        id: MessageHeader.ID,
        sender: String,
        subject: String,
        date: Date
    ) {
        self.id = id
        self.sender = sender
        self.subject = subject
        self.date = date
    }
}

struct MailboxActionAgentMatchedMessageState: Equatable, Identifiable, Sendable {
    let id: MessageHeader.ID
    let folderID: Folder.ID
    let isRead: Bool
    let isFlagged: Bool

    init(header: MessageHeader) {
        id = header.id
        folderID = header.folderID
        isRead = header.isRead
        isFlagged = header.isFlagged
    }
}

enum MailboxActionAgentUndoStep: Equatable, Sendable {
    case move(messageIDs: [MessageHeader.ID], to: Folder)
    case setRead(Bool, messageIDs: [MessageHeader.ID])
    case setFlagged(Bool, messageIDs: [MessageHeader.ID])
}

struct MailboxActionAgentUndoPlan: Equatable, Sendable {
    let description: String
    let steps: [MailboxActionAgentUndoStep]
}

enum MailboxActionAgentUndoPerformer {
    static func perform(
        _ undoPlan: MailboxActionAgentUndoPlan,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        for step in undoPlan.steps {
            switch step {
            case .move(let messageIDs, let folder):
                if let sourceID {
                    try await backend.move(
                        messageIDs: messageIDs,
                        to: folder,
                        sourceID: sourceID
                    )
                } else {
                    try await backend.move(messageIDs: messageIDs, to: folder)
                }
            case .setRead(let isRead, let messageIDs):
                if let sourceID {
                    try await backend.setRead(isRead, for: messageIDs, sourceID: sourceID)
                } else {
                    try await backend.setRead(isRead, for: messageIDs)
                }
            case .setFlagged(let isFlagged, let messageIDs):
                if let sourceID {
                    try await backend.setFlagged(isFlagged, for: messageIDs, sourceID: sourceID)
                } else {
                    try await backend.setFlagged(isFlagged, for: messageIDs)
                }
            }
        }
    }
}

enum MailboxActionAgentClarificationPresentation {
    static func message(for clarification: MailboxActionAgentClarification) -> String {
        switch clarification {
        case .unsupportedRequest:
            return "I can only prepare sender-scoped delete, move, read-state, and flag actions right now."
        case .missingSender:
            return "Tell me which sender to match."
        case .missingMoveTarget:
            return "Tell me which folder to move the messages to."
        case .unknownFolder(let name):
            return "I couldn't find a folder named \(name)."
        case .ambiguousFolder(let name):
            return "More than one folder matches \(name)."
        }
    }
}

struct MailboxActionAgentReviewSampleRow: Equatable, Sendable {
    let title: String
    let subtitle: String
}

struct MailboxActionAgentReviewDetailRow: Equatable, Sendable {
    let title: String
    let value: String
}

struct MailboxActionAgentRefinements: Equatable, Sendable {
    let folder: Folder?
    let olderThanDays: Int?
    let olderThanCutoffDate: Date?

    static let none = MailboxActionAgentRefinements(
        folder: nil,
        olderThanDays: nil,
        olderThanCutoffDate: nil
    )

    var dateRange: ClosedRange<Date>? {
        guard let olderThanCutoffDate else { return nil }
        return Date.distantPast ... olderThanCutoffDate
    }

    func matches(_ header: MessageHeader) -> Bool {
        if let folder, header.folderID != folder.id {
            return false
        }
        if let olderThanCutoffDate, header.date > olderThanCutoffDate {
            return false
        }
        return true
    }
}

struct MailboxActionAgentReviewPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let detailRows: [MailboxActionAgentReviewDetailRow]
    let sampleRows: [MailboxActionAgentReviewSampleRow]
    let warningMessage: String?
    let confirmButtonTitle: String?
    let cancelButtonTitle: String
    let requiredPhrase: String?
    let isDestructive: Bool

    var canConfirm: Bool {
        confirmButtonTitle != nil && requiredPhrase != nil
    }

    static func review(for plan: MailboxActionAgentPlan) -> Self {
        let count = plan.matchingMessageIDs.count
        guard count > 0 else {
            return noMatchReview(for: plan)
        }

        let countLabel = "\(count) \(count == 1 ? "message" : "messages")"
        let messagePrefix = count == 1
            ? "There is \(countLabel) from \(plan.senderEmail)."
            : "There are \(countLabel) from \(plan.senderEmail)."
        let objectPronoun = count == 1 ? "it" : "them"
        let message: String
        switch plan.operation {
        case .delete:
            message = "\(messagePrefix) Delete \(objectPronoun)?"
        case .move(let folder):
            message = "\(messagePrefix) Move \(objectPronoun) to \(folder.name)?"
        case .archive:
            message = "\(messagePrefix) Archive \(objectPronoun)?"
        case .markRead:
            message = "\(messagePrefix) Mark \(objectPronoun) as read?"
        case .markUnread:
            message = "\(messagePrefix) Mark \(objectPronoun) as unread?"
        case .flag:
            message = "\(messagePrefix) Flag \(objectPronoun)?"
        case .unflag:
            message = "\(messagePrefix) Unflag \(objectPronoun)?"
        }

        return MailboxActionAgentReviewPresentation(
            title: "Confirm \(plan.operation.promptVerb)",
            message: message,
            detailRows: detailRows(for: plan),
            sampleRows: sampleRows(for: plan.sampleMessages),
            warningMessage: warningMessage(for: plan.operation),
            confirmButtonTitle: "\(plan.operation.promptVerb) \(titleCaseCountLabel(count: count))",
            cancelButtonTitle: "Cancel",
            requiredPhrase: plan.confirmationChallenge.requiredPhrase,
            isDestructive: plan.isDestructive
        )
    }

    private static func noMatchReview(for plan: MailboxActionAgentPlan) -> Self {
        let actionDescription: String
        switch plan.operation {
        case .delete:
            actionDescription = "delete"
        case .move(let folder):
            actionDescription = "move to \(folder.name)"
        case .archive:
            actionDescription = "archive"
        case .markRead:
            actionDescription = "mark as read"
        case .markUnread:
            actionDescription = "mark as unread"
        case .flag:
            actionDescription = "flag"
        case .unflag:
            actionDescription = "unflag"
        }
        return MailboxActionAgentReviewPresentation(
            title: "No Matching Messages",
            message: "There are no messages from \(plan.senderEmail) to \(actionDescription).",
            detailRows: [],
            sampleRows: [],
            warningMessage: nil,
            confirmButtonTitle: nil,
            cancelButtonTitle: "Close",
            requiredPhrase: nil,
            isDestructive: false
        )
    }

    private static func detailRows(
        for plan: MailboxActionAgentPlan
    ) -> [MailboxActionAgentReviewDetailRow] {
        var rows = [
            MailboxActionAgentReviewDetailRow(
                title: "Criteria",
                value: criteriaDetail(for: plan)
            ),
            MailboxActionAgentReviewDetailRow(
                title: "Mailbox",
                value: plan.sourceScope.displayText
            )
        ]
        if !plan.matchedFolderNames.isEmpty {
            rows.append(MailboxActionAgentReviewDetailRow(
                title: "Matched folders",
                value: plan.matchedFolderNames.joined(separator: ", ")
            ))
        }
        rows.append(MailboxActionAgentReviewDetailRow(
            title: "Action",
            value: actionDetail(for: plan.operation)
        ))
        return rows
    }

    private static func criteriaDetail(
        for plan: MailboxActionAgentPlan
    ) -> String {
        var parts = ["From \(plan.senderEmail)"]
        if let folder = plan.refinements.folder {
            parts.append("Folder \(folder.name)")
        }
        if let olderThanDays = plan.refinements.olderThanDays {
            parts.append("Older than \(olderThanDays) \(olderThanDays == 1 ? "day" : "days")")
        }
        return parts.joined(separator: "; ")
    }

    private static func warningMessage(
        for operation: MailboxActionAgentOperation
    ) -> String? {
        switch operation {
        case .delete:
            return "This cannot be undone from Brev once it reaches the server."
        case .move, .archive, .markRead, .markUnread, .flag, .unflag:
            return nil
        }
    }

    private static func actionDetail(
        for operation: MailboxActionAgentOperation
    ) -> String {
        switch operation {
        case .delete:
            return "Delete matched messages"
        case .move(let folder):
            return "Move to \(folder.name)"
        case .archive:
            return "Archive matched messages"
        case .markRead:
            return "Mark as read"
        case .markUnread:
            return "Mark as unread"
        case .flag:
            return "Flag matched messages"
        case .unflag:
            return "Unflag matched messages"
        }
    }

    private static func sampleRows(
        for samples: [MailboxActionAgentMessageSample]
    ) -> [MailboxActionAgentReviewSampleRow] {
        samples.map { sample in
            MailboxActionAgentReviewSampleRow(
                title: sample.subject.isEmpty ? "(No subject)" : sample.subject,
                subtitle: sample.sender
            )
        }
    }

    private static func titleCaseCountLabel(count: Int) -> String {
        "\(count) \(count == 1 ? "Message" : "Messages")"
    }
}

enum MailboxActionAgentReviewInputPolicy {
    static func canConfirm(
        _ phrase: String,
        presentation: MailboxActionAgentReviewPresentation
    ) -> Bool {
        guard let requiredPhrase = presentation.requiredPhrase else { return false }
        return phrase.trimmingCharacters(in: .whitespacesAndNewlines) == requiredPhrase
    }
}

enum MailboxActionAgentCompletionPresentation {
    static func message(for plan: MailboxActionAgentPlan) -> String {
        let count = plan.matchingMessageIDs.count
        let countLabel = "\(count) \(count == 1 ? "message" : "messages")"
        switch plan.operation {
        case .delete:
            return "Deleted \(countLabel) from \(plan.senderEmail)."
        case .move(let folder):
            return "Moved \(countLabel) from \(plan.senderEmail) to \(folder.name)."
        case .archive:
            return "Archived \(countLabel) from \(plan.senderEmail)."
        case .markRead:
            return "Marked \(countLabel) from \(plan.senderEmail) as read."
        case .markUnread:
            return "Marked \(countLabel) from \(plan.senderEmail) as unread."
        case .flag:
            return "Flagged \(countLabel) from \(plan.senderEmail)."
        case .unflag:
            return "Unflagged \(countLabel) from \(plan.senderEmail)."
        }
    }
}

struct MailboxActionAgentPlan: Equatable, Identifiable, Sendable {
    let id: UUID
    let request: String
    let senderEmail: String
    let operation: MailboxActionAgentOperation
    let searchQuery: SearchQuery
    let matchingMessageIDs: [MessageHeader.ID]
    let matchedMessageStates: [MailboxActionAgentMatchedMessageState]
    let matchedFolderNames: [String]
    let sampleMessages: [MailboxActionAgentMessageSample]
    let sourceScope: MailboxActionAgentSourceScope
    let refinements: MailboxActionAgentRefinements
    let confirmationChallenge: MailboxActionAgentConfirmationChallenge

    var sourceID: MailSourceID? {
        sourceScope.sourceID
    }

    var isDestructive: Bool {
        operation.isDestructive
    }

    var requiresConfirmation: Bool {
        true
    }

    func authorization(
        with confirmation: MailboxActionAgentConfirmation?
    ) -> MailboxActionAgentAuthorization {
        guard let confirmation,
              confirmation.planID == id,
              confirmation.phrase == confirmationChallenge.requiredPhrase
        else {
            return .requiresConfirmation(confirmationChallenge)
        }
        return .authorized
    }

    func undoPlan(
        folders: [Folder],
        folderDisplayName: (Folder) -> String = { $0.name }
    ) -> MailboxActionAgentUndoPlan? {
        guard !matchedMessageStates.isEmpty else { return nil }

        let description: String
        let steps: [MailboxActionAgentUndoStep]
        switch operation {
        case .delete:
            return nil
        case .move(let folder):
            description = "Moved \(countLabel) to \(folderDisplayName(folder))"
            steps = moveBackSteps(folders: folders)
        case .archive:
            description = "Archived \(countLabel)"
            steps = moveBackSteps(folders: folders)
        case .markRead:
            description = "Marked \(countLabel) as Read"
            steps = readStateSteps()
        case .markUnread:
            description = "Marked \(countLabel) as Unread"
            steps = readStateSteps()
        case .flag:
            description = "Flagged \(countLabel)"
            steps = flagStateSteps()
        case .unflag:
            description = "Unflagged \(countLabel)"
            steps = flagStateSteps()
        }

        guard !steps.isEmpty else { return nil }
        return MailboxActionAgentUndoPlan(description: description, steps: steps)
    }

    private var countLabel: String {
        let count = matchedMessageStates.count
        return "\(count) \(count == 1 ? "message" : "messages")"
    }

    private func moveBackSteps(folders: [Folder]) -> [MailboxActionAgentUndoStep] {
        var foldersByID: [Folder.ID: Folder] = [:]
        for folder in folders where foldersByID[folder.id] == nil {
            foldersByID[folder.id] = folder
        }

        var groups: [(folder: Folder, messageIDs: [MessageHeader.ID])] = []
        for state in matchedMessageStates {
            guard let folder = foldersByID[state.folderID] else { continue }
            if let index = groups.firstIndex(where: { $0.folder.id == folder.id }) {
                groups[index].messageIDs.append(state.id)
            } else {
                groups.append((folder, [state.id]))
            }
        }
        return groups.map { .move(messageIDs: $0.messageIDs, to: $0.folder) }
    }

    private func readStateSteps() -> [MailboxActionAgentUndoStep] {
        groupedBooleanSteps(matchedMessageStates.map { ($0.isRead, $0.id) }) {
            .setRead($0, messageIDs: $1)
        }
    }

    private func flagStateSteps() -> [MailboxActionAgentUndoStep] {
        groupedBooleanSteps(matchedMessageStates.map { ($0.isFlagged, $0.id) }) {
            .setFlagged($0, messageIDs: $1)
        }
    }

    private func groupedBooleanSteps(
        _ values: [(Bool, MessageHeader.ID)],
        makeStep: (Bool, [MessageHeader.ID]) -> MailboxActionAgentUndoStep
    ) -> [MailboxActionAgentUndoStep] {
        var groups: [(value: Bool, messageIDs: [MessageHeader.ID])] = []
        for (value, id) in values {
            if let index = groups.firstIndex(where: { $0.value == value }) {
                groups[index].messageIDs.append(id)
            } else {
                groups.append((value, [id]))
            }
        }
        return groups.map { makeStep($0.value, $0.messageIDs) }
    }
}

struct MailboxActionAgentExecutor: Sendable {
    private let mutationIDGenerator: @Sendable () -> UUID
    private let dateProvider: @Sendable () -> Date

    init(
        mutationIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mutationIDGenerator = mutationIDGenerator
        self.dateProvider = dateProvider
    }

    func execute(
        plan: MailboxActionAgentPlan,
        confirmation: MailboxActionAgentConfirmation?,
        sourceID: MailSourceID?,
        queue: any OfflineMutationQueue
    ) async throws -> MailboxActionAgentExecutionResult {
        switch plan.authorization(with: confirmation) {
        case .authorized:
            break
        case .requiresConfirmation(let challenge):
            return .requiresConfirmation(challenge)
        }

        guard !plan.matchingMessageIDs.isEmpty else {
            return .noMatchingMessages
        }

        let mutation = PendingMutation(
            id: mutationIDGenerator(),
            kind: mutationKind(for: plan.operation),
            sourceID: sourceID,
            messageIDs: plan.matchingMessageIDs,
            createdAt: dateProvider()
        )
        try await queue.enqueue(mutation)
        return .enqueued(mutation)
    }

    private func mutationKind(
        for operation: MailboxActionAgentOperation
    ) -> PendingMutation.Kind {
        switch operation {
        case .delete:
            return .delete
        case .move(let folder):
            return .move(folderID: folder.id)
        case .archive(let folder):
            return .move(folderID: folder.id)
        case .markRead:
            return .setRead(true)
        case .markUnread:
            return .setRead(false)
        case .flag:
            return .setFlagged(true)
        case .unflag:
            return .setFlagged(false)
        }
    }
}

struct MailboxActionAgentRequestResolver: Sendable {
    typealias Search = @Sendable (SearchQuery, MailSourceID?) async throws -> [MessageHeader]

    private let planner: MailboxActionAgentPlanner

    init(
        idGenerator: @escaping @Sendable () -> UUID = { UUID() },
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        planner = MailboxActionAgentPlanner(
            idGenerator: idGenerator,
            dateProvider: dateProvider
        )
    }

    func resolve(
        request: String,
        folders: [Folder],
        focusedFolder: Folder?,
        sourceID: MailSourceID?,
        sourceScope: MailboxActionAgentSourceScope = .currentMailbox,
        search: Search
    ) async throws -> MailboxActionAgentPlanningResult {
        let preliminary = planner.plan(
            request: request,
            headers: [],
            folders: folders,
            focusedFolder: focusedFolder,
            sourceScope: sourceScope
        )
        guard case .planned(let preliminaryPlan) = preliminary else {
            return preliminary
        }

        let headers = try await search(preliminaryPlan.searchQuery, sourceID)
        return planner.plan(
            request: request,
            headers: headers,
            folders: folders,
            focusedFolder: focusedFolder,
            sourceScope: sourceScope
        )
    }
}

struct MailboxActionAgentPlanner: Sendable {
    private let idGenerator: @Sendable () -> UUID
    private let dateProvider: @Sendable () -> Date

    init(
        idGenerator: @escaping @Sendable () -> UUID = { UUID() },
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
    }

    func plan(
        request: String,
        headers: [MessageHeader],
        folders: [Folder],
        focusedFolder: Folder?,
        sourceScope: MailboxActionAgentSourceScope = .currentMailbox
    ) -> MailboxActionAgentPlanningResult {
        guard let action = Self.action(in: request) else {
            return .clarificationRequired(.unsupportedRequest)
        }
        guard let senderEmail = Self.firstEmail(in: request) else {
            return .clarificationRequired(.missingSender)
        }
        let refinements: MailboxActionAgentRefinements
        switch Self.refinements(
            in: request,
            folders: folders,
            focusedFolder: focusedFolder,
            now: dateProvider()
        ) {
        case .resolved(let resolvedRefinements):
            refinements = resolvedRefinements
        case .needsClarification(let clarification):
            return .clarificationRequired(clarification)
        }

        let operation: MailboxActionAgentOperation
        switch action {
        case .delete:
            operation = .delete
        case .move:
            switch Self.moveTarget(
                in: request,
                folders: folders,
                focusedFolder: focusedFolder
            ) {
            case .resolved(let folder):
                operation = .move(to: folder)
            case .needsClarification(let clarification):
                return .clarificationRequired(clarification)
            }
        case .archive:
            switch Self.archiveTarget(in: folders) {
            case .resolved(let folder):
                operation = .archive(to: folder)
            case .needsClarification(let clarification):
                return .clarificationRequired(clarification)
            }
        case .markRead:
            operation = .markRead
        case .markUnread:
            operation = .markUnread
        case .flag:
            operation = .flag
        case .unflag:
            operation = .unflag
        }

        let matchingHeaders = headers.filter {
            Self.normalizedEmail($0.from.email) == senderEmail
                && refinements.matches($0)
        }
        let messageIDs = matchingHeaders.map(\.id)
        let matchedMessageStates = matchingHeaders.map(MailboxActionAgentMatchedMessageState.init(header:))
        let matchedFolderNames = Self.matchedFolderNames(
            for: matchingHeaders,
            folders: folders
        )
        let sampleMessages = matchingHeaders
            .prefix(Self.maxSampleMessageCount)
            .map(MailboxActionAgentMessageSample.init(header:))
        let id = idGenerator()
        let challenge = Self.confirmationChallenge(
            id: id,
            senderEmail: senderEmail,
            operation: operation,
            count: messageIDs.count
        )

        return .planned(
            MailboxActionAgentPlan(
                id: id,
                request: request,
                senderEmail: senderEmail,
                operation: operation,
                searchQuery: SearchQuery(
                    folderID: refinements.folder?.id,
                    from: senderEmail,
                    dateRange: refinements.dateRange,
                    execution: .cacheOnly
                ),
                matchingMessageIDs: messageIDs,
                matchedMessageStates: matchedMessageStates,
                matchedFolderNames: matchedFolderNames,
                sampleMessages: sampleMessages,
                sourceScope: sourceScope,
                refinements: refinements,
                confirmationChallenge: challenge
            )
        )
    }

    func plan(
        intent: MailboxActionAgentStructuredIntent,
        headers: [MessageHeader],
        folders: [Folder],
        focusedFolder: Folder?,
        sourceScope: MailboxActionAgentSourceScope = .currentMailbox
    ) -> MailboxActionAgentPlanningResult {
        plan(
            request: intent.requestText,
            headers: headers,
            folders: folders,
            focusedFolder: focusedFolder,
            sourceScope: sourceScope
        )
    }

    private enum ParsedAction {
        case delete
        case move
        case archive
        case markRead
        case markUnread
        case flag
        case unflag
    }

    private enum MoveTargetResolution {
        case resolved(Folder)
        case needsClarification(MailboxActionAgentClarification)
    }

    private enum ArchiveTargetResolution {
        case resolved(Folder)
        case needsClarification(MailboxActionAgentClarification)
    }

    private enum FolderRefinementResolution {
        case resolved(Folder?)
        case needsClarification(MailboxActionAgentClarification)
    }

    private enum RefinementResolution {
        case resolved(MailboxActionAgentRefinements)
        case needsClarification(MailboxActionAgentClarification)
    }

    // Plain mailbox-action commands only need the first literal address.
    private static let emailExpression: NSRegularExpression =
        try! NSRegularExpression(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        )
    private static let olderThanExpression: NSRegularExpression =
        try! NSRegularExpression(
            pattern: #"older\s+than\s+(\d+)\s+days?"#,
            options: [.caseInsensitive]
        )
    private static let maxSampleMessageCount = 3

    private static func action(in request: String) -> ParsedAction? {
        let lowercased = request.lowercased()
        if lowercased.contains("delete")
            || lowercased.contains("remove")
            || lowercased.contains("trash") {
            return .delete
        }
        if lowercased.contains("move") {
            return .move
        }
        if lowercased.contains("archive") {
            return .archive
        }
        if lowercased.contains("mark"), lowercased.contains("unread") {
            return .markUnread
        }
        if lowercased.contains("mark"), lowercased.contains("read") {
            return .markRead
        }
        if lowercased.contains("unflag") {
            return .unflag
        }
        if lowercased.contains("flag") {
            return .flag
        }
        return nil
    }

    private static func firstEmail(in request: String) -> String? {
        let range = NSRange(request.startIndex ..< request.endIndex, in: request)
        guard let match = emailExpression.firstMatch(in: request, range: range),
              let matchRange = Range(match.range, in: request)
        else {
            return nil
        }
        return normalizedEmail(String(request[matchRange]))
    }

    private static func moveTarget(
        in request: String,
        folders: [Folder],
        focusedFolder: Folder?
    ) -> MoveTargetResolution {
        guard let targetName = rawMoveTarget(in: request) else {
            return .needsClarification(.missingMoveTarget)
        }

        let cleanedName = cleanedFolderReference(targetName)
        let normalizedTarget = normalizedFolderName(cleanedName)
        if isFocusedFolderReference(normalizedTarget) {
            guard let focusedFolder else {
                return .needsClarification(.missingMoveTarget)
            }
            return .resolved(focusedFolder)
        }

        let matches = folders.filter {
            normalizedFolderName($0.name) == normalizedTarget
                || normalizedFolderName($0.id) == normalizedTarget
        }
        if matches.count == 1, let folder = matches.first {
            return .resolved(folder)
        }
        if matches.isEmpty {
            return .needsClarification(.unknownFolder(cleanedName))
        }
        return .needsClarification(.ambiguousFolder(cleanedName))
    }

    private static func archiveTarget(
        in folders: [Folder]
    ) -> ArchiveTargetResolution {
        guard let archive = folders.first(where: { $0.role == .archive }) else {
            return .needsClarification(.unknownFolder("Archive"))
        }
        return .resolved(archive)
    }

    private static func refinements(
        in request: String,
        folders: [Folder],
        focusedFolder: Folder?,
        now: Date
    ) -> RefinementResolution {
        let olderThanDays = olderThanDays(in: request)
        let cutoffDate = olderThanDays.map {
            now.addingTimeInterval(TimeInterval(-$0 * 24 * 60 * 60))
        }

        switch folderRefinement(
            in: request,
            folders: folders,
            focusedFolder: focusedFolder
        ) {
        case .resolved(let folder):
            return .resolved(MailboxActionAgentRefinements(
                folder: folder,
                olderThanDays: olderThanDays,
                olderThanCutoffDate: cutoffDate
            ))
        case .needsClarification(let clarification):
            return .needsClarification(clarification)
        }
    }

    private static func olderThanDays(in request: String) -> Int? {
        let range = NSRange(request.startIndex ..< request.endIndex, in: request)
        guard let match = olderThanExpression.firstMatch(in: request, range: range),
              match.numberOfRanges > 1,
              let daysRange = Range(match.range(at: 1), in: request)
        else {
            return nil
        }
        return Int(request[daysRange])
    }

    private static func folderRefinement(
        in request: String,
        folders: [Folder],
        focusedFolder: Folder?
    ) -> FolderRefinementResolution {
        guard let targetName = rawFolderRefinement(in: request) else {
            return .resolved(nil)
        }
        let cleanedName = cleanedFolderReference(targetName)
        let normalizedTarget = normalizedFolderName(cleanedName)
        if isFocusedFolderReference(normalizedTarget) {
            guard let focusedFolder else {
                return .needsClarification(.unknownFolder(targetName))
            }
            return .resolved(focusedFolder)
        }
        let matches = folders.filter {
            normalizedFolderName($0.name) == normalizedTarget
                || normalizedFolderName($0.id) == normalizedTarget
        }
        if matches.count == 1, let folder = matches.first {
            return .resolved(folder)
        }
        if matches.isEmpty {
            return .needsClarification(.unknownFolder(cleanedName))
        }
        return .needsClarification(.ambiguousFolder(cleanedName))
    }

    private static func rawFolderRefinement(in request: String) -> String? {
        guard let range = request.range(
            of: " only in ",
            options: [.caseInsensitive, .backwards]
        ) else {
            return nil
        }
        let rawTarget = String(request[range.upperBound...])
        let withoutOlderThan = rawTarget.range(
            of: " older than ",
            options: [.caseInsensitive]
        ).map { String(rawTarget[..<$0.lowerBound]) } ?? rawTarget
        let withoutMoveTarget = withoutOlderThan.range(
            of: " to ",
            options: [.caseInsensitive]
        ).map { String(withoutOlderThan[..<$0.lowerBound]) } ?? withoutOlderThan
        let cleaned = cleanedTarget(withoutMoveTarget)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func rawMoveTarget(in request: String) -> String? {
        let separators = [" to ", " into "]
        for separator in separators {
            if let range = request.range(
                of: separator,
                options: [.caseInsensitive, .backwards]
            ) {
                let target = request[range.upperBound...]
                let cleaned = cleanedTarget(String(target))
                return cleaned.isEmpty ? nil : cleaned
            }
        }
        return nil
    }

    private static func cleanedTarget(_ target: String) -> String {
        let trimmingCharacters = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: #""'.,!?:"#)
        )
        let trimmed = target.trimmingCharacters(in: trimmingCharacters)
        if let range = trimmed.range(of: " only in ", options: [.caseInsensitive]) {
            return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: trimmingCharacters)
        }
        if let range = trimmed.range(of: " older than ", options: [.caseInsensitive]) {
            return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: trimmingCharacters)
        }
        return trimmed
    }

    private static func cleanedFolderReference(_ target: String) -> String {
        let cleaned = cleanedTarget(target)
        for prefix in ["folder named ", "folder ", "mailbox named ", "mailbox "] {
            if cleaned.range(of: prefix, options: [.caseInsensitive])?.lowerBound == cleaned.startIndex {
                let value = String(cleaned.dropFirst(prefix.count))
                return cleanedTarget(value)
            }
        }
        return cleaned
    }

    private static func isFocusedFolderReference(_ normalizedTarget: String) -> Bool {
        normalizedTarget == "this folder"
            || normalizedTarget == "this folder here"
            || normalizedTarget == "current folder"
            || normalizedTarget == "here"
    }

    private static func matchedFolderNames(
        for headers: [MessageHeader],
        folders: [Folder]
    ) -> [String] {
        let folderNamesByID = folders.reduce(into: [Folder.ID: String]()) { result, folder in
            result[folder.id] = folder.name
        }
        var seenNames = Set<String>()
        var names: [String] = []
        for header in headers {
            let name = cleanedTarget(folderNamesByID[header.folderID] ?? header.folderID)
            guard !name.isEmpty else { continue }
            let normalizedName = normalizedFolderName(name)
            guard !seenNames.contains(normalizedName) else { continue }
            seenNames.insert(normalizedName)
            names.append(name)
        }
        return names
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedFolderName(_ name: String) -> String {
        cleanedTarget(name).lowercased()
    }

    private static func confirmationChallenge(
        id: UUID,
        senderEmail: String,
        operation: MailboxActionAgentOperation,
        count: Int
    ) -> MailboxActionAgentConfirmationChallenge {
        let countLabel = "\(count) \(count == 1 ? "message" : "messages")"
        let prompt: String
        switch operation {
        case .delete:
            prompt = "\(operation.promptVerb) \(countLabel) from \(senderEmail)?"
        case .move(let folder):
            prompt = "\(operation.promptVerb) \(countLabel) from \(senderEmail) to \(folder.name)?"
        case .archive:
            prompt = "Archive \(countLabel) from \(senderEmail)?"
        case .markRead:
            prompt = "Mark \(countLabel) from \(senderEmail) as read?"
        case .markUnread:
            prompt = "Mark \(countLabel) from \(senderEmail) as unread?"
        case .flag:
            prompt = "Flag \(countLabel) from \(senderEmail)?"
        case .unflag:
            prompt = "Unflag \(countLabel) from \(senderEmail)?"
        }

        return MailboxActionAgentConfirmationChallenge(
            planID: id,
            prompt: prompt,
            requiredPhrase: "\(operation.confirmationVerb) \(count)"
        )
    }
}
