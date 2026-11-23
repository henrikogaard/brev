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
import BrevSettings
import BrevThemes
import Testing

@MainActor
@Suite("Command palette")
struct MailCommandPaletteTests {
    @Test("the palette sheet paints the selected Brev theme")
    func sheetAppearance() throws {
        for theme in [BrevTheme.brevPaper, BrevTheme.brevSlate] {
            let host = MailCommandPalette.contentController(theme: theme, entries: []) { _ in }
            host.view.frame = NSRect(x: 0, y: 0, width: 560, height: 400)
            host.view.layoutSubtreeIfNeeded()
            let bounds = host.view.bounds
            let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: bounds))
            host.view.cacheDisplay(in: bounds, to: bitmap)
            let sample = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            let expected = try #require(NSColor(theme.bgPrimary.color).usingColorSpace(.sRGB))
            #expect(sample.alphaComponent > 0.99)
            #expect(abs(sample.redComponent - expected.redComponent) < 0.02)
            #expect(abs(sample.greenComponent - expected.greenComponent) < 0.02)
            #expect(abs(sample.blueComponent - expected.blueComponent) < 0.02)
        }
    }

    @Test("nested commands follow menu validation and cannot run after removal")
    func commands() throws {
        let root = NSMenu()
        let group = root.addItem(withTitle: "Message", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        root.setSubmenu(submenu, for: group)
        submenu.autoenablesItems = false
        let target = ActionCounter()
        let archive = submenu.addItem(withTitle: "Archive", action: #selector(ActionCounter.run(_:)), keyEquivalent: "")
        archive.target = target
        let hidden = submenu.addItem(withTitle: "Hidden", action: archive.action, keyEquivalent: "")
        hidden.isHidden = true
        let rows = MailPaletteEntry.commands(in: root)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.matches("message arch"))
        row.run()
        #expect(target.calls == 1)
        archive.isEnabled = false
        row.run()
        #expect(target.calls == 1)
        archive.isEnabled = true
        submenu.removeItem(archive)
        row.run()
        #expect(target.calls == 1)
    }

    @Test("same-named mailboxes stay source scoped and settings reuse the Settings search vocabulary")
    func destinations() throws {
        func source(_ id: String) -> MailSourceSection {
            let email = "\(id)@example.org"
            return MailSourceSection(id: .init(accountID: id, mailboxID: "primary"),
                                     account: BrevAccount(id: id, displayName: id.capitalized, emailAddress: email),
                                     mailbox: .init(id: "primary", email: email, displayName: "Primary", isPrimary: true),
                                     folders: [Folder(id: "inbox", name: "Inbox", role: .inbox)])
        }
        let home = source("home"), work = source("work")
        var routed: MailSourceID?
        let rows = MailPaletteEntry.mailDestinations(in: [home, work]) { source, _ in routed = source }
        let match = try #require(rows.first { $0.title == "Inbox" && $0.matches("work inbox") })
        match.run()
        #expect(routed == work.id)
        let account = try #require(rows.first { $0.title == "Home" })
        account.run()
        #expect(routed == home.id)
        var opened: SettingsSection?
        let settings = MailPaletteEntry.settings([.privacy]) { opened = $0 }
        let privacy = try #require(settings.first { $0.matches("tracking") })
        privacy.run()
        #expect(opened == .privacy)
        #expect(!privacy.matches("unrelated"))

        var launched: [String] = []
        let workspace = MailPaletteEntry.workspaceDestinations(
            MailPaletteWorkspaceDestination.build(
                canOpenAssistant: true,
                canStartTriage: true,
                openAssistant: { launched.append("assistant") },
                startTriage: { launched.append("triage") },
                openSubscriptions: { launched.append("subscriptions") }
            )
        )
        for (query, expected) in [("assistant", "assistant"), ("triage", "triage"), ("newsletters", "subscriptions")] {
            let entry = try #require(workspace.first { $0.matches(query) })
            entry.run()
            #expect(launched.last == expected)
        }

        let limitedWorkspace = MailPaletteWorkspaceDestination.build(
            canOpenAssistant: false,
            canStartTriage: false,
            openAssistant: {},
            startTriage: {},
            openSubscriptions: {}
        )
        #expect(limitedWorkspace.map(\.title) == ["Subscriptions"])

        // Selecting Assistant from a non-default account preserves that source ID even after
        // selectSmartView clears selectedSourceID, so Assistant resolves that account's backend.
        let nav = MailNavigationState()
        nav.selectFolder("inbox", in: work.id)
        nav.selectAssistantDestination(preserving: nav.selectedSourceID)
        #expect(nav.isAssistantSelected)
        #expect(nav.selectedSourceID == nil)
        #expect(nav.assistantSourceID == work.id)
    }

    @Test("new palette copy has Norwegian translations")
    func copy() throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        for key in [
            "Command Palette…",
            "Search commands, mailboxes, accounts and settings",
            "No matching commands or destinations",
            "Account",
            "Mailbox",
            "Settings"
        ] {
            let entry = try #require(strings[key] as? [String: Any])
            let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String != nil)
        }
    }
}

@MainActor
private final class ActionCounter: NSObject {
    var calls = 0
    @objc func run(_ sender: NSMenuItem) { calls += 1 }
}
#endif
