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

struct SenderContextIdentity: Equatable, Sendable {
    var email: String
    var displayName: String
    var contactDisplayName: String?
}

struct SenderContextRecentItem: Equatable, Identifiable, Sendable {
    var id: String
    var folderID: String
    var subject: String
    var date: Date
    var folderName: String?
    var sourceID: MailSourceID?
}

struct SenderContextSnapshot: Equatable, Sendable {
    var identity: SenderContextIdentity
    var messageCount: Int?
    var firstSeen: Date?
    var lastSeen: Date?
    var recent: [SenderContextRecentItem]
}

enum SenderContextSnapshotBuilder {
    static func make(
        from selected: MessageHeader,
        matchingHeaders: [MessageHeader],
        contactDisplayName: String?,
        folderNameByID: [String: String],
        recentLimit: Int = 8
    ) -> SenderContextSnapshot {
        let sortedHeaders = matchingHeaders.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id < rhs.id
            }
            return lhs.date > rhs.date
        }
        let recent = sortedHeaders.prefix(max(0, recentLimit)).map { header in
            SenderContextRecentItem(
                id: header.id,
                folderID: header.folderID,
                subject: normalizedSubject(header.subject),
                date: header.date,
                folderName: folderNameByID[header.folderID],
                sourceID: nil
            )
        }

        return SenderContextSnapshot(
            identity: SenderContextIdentity(
                email: selected.from.email,
                displayName: selected.from.displayName,
                contactDisplayName: contactDisplayName
            ),
            messageCount: matchingHeaders.count,
            firstSeen: matchingHeaders.map(\.date).min(),
            lastSeen: matchingHeaders.map(\.date).max(),
            recent: Array(recent)
        )
    }

    private static func normalizedSubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no subject)" : subject
    }
}
