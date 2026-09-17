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

import CryptoKit
import Foundation

/// Writes a `.brevbackup` directory package (ADR-0076 decision 1):
/// `settings.json`, `accounts.json`, then `manifest.json` last so a
/// present manifest implies complete payloads. All writes are atomic.
/// Mail archives (decision 6) are out of scope; the manifest's `payloads`
/// array can already describe a future `mail/` payload.
enum BackupWriter {
    static let settingsPayloadName = "settings.json"
    static let accountsPayloadName = "accounts.json"
    static let manifestName = "manifest.json"
    static let packageExtension = "brevbackup"

    /// Encoder settings shared by writer, reader, and tests so hashes verify.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// One local-mail folder destined for `mail/` inside the package. The
    /// `write` closure streams the MBOX to the given URL so multi-GB folders
    /// never have to fit in memory (ADR-0077 decision 6).
    struct MailFile {
        /// Manifest payload name, e.g. `mail/<folderID>.mbox`.
        let name: String
        /// Display name recorded in `mail/folders.json` for restore.
        let folderName: String
        /// Streams the MBOX bytes to the destination URL.
        let write: @Sendable (URL) async throws -> Void
    }

    /// Payload recording which `mail/*.mbox` file restores which folder name.
    static let mailFoldersIndexName = "mail/folders.json"

    /// Creates the package at `url` (replacing an existing item) and writes
    /// settings, accounts, optional `mail/` payloads, then the manifest last.
    static func write(
        to url: URL,
        settings: SettingsBackupPayload,
        accounts: AccountsBackupPayload,
        appVersion: String,
        appBuild: String,
        mailPayloads: [MailFile] = []
    ) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        var payloads: [BrevBackupManifest.Payload] = []
        for (name, data) in try [
            (settingsPayloadName, encoder.encode(settings)),
            (accountsPayloadName, encoder.encode(accounts))
        ] {
            let path = url.appendingPathComponent(name)
            try data.write(to: path, options: .atomic)
            try payloads.append(BrevBackupManifest.Payload(
                name: name,
                sha256: sha256Hex(contentsOf: path)
            ))
        }

        if !mailPayloads.isEmpty {
            let mailDirectory = url.appendingPathComponent("mail", isDirectory: true)
            try fileManager.createDirectory(at: mailDirectory, withIntermediateDirectories: true)
            var index: [[String: String]] = []
            for mailFile in mailPayloads {
                let destination = mailDirectory.appendingPathComponent(
                    URL(fileURLWithPath: mailFile.name).lastPathComponent
                )
                try await mailFile.write(destination)
                try payloads.append(BrevBackupManifest.Payload(
                    name: "mail/\(destination.lastPathComponent)",
                    sha256: sha256Hex(contentsOf: destination),
                    encoding: "mbox"
                ))
                index.append(["file": "mail/\(destination.lastPathComponent)", "name": mailFile.folderName])
            }
            let indexData = try encoder.encode(index)
            let indexPath = mailDirectory.appendingPathComponent("folders.json")
            try indexData.write(to: indexPath, options: .atomic)
            try payloads.append(BrevBackupManifest.Payload(
                name: mailFoldersIndexName,
                sha256: sha256Hex(contentsOf: indexPath)
            ))
        }

        let manifest = BrevBackupManifest(
            appVersion: appVersion,
            appBuild: appBuild,
            platform: BrevBackupManifest.currentPlatform,
            payloads: payloads
        )
        try encoder.encode(manifest)
            .write(to: url.appendingPathComponent(manifestName), options: .atomic)
    }

    /// Streaming SHA-256 over a file — mail payloads can be large, so they are
    /// never loaded into memory wholesale (ADR-0077 decision 6).
    static func sha256Hex(contentsOf url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decoder matching `encoder`'s date strategy.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
