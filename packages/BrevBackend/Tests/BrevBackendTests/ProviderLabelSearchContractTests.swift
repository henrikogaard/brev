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

@testable import BrevBackend
import Foundation
import Testing

@Suite("Provider label and search contracts")
struct ProviderLabelSearchContractTests {
    @Test("label catalog entries round-trip and tolerate omitted optional fields")
    func labelCatalogEntryCodableBackcompat() throws {
        let label = ProviderLabel(
            id: "label-projects",
            name: "Projects",
            parentID: "label-work",
            kind: .user,
            visibility: ProviderLabelVisibility(
                sidebar: .shown,
                messageList: .shown
            ),
            color: ProviderLabelColor(
                foregroundHex: "#ffffff",
                backgroundHex: "#4285f4"
            ),
            counts: ProviderLabelCounts(
                messagesTotal: 12,
                messagesUnread: 3,
                threadsTotal: 8,
                threadsUnread: 2
            ),
            allowedOperations: [.rename, .delete, .setVisibility, .setColor, .applyToMessages]
        )

        let encoded = try JSONEncoder().encode(label)
        let decoded = try JSONDecoder().decode(ProviderLabel.self, from: encoded)
        #expect(decoded == label)

        let legacy = #"{"id":"INBOX","name":"Inbox","kind":"system"}"#
        let decodedLegacy = try JSONDecoder().decode(
            ProviderLabel.self,
            from: Data(legacy.utf8)
        )
        #expect(decodedLegacy.parentID == nil)
        #expect(decodedLegacy.visibility == .default)
        #expect(decodedLegacy.color == nil)
        #expect(decodedLegacy.counts == nil)

        let partialVisibility = #"{"sidebar":"hidden"}"#
        let decodedPartialVisibility = try JSONDecoder().decode(
            ProviderLabelVisibility.self,
            from: Data(partialVisibility.utf8)
        )
        #expect(decodedPartialVisibility.sidebar == .hidden)
        #expect(decodedPartialVisibility.messageList == .shown)
    }

    @Test("system labels cannot expose destructive or metadata mutation actions")
    func systemLabelsRemainImmutable() {
        let label = ProviderLabel(
            id: "STARRED",
            name: "Starred",
            kind: .system,
            allowedOperations: [
                .rename,
                .delete,
                .setVisibility,
                .setColor,
                .applyToMessages,
                .removeFromMessages,
            ]
        )

        #expect(label.kind == .system)
        #expect(label.allowedOperations == [.applyToMessages, .removeFromMessages])
        #expect(label.canRename == false)
        #expect(label.canDelete == false)
        #expect(label.canSetVisibility == false)
        #expect(label.canSetColor == false)
        #expect(label.canApplyToMessages)
        #expect(label.canRemoveFromMessages)
    }

    @Test("server search syntax descriptions round-trip with examples")
    func serverSearchSyntaxDescriptionCodable() throws {
        let description = ServerSearchSyntaxDescription(
            identifier: "native-search",
            displayName: "Server search",
            summary: "Searches the provider mailbox using its native query language.",
            examples: [
                ServerSearchSyntaxExample(
                    query: "from:alice@example.com",
                    explanation: "Messages sent by Alice."
                ),
                ServerSearchSyntaxExample(
                    query: "label:Projects",
                    explanation: "Messages carrying the Projects label."
                ),
            ],
            documentationURL: URL(string: "https://example.com/search")
        )

        let encoded = try JSONEncoder().encode(description)
        let decoded = try JSONDecoder().decode(
            ServerSearchSyntaxDescription.self,
            from: encoded
        )
        #expect(decoded == description)
        #expect(decoded.examples.count == 2)
    }
}
