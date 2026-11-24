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
import BrevAI
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Proactive on-device triage macOS snapshots")
@MainActor
struct ProactiveTriageSnapshotTests {
    @Test("message list rows show Urgent, Needs reply, and summary attribution cleanly", arguments: ["light", "dark"])
    func messageListRowsWithInsights(_ mode: String) {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        let urgentHeader = MessageHeader(
            id: "inbox:urgent",
            threadID: "thread-urgent",
            folderID: "inbox",
            from: Correspondent(name: "Nora Lind", email: "nora@example.org"),
            subject: "Lease addendum signature",
            snippet: "Raw snippet replaced by local summary.",
            date: referenceDate,
            isRead: false
        )
        let replyHeader = MessageHeader(
            id: "inbox:reply",
            threadID: "thread-reply",
            folderID: "inbox",
            from: Correspondent(name: "Jonas Bakke", email: "jonas@example.org"),
            subject: "Friday design review",
            snippet: "Raw snippet replaced by local summary.",
            date: referenceDate.addingTimeInterval(-3600),
            isRead: true
        )
        let normalHeader = MessageHeader(
            id: "inbox:normal",
            threadID: "thread-normal",
            folderID: "inbox",
            from: Correspondent(name: "Maya Okafor", email: "maya@example.org"),
            subject: "Q4 release notes draft",
            snippet: "Raw snippet replaced by local summary.",
            date: referenceDate.addingTimeInterval(-7200),
            isRead: true
        )

        let urgentInsight = ThreadTriageInsight(
            summary: "Signed addendum is due before 5 PM today to keep the move-in date.",
            priority: .urgent,
            attribution: "On this Mac",
            sourceFingerprint: "fp-urgent",
            generatedAt: referenceDate
        )
        let replyInsight = ThreadTriageInsight(
            summary: "Jonas asked whether Thursday afternoon works for the design review.",
            priority: .needsReply,
            attribution: "On this Mac",
            sourceFingerprint: "fp-reply",
            generatedAt: referenceDate
        )
        let normalInsight = ThreadTriageInsight(
            summary: "Draft release notes are ready for optional comments ahead of Friday.",
            priority: .normal,
            attribution: "On this Mac",
            sourceFingerprint: "fp-normal",
            generatedAt: referenceDate
        )

        let view = VStack(spacing: 0) {
            row(header: urgentHeader, insight: urgentInsight, isSelected: false, referenceDate: referenceDate)
            row(header: replyHeader, insight: replyInsight, isSelected: true, referenceDate: referenceDate)
            row(header: normalHeader, insight: normalInsight, isSelected: false, referenceDate: referenceDate)
            Divider()
                .padding(.vertical, BrevSpacing.sm)
            ProactiveThreadTriageCard(insight: urgentInsight)
                .padding(.horizontal, BrevSpacing.md)
        }
        .padding(.vertical, BrevSpacing.sm)
        .frame(width: 420, height: 420, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 420, height: 420)),
            as: .image(precision: 0.99),
            named: "proactive-triage-surfaces-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private func row(
        header: MessageHeader,
        insight: ThreadTriageInsight,
        isSelected: Bool,
        referenceDate: Date
    ) -> some View {
        MessageListRow(
            header: header,
            threadCount: 2,
            isSelected: isSelected,
            isChecked: false,
            isInSelectionMode: false,
            isPinned: false,
            isThreadExpanded: false,
            showAvatar: true,
            previewLineCount: 1,
            fontFamily: .system,
            textSize: .medium,
            density: .comfortable,
            showsAbsoluteArrivalTime: false,
            sourceContext: nil,
            triageInsight: insight,
            isBlockedSender: false,
            hasFollowUp: false,
            referenceDate: referenceDate,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
    }

    private static func retinaImage<Content: View>(
        of host: NSHostingController<Content>,
        size: CGSize
    ) -> NSImage {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer {
            window.contentViewController = nil
            window.close()
        }
        let view = host.view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
