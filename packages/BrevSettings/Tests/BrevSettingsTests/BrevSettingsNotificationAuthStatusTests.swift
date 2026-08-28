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
import Foundation
import Testing
import UserNotifications

@Suite("BrevSettingsNotificationAuthStatus")
struct BrevSettingsNotificationAuthStatusTests {
    @Test("maps every system status to a stable BrevSettings case")
    func mapsEverySystemStatus() {
        #expect(BrevSettingsNotificationAuthStatus.map(.notDetermined) == .notDetermined)
        #expect(BrevSettingsNotificationAuthStatus.map(.denied) == .denied)
        #expect(BrevSettingsNotificationAuthStatus.map(.authorized) == .authorized)
        #expect(BrevSettingsNotificationAuthStatus.map(.provisional) == .provisional)
        #if os(iOS)
        #expect(BrevSettingsNotificationAuthStatus.map(.ephemeral) == .ephemeral)
        #endif
    }

    @Test("display strings are non-empty for every case")
    func displayStringsAreNonEmpty() {
        for status in BrevSettingsNotificationAuthStatus.allCases {
            #expect(!status.displayTitle.isEmpty)
            #expect(!status.displaySubtitle.isEmpty)
        }
    }
}
