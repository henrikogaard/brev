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

/// Reconstructs the backend and message header for a detached window from
/// the id-only payload a fresh `WindowGroup(for:)` scene receives.
///
/// `DetachedReaderWindowView` and `DetachedComposeWindowView` (ADR-0033) both
/// open with no in-memory parent state, so they resolve their content the same
/// way: pick the backend by the payload's account id, then probe the backend's
/// per-folder header cache. That shared logic lives here so the two views can't
/// drift apart.
enum DetachedWindowResolver {
    /// Selects the backend for a detached window.
    ///
    /// Matches the backend whose account equals `sourceID.accountID` when a
    /// source is present; otherwise (no source, or no matching account) falls
    /// back to the first available backend. Returns `nil` only when `backends`
    /// is empty.
    static func resolveBackend(
        sourceID: MailSourceID?,
        in backends: [any MailBackend]
    ) -> (any MailBackend)? {
        if let accountID = sourceID?.accountID,
           let matched = backends.first(where: { $0.account.id == accountID }) {
            return matched
        }
        return backends.first
    }

    /// Resolves the cached header for `messageID` from a backend's per-folder
    /// in-memory cache via `CachedMessageHeaderProviding`.
    ///
    /// Convenience over ``resolveHeader(messageID:using:folders:)`` that pulls
    /// the provider off the backend. Returns `nil` when the backend vends no
    /// such provider or the header is not cached in any of `folders`.
    static func resolveHeader(
        messageID: MessageHeader.ID,
        in backend: any MailBackend,
        folders: [Folder]
    ) async -> MessageHeader? {
        await resolveHeader(
            messageID: messageID,
            using: backend.extensionService(CachedMessageHeaderProviding.self),
            folders: folders
        )
    }

    /// Scans `folders` in order and returns the first cached header `provider`
    /// reports for `messageID`, or `nil` if none (including when `provider` is
    /// `nil`). The provider's `cachedMessageHeader` requires a folder id, so the
    /// caller's folder list is the search space.
    static func resolveHeader(
        messageID: MessageHeader.ID,
        using provider: (any CachedMessageHeaderProviding)?,
        folders: [Folder]
    ) async -> MessageHeader? {
        guard let provider else { return nil }
        for folder in folders {
            if let header = await provider.cachedMessageHeader(
                messageID: messageID,
                folderID: folder.id
            ) {
                return header
            }
        }
        return nil
    }

    /// Builds the multi-identity sender sections for a detached compose window
    /// from a backend's mailboxes.
    ///
    /// Folders are intentionally omitted — only the mailbox identity is needed
    /// to drive the "From:" picker, so the window does not pay for a folder
    /// load per mailbox. Mirrors the per-mailbox section construction in
    /// `BrevMailRootView.loadSourceSections()`, scoped to a single backend.
    /// Returns an empty array when the backend cannot list its mailboxes.
    static func resolveSenderSections(in backend: any MailBackend) async -> [MailSourceSection] {
        let mailboxes = await (try? backend.mailboxes()) ?? []
        return mailboxes.map { mailbox in
            MailSourceSection(
                id: backend.sourceID(for: mailbox),
                account: backend.account,
                mailbox: mailbox,
                folders: []
            )
        }
    }
}
