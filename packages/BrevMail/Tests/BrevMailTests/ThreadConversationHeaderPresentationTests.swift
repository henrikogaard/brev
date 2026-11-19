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
@testable import BrevMail
import Testing

/// The thread header's visible participant line (#306 slice 4).
@Suite("Thread conversation header presentation")
struct ThreadConversationHeaderPresentationTests {
    private let maya = Correspondent(name: "Maya Okafor", email: "maya@example.com")
    private let daniel = Correspondent(name: "Daniel Reyes", email: "daniel@example.com")
    private let priya = Correspondent(name: nil, email: "priya@example.com")
    private let sam = Correspondent(name: "Sam Lee", email: "sam@example.com")

    @Test("no participants yields no line")
    func empty() {
        #expect(ThreadConversationHeaderPresentation.participantLine([]) == nil)
    }

    @Test("one and two participants are named in full")
    func fewNames() {
        #expect(ThreadConversationHeaderPresentation.participantLine([maya]) == "Maya Okafor")
        #expect(ThreadConversationHeaderPresentation.participantLine([maya, daniel]) == "Maya Okafor and Daniel Reyes")
    }

    @Test("three participants are all named; the address stands in for a missing name")
    func threeNames() {
        #expect(ThreadConversationHeaderPresentation.participantLine([maya, daniel, priya])
            == "Maya Okafor, Daniel Reyes, and priya@example.com")
    }

    @Test("more than three participants collapse into a count")
    func manyNames() {
        #expect(ThreadConversationHeaderPresentation.participantLine([maya, daniel, priya, sam])
            == "Maya Okafor, Daniel Reyes, and 2 others")
    }
}
