/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

import Foundation
import Testing

/// Guards the status and empty-state copy that the mail UI renders through
/// `String(localized:bundle:.module)`. A missing catalog entry silently falls
/// back to English, so a Norwegian interface would mix languages again.
@Suite("MailStatusCopyLocalization")
struct MailStatusCopyLocalizationTests {
    /// Runtime keys exactly as `String(localized:)` builds them. Interpolations
    /// become `%@`/`%lld` format specifiers rather than the raw `\(name)`
    /// source text.
    private static let statusCopyKeys = [
        // Action titles
        "Try Again",
        "Refresh",
        "Clear search",
        // Reuses the existing key from MessageListView's filters menu; the
        // catalog rejects two keys that differ only by case.
        "Clear Filters",
        // Load, refresh, and mutation failures
        "Couldn't refresh mail.",
        "Couldn't refresh folders.",
        "Couldn't load mailboxes.",
        "Couldn't switch mailboxes.",
        "Couldn't load messages.",
        "Couldn't run search.",
        "Couldn't load more messages.",
        "Couldn't update message.",
        "Some mailboxes couldn't load. %@",
        "That action is taking too long. The view has been unblocked — refresh to confirm the result.",
        // Reader statuses
        "Couldn't load message body.",
        "Couldn't load message",
        "Couldn't mark as read",
        "Couldn't mark this message as read.",
        "Couldn't respond to invite",
        "Couldn't send your invite response.",
        "Couldn't load calendar invite",
        "Couldn't load the calendar invite.",
        "Couldn't read calendar invite",
        "Brev couldn't parse \"%@\" as a calendar invite.",
        "Couldn't download \"%@\": %@",
        "Unknown error.",
        "Showing a preview only",
        "The full message couldn't be downloaded.",
        // Empty states
        "No folder selected",
        "Choose a folder from the sidebar.",
        "Something went wrong",
        "No messages",
        "No matching messages",
        "No matches",
        "No results for \"%@\".",
        "No messages match the current filters.",
        "No messages match this saved search.",
        "Messages you receive will appear here.",
        "Messages received today will appear here.",
        "Flagged messages will appear here.",
        "Snoozed messages will appear here.",
        "Messages marked done will appear here.",
        "Messages from your VIP senders will appear here.",
        // Calendar/Contacts/Tasks kept-cache banner
        "Showing cached data",
        "Last updated %@"
    ]

    @Test("mail status and empty-state copy carries Norwegian translations")
    func statusCopyCarriesNorwegianTranslations() throws {
        let strings = try Self.loadCatalogStrings()

        for key in Self.statusCopyKeys {
            let entry = strings[key] as? [String: Any]
            let localization = (entry?["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = localization?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String

            #expect(entry != nil, "missing catalog entry for \(key)")
            #expect(unit?["state"] as? String == "translated", "missing nb translation for \(key)")
            #expect(value?.isEmpty == false && value != key, "\(key) still falls back to English")
        }
    }

    @Test("skipped-mailbox status carries Norwegian plural translations")
    func skippedMailboxStatusCarriesNorwegianPlurals() throws {
        let strings = try Self.loadCatalogStrings()
        let key = "%lld mailboxes skipped because server search is unavailable."

        let entry = strings[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]

        for language in ["en", "nb"] {
            let variations = (localizations?[language] as? [String: Any])?["variations"] as? [String: Any]
            let plural = variations?["plural"] as? [String: Any]

            for form in ["one", "other"] {
                let unit = (plural?[form] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String

                #expect(unit?["state"] as? String == "translated", "missing \(language) plural \(form) for \(key)")
                #expect(value?.isEmpty == false, "empty \(language) plural \(form) for \(key)")
            }
        }

        let nbPlural = ((localizations?["nb"] as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        let one = ((nbPlural?["one"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        let other = ((nbPlural?["other"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String

        #expect(one != other, "Norwegian plural forms are identical, so the count reads wrong")
    }

    private static func loadCatalogStrings() throws -> [String: Any] {
        // Resolve from the source file so the check works from any runner
        // working directory, with the repository root as a fallback.
        let relativePath = "packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings"
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
