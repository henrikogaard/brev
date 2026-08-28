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

/// Bridges `ContactsSyncCoordinator` (BrevCalendar) to the `ContactLookupProviding`
/// protocol (BrevBackend) so compose autocomplete can query the synced CardDAV contacts.
public final class CardDAVContactLookupAdapter: ContactLookupProviding {
    private let coordinator: ContactsSyncCoordinator

    public init(coordinator: ContactsSyncCoordinator) {
        self.coordinator = coordinator
    }

    public func contacts(matching query: ContactLookupQuery) async throws -> [ContactLookupResult] {
        let records = await coordinator.contacts(matching: query.text, limit: query.limit)
        return records.flatMap { record -> [ContactLookupResult] in
            record.emails.map { email in
                ContactLookupResult(
                    id: "\(record.id)-\(email)",
                    displayName: record.displayName,
                    email: email,
                    sourceID: query.sourceID
                )
            }
        }
    }
}
