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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Agent access settings macOS snapshots (#305, ADR-0095)", .serialized)
@MainActor
struct AgentAccessSectionSnapshotTests {
    @Test("AgentAccessSection renders toggles, tool inventory, snippet, and audit log", arguments: ["light", "dark"])
    func agentAccessSectionRenders(_ mode: String) throws {
        guard #available(macOS 26.0, *) else { return }

        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suite = "AgentAccessSnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: ["acct-work"])
        settings.save(to: defaults)

        let auditStore = AgentAccessAuditLogStore(fileURL: nil, postsChangeNotification: false)
        auditStore.record(AgentAccessAuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_735_689_600),
            clientName: "claude-code #4102",
            clientPID: 4102,
            toolName: "search_messages",
            accountID: "acct-work",
            parameterSummary: "query_len=12 limit=20 results=4",
            outcome: .allowed
        ))
        auditStore.record(AgentAccessAuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_735_689_660),
            clientName: "claude-code #4102",
            clientPID: 4102,
            toolName: "archive_messages",
            accountID: "acct-work",
            parameterSummary: "count=2 folder=archive ids=m1,m2",
            outcome: .approved
        ))

        let accounts = [
            BrevAccount(id: "acct-work", displayName: "Work", emailAddress: "work@northwind.example"),
            BrevAccount(id: "acct-personal", displayName: "Personal", emailAddress: "personal@example.org")
        ]

        let view = AgentAccessSection(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            auditStore: auditStore,
            accounts: accounts,
            helperPath: "/Applications/Brev.app/Contents/Helpers/brev-mcp",
            socketPath: "/Users/demo/Library/Group Containers/group.eu.brevmail.brev/mcp.sock"
        )
        .frame(width: 700, height: 1240)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .defaultAppStorage(defaults)
        .transaction { $0.animation = nil }

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 700, height: 1240)),
            as: .image(precision: 0.99),
            named: "agent-access-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
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
