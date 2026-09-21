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
import BrevCalendar
import Foundation

/// Bridges the shared PIM contact cache (ADR-0072) to the
/// ContactLookupProviding protocol so compose autocomplete queries
/// every synced contacts source — Google and CardDAV — instead of the
/// legacy per-backend CardDAV lookup (#10).
///
/// Reads the local cache only; the adapter never contacts a provider.
/// A caller-supplied fallback provider keeps the legacy CardDAV
/// addressbook-query path alive for sessions whose PIM sources are not
/// synced yet.
public final class PIMContactLookupAdapter: ContactLookupProviding {
    private let coordinator: PIMSourceCoordinator
    private let syncService: PIMContactSyncService
    private let fallback: (any ContactLookupProviding)?

    public init(
        coordinator: PIMSourceCoordinator,
        syncService: PIMContactSyncService,
        fallback: (any ContactLookupProviding)? = nil
    ) {
        self.coordinator = coordinator
        self.syncService = syncService
        self.fallback = fallback
    }

    public func contacts(
        matching query: ContactLookupQuery
    ) async throws -> [ContactLookupResult] {
        let sources = try await coordinator.allSources()
            .filter { $0.kind == .contacts }
        var results: [ContactLookupResult] = []
        for source in sources {
            let matches = try await syncService.searchContacts(
                matching: query.text,
                for: source.id,
                limit: query.limit
            )
            for contact in matches {
                for field in contact.emails {
                    results.append(
                        ContactLookupResult(
                            id: "\(contact.id)-\(field.value)",
                            displayName: contact.displayName,
                            email: field.value,
                            sourceID: query.sourceID,
                            sourceLabel: source.displayName
                        )
                    )
                }
            }
        }
        if let fallback {
            results += try await fallback.contacts(matching: query)
        }
        return results
    }
}
