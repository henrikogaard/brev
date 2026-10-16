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

@Suite("CalendarDriveSaveEligibility")
@MainActor
struct CalendarDriveSaveEligibilityTests {
    private let attachment = PIMEventAttachment(
        url: "https://drive.google.com/file/d/file_1/view"
    )

    @Test("read-only source with a linked eligible account resolves")
    func readOnlySource() async {
        let state = Self.state()
        let result = await CalendarDriveSaveEligibility.resolve(
            eventID: state.event.id,
            attachment: attachment,
            feature: Self.feature(),
            state: { state }
        )

        #expect(result?.accountID == "acct1")
        #expect(result?.sourceID == "source")
        #expect(result?.collectionID == "collection")
    }

    @Test("missing account or attachment membership does not resolve")
    func absentIdentityDoesNotResolve() async {
        let unlinked = Self.state(linkedAccountID: nil)
        let linked = Self.state()
        let wrongCollection = Self.state(collectionSourceID: "other")
        let missingAttachment = PIMEventAttachment(
            url: "https://drive.google.com/file/d/other"
        )

        let noAccount = await CalendarDriveSaveEligibility.resolve(
            eventID: unlinked.event.id,
            attachment: attachment,
            feature: Self.feature(),
            state: { unlinked }
        )
        let noAttachment = await CalendarDriveSaveEligibility.resolve(
            eventID: unlinked.event.id,
            attachment: missingAttachment,
            feature: Self.feature(),
            state: { unlinked }
        )
        let ineligibleAccount = await CalendarDriveSaveEligibility.resolve(
            eventID: linked.event.id,
            attachment: attachment,
            feature: GoogleDriveFeature(configuration: { _ in nil }),
            state: { linked }
        )
        let mismatchedCollection = await CalendarDriveSaveEligibility.resolve(
            eventID: wrongCollection.event.id,
            attachment: attachment,
            feature: Self.feature(),
            state: { wrongCollection }
        )

        #expect(noAccount == nil)
        #expect(noAttachment == nil)
        #expect(ineligibleAccount == nil)
        #expect(mismatchedCollection == nil)
    }

    @Test("source or linked account replacement during eligibility is rejected")
    func replacementDuringEligibility() async {
        let gate = GoogleDriveSaveTestGate()
        let original = Self.state()
        var current = original
        let configuration = Self.configuration()
        let feature = GoogleDriveFeature(
            configuration: { _ in
                await gate.pause()
                return configuration
            }
        )
        let pending = Task {
            await CalendarDriveSaveEligibility.resolve(
                eventID: original.event.id,
                attachment: attachment,
                feature: feature,
                state: { current }
            )
        }

        await gate.waitUntilEntered()
        current = Self.state(linkedAccountID: "acct2")
        await gate.release()

        #expect(await pending.value == nil)
    }

    @Test("source replacement during eligibility is rejected")
    func sourceReplacementDuringEligibility() async {
        let gate = GoogleDriveSaveTestGate()
        let original = Self.state()
        var current = original
        let configuration = Self.configuration()
        let feature = GoogleDriveFeature(
            configuration: { _ in
                await gate.pause()
                return configuration
            }
        )
        let pending = Task {
            await CalendarDriveSaveEligibility.resolve(
                eventID: original.event.id,
                attachment: attachment,
                feature: feature,
                state: { current }
            )
        }

        await gate.waitUntilEntered()
        current = Self.state(sourceID: "replacement")
        await gate.release()

        #expect(await pending.value == nil)
    }

    @Test("removed attachment during eligibility is rejected")
    func attachmentRemovalDuringEligibility() async {
        let gate = GoogleDriveSaveTestGate()
        let original = Self.state()
        var current = original
        let configuration = Self.configuration()
        let feature = GoogleDriveFeature(
            configuration: { _ in
                await gate.pause()
                return configuration
            }
        )
        let pending = Task {
            await CalendarDriveSaveEligibility.resolve(
                eventID: original.event.id,
                attachment: attachment,
                feature: feature,
                state: { current }
            )
        }

        await gate.waitUntilEntered()
        current = Self.state(includeAttachment: false)
        await gate.release()

        #expect(await pending.value == nil)
    }

    @Test("replaced attachment during eligibility is rejected")
    func attachmentReplacementDuringEligibility() async {
        let gate = GoogleDriveSaveTestGate()
        let original = Self.state()
        var current = original
        let configuration = Self.configuration()
        let feature = GoogleDriveFeature(
            configuration: { _ in
                await gate.pause()
                return configuration
            }
        )
        let pending = Task {
            await CalendarDriveSaveEligibility.resolve(
                eventID: original.event.id,
                attachment: attachment,
                feature: feature,
                state: { current }
            )
        }

        await gate.waitUntilEntered()
        current = Self.state(
            attachment: PIMEventAttachment(
                url: attachment.url,
                title: "Replaced"
            )
        )
        await gate.release()

        #expect(await pending.value == nil)
    }

    @Test("an open request rejects replaced event, source, collection, or attachment state")
    func openRequestTracksCurrentState() async throws {
        let original = Self.state()
        let resolved = try #require(await CalendarDriveSaveEligibility.resolve(
            eventID: original.event.id,
            attachment: attachment,
            feature: Self.feature(),
            state: { original }
        ))
        #expect(resolved.isCurrent(original))
        #expect(!resolved.isCurrent(nil))

        var event = original.event
        event.summary = "Replacement"
        #expect(!resolved.isCurrent(CalendarDriveSaveState(
            event: event,
            collection: original.collection,
            source: original.source
        )))
        var collection = original.collection
        collection.displayName = "Replacement"
        #expect(!resolved.isCurrent(CalendarDriveSaveState(
            event: original.event,
            collection: collection,
            source: original.source
        )))
        var source = original.source
        source.displayName = "Replacement"
        #expect(!resolved.isCurrent(CalendarDriveSaveState(
            event: original.event,
            collection: original.collection,
            source: source
        )))
        #expect(!resolved.isCurrent(Self.state(linkedAccountID: "acct2")))
        #expect(!resolved.isCurrent(Self.state(includeAttachment: false)))
        #expect(!resolved.isCurrent(Self.state(attachment: PIMEventAttachment(
            url: attachment.url,
            title: "Replacement"
        ))))
    }

    private static func feature() -> GoogleDriveFeature {
        let configuration = Self.configuration()
        return GoogleDriveFeature(configuration: { _ in configuration })
    }

    private static func configuration() -> GoogleOAuthAccountConfiguration {
        GoogleOAuthAccountConfiguration(
            subject: "subject",
            email: "user@gmail.com",
            grantedScopes: [],
            platform: .macOS
        )
    }

    private static func state(
        linkedAccountID: String? = "acct1",
        sourceID: String = "source",
        includeAttachment: Bool = true,
        collectionSourceID: String? = nil,
        attachment: PIMEventAttachment? = nil
    )
        -> CalendarDriveSaveState {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let source = PIMSource(
            id: sourceID,
            kind: .calendar,
            provider: .google,
            linkedAccountID: linkedAccountID,
            displayName: "Google",
            enabledCapabilities: [.read],
            status: .ready,
            createdAt: start,
            updatedAt: start
        )
        let collection = PIMCollection(
            id: "collection",
            sourceID: collectionSourceID ?? sourceID,
            kind: .calendar,
            displayName: "Work",
            isReadOnly: true,
            isPrimary: true,
            supportsSyncToken: true,
            providerKey: "collection",
            isVisible: true,
            updatedAt: start
        )
        let event = PIMEvent(
            id: "event",
            sourceID: source.id,
            collectionID: collection.id,
            providerItemKey: "event",
            attachments: includeAttachment ? [
                attachment
                    ?? PIMEventAttachment(
                        url: "https://drive.google.com/file/d/file_1/view"
                    ),
            ] : [],
            syncedAt: start
        )
        return CalendarDriveSaveState(
            event: event,
            collection: collection,
            source: source
        )
    }
}
