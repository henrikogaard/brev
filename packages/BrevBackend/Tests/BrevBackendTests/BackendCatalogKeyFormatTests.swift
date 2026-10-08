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

/// Guards the BrevBackend string catalog. `String(localized:)` looks up a
/// `%@`/`%lld` format-specifier key, so a catalog entry keyed `\(expression)`
/// can never match and silently falls back to English.
@Suite("BackendCatalogKeyFormat")
struct BackendCatalogKeyFormatTests {
    @Test("no catalog key keeps raw string-interpolation source")
    func noCatalogKeyKeepsRawInterpolationSource() throws {
        let strings = try Self.loadBackendCatalogStrings()

        for key in strings.keys {
            #expect(!key.contains("\\("), "catalog key keeps raw interpolation source: \(key)")
        }
    }

    @Test("no two catalog keys generate the same symbol")
    func catalogKeysGenerateUniqueSymbols() throws {
        // xcstringstool derives a Swift symbol from each key: format
        // specifiers become the argument signature and the remaining literal
        // text camelCases into the base name. Two keys that only differ in
        // case or punctuation collide in the generated code and fail the
        // build.
        let strings = try Self.loadBackendCatalogStrings()
        var firstSeen: [String: String] = [:]
        var collisions: [String] = []

        for key in strings.keys.sorted() {
            let fingerprint = Self.generatedSymbolAndSignature(for: key)
            if let existing = firstSeen[fingerprint] {
                collisions.append("'\(existing)' collides with '\(key)'")
            } else {
                firstSeen[fingerprint] = key
            }
        }

        #expect(collisions.isEmpty, "catalog keys generate duplicate symbols: \(collisions.joined(separator: "; "))")
    }

    /// Approximates xcstringstool's key normalization: specifiers form the
    /// signature suffix and the literal text is tokenized on non-alphanumerics
    /// and camelCased with a lowercased first token.
    private static func generatedSymbolAndSignature(for key: String) -> String {
        var literal = ""
        var signature: [String] = []
        var index = key.startIndex
        while index < key.endIndex {
            if key[index] == "%", let specifier = Self.specifierBody(at: index, in: key) {
                signature.append(specifier.body)
                index = specifier.end
                continue
            }
            literal.append(key[index])
            index = key.index(after: index)
        }

        let tokens = literal
            .components(separatedBy: Self.nonAlphanumerics)
            .filter { !$0.isEmpty }
        guard let first = tokens.first else { return signature.joined(separator: ",") }
        let symbol = first.lowercased() + tokens.dropFirst().map { token in
            token.prefix(1).uppercased() + token.dropFirst().lowercased()
        }.joined()
        return symbol + "§" + signature.joined(separator: ",")
    }

    /// Matches a printf-style specifier at `index`, accepting an optional
    /// `N$` position. `%%` is a literal percent and returns nil.
    private static func specifierBody(at index: String.Index, in key: String) -> (body: String, end: String.Index)? {
        var cursor = key.index(after: index)
        while cursor < key.endIndex, key[cursor].isNumber {
            cursor = key.index(after: cursor)
        }
        if key.index(after: index) < cursor {
            guard cursor < key.endIndex, key[cursor] == "$" else { return nil }
            cursor = key.index(after: cursor)
        }
        // Longest bodies first so `%lld` isn't consumed as `%l`.
        for body in ["lld", "llu", "llf", "llx", "@", "d", "D", "u", "U", "x", "X", "f", "F", "i", "o", "s", "c", "C", "p"]
            where key[cursor...].hasPrefix(body) {
            return (body, key.index(cursor, offsetBy: body.count))
        }
        return nil
    }

    private static let nonAlphanumerics = CharacterSet.alphanumerics.inverted

    private static func loadBackendCatalogStrings() throws -> [String: Any] {
        // Resolve from the source file so the check works from any runner
        // working directory, with the repository root as a fallback.
        let relativePath = "packages/BrevBackend/Sources/BrevBackend/Resources/Localizable.xcstrings"
        var candidates: [URL] = []
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 7 {
            candidates.append(directory.appendingPathComponent(relativePath))
            directory.deleteLastPathComponent()
        }
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 7 {
            candidates.append(directory.appendingPathComponent(relativePath))
            directory.deleteLastPathComponent()
        }

        guard let catalogURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CatalogLookupError.notFound
        }
        let data = try Data(contentsOf: catalogURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(root?["strings"] as? [String: Any])
    }

    private enum CatalogLookupError: Error {
        case notFound
    }
}
