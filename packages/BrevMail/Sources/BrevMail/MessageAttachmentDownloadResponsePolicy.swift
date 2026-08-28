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

struct MessageAttachmentDownloadRequest: Equatable, Sendable {
    let messageID: String
    let sourceID: MailSourceID?
    let attachmentID: String

    init(
        messageID: String,
        sourceID: MailSourceID? = nil,
        attachmentID: String
    ) {
        self.messageID = messageID
        self.sourceID = sourceID
        self.attachmentID = attachmentID
    }
}

enum MessageAttachmentDownloadStartPolicy {
    static func canStartDownload(
        activeRequest: MessageAttachmentDownloadRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest == nil
    }
}

enum MessageAttachmentDownloadResponsePolicy {
    static func canApplyResponse(
        request: MessageAttachmentDownloadRequest,
        activeRequest: MessageAttachmentDownloadRequest?,
        currentSourceID: MailSourceID? = nil,
        currentMessageID: String?
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentMessageID == request.messageID
    }
}

enum MessageAttachmentDownloadFilenamePolicy {
    private static let maxFilenameLength = 180

    static func safeFilename(suggestedName: String) -> String {
        let trimmed = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            return "attachment"
        }

        let invalidScalars = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let safeScalars = trimmed.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? "_" : Character(scalar)
        }
        let safeName = String(safeScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !safeName.isEmpty, safeName != ".", safeName != ".." else {
            return "attachment"
        }
        return shortened(safeName)
    }

    static func uniqueFilename(
        baseName: String,
        fileExists: (String) -> Bool
    ) -> String {
        let baseName = shortened(baseName)
        guard fileExists(baseName) else {
            return baseName
        }

        var counter = 1
        while true {
            let candidate = duplicateFilename(baseName: baseName, counter: counter)
            guard fileExists(candidate) else {
                return candidate
            }
            counter += 1
        }
    }

    private static func shortened(_ name: String) -> String {
        guard name.count > maxFilenameLength else {
            return name
        }

        let nsName = name as NSString
        let pathExtension = nsName.pathExtension
        guard !pathExtension.isEmpty else {
            return String(name.prefix(maxFilenameLength))
        }

        let suffix = ".\(pathExtension)"
        guard suffix.count < maxFilenameLength else {
            return String(name.prefix(maxFilenameLength))
        }

        let stem = nsName.deletingPathExtension
        let maxStemLength = maxFilenameLength - suffix.count
        return "\(String(stem.prefix(maxStemLength)))\(suffix)"
    }

    private static func duplicateFilename(baseName: String, counter: Int) -> String {
        let disambiguator = " (\(counter))"
        guard disambiguator.count < maxFilenameLength else {
            return String(baseName.prefix(maxFilenameLength))
        }

        let nsName = baseName as NSString
        let pathExtension = nsName.pathExtension
        guard !pathExtension.isEmpty else {
            let maxStemLength = maxFilenameLength - disambiguator.count
            return "\(String(baseName.prefix(maxStemLength)))\(disambiguator)"
        }

        let suffix = "\(disambiguator).\(pathExtension)"
        guard suffix.count < maxFilenameLength else {
            let maxStemLength = maxFilenameLength - disambiguator.count
            return "\(String(baseName.prefix(maxStemLength)))\(disambiguator)"
        }

        let stem = nsName.deletingPathExtension
        let maxStemLength = maxFilenameLength - suffix.count
        return "\(String(stem.prefix(maxStemLength)))\(suffix)"
    }
}

enum MessageAttachmentDownloadStoragePurpose: Equatable, Sendable {
    case previewOrOpen
    case savePanelStaging
}

enum MessageAttachmentDownloadStoragePolicy {
    static func directory(
        purpose _: MessageAttachmentDownloadStoragePurpose,
        temporaryDirectory: URL
    ) -> URL {
        temporaryDirectory
    }
}

enum MessageAttachmentDownloadedFilePolicy {
    static func reusableCachedURL(
        _ url: URL?,
        fileExists: (URL) -> Bool
    ) -> URL? {
        guard let url, fileExists(url) else {
            return nil
        }
        return url
    }
}
