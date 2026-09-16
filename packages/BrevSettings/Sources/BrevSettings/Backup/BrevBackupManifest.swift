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

/// Manifest of a `.brevbackup` directory package (ADR-0076).
///
/// A backup package contains `manifest.json` plus one JSON file per payload
/// (`settings.json`, `accounts.json`, and — in a future slice — `mail/`).
/// `manifest.json` is written last so its presence marks a complete backup.
/// `payloads` can describe any future payload shape; readers verify every
/// listed payload's SHA-256 and skip names they do not know.
public struct BrevBackupManifest: Codable, Equatable, Sendable {
    /// One payload entry in the manifest, e.g. `settings.json`.
    public struct Payload: Codable, Equatable, Sendable {
        /// File name inside the package, e.g. `settings.json`.
        public var name: String
        /// Lowercase hex SHA-256 of the payload file's bytes.
        public var sha256: String
        /// Payload encoding; always `"json"` for the current payloads.
        public var encoding: String

        public init(name: String, sha256: String, encoding: String = "json") {
            self.name = name
            self.sha256 = sha256
            self.encoding = encoding
        }
    }

    /// Highest format version this build can read and write.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var appBuild: String
    /// Source platform, e.g. `macOS` or `iOS`.
    public var platform: String
    /// Always `false` — backups never contain passwords, tokens, or keys.
    public var containsSecrets: Bool
    public var payloads: [Payload]

    public init(
        createdAt: Date = Date(),
        appVersion: String,
        appBuild: String,
        platform: String,
        payloads: [Payload]
    ) {
        formatVersion = Self.currentFormatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.platform = platform
        containsSecrets = false
        self.payloads = payloads
    }

    /// Platform string recorded in new manifests.
    public static var currentPlatform: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #else
        "unknown"
        #endif
    }
}

/// How a restore applies backup values to existing local settings.
public enum BackupRestoreMode: String, CaseIterable, Sendable {
    /// Backup wins for scalar values; list items are unioned by identity
    /// without reordering local items.
    case merge
    /// Families present in the backup replace the local value wholesale.
    case replace
}

/// Errors surfaced when reading or restoring a `.brevbackup` package.
public enum BackupError: LocalizedError, Equatable {
    /// The manifest's `formatVersion` is newer than this build supports.
    case unsupportedVersion(Int)
    /// A payload file is missing, fails its SHA-256 check, or does not decode.
    case corrupted(String)
    /// The package directory has no `manifest.json`.
    case missingManifest
    /// The URL is not a `.brevbackup` directory package.
    case notABackup

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            String(
                localized: "This backup uses a newer format (version \(version)) that this version of Brev cannot read.",
                bundle: .module
            )
        case .corrupted(let payload):
            String(localized: "The backup payload “\(payload)” is missing or corrupted.", bundle: .module)
        case .missingManifest:
            String(localized: "This backup is missing its manifest and cannot be verified.", bundle: .module)
        case .notABackup:
            String(localized: "The selected item is not a Brev backup.", bundle: .module)
        }
    }
}
