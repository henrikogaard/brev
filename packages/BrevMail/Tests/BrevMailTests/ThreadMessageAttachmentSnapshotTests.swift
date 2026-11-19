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

#if os(macOS)
import AppKit
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// An expanded thread message card lists its attachments as the reader's
/// cards. The inline CID image and the calendar invite are not listed.
/// Sizes are whole numbers so the decimal separator of the host locale does
/// not change the picture. Set `RECORD_SNAPSHOTS=YES` to record.
@Suite("Thread message attachment snapshots")
@MainActor
struct ThreadMessageAttachmentSnapshotTests {
    private static let header = MessageHeader(
        id: "m-attachments",
        threadID: "thread-attachments",
        folderID: "inbox",
        from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
        to: [Correspondent(name: "Henrik", email: "henrik@ogard.example")],
        subject: "Cabin plans",
        snippet: "Plans and photos attached.",
        date: Date(timeIntervalSince1970: 1_779_960_600),
        isRead: true,
        hasAttachments: true
    )

    private static let attachments = [
        BrevBackend.Attachment(id: "a1", name: "Cabin floor plan.pdf", mimeType: "application/pdf",
                               sizeBytes: 245_760, resource: "r1"),
        BrevBackend.Attachment(id: "a2", name: "Hemsedal.jpeg", mimeType: "image/jpeg",
                               sizeBytes: 2_000_000, resource: "r2"),
        BrevBackend.Attachment(id: "cid", name: "logo.png", mimeType: "image/png", sizeBytes: 4096,
                               isInline: true, contentID: "logo@example.org", resource: "r3"),
        BrevBackend.Attachment(id: "ics", name: "invite.ics", mimeType: "text/calendar", sizeBytes: 900, resource: "r4"),
    ]

    @Test("expanded thread card lists its attachments", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func expandedCard(_ themeName: String) throws {
        let theme = try #require(Self.theme(named: themeName))
        let size = CGSize(width: 720, height: 170)
        let view = ThreadMessageCard(
            header: Self.header,
            isExpanded: true,
            backend: MockBackend(),
            sourceID: nil,
            dateTextOverride: "12:00",
            initialRenderedBody: RenderedBody(
                html: nil,
                plainText: "Floor plan and a photo from the last trip.",
                attachments: Self.attachments
            )
        ) {}
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .htmlBodyRenderTarget(.staticSnapshot)
            .environment(\.colorScheme, theme.mode.colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(of: host, as: .image(size: size), named: themeName,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    private static func theme(named name: String) -> BrevTheme? {
        switch name {
        case "brevMonoLight": .brevMonoLight
        case "brevMonoDark": .brevMonoDark
        case "solarizedLight": .solarizedLight
        case "solarizedDark": .solarizedDark
        case "gruvboxLight": .gruvboxLight
        case "gruvboxDark": .gruvboxDark
        default: nil
        }
    }
}
#endif
