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

    /// Creates the package at `url` (replacing an existing item) and writes
    /// both payloads plus the manifest.
    static func write(
        to url: URL,
        settings: SettingsBackupPayload,
        accounts: AccountsBackupPayload,
        appVersion: String,
        appBuild: String
    ) throws {
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
            try data.write(to: url.appendingPathComponent(name), options: .atomic)
            payloads.append(BrevBackupManifest.Payload(
                name: name,
                sha256: sha256Hex(data)
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
