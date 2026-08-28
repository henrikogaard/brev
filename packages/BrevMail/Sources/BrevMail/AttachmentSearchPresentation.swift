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

enum AttachmentSearchFileType: Equatable, Sendable {
    case pdf
    case image
    case document
    case spreadsheet
    case archive
    case other
}

struct AttachmentSearchFilter: Equatable, Sendable {
    static let allAttachments = AttachmentSearchFilter()

    var query: String
    var fileType: AttachmentSearchFileType?
    var sender: String?
    var folderID: Folder.ID?
    var startDate: Date?
    var endDate: Date?

    init(
        query: String = "",
        fileType: AttachmentSearchFileType? = nil,
        sender: String? = nil,
        folderID: Folder.ID? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.query = query
        self.fileType = fileType
        self.sender = sender
        self.folderID = folderID
        self.startDate = startDate
        self.endDate = endDate
    }
}

enum AttachmentSearchBodyCacheState: Equatable, Sendable {
    case cached
    case headerOnly
}

enum AttachmentSearchContentIndexState: Equatable, Sendable {
    case indexed
    case notIndexed
    case unsupported
}

struct AttachmentSearchRecord: Equatable, Sendable {
    var sourceID: MailSourceID
    var sourceName: String
    var header: MessageHeader
    var folderName: String
    var attachment: Attachment
    var bodyCacheState: AttachmentSearchBodyCacheState
    var contentIndexState: AttachmentSearchContentIndexState
}

struct AttachmentSearchRoute: Equatable, Hashable, Sendable {
    var sourceID: MailSourceID
    var folderID: Folder.ID
    var messageID: MessageHeader.ID
    var attachmentID: Attachment.ID
}

enum AttachmentSearchAvailability: Equatable, Sendable {
    case cached
    case downloadRequired
}

struct AttachmentSearchRow: Equatable, Sendable, Identifiable {
    var id: AttachmentSearchRoute { route }
    var filename: String
    var subject: String
    var sender: String
    var date: Date
    var sourceName: String
    var folderName: String
    var sizeBytes: Int?
    var attachmentID: Attachment.ID
    var route: AttachmentSearchRoute
    var availability: AttachmentSearchAvailability
    var degradedStateMessages: [String]
}

enum AttachmentSearchPresentation {
    static func rows(
        records: [AttachmentSearchRecord],
        filter: AttachmentSearchFilter
    ) -> [AttachmentSearchRow] {
        records
            .filter { record in
                matches(filter: filter, record: record)
            }
            .sorted { lhs, rhs in
                if lhs.header.date != rhs.header.date {
                    return lhs.header.date > rhs.header.date
                }
                if lhs.attachment.name != rhs.attachment.name {
                    return lhs.attachment.name.localizedStandardCompare(rhs.attachment.name) == .orderedAscending
                }
                return lhs.attachment.id < rhs.attachment.id
            }
            .map(row(for:))
    }

    private static func matches(
        filter: AttachmentSearchFilter,
        record: AttachmentSearchRecord
    ) -> Bool {
        if let folderID = filter.folderID, record.header.folderID != folderID {
            return false
        }

        if let startDate = filter.startDate, record.header.date < startDate {
            return false
        }

        if let endDate = filter.endDate, record.header.date > endDate {
            return false
        }

        if let sender = filter.sender,
           record.header.from.email.localizedCaseInsensitiveCompare(sender) != .orderedSame {
            return false
        }

        if let fileType = filter.fileType, !fileType.matches(record.attachment) {
            return false
        }

        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystacks = [
            record.attachment.name,
            record.attachment.mimeType,
            record.header.subject,
            record.header.from.email,
            record.sourceName,
            record.folderName
        ]

        return haystacks.contains { value in
            value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func row(for record: AttachmentSearchRecord) -> AttachmentSearchRow {
        let route = AttachmentSearchRoute(
            sourceID: record.sourceID,
            folderID: record.header.folderID,
            messageID: record.header.id,
            attachmentID: record.attachment.id
        )

        return AttachmentSearchRow(
            filename: record.attachment.name,
            subject: record.header.subject,
            sender: record.header.from.email,
            date: record.header.date,
            sourceName: record.sourceName,
            folderName: record.folderName,
            sizeBytes: record.attachment.sizeBytes,
            attachmentID: record.attachment.id,
            route: route,
            availability: availability(for: record),
            degradedStateMessages: degradedStateMessages(for: record)
        )
    }

    private static func availability(for record: AttachmentSearchRecord) -> AttachmentSearchAvailability {
        guard record.bodyCacheState == .cached,
              record.attachment.resource != nil
        else {
            return .downloadRequired
        }

        return .cached
    }

    private static func degradedStateMessages(for record: AttachmentSearchRecord) -> [String] {
        var messages: [String] = []

        if record.bodyCacheState == .headerOnly || record.attachment.resource == nil {
            messages.append("Download required before preview or content indexing.")
        }

        switch record.contentIndexState {
        case .indexed:
            break
        case .notIndexed:
            messages.append("Attachment contents are not indexed.")
        case .unsupported:
            messages.append("Attachment type is not supported for content indexing.")
        }

        return messages
    }
}

private extension AttachmentSearchFileType {
    func matches(_ attachment: Attachment) -> Bool {
        let mimeType = attachment.mimeType.lowercased()
        let fileExtension = (attachment.name as NSString).pathExtension.lowercased()

        switch self {
        case .pdf:
            return mimeType == "application/pdf" || fileExtension == "pdf"
        case .image:
            return mimeType.hasPrefix("image/")
        case .document:
            return [
                "doc",
                "docx",
                "odt",
                "pages",
                "rtf",
                "txt"
            ].contains(fileExtension)
        case .spreadsheet:
            return [
                "csv",
                "numbers",
                "ods",
                "xls",
                "xlsx"
            ].contains(fileExtension)
        case .archive:
            return [
                "7z",
                "gz",
                "rar",
                "tar",
                "zip"
            ].contains(fileExtension)
        case .other:
            return !AttachmentSearchFileType.pdf.matches(attachment)
                && !AttachmentSearchFileType.image.matches(attachment)
                && !AttachmentSearchFileType.document.matches(attachment)
                && !AttachmentSearchFileType.spreadsheet.matches(attachment)
                && !AttachmentSearchFileType.archive.matches(attachment)
        }
    }
}
