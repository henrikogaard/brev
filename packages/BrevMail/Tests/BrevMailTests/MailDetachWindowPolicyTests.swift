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
import Testing
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

@Suite("MailDetachWindowPolicy")
struct MailDetachWindowPolicyTests {
    @Test("iPad regular width detaches into a window")
    func iPadRegularDetaches() {
        #expect(MailDetachWindowPolicy.shouldDetach(idiom: .pad, isRegularWidth: true))
    }

    @Test("iPad compact and iPhone use a sheet")
    func compactUsesSheet() {
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .pad, isRegularWidth: false))
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .phone, isRegularWidth: false))
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .phone, isRegularWidth: true))
    }

    // The UIKit bridge only compiles under an iOS toolchain; on the macOS
    // `swift test` runner these are skipped (the pure cases above cover the
    // policy). They guard the centralized mapping against drift in iOS CI.
    #if canImport(UIKit)
    @Test("UIKit convenience detaches only for iPad at regular width")
    func uiKitConvenienceMapping() {
        #expect(MailDetachWindowPolicy.shouldDetach(idiom: .pad, horizontalSizeClass: .regular))
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .pad, horizontalSizeClass: .compact))
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .pad, horizontalSizeClass: nil))
        #expect(!MailDetachWindowPolicy.shouldDetach(idiom: .phone, horizontalSizeClass: .regular))
    }

    @Test("MailWindowIdiom maps every non-iPad idiom to phone")
    func idiomBridgeMapping() {
        #expect(MailWindowIdiom(.pad) == .pad)
        #expect(MailWindowIdiom(.phone) == .phone)
        #expect(MailWindowIdiom(.unspecified) == .phone)
        #expect(MailWindowIdiom(.tv) == .phone)
    }
    #endif
}
