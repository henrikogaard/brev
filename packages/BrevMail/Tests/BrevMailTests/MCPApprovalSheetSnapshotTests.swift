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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for the local MCP change-approval sheet (#305, ADR-0095).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("MCP approval sheet snapshots")
@MainActor
struct MCPApprovalSheetSnapshotTests {
    @Test("approval sheet renders archive preview in light and dark themes", arguments: ["light", "dark"])
    func approvalSheetPresentation(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let request = MCPApprovalRequest(
            clientName: "Claude",
            clientPID: 4242,
            toolName: "archive_messages",
            accountID: "acct-work",
            accountLabel: "Work",
            targetFolderName: nil,
            messageCount: 7,
            previews: [
                MCPApprovalRequest.MessagePreview(
                    id: "m1",
                    sender: "Maya Patel <maya@northwind.example>",
                    subject: "Q3 vendor contract renewal"
                ),
                MCPApprovalRequest.MessagePreview(
                    id: "m2",
                    sender: "Jonas Berg <jonas@fjord.example>",
                    subject: "Invoice #4819 ready for review"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let view = MCPApprovalSheetView(request: request, onApprove: {}, onDeny: {})
            .frame(width: 440, height: 300, alignment: .top)
            .background(theme.bgPrimary.color)
            .environment(\.brevTheme, theme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 440, height: 300)),
            named: "mcp-approval-sheet-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("approval sheet renders create_draft preview in light and dark themes", arguments: ["light", "dark"])
    func createDraftApprovalSheetPresentation(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let request = MCPApprovalRequest(
            clientName: "Claude",
            clientPID: 4242,
            toolName: "create_draft",
            accountID: "acct-work",
            accountLabel: "Work",
            targetFolderName: nil,
            messageCount: 0,
            previews: [],
            draftPreview: MCPApprovalRequest.DraftPreview(
                to: ["maya@northwind.example"],
                cc: ["sam@northwind.example"],
                bcc: [],
                subject: "Re: Q3 vendor contract renewal",
                bodyPreview: "Hi Maya,\n\nThanks for sending over the updated terms. I will review section 4 and follow up tomorrow morning.",
                isBodyTruncated: false,
                inReplyToSubject: "Q3 vendor contract renewal"
            ),
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let view = MCPApprovalSheetView(request: request, onApprove: {}, onDeny: {})
            .frame(width: 440, height: 390, alignment: .top)
            .background(theme.bgPrimary.color)
            .environment(\.brevTheme, theme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 440, height: 390)),
            named: "mcp-approval-sheet-create-draft-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
