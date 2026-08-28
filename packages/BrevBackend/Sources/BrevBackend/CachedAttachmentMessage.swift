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

/// An attachment-bearing message that is already present in Brev's local
/// cache, surfaced read-only for the All Attachments view (#259/#264).
///
/// It carries the existing domain values needed to build an attachment
/// record and route back to the owning message. Producing one never causes
/// a connection, fetch, or download (ADR-0006, ADR-0041, ADR-0044).
public struct CachedAttachmentMessage: Sendable, Equatable {
    /// The folder the message belongs to.
    public let folder: Folder
    /// The cached header for the message.
    public let header: MessageHeader
    /// The parsed body, whose `attachments` are already available.
    public let body: MessageBody

    public init(folder: Folder, header: MessageHeader, body: MessageBody) {
        self.folder = folder
        self.header = header
        self.body = body
    }
}
