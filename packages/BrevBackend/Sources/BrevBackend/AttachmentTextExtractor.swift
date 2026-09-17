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
import PDFKit

/// Error raised when one attachment extraction exceeds its time budget.
public enum AttachmentTextExtractionError: Error, Sendable {
    /// Extraction did not finish inside the caller's timeout.
    case timedOut
}

/// Bounded text extraction from attachment bytes already present on device
/// (ADR-0078 §3). Pure and local: no OCR, no plug-ins, no network, and it
/// never loads attachment data itself — the caller supplies bytes that were
/// already cached.
///
/// Supported inputs:
/// - PDF via `PDFDocument` (encrypted/locked documents return `nil`).
/// - `text/*`, CSV and Markdown, decoded with charset fallback.
/// - RTF via `NSAttributedString`.
/// - HTML via pure-string tag/entity stripping — never a document importer,
///   so remote subresources (`<img>`, stylesheets) are never fetched.
///
/// Office Open XML (`.docx`/`.xlsx`/`.pptx`) is not extracted: whether the
/// platform OOXML importer resolves external relationships is undocumented,
/// so it is left out of the closed format table.
///
/// Bounds enforced here: inputs above 25 MB are skipped, output text is
/// truncated to 512 KB, and `Task.isCancelled` is checked between steps.
/// Callers wrap each extraction in a 10-second timeout via
/// `extract(data:mimeType:fileName:timeout:)`.
public enum AttachmentTextExtractor {
    /// Attachments larger than this are skipped without being decoded.
    public static let maxInputBytes = 25 * 1024 * 1024

    /// Extracted text is truncated to this many characters.
    public static let maxOutputCharacters = 512 * 1024

    /// Default per-attachment extraction timeout (ADR-0078 §3).
    public static let defaultTimeout: Duration = .seconds(10)

    /// Extracts searchable text, or `nil` when the format is unsupported or
    /// the document is encrypted. Respects the input/output bounds and
    /// cancellation between steps.
    public static func extract(
        data: Data,
        mimeType: String,
        fileName: String
    ) async throws -> String? {
        guard data.count <= maxInputBytes else { return nil }
        try Task.checkCancellation()
        let kind = Kind(mimeType: mimeType, fileName: fileName)
        let text: String?
        switch kind {
        case .pdf:
            text = extractPDF(data: data)
        case .plainText:
            text = decodeText(data: data)
        case .rtf:
            text = extractAttributed(data: data, documentType: .rtf)
        case .html:
            // NSAttributedString's HTML importer resolves remote subresources;
            // indexing untrusted bytes must never touch the network.
            text = HTMLTextStripper.visibleText(from: data)
        case .officeOpenXML:
            text = nil
        case .unsupported:
            text = nil
        }
        try Task.checkCancellation()
        guard let text else { return nil }
        if text.count > maxOutputCharacters {
            return String(text.prefix(maxOutputCharacters))
        }
        return text
    }

    /// Runs `extract` under a wall-clock timeout using a task-group race; the
    /// losing branch is cancelled. Throws `AttachmentTextExtractionError.timedOut`.
    public static func extract(
        data: Data,
        mimeType: String,
        fileName: String,
        timeout: Duration
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await extract(data: data, mimeType: mimeType, fileName: fileName)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AttachmentTextExtractionError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    // MARK: - Format detection

    private enum Kind {
        case pdf
        case plainText
        case rtf
        case html
        case officeOpenXML
        case unsupported

        init(mimeType: String, fileName: String) {
            let mime = mimeType.lowercased()
            let ext = (fileName as NSString).pathExtension.lowercased()
            if mime == "application/pdf" || ext == "pdf" {
                self = .pdf
            } else if mime.contains("rtf") || ext == "rtf" {
                self = .rtf
            } else if mime == "text/html" || ext == "html" || ext == "htm" {
                self = .html
            } else if Self.officeTypes.contains(mime)
                || ["docx", "xlsx", "pptx"].contains(ext) {
                self = .officeOpenXML
            } else if mime.hasPrefix("text/")
                || mime == "application/json"
                || ["csv", "md", "markdown", "txt", "log"].contains(ext) {
                self = .plainText
            } else {
                self = .unsupported
            }
        }

        private static let officeTypes: Set<String> = [
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ]
    }

    // MARK: - Extractors

    private static func extractPDF(data: Data) -> String? {
        guard let document = PDFDocument(data: data), !document.isLocked else {
            return nil
        }
        return document.string
    }

    private static func decodeText(data: Data) -> String? {
        // UTF-8 first, then the declared-encoding-agnostic Latin-1 fallback;
        // `String(decoding:)` replaces undecodable bytes so text attachments
        // always produce *something* indexable rather than failing.
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }

    private static func extractAttributed(
        data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ).string
    }
}
