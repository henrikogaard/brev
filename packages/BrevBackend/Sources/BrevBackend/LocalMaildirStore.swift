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

/// Durable Maildir-on-disk store behind `LocalMailBackend` (ADR-0077).
///
/// Each local folder is `<root>/<folder-uuid>/{cur,new,tmp}` with one RFC 5322
/// file per message; flags ride in the `:2,<flags>` filename suffix the
/// existing `MaildirReader.parseFilename` grammar understands. Folder names
/// and hierarchy live in a small `folders.json` manifest next to the folders.
///
/// The root lives outside every cache root, so no retention sweep, body-cache
/// prune, or "Clear cache" action can touch it; the files are the authority
/// and survive Brev's schema, caches, and account removals.
public actor LocalMaildirStore {
    /// One entry in the `folders.json` manifest.
    public struct FolderRecord: Codable, Sendable, Hashable {
        /// Stable storage identity — also the on-disk directory name.
        public var id: String
        public var name: String
        public var parentID: String?

        public init(id: String, name: String, parentID: String? = nil) {
            self.id = id
            self.name = name
            self.parentID = parentID
        }
    }

    /// A stored message: which folder it sits in and its Maildir unique id.
    public struct LocalMessageRef: Sendable, Hashable {
        public let folderID: String
        public let uniqueID: String

        public init(folderID: String, uniqueID: String) {
            self.folderID = folderID
            self.uniqueID = uniqueID
        }
    }

    /// A message read back from disk with its flags and raw bytes.
    public struct StoredMessage: Sendable {
        public let ref: LocalMessageRef
        public let flags: Set<MaildirFlag>
        public let data: Data
    }

    /// Default on-disk root: `~/Library/Application Support/Brev/LocalFolders`.
    public static var defaultRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brev/LocalFolders", isDirectory: true)
    }

    /// Errors thrown by the store.
    public enum StoreError: LocalizedError, Equatable {
        case folderNotFound(String)
        case messageNotFound(String)
        case duplicateFolderName(String)
        case emptyFolderName

        public var errorDescription: String? {
            switch self {
            case .folderNotFound(let id):
                String(localized: "Local folder \(id) does not exist.", bundle: .module)
            case .messageNotFound(let id):
                String(localized: "Local message \(id) does not exist.", bundle: .module)
            case .duplicateFolderName(let name):
                String(localized: "A local folder named “\(name)” already exists.", bundle: .module)
            case .emptyFolderName:
                String(localized: "Local folder names can't be empty.", bundle: .module)
            }
        }
    }

    private let root: URL
    private var records: [FolderRecord]?

    public init(rootURL: URL = LocalMaildirStore.defaultRootURL) {
        root = rootURL
    }

    /// The store's root directory (for backup traversal and diagnostics).
    public nonisolated var rootURL: URL { root }

    /// The manifest's folder records in insertion order.
    public func folders() throws -> [FolderRecord] {
        try loadManifest()
    }

    /// Creates a folder, its `cur/new/tmp` directories, and the manifest entry.
    public func createFolder(name: String, parentID: String? = nil) throws -> FolderRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyFolderName }
        var manifest = try loadManifest()
        if manifest.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                && $0.parentID == parentID
        }) {
            throw StoreError.duplicateFolderName(trimmed)
        }
        let record = FolderRecord(id: UUID().uuidString.lowercased(), name: trimmed, parentID: parentID)
        let directory = folderDirectory(id: record.id)
        for sub in ["cur", "new", "tmp"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
        manifest.append(record)
        try saveManifest(manifest)
        return record
    }

    /// Renames a folder in the manifest; files do not move.
    public func renameFolder(id: String, name: String) throws -> FolderRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyFolderName }
        var manifest = try loadManifest()
        guard let index = manifest.firstIndex(where: { $0.id == id }) else {
            throw StoreError.folderNotFound(id)
        }
        manifest[index].name = trimmed
        try saveManifest(manifest)
        return manifest[index]
    }

    /// Deletes a folder and its descendants, including all message files.
    /// This is the only destructive path — it deletes user-owned mail.
    public func deleteFolder(id: String) throws {
        var manifest = try loadManifest()
        guard manifest.contains(where: { $0.id == id }) else {
            throw StoreError.folderNotFound(id)
        }
        var doomed = Set([id])
        var frontier = [id]
        while let current = frontier.popLast() {
            for record in manifest where record.parentID == current && doomed.insert(record.id).inserted {
                frontier.append(record.id)
            }
        }
        manifest.removeAll { doomed.contains($0.id) }
        for folderID in doomed {
            try? FileManager.default.removeItem(at: folderDirectory(id: folderID))
        }
        try saveManifest(manifest)
    }

    /// Appends a message: writes to `tmp/`, fsyncs, then renames into `cur/`
    /// with the Maildir flag suffix so the file is never observed half-written.
    public func append(
        rawMessage: Data,
        flags: Set<MaildirFlag>,
        folderID: String
    ) throws -> LocalMessageRef {
        _ = try folder(id: folderID)
        let uniqueID = Self.makeUniqueID()
        let tmpURL = folderDirectory(id: folderID)
            .appendingPathComponent("tmp")
            .appendingPathComponent(uniqueID)
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmpURL)
        do {
            try handle.write(contentsOf: rawMessage)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
        let finalName = "\(uniqueID):2,\(Self.flagString(flags))"
        let finalURL = folderDirectory(id: folderID)
            .appendingPathComponent("cur")
            .appendingPathComponent(finalName)
        try FileManager.default.moveItem(at: tmpURL, to: finalURL)
        return LocalMessageRef(folderID: folderID, uniqueID: uniqueID)
    }

    /// Re-encodes a stored message's flags by renaming its file.
    public func setFlags(_ flags: Set<MaildirFlag>, for ref: LocalMessageRef) throws {
        let curURL = folderDirectory(id: ref.folderID).appendingPathComponent("cur")
        let newURL = folderDirectory(id: ref.folderID).appendingPathComponent("new")
        for directory in [curURL, newURL] {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in contents {
                let parsed = MaildirReader.parseFilename(file.lastPathComponent)
                guard parsed.uniqueID == ref.uniqueID else { continue }
                let renamed = directory.appendingPathComponent(
                    "\(ref.uniqueID):2,\(Self.flagString(flags))"
                )
                if file != renamed {
                    try FileManager.default.moveItem(at: file, to: renamed)
                }
                return
            }
        }
        throw StoreError.messageNotFound(ref.uniqueID)
    }

    /// Current flags of a stored message, or nil when absent.
    public func flags(for ref: LocalMessageRef) throws -> Set<MaildirFlag> {
        for sub in ["cur", "new"] {
            let directory = folderDirectory(id: ref.folderID).appendingPathComponent(sub)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in contents {
                let parsed = MaildirReader.parseFilename(file.lastPathComponent)
                if parsed.uniqueID == ref.uniqueID {
                    return parsed.flags
                }
            }
        }
        throw StoreError.messageNotFound(ref.uniqueID)
    }

    /// Permanently deletes one message file.
    public func remove(_ ref: LocalMessageRef) throws {
        for sub in ["cur", "new"] {
            let directory = folderDirectory(id: ref.folderID).appendingPathComponent(sub)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in contents where MaildirReader.parseFilename(file.lastPathComponent).uniqueID == ref.uniqueID {
                try FileManager.default.removeItem(at: file)
                return
            }
        }
        throw StoreError.messageNotFound(ref.uniqueID)
    }

    /// Streams every stored message in a folder (cur + new; tmp is skipped).
    public func enumerate(folderID: String) throws -> [StoredMessage] {
        _ = try folder(id: folderID)
        var stored: [StoredMessage] = []
        for sub in ["cur", "new"] {
            let directory = folderDirectory(id: folderID).appendingPathComponent(sub)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where !file.hasDirectoryPath {
                let parsed = MaildirReader.parseFilename(file.lastPathComponent)
                guard let data = try? Data(contentsOf: file) else { continue }
                stored.append(StoredMessage(
                    ref: LocalMessageRef(folderID: folderID, uniqueID: parsed.uniqueID),
                    flags: parsed.flags,
                    data: data
                ))
            }
        }
        return stored
    }

    /// Raw bytes of one stored message.
    public func data(for ref: LocalMessageRef) throws -> Data {
        for sub in ["cur", "new"] {
            let directory = folderDirectory(id: ref.folderID).appendingPathComponent(sub)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in contents where MaildirReader.parseFilename(file.lastPathComponent).uniqueID == ref.uniqueID {
                return try Data(contentsOf: file)
            }
        }
        throw StoreError.messageNotFound(ref.uniqueID)
    }

    /// Total bytes of all local folders (manifest excluded). The only sizing
    /// surface — there is deliberately no cap (ADR-0077 decision 6).
    public func size() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent != "folders.json",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Sorted Maildir flag letters (`:2,<flags>` grammar).
    public static func flagString(_ flags: Set<MaildirFlag>) -> String {
        String(flags.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue))
    }

    private static func makeUniqueID() -> String {
        "\(Int(Date().timeIntervalSince1970)).\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    private func folderDirectory(id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private var manifestURL: URL {
        root.appendingPathComponent("folders.json")
    }

    private func loadManifest() throws -> [FolderRecord] {
        if let records { return records }
        guard let data = try? Data(contentsOf: manifestURL) else {
            records = []
            return []
        }
        let decoded = (try? BackupManifestDecoder.decode(data)) ?? []
        records = decoded
        return decoded
    }

    private func saveManifest(_ manifest: [FolderRecord]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        records = manifest
    }

    private func folder(id: String) throws -> FolderRecord {
        guard let record = try loadManifest().first(where: { $0.id == id }) else {
            throw StoreError.folderNotFound(id)
        }
        return record
    }
}

/// Small wrapper so the manifest decode failure path stays non-throwing.
private enum BackupManifestDecoder {
    static func decode(_ data: Data) throws -> [LocalMaildirStore.FolderRecord] {
        try JSONDecoder().decode([LocalMaildirStore.FolderRecord].self, from: data)
    }
}
