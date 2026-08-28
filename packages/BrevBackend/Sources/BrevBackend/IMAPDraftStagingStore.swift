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

public struct IMAPDraftStagedAttachment: Sendable, Hashable, Codable {
    public let id: String
    public let draftID: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    /// Inline (body-referenced) part: emitted with Content-Disposition: inline and a Content-ID.
    public let isInline: Bool
    /// RFC 2392 Content-ID (no angle brackets), required when `isInline` is true.
    public let contentID: String?

    public init(
        id: String,
        draftID: String,
        filename: String,
        mimeType: String,
        data: Data,
        isInline: Bool = false,
        contentID: String? = nil
    ) {
        self.id = id
        self.draftID = draftID
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.isInline = isInline
        self.contentID = contentID
    }

    // Custom decoder so records persisted before `isInline`/`contentID` were
    // added still decode without failing on `keyNotFound`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        draftID = try c.decode(String.self, forKey: .draftID)
        filename = try c.decode(String.self, forKey: .filename)
        mimeType = try c.decode(String.self, forKey: .mimeType)
        data = try c.decode(Data.self, forKey: .data)
        isInline = try c.decodeIfPresent(Bool.self, forKey: .isInline) ?? false
        contentID = try c.decodeIfPresent(String.self, forKey: .contentID)
    }
}

public protocol IMAPDraftStagingStore: Sendable {
    func draft(accountID: BrevAccount.ID, draftID: Draft.ID) async -> Draft?
    func setDraft(_ draft: Draft, accountID: BrevAccount.ID) async
    func attachment(accountID: BrevAccount.ID, attachmentID: String) async -> IMAPDraftStagedAttachment?
    func setAttachment(_ attachment: IMAPDraftStagedAttachment, accountID: BrevAccount.ID) async
    func removeDraft(accountID: BrevAccount.ID, draftID: Draft.ID) async
    func clear(accountID: BrevAccount.ID) async
}

public actor InMemoryIMAPDraftStagingStore: IMAPDraftStagingStore {
    private var draftsByIDByAccount: [BrevAccount.ID: [Draft.ID: Draft]]
    private var attachmentsByIDByAccount: [BrevAccount.ID: [String: IMAPDraftStagedAttachment]]

    public init(
        draftsByIDByAccount: [BrevAccount.ID: [Draft.ID: Draft]] = [:],
        attachmentsByIDByAccount: [BrevAccount.ID: [String: IMAPDraftStagedAttachment]] = [:]
    ) {
        self.draftsByIDByAccount = draftsByIDByAccount
        self.attachmentsByIDByAccount = attachmentsByIDByAccount
    }

    public func draft(accountID: BrevAccount.ID, draftID: Draft.ID) -> Draft? {
        draftsByIDByAccount[accountID]?[draftID]
    }

    public func setDraft(_ draft: Draft, accountID: BrevAccount.ID) {
        var drafts = draftsByIDByAccount[accountID] ?? [:]
        drafts[draft.id] = draft
        if let remoteID = draft.remoteID {
            drafts[remoteID] = draft
        }
        draftsByIDByAccount[accountID] = drafts
    }

    public func attachment(
        accountID: BrevAccount.ID,
        attachmentID: String
    ) -> IMAPDraftStagedAttachment? {
        attachmentsByIDByAccount[accountID]?[attachmentID]
    }

    public func setAttachment(
        _ attachment: IMAPDraftStagedAttachment,
        accountID: BrevAccount.ID
    ) {
        var attachments = attachmentsByIDByAccount[accountID] ?? [:]
        attachments[attachment.id] = attachment
        attachmentsByIDByAccount[accountID] = attachments
    }

    public func removeDraft(accountID: BrevAccount.ID, draftID: Draft.ID) {
        let storedDraft = draftsByIDByAccount[accountID]?[draftID]
        let idsToRemove = Set([draftID, storedDraft?.id, storedDraft?.remoteID].compactMap { $0 })
        for id in idsToRemove {
            draftsByIDByAccount[accountID]?.removeValue(forKey: id)
        }
        attachmentsByIDByAccount[accountID] = attachmentsByIDByAccount[accountID]?.filter { _, attachment in
            !idsToRemove.contains(attachment.draftID)
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        draftsByIDByAccount.removeValue(forKey: accountID)
        attachmentsByIDByAccount.removeValue(forKey: accountID)
    }
}

public actor FileIMAPDraftStagingStore: IMAPDraftStagingStore {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func draft(accountID: BrevAccount.ID, draftID: Draft.ID) -> Draft? {
        let url = draftURL(accountID: accountID, draftID: draftID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    public func setDraft(_ draft: Draft, accountID: BrevAccount.ID) {
        let urls = draftStorageURLs(accountID: accountID, draft: draft)
        do {
            try FileManager.default.createDirectory(
                at: draftsDirectory(accountID: accountID),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(draft)
            for url in urls {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            return
        }
    }

    public func attachment(
        accountID: BrevAccount.ID,
        attachmentID: String
    ) -> IMAPDraftStagedAttachment? {
        let url = attachmentURL(accountID: accountID, attachmentID: attachmentID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IMAPDraftStagedAttachment.self, from: data)
    }

    public func setAttachment(
        _ attachment: IMAPDraftStagedAttachment,
        accountID: BrevAccount.ID
    ) {
        let url = attachmentURL(accountID: accountID, attachmentID: attachment.id)
        do {
            try FileManager.default.createDirectory(
                at: attachmentsDirectory(accountID: accountID),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(attachment)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public func removeDraft(accountID: BrevAccount.ID, draftID: Draft.ID) {
        let storedDraft = draft(accountID: accountID, draftID: draftID)
        let idsToRemove = Set([draftID, storedDraft?.id, storedDraft?.remoteID].compactMap { $0 })
        for id in idsToRemove {
            try? FileManager.default.removeItem(at: draftURL(accountID: accountID, draftID: id))
        }
        removeAttachments(accountID: accountID, draftIDs: idsToRemove)
    }

    public func clear(accountID: BrevAccount.ID) {
        try? FileManager.default.removeItem(at: accountDirectory(accountID: accountID))
    }

    private func removeAttachments(accountID: BrevAccount.ID, draftIDs: Set<Draft.ID>) {
        let directory = attachmentsDirectory(accountID: accountID)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  let attachment = try? JSONDecoder().decode(IMAPDraftStagedAttachment.self, from: data),
                  draftIDs.contains(attachment.draftID)
            else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func draftStorageURLs(accountID: BrevAccount.ID, draft: Draft) -> [URL] {
        var ids = [draft.id]
        if let remoteID = draft.remoteID {
            ids.append(remoteID)
        }
        return Set(ids).map { draftURL(accountID: accountID, draftID: $0) }
    }

    private func draftURL(accountID: BrevAccount.ID, draftID: Draft.ID) -> URL {
        draftsDirectory(accountID: accountID)
            .appendingPathComponent("\(Self.fileKey(draftID)).json", isDirectory: false)
    }

    private func attachmentURL(
        accountID: BrevAccount.ID,
        attachmentID: String
    ) -> URL {
        attachmentsDirectory(accountID: accountID)
            .appendingPathComponent("\(Self.fileKey(attachmentID)).json", isDirectory: false)
    }

    private func draftsDirectory(accountID: BrevAccount.ID) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("drafts", isDirectory: true)
    }

    private func attachmentsDirectory(accountID: BrevAccount.ID) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    private func accountDirectory(accountID: BrevAccount.ID) -> URL {
        rootDirectory.appendingPathComponent(Self.fileKey(accountID), isDirectory: true)
    }

    private static func fileKey(_ value: String) -> String {
        guard !value.isEmpty else { return "_" }
        return value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
