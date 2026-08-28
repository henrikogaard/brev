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

@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeSendGuardPolicy")
struct ComposeSendGuardPolicyTests {
    @Test("attachment reminder warns when attachment language has no attachments")
    func attachmentReminderWarnsWhenAttachmentLanguageHasNoAttachments() {
        let warning = ComposeSendGuardPolicy.warning(
            for: Self.snapshot(subject: "Invoice", bodyText: "I attached the signed invoice."),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: true)
        )

        #expect(warning == .missingAttachment)
    }

    @Test("attachment reminder stays quiet when disabled or attachments exist")
    func attachmentReminderHonorsPreferenceAndExistingAttachments() {
        #expect(ComposeSendGuardPolicy.warning(
            for: Self.snapshot(bodyText: "See attached", hasAttachments: true),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: true)
        ) == nil)
        #expect(ComposeSendGuardPolicy.warning(
            for: Self.snapshot(bodyText: "See attached"),
            preferences: .init(attachmentReminderEnabled: false, externalRecipientWarningEnabled: true)
        ) == nil)
    }

    @Test("external recipient warning catches domains outside the sender account")
    func externalRecipientWarningCatchesOutsideDomains() {
        let warning = ComposeSendGuardPolicy.warning(
            for: Self.snapshot(to: ["ada@example.org", "grace@external.test"]),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: true)
        )

        #expect(warning == .externalRecipients)
    }

    @Test("external recipient warning ignores same-domain recipients and disabled preference")
    func externalRecipientWarningHonorsSameDomainAndPreference() {
        #expect(ComposeSendGuardPolicy.warning(
            for: Self.snapshot(to: ["Ada <ada@example.org>"], cc: ["team@example.org"]),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: true)
        ) == nil)
        #expect(ComposeSendGuardPolicy.warning(
            for: Self.snapshot(to: ["ada@external.test"]),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: false)
        ) == nil)
    }

    @Test("attachment reminder takes priority before external recipient warning")
    func attachmentReminderTakesPriorityBeforeExternalWarning() {
        let warning = ComposeSendGuardPolicy.warning(
            for: Self.snapshot(to: ["ada@external.test"], bodyText: "Please see attached."),
            preferences: .init(attachmentReminderEnabled: true, externalRecipientWarningEnabled: true)
        )

        #expect(warning == .missingAttachment)
    }

    private static func snapshot(
        fromEmail: String = "henrik@example.org",
        to: [String] = ["ada@example.org"],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String = "Status",
        bodyText: String = "Body",
        hasAttachments: Bool = false
    ) -> ComposeSendGuardSnapshot {
        ComposeSendGuardSnapshot(
            fromEmail: fromEmail,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            bodyText: bodyText,
            hasAttachments: hasAttachments
        )
    }
}
