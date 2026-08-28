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

@testable import BrevAvatars
import Testing

@Suite("AvatarViewResolutionRequest")
struct AvatarViewResolutionRequestTests {
    @Test("changing any avatar preference changes the view resolution request")
    func changingAvatarPreferencesChangesViewResolutionRequest() {
        let base = AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: "Alex",
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: false,
                useFavicon: false
            )
        )

        #expect(base != AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: "Alex",
            preferences: AvatarPreferences(
                useContacts: false,
                useGravatar: false,
                useBIMI: false,
                useFavicon: false
            )
        ))
        #expect(base != AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: "Alex",
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: true,
                useBIMI: false,
                useFavicon: false
            )
        ))
        #expect(base != AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: "Alex",
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: true,
                useFavicon: false
            )
        ))
        #expect(base != AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: "Alex",
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: false,
                useFavicon: true
            )
        ))
    }

    @Test("request exposes the preferences used for resolving")
    func requestExposesPreferencesUsedForResolving() {
        let preferences = AvatarPreferences(
            useContacts: false,
            useGravatar: true,
            useBIMI: true,
            useFavicon: false
        )
        let request = AvatarViewResolutionRequest(
            email: "alex@example.test",
            displayName: nil,
            preferences: preferences
        )

        #expect(request.preferences == preferences)
    }
}
