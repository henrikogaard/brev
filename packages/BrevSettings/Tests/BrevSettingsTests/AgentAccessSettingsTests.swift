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
@testable import BrevSettings
import Foundation
import Testing

@Suite("Agent access settings and audit log (#305, ADR-0095)")
struct AgentAccessSettingsTests {
    @Test("master switch and per-account consent default to off and round-trip locally")
    func defaultOffAndRoundTrip() throws {
        let suite = "AgentAccessSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = AgentAccessSettings.load(from: defaults)
        #expect(settings == .defaults)
        #expect(!settings.isEnabled)
        #expect(settings.enabledAccountIDs.isEmpty)
        #expect(!settings.isAccountEnabled("acct-1"))

        settings.setAccount("acct-1", enabled: true)
        #expect(!settings.isAccountEnabled("acct-1")) // Master switch is still off.

        settings.isEnabled = true
        #expect(settings.isAccountEnabled("acct-1"))
        #expect(!settings.isAccountEnabled("acct-2"))

        settings.save(to: defaults)
        let reloaded = AgentAccessSettings.load(from: defaults)
        #expect(reloaded == settings)
    }

    @Test("agent access keys are excluded from settings backup and iCloud preference sync")
    func excludedFromBackupAndPreferenceSync() throws {
        let suite = "AgentAccessBackupExclusion-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: ["acct-secret"])
        settings.save(to: defaults)

        let store = SettingsPersistenceStore(defaults: defaults)
        let relatedConsent = RelatedConversationConsentStore(defaults: defaults)
        let backup = SettingsBackupCodec.export(from: store, consentStore: relatedConsent, accountIDs: ["acct-secret"])
        let encoded = try JSONEncoder().encode(backup)
        let jsonText = String(decoding: encoded, as: UTF8.self)
        #expect(!jsonText.contains("agentAccess"))
        #expect(!jsonText.contains("acct-secret"))

        let syncAllowlist = PreferenceSyncAllowlist.keys
        #expect(!syncAllowlist.contains(AgentAccessSettings.Key.isEnabled))
        #expect(!syncAllowlist.contains(AgentAccessSettings.Key.enabledAccountIDs))
    }

    @Test("audit log ring buffer caps at 1,000 entries, excludes backups, persists, and clears")
    func auditLogRingBufferAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentAccessAuditTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("audit.json")

        let store = AgentAccessAuditLogStore(fileURL: fileURL, postsChangeNotification: false)
        for index in 1 ... (AgentAccessAuditLogStore.maxEntries + 25) {
            store.record(AgentAccessAuditEntry(
                clientName: "claude-code",
                clientPID: 1234,
                toolName: "search_messages",
                accountID: "acct-1",
                parameterSummary: "seq=\(index)",
                outcome: .allowed
            ))
        }

        let entries = store.entries()
        #expect(entries.count == AgentAccessAuditLogStore.maxEntries)
        #expect(entries.first?.parameterSummary == "seq=\(AgentAccessAuditLogStore.maxEntries + 25)")
        #expect(entries.last?.parameterSummary == "seq=26")

        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)

        // Reload from disk.
        let reloaded = AgentAccessAuditLogStore(fileURL: fileURL, postsChangeNotification: false)
        #expect(reloaded.entries().count == AgentAccessAuditLogStore.maxEntries)

        reloaded.clear()
        #expect(reloaded.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("exposed tool inventory lists only the six ADR-0095 tools and excludes send/delete")
    func exposedToolsInventory() {
        let names = AgentAccessToolSpec.exposedTools.map(\.name)
        #expect(names == [
            "list_accounts",
            "list_folders",
            "search_messages",
            "read_message",
            "archive_messages",
            "label_messages"
        ])
        let changeTools = AgentAccessToolSpec.exposedTools.filter { $0.permission == .approvalRequired }.map(\.name)
        #expect(changeTools == ["archive_messages", "label_messages"])

        let socketPath = "/Users/demo/Library/Group Containers/group.eu.brevmail.brev/mcp.sock"
        let jsonSnippet = AgentAccessSocketConfiguration.clientConfigSnippet(
            for: .json,
            helperPath: "/Applications/Brev.app/Contents/Helpers/brev-mcp",
            socketPath: socketPath
        )
        #expect(jsonSnippet.contains("\"mcpServers\""))
        #expect(jsonSnippet.contains("\"args\": [\"--socket\", \"\(socketPath)\"]"))

        let codexSnippet = AgentAccessSocketConfiguration.clientConfigSnippet(
            for: .codexTOML,
            helperPath: "/Applications/Brev.app/Contents/Helpers/brev-mcp",
            socketPath: socketPath
        )
        #expect(codexSnippet.contains("[mcp_servers.brev]"))
        #expect(codexSnippet.contains("command = \"/Applications/Brev.app/Contents/Helpers/brev-mcp\""))
        #expect(codexSnippet.contains("args = [\"--socket\", \"\(socketPath)\"]"))
        #expect(AgentAccessSocketConfiguration.defaultSocketURL().path.utf8.count <= 100)
    }

    @Test("socket paths isolate stable, nightly, and test builds and stay within sun_path limit")
    func socketPathsIsolateBuildsAndRespectLengthLimit() {
        let shortContainer = URL(fileURLWithPath: "/Users/alice/Library/Group Containers/group.eu.brevmail.brev")
        let stableURL = AgentAccessSocketConfiguration.defaultSocketURL(
            bundleIdentifier: "eu.brevmail.brev",
            groupContainerURL: shortContainer
        )
        let nightlyURL = AgentAccessSocketConfiguration.defaultSocketURL(
            bundleIdentifier: "eu.brevmail.brev.nightly",
            groupContainerURL: shortContainer
        )
        let testURL = AgentAccessSocketConfiguration.defaultSocketURL(
            bundleIdentifier: "eu.brevmail.brev.test",
            groupContainerURL: shortContainer
        )
        #expect(stableURL.lastPathComponent == "mcp.sock")
        #expect(nightlyURL.lastPathComponent == "mcp-nightly.sock")
        #expect(testURL.lastPathComponent != stableURL.lastPathComponent)
        #expect(testURL.lastPathComponent != nightlyURL.lastPathComponent)

        let overlongContainer = URL(
            fileURLWithPath: "/Users/\(String(repeating: "very-long-home-name-", count: 5))/Library/Group Containers/group.eu.brevmail.brev"
        )
        let normalTemp = URL(fileURLWithPath: "/var/folders/ab/cdef/T")
        let tempFallback = AgentAccessSocketConfiguration.defaultSocketURL(
            bundleIdentifier: "eu.brevmail.brev",
            groupContainerURL: overlongContainer,
            temporaryDirectoryURL: normalTemp
        )
        #expect(tempFallback.path.hasPrefix(normalTemp.path))
        #expect(tempFallback.path.utf8.count <= 100)

        let overlongTemp = URL(
            fileURLWithPath: "/var/folders/\(String(repeating: "x", count: 95))/T"
        )
        let tmpFallback = AgentAccessSocketConfiguration.defaultSocketURL(
            bundleIdentifier: "eu.brevmail.brev.nightly",
            groupContainerURL: overlongContainer,
            temporaryDirectoryURL: overlongTemp
        )
        #expect(tmpFallback.path.hasPrefix("/tmp/"))
        #expect(tmpFallback.path.utf8.count <= 100)
    }

    @Test("removing an account revokes its agent-access grant so re-adding requires fresh opt-in")
    func removeAccountRevokesAgentGrant() {
        let suiteName = "eu.brevmail.tests.agent-access-revoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AgentAccessSettings(isEnabled: true, enabledAccountIDs: ["imap:alice@example.org", "acct-keep"])
        settings.save(to: defaults)
        #expect(AgentAccessSettings.load(from: defaults).isAccountEnabled("imap:alice@example.org"))

        SettingsPersistenceStore(defaults: defaults).removeAccountScopedState(accountID: "imap:alice@example.org")

        let afterRemoval = AgentAccessSettings.load(from: defaults)
        #expect(afterRemoval.isEnabled)
        #expect(!afterRemoval.isAccountEnabled("imap:alice@example.org"))
        #expect(afterRemoval.isAccountEnabled("acct-keep"))
    }
}
