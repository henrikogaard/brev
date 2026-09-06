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
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum MessageEMLExport {
    static func fileName(for header: MessageHeader) -> String {
        let trimmed = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "message" : trimmed
        return "\(safeFileBaseName(baseName)).eml"
    }

    /// Writes the complete MIME message without decoding or rebuilding it.
    static func write(_ rawMessageData: Data, to url: URL) throws {
        try rawMessageData.write(to: url, options: [.atomic])
    }

    private static func safeFileBaseName(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = value
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading dots so a subject of "." / ".." can't produce a hidden
        // or reserved name like "..eml".
        let withoutLeadingDots = String(sanitized.drop { $0 == "." })
        return withoutLeadingDots.isEmpty ? "message" : withoutLeadingDots
    }

    #if canImport(AppKit)
    @MainActor
    static func presentSavePanel(header: MessageHeader, rawMessageData: Data) throws -> Bool {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Message As", bundle: .module)
        panel.prompt = String(localized: "Save", bundle: .module)
        panel.message = String(localized: "Choose a location to save the message as an .eml file.", bundle: .module)
        panel.nameFieldStringValue = fileName(for: header)
        panel.allowedContentTypes = [.eml]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        try write(rawMessageData, to: url)
        return true
    }
    #endif
}

private extension UTType {
    static let eml = UTType(filenameExtension: "eml") ?? .data
}
