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

#if os(iOS)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SwiftUI
import Testing
import UIKit

/// Verifies that the expanded iOS `ThreadMessageCard` aligns its trailing
/// metadata cluster (timestamp, collapse chevron, and HTML overflow menu) onto
/// one vertical center baseline while keeping comfortable 44 pt touch targets.
@Suite("ThreadMessageCard header alignment on iOS", .serialized)
@MainActor
struct ThreadMessageCardHeaderAlignmentIOSTests {
    private static let header = MessageHeader(
        id: "m-align",
        threadID: "thread-align",
        folderID: "inbox",
        from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
        to: [Correspondent(name: "Henrik", email: "henrik@ogard.example")],
        subject: "Hytte weekend in Hemsedal",
        snippet: "Booked the cabin for three nights.",
        date: Date(timeIntervalSince1970: 1_779_960_600),
        isRead: true
    )

    @Test("expanded HTML card aligns timestamp, collapse chevron, and overflow menu with 44 pt hit targets")
    func expandedHTMLCardAlignsTrailingMetadataCluster() throws {
        let frames = measureHeaderFrames(
            isExpanded: true,
            renderedBody: RenderedBody(
                html: "<p>Deterministic HTML body.</p>",
                plainText: "Deterministic HTML body.",
                attachments: []
            )
        )

        let toggleFrame = try #require(frames[.toggleButton], "Expected toggle button frame; got \(frames)")
        let timestampFrame = try #require(frames[.timestamp], "Expected timestamp frame; got \(frames)")
        let chevronFrame = try #require(frames[.chevron], "Expected chevron frame; got \(frames)")
        let overflowFrame = try #require(frames[.overflowButton], "Expected overflow button frame; got \(frames)")

        #expect(toggleFrame.height >= 44, "Header toggle target below 44 pt: \(toggleFrame)")
        #expect(overflowFrame.width >= 44 && overflowFrame.height >= 44, "Overflow target below 44 pt: \(overflowFrame)")

        #expect(
            abs(timestampFrame.midY - chevronFrame.midY) <= 1.5,
            "Chevron midY (\(chevronFrame.midY)) drifted from timestamp midY (\(timestampFrame.midY))"
        )
        #expect(
            abs(timestampFrame.midY - overflowFrame.midY) <= 1.5,
            "Overflow midY (\(overflowFrame.midY)) drifted from timestamp midY (\(timestampFrame.midY))"
        )
        #expect(
            timestampFrame.maxX <= chevronFrame.minX + 0.5,
            "Timestamp (\(timestampFrame)) overlapped chevron (\(chevronFrame))"
        )
        #expect(
            chevronFrame.maxX <= overflowFrame.minX + 0.5,
            "Chevron (\(chevronFrame)) overlapped overflow (\(overflowFrame))"
        )
    }

    @Test("expanded plain-text card aligns timestamp and collapse chevron cleanly")
    func expandedPlainTextCardAlignsTimestampAndChevron() throws {
        let frames = measureHeaderFrames(
            isExpanded: true,
            renderedBody: RenderedBody(
                html: nil,
                plainText: "Deterministic plain text body.",
                attachments: []
            )
        )

        let timestampFrame = try #require(frames[.timestamp], "Expected timestamp frame; got \(frames)")
        let chevronFrame = try #require(frames[.chevron], "Expected chevron frame; got \(frames)")

        #expect(frames[.overflowButton] == nil)
        #expect(
            abs(timestampFrame.midY - chevronFrame.midY) <= 1.5,
            "Chevron midY (\(chevronFrame.midY)) drifted from timestamp midY (\(timestampFrame.midY))"
        )
    }

    private func measureHeaderFrames(
        isExpanded: Bool,
        renderedBody: RenderedBody
    ) -> [ThreadCardHeaderControlKey: CGRect] {
        var captured: [ThreadCardHeaderControlKey: CGRect] = [:]
        let viewport = CGSize(width: 393, height: 260)
        let view = ThreadMessageCard(
            header: Self.header,
            isExpanded: isExpanded,
            isSelected: false,
            backend: MockBackend(),
            sourceID: nil,
            dateTextOverride: "15:55",
            initialRenderedBody: renderedBody
        ) {}
            .frame(width: viewport.width, alignment: .topLeading)
            .background(BrevTheme.brevMonoLight.bgPrimary.color)
            .brevTheme(.brevMonoLight)
            .htmlBodyRenderTarget(.staticSnapshot)
            .onPreferenceChange(ThreadCardHeaderControlFramesKey.self) { frames in
                captured = frames
            }

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.view.frame = CGRect(origin: .zero, size: viewport)
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        window.layoutIfNeeded()
        return captured
    }
}
#endif
