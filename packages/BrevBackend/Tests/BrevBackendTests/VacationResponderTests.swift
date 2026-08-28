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

@Suite("Vacation responder")
struct VacationResponderTests {
    @Test("vacation responder settings survive coding")
    func vacationResponderSettingsSurviveCoding() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let settings = VacationResponderSettings(
            id: "ooo-1",
            name: "Summer break",
            isEnabled: true,
            message: "I am away this week.",
            schedule: VacationResponderSchedule(
                startsAt: start,
                endsAt: end,
                recurrence: .weekly(days: [.monday, .friday])
            ),
            excludedRecipients: ["alerts@example.org"],
            replyFrom: Correspondent(name: "Ada", email: "ada@example.org")
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(VacationResponderSettings.self, from: data)

        #expect(decoded == settings)
    }

    @Test("draft validation catches empty message and reversed dates")
    func draftValidationCatchesEmptyMessageAndReversedDates() {
        let draft = VacationResponderDraft(
            name: "OOO",
            isEnabled: true,
            message: "   ",
            startsAt: Date(timeIntervalSince1970: 200),
            endsAt: Date(timeIntervalSince1970: 100),
            excludedRecipients: ["not-an-email"]
        )

        #expect(draft.validationErrors.contains(.emptyMessage))
        #expect(draft.validationErrors.contains(.endsBeforeStart))
        #expect(draft.validationErrors.contains(.invalidExcludedRecipient("not-an-email")))
    }
}
