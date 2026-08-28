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

/// Canonical mapping between an account identifier and its on-disk cache
/// directory name, plus the redacted display form of a cache path.
///
/// Both the Settings storage panel (`MailStorageInfo`) and the mailbox storage
/// helper (`MailboxStorageInfo`) surface cache sizes and paths and must agree on
/// this mapping — otherwise the object-count parity between the two diverges and
/// a path could be displayed unredacted. This is the single source of truth so
/// they cannot drift.
public enum MailCacheKeyNaming {
    /// Lowercase hex encoding of the UTF-8 bytes of `value`, matching the
    /// `fileKey` derivation in the file-backed caches (`Brev/Cache/<utf8-hex>`).
    public static func hexKey(_ value: String) -> String {
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `value` looks like an account cache-key directory name (an even
    /// number of hex digits, at least 16). Used to redact the key in a path.
    public static func isHexCacheKey(_ value: String) -> Bool {
        guard value.count >= 16, value.count.isMultiple(of: 2) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
        }
    }

    /// A path suitable for display: abbreviates the home directory with `~` and
    /// replaces an account-specific cache key with `account-cache`.
    public static func displayPath(for url: URL) -> String {
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        let directoryName = url.lastPathComponent
        guard isHexCacheKey(directoryName) else { return path }

        let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return "\(parent)/account-cache"
    }
}
