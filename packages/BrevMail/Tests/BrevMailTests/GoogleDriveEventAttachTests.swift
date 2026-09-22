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

import BrevBackend
import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

/// Event-side Drive attachment coverage (#14): the pick-to-link
/// mapping, editing-model Drive eligibility, and draft round-trip.
@Suite("GoogleDriveEventAttach")
@MainActor
struct GoogleDriveEventAttachTests {
    private nonisolated static func configuration() -> GoogleOAuthAccountConfiguration {
        GoogleOAuthAccountConfiguration(
            subject: "sub",
            email: "user@gmail.com",
            grantedScopes: ["mail"],
            platform: .macOS
        )
    }

    @Test("a picked file maps to a link attachment")
    func pickToAttachment() {
        let pick = GoogleDrivePick(
            id: "f1",
            name: "Deck.pdf",
            mimeType: "application/pdf",
            url: "https://drive.google.com/file/d/f1/view"
        )
        let attachment = GoogleDriveEventAttachSheet.attachment(for: pick)
        #expect(attachment.url == "https://drive.google.com/file/d/f1/view")
        #expect(attachment.title == "Deck.pdf")
        #expect(attachment.mimeType == "application/pdf")
    }

    @Test("a pick without a web link falls back to the file URL form")
    func pickWithoutURL() {
        let pick = GoogleDrivePick(id: "f2", name: "Doc", mimeType: "text/plain")
        let attachment = GoogleDriveEventAttachSheet.attachment(for: pick)
        #expect(
            attachment.url
                == "https://drive.google.com/file/d/f2/view"
        )
    }

    @Test("draft round-trips attachments into the event")
    func draftRoundTrip() {
        var draft = CalendarEventDraft(start: Date())
        draft.attachments = [
            PIMEventAttachment(
                url: "https://drive.google.com/file/d/f1/view",
                title: "Deck"
            )
        ]
        let event = draft.makeEvent(sourceID: "s1", collectionID: "c1")
        #expect(event.attachments.count == 1)
        #expect(event.attachments.first?.title == "Deck")

        let editing = CalendarEventDraft(event: event)
        #expect(editing.attachments == draft.attachments)
    }

    @Test("Drive attach is offered only for Gmail-linked sources")
    func driveEligibility() async throws {
        let feature = GoogleDriveFeature { _ in Self.configuration() }
        let googleSource = PIMSource(
            id: "g-cal",
            kind: .calendar,
            provider: .google,
            linkedAccountID: "acct1",
            displayName: "Google",
            enabledCapabilities: [.read, .write],
            status: .ready
        )
        let davSource = PIMSource(
            id: "dav-cal",
            kind: .calendar,
            provider: .calDAV,
            displayName: "DAV",
            enabledCapabilities: [.read, .write],
            status: .ready
        )
        let model = try await makeModel(
            sources: [googleSource, davSource],
            collections: [
                "g-cal": [
                    PIMCollection(
                        id: "g-col",
                        sourceID: "g-cal",
                        kind: .calendar,
                        displayName: "Work",
                        providerKey: "primary"
                    )
                ],
                "dav-cal": [
                    PIMCollection(
                        id: "d-col",
                        sourceID: "dav-cal",
                        kind: .calendar,
                        displayName: "Work",
                        providerKey: "/dav/"
                    )
                ],
            ],
            driveFeature: feature
        )
        await model.load()

        #expect(model.driveAttachAccountID(for: "g-col") == "acct1")
        #expect(model.driveAttachAccountID(for: "d-col") == nil)
        #expect(model.driveAttachAccountID(for: "unknown") == nil)
    }

    // MARK: - Doubles

    private actor SourceStore: PIMSourceStore {
        var records: [PIMSource.ID: PIMSource] = [:]
        func allSources() async throws -> [PIMSource] {
            Array(records.values)
        }

        func save(_ source: PIMSource) async throws {
            records[source.id] = source
        }

        func deleteSource(id: PIMSource.ID) async throws {
            records[id] = nil
        }
    }

    private actor CredentialStore: CalDAVCredentialStore {
        func credential(for account: String) async throws -> CalDAVCredential? {
            nil
        }

        func setCredential(
            _ credential: CalDAVCredential,
            for account: String
        ) async throws {}
        func deleteCredential(for account: String) async throws {}
    }

    private actor LocalDataStore: PIMSourceLocalDataStore {
        func deleteSyncAndDraftData(for sourceID: PIMSource.ID) async throws {}
        func deleteCachedContent(for sourceID: PIMSource.ID) async throws {}
        func markCacheDisconnected(for sourceID: PIMSource.ID) async throws {}
    }

    private actor CollectionStore: PIMCollectionStore {
        var records: [PIMSource.ID: [PIMCollection]] = [:]
        func collections(
            for sourceID: PIMSource.ID
        ) async throws -> [PIMCollection] {
            records[sourceID] ?? []
        }

        func saveCollections(
            _ collections: [PIMCollection],
            for sourceID: PIMSource.ID
        ) async throws {
            records[sourceID] = collections
        }

        func deleteCollections(for sourceID: PIMSource.ID) async throws {
            records[sourceID] = nil
        }
    }

    private struct StubWriter: CalendarEventWriting {
        func canWrite(
            source: PIMSource,
            collection: PIMCollection
        ) -> Bool {
            source.enabledCapabilities.contains(.write)
                && !collection.isReadOnly
        }

        func create(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent { event }
        func update(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws -> PIMEvent { event }
        func delete(
            _ event: PIMEvent,
            in collection: PIMCollection,
            source: PIMSource
        ) async throws {}
    }

    private func makeModel(
        sources: [PIMSource],
        collections: [PIMSource.ID: [PIMCollection]],
        driveFeature: GoogleDriveFeature
    ) async throws -> CalendarEditingModel {
        let sourceStore = SourceStore()
        for source in sources {
            try await sourceStore.save(source)
        }
        let coordinator = PIMSourceCoordinator(
            store: sourceStore,
            credentials: CredentialStore(),
            localData: LocalDataStore()
        )
        let collectionStore = CollectionStore()
        for (sourceID, list) in collections {
            try await collectionStore.saveCollections(list, for: sourceID)
        }
        return CalendarEditingModel(
            writeService: StubWriter(),
            coordinator: coordinator,
            collectionService: PIMCollectionService(
                coordinator: coordinator,
                store: collectionStore,
                credentials: CredentialStore()
            ),
            driveFeature: driveFeature
        )
    }
}
