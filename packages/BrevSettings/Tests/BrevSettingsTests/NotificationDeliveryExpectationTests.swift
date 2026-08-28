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

@testable import BrevSettings
import Testing

@Suite("NotificationDeliveryExpectation")
struct NotificationDeliveryExpectationTests {
    @Test("settings copy distinguishes live local alerts from best-effort closed-app delivery")
    func settingsCopyDistinguishesDeliveryModes() {
        let copy = NotificationDeliveryExpectation.settingsCalloutMessage

        #expect(copy.contains("While Brev is running"))
        #expect(copy.contains("best-effort background refresh"))
        #expect(copy.contains("does not operate a push relay"))
        #expect(copy.contains("does not promise closed-app delivery"))
    }

    @Test("quiet-hours copy describes local notification suppression")
    func quietHoursCopyDescribesLocalSuppression() {
        let copy = NotificationDeliveryExpectation.quietHoursCalloutMessage

        #expect(copy.contains("local notifications"))
        #expect(copy.contains("sync and background refresh continue"))
        #expect(!copy.contains("push"))
        #expect(!copy.contains("server"))
    }
}
