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

/// Reads and writes `WidgetSnapshot.json` inside the App Group container.
///
/// Every failure degrades to nil / a silent no-op: an unsigned local
/// build without the group entitlement, a missing container, or a
/// schema the extension doesn't understand must never take the widget
/// or the app down (ADR-0083 risk section).
public struct WidgetSnapshotStore: Sendable {
    /// The App Group both app targets and the widget extensions share.
    public static let appGroupID = "group.eu.brevmail.brev"

    /// File name inside the container; kept stable across versions so a
    /// stale file from an older install can still be read or replaced.
    public static let fileName = "WidgetSnapshot.json"

    private let fileURL: URL?

    /// - Parameter directory: override for tests; `nil` selects the App
    ///   Group container, resolving to no storage when it is unavailable.
    public init(directory: URL? = WidgetSnapshotStore.defaultDirectory()) {
        fileURL = directory?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Resolves the App Group container directory, or nil when the
    /// entitlement/container isn't available in this process.
    public static func defaultDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Decodes the snapshot, returning nil on any read/parse/version
    /// failure so the widget can render its empty state.
    public func load() -> WidgetSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder.snapshot.decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }

    /// Atomically replaces the snapshot file; failures are ignored —
    /// the widget simply keeps the previous file's content.
    public func save(_ snapshot: WidgetSnapshot) {
        guard let fileURL,
              let data = try? JSONEncoder.snapshot.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static let snapshot: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
}

private extension JSONDecoder {
    static let snapshot: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
