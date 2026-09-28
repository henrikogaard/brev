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

/// ADR-0082 Layer A: applies the strongest compatible iOS data
/// protection to the on-device store root and its existing contents.
///
/// `completeUntilFirstUserAuthentication` — not `.complete` — because
/// BGAppRefresh windows must still reach the store while the device is
/// locked (ADR-0037 posture). On macOS this is a deliberate no-op:
/// file-protection classes are iOS-family only and confidentiality
/// there rests on FileVault.
public enum BrevStoreProtection {
    /// The shared store root every backend file cache hangs off:
    /// `~/Library/Application Support/Brev` (sync caches, header/body
    /// caches, draft staging, local folders).
    public static func storeRoot(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev", isDirectory: true)
    }

    /// Protects the store root — creating it first so files created
    /// later inherit the directory's protection class — then walks any
    /// existing contents so pre-upgrade files get the class too.
    /// The walk is a one-time migration: once it completes cleanly its
    /// coverage is recorded, so later launches only re-assert the root
    /// class (new files inherit it) instead of re-walking a mail store
    /// that can hold tens of thousands of entries. Every step degrades
    /// silently: unsigned builds and simulator quirks must never block
    /// launch.
    public static func applyProtection(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        applyProtection(
            root: storeRoot(fileManager: fileManager),
            fileManager: fileManager,
            defaults: defaults
        )
    }

    /// Applies the protection class at `root`; nil root is a no-op.
    /// Exposed for tests so the walk can run on a scratch directory.
    static func applyProtection(root: URL?, fileManager: FileManager, defaults: UserDefaults = .standard) {
        #if os(iOS)
        guard let root else { return }
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        protect(root, fileManager: fileManager)
        guard !defaults.bool(forKey: migrationWalkedKey) else { return }
        var failures = 0
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if !protect(url, fileManager: fileManager) { failures += 1 }
            }
        }
        if failures == 0 {
            defaults.set(true, forKey: migrationWalkedKey)
        }
        #endif
    }

    #if os(iOS)
    /// Marks the pre-upgrade migration walk complete so it never runs
    /// again on launch.
    private static let migrationWalkedKey = "BrevStoreProtection.migrationWalked"

    @discardableResult
    private static func protect(_ url: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }
    #endif
}
