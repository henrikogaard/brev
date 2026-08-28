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

struct SenderContextLoader: Sendable {
    var folderNameByID: [String: String] = [:]
    var recentLimit = 8

    func load(
        selected: MessageHeader,
        sourceID: MailSourceID?,
        backend: any MailBackend
    ) async -> Result<SenderContextSnapshot, Error> {
        let query = Self.senderSearchQuery(for: selected.from.email)

        do {
            let matchingHeaders = try await search(
                query: query,
                sourceID: sourceID,
                backend: backend
            )
            let contactDisplayName = await contactDisplayName(
                for: selected.from.email,
                sourceID: sourceID,
                backend: backend
            )
            var snapshot = SenderContextSnapshotBuilder.make(
                from: selected,
                matchingHeaders: matchingHeaders,
                contactDisplayName: contactDisplayName,
                folderNameByID: folderNameByID,
                recentLimit: recentLimit
            )
            snapshot.recent = snapshot.recent.map { item in
                var stamped = item
                stamped.sourceID = sourceID
                return stamped
            }
            return .success(snapshot)
        } catch {
            return .failure(error)
        }
    }

    static func senderSearchQuery(for senderEmail: String) -> SearchQuery {
        SearchQuery(
            text: senderEmail,
            from: senderEmail,
            execution: .cacheOnly
        )
    }

    private func search(
        query: SearchQuery,
        sourceID: MailSourceID?,
        backend: any MailBackend
    ) async throws -> [MessageHeader] {
        if let sourceID {
            return try await backend.search(query, sourceID: sourceID)
        }
        return try await backend.search(query)
    }

    private func contactDisplayName(
        for email: String,
        sourceID: MailSourceID?,
        backend: any MailBackend
    ) async -> String? {
        guard let sourceID,
              let contactLookup = backend.extensionService(ContactLookupProviding.self)
        else {
            return nil
        }

        do {
            let contacts = try await contactLookup.contacts(
                matching: ContactLookupQuery(text: email, sourceID: sourceID, limit: 1)
            )
            return contacts.first?.displayName
        } catch {
            return nil
        }
    }
}
