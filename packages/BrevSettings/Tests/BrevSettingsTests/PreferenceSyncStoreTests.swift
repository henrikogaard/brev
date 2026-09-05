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

@testable import BrevSettings
import Foundation
import Testing

/// In-memory stand-in for `NSUbiquitousKeyValueStore`.
///
/// Records writes so tests can assert on exactly what reached "iCloud",
/// and can simulate an external change by posting the same notification
/// the real store posts.
private final class FakeKeyValueTransport: PreferenceSyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    private(set) var writtenKeys: [String] = []
    private(set) var removedKeys: [String] = []
    private var storedSynchronizeCount = 0

    var synchronizeCount: Int {
        lock.withLock { storedSynchronizeCount }
    }

    func object(forKey key: String) -> Any? {
        lock.withLock { storage[key] }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock {
            storage[key] = value
            writtenKeys.append(key)
        }
    }

    func removeObject(forKey key: String) {
        lock.withLock {
            storage.removeValue(forKey: key)
            removedKeys.append(key)
        }
    }

    var dictionaryRepresentation: [String: Any] {
        lock.withLock { storage }
    }

    @discardableResult
    func synchronize() -> Bool {
        lock.withLock { storedSynchronizeCount += 1 }
        return true
    }

    /// Simulate another device writing `values`, then iCloud delivering
    /// the change to this device.
    func simulateExternalChange(_ values: [String: Any]) {
        lock.withLock {
            for (key, value) in values {
                storage[key] = value
            }
        }
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self,
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
                NSUbiquitousKeyValueStoreChangedKeysKey: Array(values.keys)
            ]
        )
    }
}

@Suite("PreferenceSyncStore")
struct PreferenceSyncStoreTests {
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "PreferenceSyncStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static let allowlist = ["vip.senders", "compose.messageFormat", "folders.showTrash"]

    private static func makeStore(
        defaults: UserDefaults,
        transport: FakeKeyValueTransport,
        allowlist: [String] = allowlist,
        debounceInterval: TimeInterval = 0
    ) -> ICloudKeyValuePreferenceSyncStore {
        ICloudKeyValuePreferenceSyncStore(
            defaults: defaults,
            transport: transport,
            allowlist: allowlist,
            debounceInterval: debounceInterval
        )
    }

    @Test("sync setting defaults to off")
    func syncSettingDefaultsOff() throws {
        let defaults = try Self.makeDefaults()
        #expect(PreferenceSyncSettings.load(from: defaults).isICloudSyncEnabled == false)
    }

    @Test("the opt-in key itself is never on the allowlist")
    func optInKeyNotSynced() {
        #expect(!PreferenceSyncAllowlist.keys.contains(PreferenceSyncSettings.Key.iCloudSyncEnabled))
    }

    @Test("allowlist contains only the phase-1 keys and no consent or credential keys")
    func allowlistShape() {
        let keys = Set(PreferenceSyncAllowlist.keys)
        #expect(keys.contains("message.workflowState.v1"))
        #expect(keys.contains("vip.senders"))
        #expect(keys.contains("list.inboxCategoryOverrides"))
        #expect(keys.contains("list.pinnedSourceMessageIDs.v2"))
        for key in keys {
            #expect(!key.hasPrefix("avatar."), "consent flag \(key) must not sync")
            #expect(!key.hasPrefix("notifications."), "per-device key \(key) must not sync")
            #expect(!key.hasPrefix("account."), "account key \(key) must not sync")
            #expect(!key.hasPrefix("caldav."), "credential-adjacent key \(key) must not sync")
        }
        #expect(keys.count == PreferenceSyncAllowlist.keys.count, "allowlist has duplicates")
    }

    @Test("store that has not started writes nothing to the transport")
    func inactiveStoreWritesNothing() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        _ = store

        defaults.set("plain", forKey: "compose.messageFormat")
        defaults.set(Data([1, 2, 3]), forKey: "vip.senders")

        #expect(transport.writtenKeys.isEmpty)
        #expect(transport.synchronizeCount == 0)
        #expect(store.isActive == false)
    }

    @Test("start pushes existing allowlisted values with the namespace prefix")
    func startPushesExistingValues() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("plain", forKey: "compose.messageFormat")
        defaults.set(true, forKey: "folders.showTrash")
        defaults.set("device-only", forKey: "mail.reader.lastPaneWidth")
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)

        store.start()

        #expect(store.isActive)
        #expect(transport.object(forKey: "brev.prefs.v1.compose.messageFormat") as? String == "plain")
        #expect(transport.object(forKey: "brev.prefs.v1.folders.showTrash") as? Bool == true)
        #expect(transport.object(forKey: "brev.prefs.v1.mail.reader.lastPaneWidth") == nil)
        #expect(transport.object(forKey: "brev.prefs.v1.vip.senders") == nil)
        #expect(transport.synchronizeCount >= 1)
    }

    @Test("start adopts values the cloud already has")
    func startAdoptsCloudValues() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("plain", forKey: "compose.messageFormat")
        let transport = FakeKeyValueTransport()
        transport.set("html", forKey: "brev.prefs.v1.compose.messageFormat")
        let store = Self.makeStore(defaults: defaults, transport: transport)
        let writesBeforeStart = transport.writtenKeys.count

        store.start()

        #expect(defaults.string(forKey: "compose.messageFormat") == "html")
        // The adopted value must not bounce back as a fresh write.
        #expect(transport.writtenKeys.count == writesBeforeStart)
    }

    @Test("local change to an allowlisted key is pushed; non-allowlisted keys never touch the transport")
    func localChangeIsPushed() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()
        let syncsAfterStart = transport.synchronizeCount

        let payload = Data("vip-list".utf8)
        defaults.set(payload, forKey: "vip.senders")
        defaults.set(42, forKey: "notifications.badgePolicy")
        defaults.set(720.0, forKey: "mail.reader.lastPaneWidth")

        #expect(transport.object(forKey: "brev.prefs.v1.vip.senders") as? Data == payload)
        #expect(transport.dictionaryRepresentation.keys.allSatisfy { $0.hasPrefix("brev.prefs.v1.") })
        #expect(transport.dictionaryRepresentation.count == 1)
        #expect(transport.synchronizeCount > syncsAfterStart)
    }

    @Test("unchanged local value is not re-pushed")
    func unchangedValueNotRepushed() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()

        defaults.set("plain", forKey: "compose.messageFormat")
        let writesAfterFirst = transport.writtenKeys.count
        defaults.set("plain", forKey: "compose.messageFormat")
        defaults.set("irrelevant", forKey: "some.other.key")

        #expect(transport.writtenKeys.count == writesAfterFirst)
    }

    @Test("bursts of local defaults changes coalesce into one reconciliation")
    func localChangesAreCoalesced() async throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(
            defaults: defaults,
            transport: transport,
            debounceInterval: 0.05
        )
        store.start()
        let syncsAfterStart = transport.synchronizeCount

        defaults.set("plain", forKey: "compose.messageFormat")
        defaults.set(false, forKey: "folders.showTrash")

        let expectedSynchronizeCount = syncsAfterStart + 1
        for _ in 0 ..< 100 {
            if transport.synchronizeCount >= expectedSynchronizeCount {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(transport.synchronizeCount == expectedSynchronizeCount)
        #expect(transport.object(forKey: "brev.prefs.v1.compose.messageFormat") as? String == "plain")
        #expect(transport.object(forKey: "brev.prefs.v1.folders.showTrash") as? Bool == false)
    }

    @Test("external change updates local defaults and posts a notification")
    func externalChangeUpdatesLocal() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()

        var notifiedKeys: [String] = []
        let token = NotificationCenter.default.addObserver(
            forName: PreferenceSync.didApplyRemoteChangesNotification,
            object: store,
            queue: nil
        ) { note in
            notifiedKeys = note.userInfo?[PreferenceSync.changedKeysUserInfoKey] as? [String] ?? []
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let payload = Data("from-other-device".utf8)
        transport.simulateExternalChange([
            "brev.prefs.v1.vip.senders": payload,
            "brev.prefs.v1.folders.showTrash": false,
            "brev.prefs.v1.mail.reader.lastPaneWidth": 999.0,
            "unrelated.key": "x"
        ])

        // Parallel stores publish on the same center. Their events must not
        // overwrite the observation for the store under test.
        NotificationCenter.default.post(
            name: PreferenceSync.didApplyRemoteChangesNotification,
            object: NSObject(),
            userInfo: [PreferenceSync.changedKeysUserInfoKey: ["compose.messageFormat"]]
        )

        #expect(defaults.data(forKey: "vip.senders") == payload)
        #expect(defaults.object(forKey: "folders.showTrash") as? Bool == false)
        #expect(defaults.object(forKey: "mail.reader.lastPaneWidth") == nil)
        #expect(Set(notifiedKeys) == ["vip.senders", "folders.showTrash"])
        // Applying a remote value must not echo it back as a local write.
        #expect(!transport.writtenKeys.contains("brev.prefs.v1.vip.senders"))
    }

    @Test("external change is ignored after stop and stop does not clear the cloud")
    func stopStopsObserving() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()
        defaults.set("plain", forKey: "compose.messageFormat")
        store.stop()

        transport.simulateExternalChange(["brev.prefs.v1.compose.messageFormat": "html"])
        defaults.set(true, forKey: "folders.showTrash")

        #expect(store.isActive == false)
        #expect(defaults.string(forKey: "compose.messageFormat") == "plain")
        #expect(transport.object(forKey: "brev.prefs.v1.folders.showTrash") == nil)
        #expect(transport.object(forKey: "brev.prefs.v1.compose.messageFormat") as? String == "html")
        #expect(transport.removedKeys.isEmpty)
    }

    @Test("oversized values are skipped instead of pushed")
    func oversizedValueSkipped() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()

        defaults.set(Data(count: 1_000_000), forKey: "vip.senders")

        #expect(transport.object(forKey: "brev.prefs.v1.vip.senders") == nil)
    }

    @Test("removeAllRemoteValues clears only namespaced keys")
    func removeAllRemoteValues() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("plain", forKey: "compose.messageFormat")
        let transport = FakeKeyValueTransport()
        transport.set("keep", forKey: "other.app.key")
        let store = Self.makeStore(defaults: defaults, transport: transport)
        store.start()

        store.removeAllRemoteValues()

        #expect(transport.object(forKey: "brev.prefs.v1.compose.messageFormat") == nil)
        #expect(transport.object(forKey: "other.app.key") as? String == "keep")
    }

    @Test("local-only store is a no-op")
    func localOnlyStoreIsNoop() throws {
        let store = LocalOnlyPreferenceSyncStore()
        store.start()
        #expect(store.isActive == false)
        store.stop()
    }
}

@Suite("PreferenceSyncController")
struct PreferenceSyncControllerTests {
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "PreferenceSyncControllerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("controller keeps the local-only store while the toggle is off")
    func offMeansLocalOnly() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let controller = PreferenceSyncController(
            defaults: defaults,
            makeICloudStore: {
                ICloudKeyValuePreferenceSyncStore(
                    defaults: defaults,
                    transport: transport,
                    allowlist: ["vip.senders"],
                    debounceInterval: 0
                )
            }
        )

        controller.activate()
        defaults.set(Data([1]), forKey: "vip.senders")

        #expect(controller.activeStore is LocalOnlyPreferenceSyncStore)
        #expect(transport.writtenKeys.isEmpty)
    }

    @Test("turning the toggle on starts iCloud sync; off stops it")
    func toggleStartsAndStops() throws {
        let defaults = try Self.makeDefaults()
        let transport = FakeKeyValueTransport()
        let controller = PreferenceSyncController(
            defaults: defaults,
            makeICloudStore: {
                ICloudKeyValuePreferenceSyncStore(
                    defaults: defaults,
                    transport: transport,
                    allowlist: ["vip.senders"],
                    debounceInterval: 0
                )
            }
        )
        controller.activate()

        var settings = PreferenceSyncSettings.load(from: defaults)
        settings.isICloudSyncEnabled = true
        settings.save(to: defaults)
        defaults.set(Data([1]), forKey: "vip.senders")

        #expect(controller.activeStore is ICloudKeyValuePreferenceSyncStore)
        #expect(transport.object(forKey: "brev.prefs.v1.vip.senders") as? Data == Data([1]))

        settings.isICloudSyncEnabled = false
        settings.save(to: defaults)
        defaults.set(Data([2]), forKey: "vip.senders")

        #expect(controller.activeStore is LocalOnlyPreferenceSyncStore)
        #expect(transport.object(forKey: "brev.prefs.v1.vip.senders") as? Data == Data([1]))
    }
}
