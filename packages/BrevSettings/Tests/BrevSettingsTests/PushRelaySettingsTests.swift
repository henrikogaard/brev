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

@Suite("Closed-app push relay settings & controller (#11)")
struct PushRelaySettingsTests {
    @Test("defaults are strictly off and round-trip locally without secrets or raw emails")
    func defaultsOffAndLocalRoundTrip() throws {
        let suite = "PushRelaySettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!NotificationSettings.defaults.notificationsEnabled)

        var settings = PushRelaySettings.load(from: defaults)
        #expect(!settings.isEnabled)
        #expect(settings.mode == .userHostedRelay)
        #expect(settings.endpointURLString.isEmpty)
        #expect(settings.webPushDeliveryURLString.isEmpty)
        #expect(settings.enabledAccountIDs.isEmpty)
        #expect(settings.opaqueAccountTokens.isEmpty)
        #expect(settings.activeRegistration == nil)
        #expect(settings.lastRegistrationError == nil)

        let imapID = BrevAccount.imapSMTPAccountID(forEmailAddress: "alice@northwind.example")
        settings.setAccount(imapID, enabled: true)
        #expect(!settings.isAccountEnabled(imapID)) // Master switch is still off.

        let opaqueToken = settings.opaqueToken(forAccountID: imapID)
        #expect(opaqueToken.hasPrefix("acct-"))
        #expect(!opaqueToken.contains("alice"))
        #expect(!opaqueToken.contains("northwind"))
        #expect(settings.resolveAccountID(forOpaqueToken: opaqueToken) == imapID)

        settings.isEnabled = true
        settings.mode = .jmapWebPush
        settings.endpointURLString = "https://jmap.example.com/api/"
        settings.webPushDeliveryURLString = "https://webpush.example.com/push/dev1"
        settings.activeRegistration = ActivePushRelayRegistration(
            mode: .jmapWebPush,
            endpointURLString: "https://jmap.example.com/api/",
            webPushDeliveryURLString: "https://webpush.example.com/push/dev1",
            subscriptionID: "sub-42",
            state: .pendingVerification,
            registeredAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        #expect(settings.isAccountEnabled(imapID))
        settings.save(to: defaults)

        let reloaded = PushRelaySettings.load(from: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.mode == .jmapWebPush)
        #expect(reloaded.endpointURLString == "https://jmap.example.com/api/")
        #expect(reloaded.webPushDeliveryURLString == "https://webpush.example.com/push/dev1")
        #expect(reloaded.enabledAccountIDs == [imapID])
        #expect(reloaded.resolveAccountID(forOpaqueToken: opaqueToken) == imapID)
        #expect(reloaded.activeRegistration?.subscriptionID == "sub-42")
        #expect(reloaded.activeRegistration?.state == .pendingVerification)
        #expect(!reloaded.deviceClientID.isEmpty)

        // Removing an account clears both its opt-in and opaque token mapping.
        let store = SettingsPersistenceStore(defaults: defaults)
        store.removeAccountScopedState(accountID: imapID)
        let afterRemoval = PushRelaySettings.load(from: defaults)
        #expect(!afterRemoval.enabledAccountIDs.contains(imapID))
        #expect(afterRemoval.resolveAccountID(forOpaqueToken: opaqueToken) == nil)
    }

    @Test("push relay settings are excluded from settings backups and iCloud preference sync")
    func excludedFromBackupAndPreferenceSync() throws {
        let suite = "PushRelayBackupExclusion-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = PushRelaySettings.defaults
        settings.isEnabled = true
        settings.mode = .userHostedRelay
        settings.endpointURLString = "https://private-relay.example.net/hook"
        settings.setAccount("acct-push-only", enabled: true)
        settings.activeRegistration = ActivePushRelayRegistration(
            mode: .userHostedRelay,
            endpointURLString: "https://private-relay.example.net/hook",
            subscriptionID: "sub-device-local",
            state: .active
        )
        settings.save(to: defaults)

        let store = SettingsPersistenceStore(defaults: defaults)
        let relatedConsent = RelatedConversationConsentStore(defaults: defaults)
        let backup = SettingsBackupCodec.export(
            from: store,
            consentStore: relatedConsent,
            accountIDs: ["acct-push-only"]
        )
        let encoded = try JSONEncoder().encode(backup)
        let jsonText = String(decoding: encoded, as: UTF8.self)
        #expect(!jsonText.contains("pushRelay"))
        #expect(!jsonText.contains("private-relay.example.net"))
        #expect(!jsonText.contains("acct-push-only"))
        #expect(!jsonText.contains("sub-device-local"))

        let syncAllowlist = PreferenceSyncAllowlist.keys
        for key in [
            PushRelaySettings.Key.isEnabled,
            PushRelaySettings.Key.mode,
            PushRelaySettings.Key.endpointURLString,
            PushRelaySettings.Key.webPushDeliveryURLString,
            PushRelaySettings.Key.enabledAccountIDs,
            PushRelaySettings.Key.opaqueAccountTokens,
            PushRelaySettings.Key.deviceClientID,
            PushRelaySettings.Key.activeRegistration,
            PushRelaySettings.Key.subscriptionID,
            PushRelaySettings.Key.lastRegisteredAt,
            PushRelaySettings.Key.lastRegistrationError
        ] {
            #expect(!syncAllowlist.contains(key))
        }
    }

    @Test("secret store scopes bearer tokens strictly by normalized relay origin")
    func secretStoreOriginScoping() throws {
        let secretStore = InMemoryPushRelaySecretStore()
        try secretStore.saveBearerToken("token-for-a", forOrigin: "https://RELAY-A.example.com:443/v1/push")
        #expect(try secretStore.bearerToken(forOrigin: "https://relay-a.example.com/other") == "token-for-a")
        #expect(try secretStore.bearerToken(forOrigin: "https://relay-b.example.com/v1/push") == nil)
        #expect(try secretStore.bearerToken(forOrigin: "https://relay-a.example.com:8443/v1/push") == nil)

        let firstKey = try secretStore.loadOrCreateEncryptionKeyMaterial()
        let secondKey = try secretStore.loadOrCreateEncryptionKeyMaterial()
        #expect(firstKey == secondKey)

        try secretStore.saveBearerToken("   ", forOrigin: "https://relay-a.example.com")
        #expect(try secretStore.bearerToken(forOrigin: "https://relay-a.example.com") == nil)

        try secretStore.clearAll()
        #expect(try secretStore.encryptionKeyMaterial() == nil)
    }

    @Test("invalid or credential-bearing URLs are never persisted to UserDefaults")
    @MainActor
    func credentialBearingURLsNeverPersistToUserDefaults() throws {
        let suite = "PushRelayCredentialURL-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let controller = PushRelayRegistrationController(
            settingsStore: store,
            secretStore: InMemoryPushRelaySecretStore()
        )
        controller.updateEndpointDraft("https://user:supersecretpass@relay.example.com/push")
        controller.updateWebPushDeliveryURLDraft("https://alice:anothersecret@webpush.example.com/dev")

        #expect(controller.endpointValidationError != nil)
        #expect(defaults
            .string(forKey: PushRelaySettings.Key.endpointURLString) != "https://user:supersecretpass@relay.example.com/push")
        let allDefaultsText = String(describing: defaults.dictionaryRepresentation())
        #expect(!allDefaultsText.contains("supersecretpass"))
        #expect(!allDefaultsText.contains("anothersecret"))
    }

    @Test("controller blocks registration without a real APNs token and never sends raw email IDs")
    @MainActor
    func requiresRealAPNSTokenAndSendsOpaqueTokensOnly() async throws {
        let suite = "PushRelayOpaqueAndAPNS-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let imapAccountID = BrevAccount.imapSMTPAccountID(forEmailAddress: "henrik@northwind.example")
        let store = SettingsPersistenceStore(defaults: defaults)

        // 1. Without a real APNs device token, user-hosted relay cannot register and makes zero calls.
        let unprovisionedTransport = SequencedPushTransport(responses: [])
        let unprovisioned = PushRelayRegistrationController(
            settingsStore: store,
            secretStore: InMemoryPushRelaySecretStore(),
            client: PushRelayClient(transport: unprovisionedTransport),
            devicePushTokenProvider: { nil }
        )
        await unprovisioned.setEnabled(true)
        unprovisioned.updateEndpointDraft("https://relay.example.com/register")
        unprovisioned.setAccount(imapAccountID, enabled: true)
        #expect(!unprovisioned.canRegister)
        await unprovisioned.register()
        #expect(await unprovisionedTransport.requests().isEmpty)

        // 2. With a real APNs token, registration succeeds and sends ONLY opaque `acct-<uuid>` tokens.
        let registerJSON = Data("""
        {"subscriptionID":"sub-real-1","state":"active"}
        """.utf8)
        let transport = SequencedPushTransport(responses: [(registerJSON, 201)])
        let controller = PushRelayRegistrationController(
            settingsStore: store,
            secretStore: InMemoryPushRelaySecretStore(),
            client: PushRelayClient(transport: transport),
            devicePushTokenProvider: { "apns-hex-device-token-99" }
        )
        #expect(controller.canRegister)
        await controller.register()

        let requests = await transport.requests()
        #expect(requests.count == 1)
        let body = try String(decoding: #require(requests[0].httpBody), as: UTF8.self)
        #expect(body.contains("apns-hex-device-token-99"))
        #expect(!body.contains("henrik@northwind.example"))
        #expect(!body.contains("imap-smtp:"))
        let opaqueToken = try #require(controller.settings.opaqueAccountTokens[imapAccountID])
        #expect(body.contains(opaqueToken))
    }

    @Test("switching relay URL creates fresh subscription, isolates bearer tokens, and unregisters old relay")
    @MainActor
    func relaySwitchIsolatesBearerTokensAndUnregistersOldTarget() async throws {
        let suite = "PushRelaySwitch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsPersistenceStore(defaults: defaults)
        let secretStore = InMemoryPushRelaySecretStore()
        let transport = SequencedPushTransport(responses: [
            (Data("""
            {"subscriptionID":"sub-on-A"}
            """.utf8), 201),
            (Data("""
            {"subscriptionID":"sub-on-B"}
            """.utf8), 201),
            (Data(), 200) // DELETE to relay A
        ])

        let controller = PushRelayRegistrationController(
            settingsStore: store,
            secretStore: secretStore,
            client: PushRelayClient(transport: transport),
            devicePushTokenProvider: { "apns-device-token-1" }
        )

        // Register on Relay A with secret-A.
        await controller.setEnabled(true)
        controller.updateEndpointDraft("https://relay-a.example/register")
        controller.bearerTokenInput = "secret-for-relay-A"
        controller.setAccount("acct-1", enabled: true)
        await controller.register()
        #expect(controller.settings.activeRegistration?.subscriptionID == "sub-on-A")
        #expect(controller.hasSavedBearerToken)

        // Switch draft URL to Relay B (leaving bearer field empty): Relay A's secret MUST NOT leak!
        controller.updateEndpointDraft("https://relay-b.example/register")
        #expect(!controller.hasSavedBearerToken)
        await controller.register()

        let requests = await transport.requests()
        #expect(requests.count == 3)
        // Request 0: POST to Relay A with Bearer secret-for-relay-A
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.host == "relay-a.example")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer secret-for-relay-A")
        // Request 1: FRESH POST (not PUT!) to Relay B with ZERO Authorization header
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].url?.host == "relay-b.example")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "X-Brev-Subscription-ID") == nil)
        // Request 2: DELETE cleanup to Relay A using Relay A's subscription ID and Relay A's bearer token
        #expect(requests[2].httpMethod == "DELETE")
        #expect(requests[2].url?.host == "relay-a.example")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer secret-for-relay-A")
        #expect(requests[2].value(forHTTPHeaderField: "X-Brev-Subscription-ID") == "sub-on-A")

        #expect(controller.settings.activeRegistration?.endpointURLString == "https://relay-b.example/register")
        #expect(controller.settings.activeRegistration?.subscriptionID == "sub-on-B")
    }

    @Test("disabling push while registration is in flight immediately unregisters the returned subscription")
    @MainActor
    func concurrentDisableUnregistersInFlightSubscription() async throws {
        let suite = "PushRelayConcurrentDisable-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let gate = InFlightRequestGate()
        let transport = GatedPushTransport(
            gate: gate,
            registerResponse: (Data("""
            {"subscriptionID":"sub-race-1"}
            """.utf8), 201),
            unregisterResponse: (Data(), 200)
        )
        let controller = PushRelayRegistrationController(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            secretStore: InMemoryPushRelaySecretStore(),
            client: PushRelayClient(transport: transport),
            devicePushTokenProvider: { "apns-token-race" }
        )

        await controller.setEnabled(true)
        controller.updateEndpointDraft("https://relay.example.com/register")
        controller.setAccount("acct-1", enabled: true)

        let registerTask = Task { await controller.register() }
        await gate.waitUntilRequestStarted()

        // User turns push off while register() is awaiting network response.
        await controller.setEnabled(false)
        await gate.release()
        await registerTask.value

        #expect(!controller.settings.isEnabled)
        #expect(controller.settings.activeRegistration == nil)
        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[1].httpMethod == "DELETE")
        #expect(requests[1].value(forHTTPHeaderField: "X-Brev-Subscription-ID") == "sub-race-1")
    }

    @Test("JMAP controller transitions from pendingVerification to active only after RFC 8620 §7.2.2 verify")
    @MainActor
    func jmapVerificationStateTransitionInController() async throws {
        let suite = "PushRelayJMAPVerify-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let createJSON = Data("""
        {"methodResponses":[["PushSubscription/set",{"created":{"brev-push-sub":{"id":"jmap-1"}}},"c0"]]}
        """.utf8)
        let verifyJSON = Data("""
        {"methodResponses":[["PushSubscription/set",{"updated":{"jmap-1":null}},"c0"]]}
        """.utf8)
        let transport = SequencedPushTransport(responses: [(createJSON, 200), (verifyJSON, 200)])

        let controller = PushRelayRegistrationController(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            secretStore: InMemoryPushRelaySecretStore(),
            client: PushRelayClient(transport: transport)
        )
        await controller.setEnabled(true)
        controller.setMode(.jmapWebPush)
        controller.updateEndpointDraft("https://jmap.example.com/api/")
        controller.updateWebPushDeliveryURLDraft("https://webpush.example.com/push/dev1")
        controller.setAccount("acct-jmap", enabled: true)
        #expect(controller.canRegister)

        await controller.register()
        #expect(controller.settings.activeRegistration?.state == .pendingVerification)
        #expect(controller.isAwaitingJMAPVerification)

        await controller.verifyActiveJMAPSubscription(code: "code-1234")
        #expect(controller.settings.activeRegistration?.state == .active)
        #expect(!controller.isAwaitingJMAPVerification)
    }

    @Test("settings search indexes Closed-App Push and scrolls JMAP/push queries to the always-visible group title")
    func settingsSearchIndexesPushRelayWithVisibleTarget() {
        let groupTitle = String(localized: "Closed-App Push (Self-Hosted)", bundle: .module)
        let titles = SettingsSection.notifications.searchableControlTitles
        #expect(titles.contains(groupTitle))
        #expect(titles.contains(String(localized: "JMAP WebPush", bundle: .module)))

        let jmapResults = SettingsSearchResult.results(for: "JMAP", sections: [.notifications])
        #expect(jmapResults.count == 1)
        #expect(jmapResults.first?.target == groupTitle)

        let urlResults = SettingsSearchResult.results(for: "Push relay URL", sections: [.notifications])
        #expect(urlResults.first?.target == groupTitle)
    }
}

private actor SequencedPushTransport: PushRelayHTTPTransport {
    private var queued: [(Data, Int)]
    private var recorded: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        queued = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        let next = queued.isEmpty ? (Data(), 200) : queued.removeFirst()
        let url = request.url ?? URL(string: "https://relay.example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.1,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.0, response)
    }

    func requests() -> [URLRequest] {
        recorded
    }
}

private actor InFlightRequestGate {
    private var started = false
    private var released = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func markStartedAndWait() async {
        started = true
        for cont in startedContinuations {
            cont.resume()
        }
        startedContinuations.removeAll()
        guard !released else { return }
        await withCheckedContinuation { cont in
            releaseContinuations.append(cont)
        }
    }

    func waitUntilRequestStarted() async {
        guard !started else { return }
        await withCheckedContinuation { cont in
            startedContinuations.append(cont)
        }
    }

    func release() {
        released = true
        for cont in releaseContinuations {
            cont.resume()
        }
        releaseContinuations.removeAll()
    }
}

private actor GatedPushTransport: PushRelayHTTPTransport {
    private let gate: InFlightRequestGate
    private let registerResponse: (Data, Int)
    private let unregisterResponse: (Data, Int)
    private var recorded: [URLRequest] = []

    init(
        gate: InFlightRequestGate,
        registerResponse: (Data, Int),
        unregisterResponse: (Data, Int)
    ) {
        self.gate = gate
        self.registerResponse = registerResponse
        self.unregisterResponse = unregisterResponse
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        let isFirst = recorded.count == 1
        if isFirst {
            await gate.markStartedAndWait()
        }
        let next = isFirst ? registerResponse : unregisterResponse
        let url = request.url ?? URL(string: "https://relay.example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.1,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.0, response)
    }

    func requests() -> [URLRequest] {
        recorded
    }
}
