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

/// Supplies cached attachment metadata for the All Attachments surface.
/// Implementations MUST be read-only and MUST NOT trigger downloads or
/// network calls (ADR-0041).
protocol AttachmentSearchRecordProviding: Sendable {
    func attachmentRecords() async -> [AttachmentSearchRecord]
}

/// Fixed records, for previews and snapshot tests.
struct StubAttachmentSearchRecordProvider: AttachmentSearchRecordProviding {
    let records: [AttachmentSearchRecord]
    func attachmentRecords() async -> [AttachmentSearchRecord] { records }
}
