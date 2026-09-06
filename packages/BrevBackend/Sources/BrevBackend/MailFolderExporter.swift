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

/// Full-folder export formats supported by the local file exporter.
public enum MailFolderExportFormat: Sendable, Equatable { case mbox, emlDirectory }

/// Published output and the number of complete messages it contains.
public struct MailFolderExportResult: Sendable, Equatable {
    public let url: URL
    public let messageCount: Int
}

/// Exports one immutable mailbox/folder context using original MIME bytes.
public struct MailFolderExporter: Sendable {
    private let backend: any MailBackend
    private let sourceID: MailSourceID
    private let folder: Folder

    /// Captures the owning backend and folder before the user changes navigation.
    public init(backend: any MailBackend, sourceID: MailSourceID, folder: Folder) {
        self.backend = backend
        self.sourceID = sourceID
        self.folder = folder
    }

    /// Exports a folder; EML output creates a new directory inside the chosen destination.
    public func export(to destination: URL, format: MailFolderExportFormat,
                       replacingExistingFile: Bool = true, accessing securityScopedURL: URL? = nil,
                       progress: @Sendable (Int) async -> Void = { _ in }) async throws -> MailFolderExportResult {
        try Task.checkCancellation()
        guard backend.extendedCapabilities.contains(.rawMessageBytes) else {
            throw MailBackendError.notSupported(backend.capabilities)
        }
        #if canImport(Darwin)
        let scope = securityScopedURL ?? destination
        let accessedScope = scope.startAccessingSecurityScopedResource()
        defer { if accessedScope { scope.stopAccessingSecurityScopedResource() } }
        #endif
        let manager = FileManager.default
        if format == .mbox, !replacingExistingFile,
           (try? manager.attributesOfItem(atPath: destination.path)) != nil {
            throw MailFolderExportError.destinationExists
        }
        let stagingDirectory = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: stagingDirectory) }
        let stagingOutput = stagingDirectory.appendingPathComponent(format == .mbox ? "Mailbox.mbox" : "Messages")
        let handle: FileHandle?
        if format == .mbox {
            guard manager.createFile(atPath: stagingOutput.path, contents: nil) else {
                throw MailExportError.cannotOpenFile(destination.lastPathComponent)
            }
            handle = try FileHandle(forWritingTo: stagingOutput)
        } else {
            guard try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw MailFolderExportError.destinationMustBeFolder
            }
            try manager.createDirectory(at: stagingOutput, withIntermediateDirectories: false)
            handle = nil
        }
        defer { try? handle?.close() }
        let exporter = MBOXExporter()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        var pageToken: String?
        var visitedTokens: Set<String> = []
        var exportedIDs: Set<MessageHeader.ID> = []
        var completed = 0
        await progress(completed)
        while true {
            try Task.checkCancellation()
            let page = try await backend.enumerateMessages(in: folder, sourceID: sourceID, pageToken: pageToken)
            for header in page.headers where exportedIDs.insert(header.id).inserted {
                try Task.checkCancellation()
                let bytes = try await backend.rawMessageData(for: header.id, sourceID: sourceID)
                try Task.checkCancellation()
                guard !bytes.isEmpty else { throw MailFolderExportError.emptyMessage }
                if let handle {
                    let invalidSenderCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
                    let sender = header.from.email.isEmpty || header.from.email
                        .rangeOfCharacter(from: invalidSenderCharacters) != nil
                        ? "MAILER-DAEMON" : header.from.email
                    try exporter.append(message: ImportedMessage(
                        headers: [("From", sender), ("Date", Self.envelopeDate(header.date, formatter: dateFormatter))],
                        bodyData: bytes
                    ), to: handle)
                } else {
                    let filename = "\(completed + 1) - \(Self.safeName(header.subject, fallback: "Message")).eml"
                    try bytes.write(to: stagingOutput.appendingPathComponent(filename), options: [.withoutOverwriting])
                }
                completed += 1
                await progress(completed)
            }
            guard let next = page.nextPageToken else { break }
            guard visitedTokens.insert(next).inserted else { throw MailFolderExportError.repeatedPage }
            pageToken = next
        }
        try Task.checkCancellation()
        try handle?.synchronize()
        try handle?.close()
        try Task.checkCancellation()
        let output: URL
        if format == .emlDirectory {
            let base = Self.safeName(folder.name, fallback: "Mailbox") + " Export"
            var candidate = destination.appendingPathComponent(base)
            var suffix = 2
            while (try? manager.attributesOfItem(atPath: candidate.path)) != nil {
                try Task.checkCancellation()
                candidate = destination.appendingPathComponent("\(base) (\(suffix))")
                suffix += 1
            }
            try Task.checkCancellation()
            try manager.moveItem(at: stagingOutput, to: candidate)
            output = candidate
        } else {
            if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
                guard replacingExistingFile else { throw MailFolderExportError.destinationExists }
                _ = try manager.replaceItemAt(destination, withItemAt: stagingOutput)
            } else {
                try manager.moveItem(at: stagingOutput, to: destination)
            }
            output = destination
        }
        return MailFolderExportResult(url: output, messageCount: completed)
    }

    private static func envelopeDate(_ date: Date, formatter: DateFormatter) -> String {
        var value = formatter.string(from: date)
        // UTC ctime uses a space-padded day, not a leading zero.
        if value.count >= 10 {
            let day = value.index(value.startIndex, offsetBy: 8)
            if value[day] == "0" { value.replaceSubrange(day ... day, with: " ") }
        }
        return value
    }

    /// Safe, byte-bounded filename suggested by native archive save panels.
    public static func suggestedArchiveName(for folderName: String) -> String {
        safeName(folderName, fallback: "Mailbox") + ".mbox"
    }

    /// Chooses a new MBOX filename when the platform picker selects a parent folder.
    public static func availableArchiveURL(in directory: URL, folderName: String) -> URL {
        #if canImport(Darwin)
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        #endif
        let base = safeName(folderName, fallback: "Mailbox")
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("mbox")
        var suffix = 2
        while (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil {
            candidate = directory.appendingPathComponent("\(base) (\(suffix))").appendingPathExtension("mbox")
            suffix += 1
        }
        return candidate
    }

    private static func safeName(_ value: String, fallback: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = value.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "." })
        var result = ""
        var byteCount = 0
        for character in cleaned {
            let count = String(character).utf8.count
            guard byteCount + count <= 180 else { break }
            result.append(character)
            byteCount += count
        }
        return result.isEmpty ? fallback : result
    }
}

/// Export errors that must not leave a partial output presented as complete.
public enum MailFolderExportError: Error, LocalizedError, Sendable {
    case emptyMessage
    case repeatedPage
    case destinationExists
    case destinationMustBeFolder

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            String(localized: "The server returned an empty message source. Export stopped.", bundle: .module)
        case .repeatedPage:
            String(localized: "The server repeated an export page. Refresh the mailbox and try again.", bundle: .module)
        case .destinationExists:
            String(localized: "An export already exists at this location. Choose another destination.", bundle: .module)
        case .destinationMustBeFolder:
            String(localized: "Choose a destination folder for the EML files.", bundle: .module)
        }
    }
}
