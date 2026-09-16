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

extension IMAPSMTPBackend {
    /// Bound on identifiers per UID SEARCH and total remote requests per lookup
    /// (ADR-0074 §8): every query is one finite batch, never a folder scan.
    private static let relatedSearchIdentifierChunkSize = 30
    private static let relatedSearchResultLimit = 50
    private static let relatedSearchRequestBudget = 64

    /// Folder IDs whose role is Spam or Trash within a known folder list.
    static func spamAndTrashFolderIDs(in folders: [Folder]) -> Set<Folder.ID> {
        Set(folders.filter { $0.role == .spam || $0.role == .trash }.map(\.id))
    }

    /// Consented remote discovery: expands the reply-identifier frontier across
    /// eligible folders with bounded UID SEARCH HEADER queries (ADR-0074 §4/§7).
    /// Each candidate hit is verified locally before it becomes a member;
    /// bodies and attachments stay lazy.
    public func loadRelatedConversation(
        around anchor: ConversationMember,
        includeSpamAndTrash: Bool,
        continuation: String?,
        onUpdate: @escaping @Sendable (ConversationSnapshot) async -> Void
    ) async throws -> ConversationSnapshot {
        guard anchor.sourceID.accountID == account.id,
              anchor.sourceID.mailboxID == account.id else {
            throw ConversationLookupError.foreignSource
        }
        guard let searchRelatedHeaders = searchRelatedHeadersOperation,
              let relatedConversationConsent else {
            throw MailBackendError.notSupported(capabilities)
        }
        // Consent is enforced at invocation, not merely surfaced by the caller.
        guard await relatedConversationConsent.isRelatedConversationConsented(accountID: account.id) else {
            throw ConversationLookupError.consentRequired
        }
        try await connect()
        guard await state.isRemoteAvailable() else {
            // Cache-restored or offline mailboxes must not issue remote searches.
            throw MailBackendError.notConnected
        }
        let folders = try await state.requireConnectedFolders()
        let excludedFolderIDs = includeSpamAndTrash
            ? []
            : Self.spamAndTrashFolderIDs(in: folders)
        let eligible = folders.filter { !excludedFolderIDs.contains($0.id) }

        var membersByLocation: [ConversationLocation: ConversationMember] = [anchor.location: anchor]
        var ambiguousIdentifiers: [String] = []
        if let cached = try? await cachedConversation(around: anchor, includeSpamAndTrash: includeSpamAndTrash) {
            for member in cached.members {
                membersByLocation[member.location] = member
            }
            ambiguousIdentifiers = cached.ambiguousIdentifiers
        }

        // Per-folder pending/searched identifier sets implement §4's frontier
        // expansion: every identifier is searched in every eligible folder once.
        var frontier = RelatedSearchFrontier()

        func linkIdentifiers(of member: ConversationMember) -> Set<String> {
            Set(ConversationMembershipResolver.cachedLinkIdentifiers(
                for: member.header, references: member.references
            ) ?? [])
        }
        func snapshot(coverage: ConversationCoverage) throws -> ConversationSnapshot {
            try ConversationSnapshot(
                anchor: anchor.location,
                members: Array(membersByLocation.values),
                coverage: coverage,
                excludedFolderIDs: Array(excludedFolderIDs),
                unavailableFolderIDs: frontier.unavailableFolders,
                ambiguousIdentifiers: ambiguousIdentifiers
            )
        }

        frontier.enqueue(membersByLocation.values.reduce(into: Set<String>()) {
            $0.formUnion(linkIdentifiers(of: $1))
        }, into: eligible)
        try await onUpdate(snapshot(coverage: .loading))

        while frontier.queriedCount < Self.relatedSearchRequestBudget, !Task.isCancelled {
            // A disconnect mid-scan stops remote work; the result stays honest.
            guard await state.isRemoteAvailable() else {
                frontier.markPendingFoldersUnavailable(in: eligible)
                break
            }
            var progressed = false
            for folder in eligible {
                guard frontier.queriedCount < Self.relatedSearchRequestBudget else { break }
                guard let pending = frontier.pendingByFolder[folder.id], !pending.isEmpty else { continue }
                let chunk = Array(pending.sorted().prefix(Self.relatedSearchIdentifierChunkSize))
                do {
                    // Follow the result window's page cursor within the request
                    // budget so a hit-heavy search is not silently capped (§8).
                    var pageToken: String?
                    repeat {
                        guard frontier.queriedCount < Self.relatedSearchRequestBudget,
                              !Task.isCancelled else { break }
                        let page = try await searchRelatedHeaders(
                            configuration, credential, folder.id, chunk,
                            Self.relatedSearchResultLimit, pageToken
                        )
                        frontier.queriedCount += 1
                        progressed = true
                        pageToken = page.nextPageToken
                        let generation = page.uidValidity.map { UInt64($0) }
                        var batchHeaders: [MessageHeader] = []
                        var discovered: Set<String> = []
                        for listing in page.messages {
                            let header = Self.header(from: listing, folderID: folder.id)
                            let links = Set(ConversationMembershipResolver.cachedLinkIdentifiers(for: header) ?? [])
                            // Candidate-search verification: keep only hits citing a
                            // queried identifier (ADR-0074 §4).
                            guard !links.isDisjoint(with: chunk) else { continue }
                            let member = ConversationMember(
                                sourceID: anchor.sourceID,
                                header: header,
                                folderGeneration: generation,
                                references: header.references
                            )
                            if membersByLocation[member.location] == nil {
                                membersByLocation[member.location] = member
                                discovered.formUnion(links)
                            }
                            batchHeaders.append(header)
                        }
                        // Persist only while this lookup still owns the session —
                        // a disconnect mid-scan must not keep refilling caches for
                        // a retired or replacement account (§10).
                        if !batchHeaders.isEmpty,
                           !Task.isCancelled,
                           await state.isRemoteAvailable() {
                            await localSearchIndex?.storeHeaders(batchHeaders, account: account)
                        }
                        frontier.enqueue(discovered, into: eligible)
                        try await onUpdate(snapshot(coverage: .loading))
                    } while pageToken != nil
                    // A page cursor left over means uninspected candidates —
                    // coverage can never claim complete-for-scope.
                    if pageToken != nil {
                        frontier.unfetchedResultPages = true
                    }
                    frontier.completeChunk(chunk, in: folder.id)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Folder failure is reported, not hidden; the rest continue.
                    frontier.failFolder(folder.id)
                }
            }
            if !progressed { break }
        }

        // Honest completion: every eligible folder drained its frontier, no
        // folder failed and no search result window was left unfetched. Failed
        // folders, truncated pages or budget-limited leftovers stay partial.
        let final = try snapshot(
            coverage: frontier.unavailableFolders.isEmpty
                && !frontier.hasPendingWork(in: eligible)
                && !frontier.unfetchedResultPages
                && ambiguousIdentifiers.isEmpty
                ? .completeForScope
                : .partial
        )
        await onUpdate(final)
        return final
    }
}

/// Frontier state for one remote related-header lookup (ADR-0074 §4/§8):
/// the per-folder pending and searched identifier sets, folder failures, the
/// spent request budget, and whether any result window was left unfetched.
private struct RelatedSearchFrontier {
    /// Identifiers still to search, per folder.
    var pendingByFolder: [Folder.ID: Set<String>] = [:]
    /// Identifiers already searched, per folder.
    var searchedByFolder: [Folder.ID: Set<String>] = [:]
    /// Folders whose search failed or went offline mid-scan.
    var unavailableFolders: [Folder.ID] = []
    /// Remote requests spent so far; bounded by the request budget.
    var queriedCount = 0
    /// A search returned a page cursor that was never followed to exhaustion.
    var unfetchedResultPages = false

    /// Adds identifiers to every still-available eligible folder's pending set,
    /// skipping identifiers that folder already searched.
    mutating func enqueue(_ identifiers: Set<String>, into eligible: [Folder]) {
        for folder in eligible where !unavailableFolders.contains(folder.id) {
            let searched = searchedByFolder[folder.id, default: []]
            pendingByFolder[folder.id, default: []].formUnion(identifiers.subtracting(searched))
        }
    }

    /// Marks folders with undrained pending work unavailable; used when the
    /// remote connection goes away mid-scan.
    mutating func markPendingFoldersUnavailable(in eligible: [Folder]) {
        for folder in eligible where pendingByFolder[folder.id]?.isEmpty == false {
            unavailableFolders.append(folder.id)
        }
    }

    /// Records a failed folder search; the rest of the scan continues.
    mutating func failFolder(_ folderID: Folder.ID) {
        unavailableFolders.append(folderID)
        pendingByFolder[folderID] = []
    }

    /// Moves a searched chunk from pending to searched for the folder.
    mutating func completeChunk(_ chunk: [String], in folderID: Folder.ID) {
        pendingByFolder[folderID]?.subtract(chunk)
        searchedByFolder[folderID, default: []].formUnion(chunk)
    }

    /// True while any eligible folder still has identifiers left to search.
    func hasPendingWork(in eligible: [Folder]) -> Bool {
        eligible.contains { pendingByFolder[$0.id]?.isEmpty == false }
    }
}
