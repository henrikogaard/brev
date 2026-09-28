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
import Testing

// BrevStoreProtection.swift is compiled directly into this test target
// (see BrevIOSTests sources in apps/iOS/Project.swift) — no module import.

@Suite("BrevStoreProtection (ADR-0082 Layer A)")
struct BrevStoreProtectionTests {
    // The iOS Simulator accepts .protectionKey writes but does not persist them
    // (Data Protection is not simulated), so the class value itself can only be
    // verified on device. What stays testable here: the root is created when
    // missing, an existing tree is traversed without throwing, and the
    // one-time migration flag keeps later calls off the tree.

    /// A fresh suite per test — the migration flag must not leak between
    /// tests or across runs on the same simulator.
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BrevStoreProtectionTests.\(UUID().uuidString)")!
    }

    @Test("missing store root is created")
    func createsRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-protection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: root.path))

        BrevStoreProtection.applyProtection(root: root, fileManager: .default, defaults: freshDefaults())

        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test("existing tree is traversed without throwing and the migration is recorded")
    func protectsTree() throws {
        let defaults = freshDefaults()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-protection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("store.sqlite")
        try Data("x".utf8).write(to: file, options: .atomic)

        BrevStoreProtection.applyProtection(root: root, fileManager: .default, defaults: defaults)

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["store.sqlite"])
        #expect(defaults.bool(forKey: "BrevStoreProtection.migrationWalked"))
    }

    @Test("nil root is a no-op")
    func nilRootNoOp() {
        BrevStoreProtection.applyProtection(root: nil, fileManager: .default, defaults: freshDefaults())
    }
}
