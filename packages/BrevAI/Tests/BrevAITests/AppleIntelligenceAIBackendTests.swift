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

@testable import BrevAI
import Foundation
import Testing

private actor MockAppleIntelligenceGenerator: AppleIntelligenceTextGenerating {
    var recordedInstructions: [String] = []
    var recordedPrompts: [String] = []
    var stubbedResult: Result<String, Error> = .success("On-device draft response.")

    func respond(instructions: String, prompt: String) async throws -> String {
        recordedInstructions.append(instructions)
        recordedPrompts.append(prompt)
        return try stubbedResult.get()
    }
}

private actor EmptySecretStore: AIProviderSecretStore {
    func apiKey(for _: AIProviderID) async throws -> String? { nil }
    func setAPIKey(_: String, for _: AIProviderID) async throws {}
    func deleteAPIKey(for _: AIProviderID) async throws {}
}

@Suite("Apple Intelligence on-device AI (ADR-0094)")
struct AppleIntelligenceAIBackendTests {
    @Test("Platform labels report On this Mac / iPhone / iPad")
    func platformLabels() {
        #expect(OnDeviceAIPlatformLabel.transparencyLabel(for: .mac) == "On this Mac")
        #expect(OnDeviceAIPlatformLabel.transparencyLabel(for: .iPhone) == "On this iPhone")
        #expect(OnDeviceAIPlatformLabel.transparencyLabel(for: .iPad) == "On this iPad")
        #expect(OnDeviceAIPlatformLabel.appleIntelligenceDisplayName(for: .mac) == "On this Mac (Apple Intelligence)")
        #expect(OnDeviceAIPlatformLabel.appleIntelligenceDisplayName(for: .iPhone) == "On this iPhone (Apple Intelligence)")
        #expect(OnDeviceAIPlatformLabel.appleIntelligenceDisplayName(for: .iPad) == "On this iPad (Apple Intelligence)")
    }

    @Test("Availability gating marks only .available selectable and explains every disabled reason")
    func availabilityGating() {
        #expect(AppleIntelligenceAvailability.available.isSelectable)
        for unavailable in [
            AppleIntelligenceAvailability.unsupportedOS,
            .deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unavailable(reason: "")
        ] {
            #expect(!unavailable.isSelectable)
            #expect(!unavailable.settingsStatusMessage.isEmpty)
        }
    }

    @Test("generateReply wraps mail as untrusted and enforces conservative on-device context budget")
    func generateReplyAppliesSafetyAndBudget() async throws {
        let generator = MockAppleIntelligenceGenerator()
        let backend = AppleIntelligenceAIBackend(
            contextBudget: .onDevice,
            availability: { .available },
            generator: generator
        )

        let budget = try #require(backend.contextBudget)
        #expect(budget == .onDevice)
        #expect(budget.maxSourceMessages < AIBackendContextBudget.standard.maxSourceMessages)
        #expect(budget.maxTotalContextBytes < AIBackendContextBudget.standard.maxTotalContextBytes)

        let messages = (1 ... 10).map { index in
            AIMessage(role: .user, content: "Message \(index) body")
        }
        let response = try await backend.generateReply(to: messages, instruction: "Summarize briefly.")
        #expect(response.text == "On-device draft response.")
        let instructions = await generator.recordedInstructions
        let prompts = await generator.recordedPrompts
        #expect(instructions.count == 1)
        #expect(instructions[0].contains(AISafetyPolicy.untrustedMailSystemInstruction))
        #expect(instructions[0].contains("Summarize briefly."))
        #expect(prompts[0].contains("<<<UNTRUSTED_EMAIL_CONTENT>>>"))
        #expect(!prompts[0].contains("Message 1 body"))
        #expect(prompts[0].contains("Message 10 body"))
    }

    @Test("shortcut and generateReply fail closed when Apple Intelligence is unavailable")
    func failsClosedWhenUnavailable() async {
        let generator = MockAppleIntelligenceGenerator()
        let backend = AppleIntelligenceAIBackend(
            availability: { .appleIntelligenceNotEnabled },
            generator: generator
        )

        await #expect(throws: AIBackendError.self) {
            _ = try await backend.generateReply(
                to: [AIMessage(role: .user, content: "Hello")],
                instruction: nil
            )
        }
        await #expect(throws: AIBackendError.self) {
            _ = try await backend.shortcut(.shorten, on: "Hello world")
        }
        #expect(await generator.recordedPrompts.isEmpty)
    }

    @Test("shortcut fails closed with contextWindowExceeded instead of silently dropping draft tail")
    func shortcutFailsClosedWhenOverBudget() async {
        let generator = MockAppleIntelligenceGenerator()
        let backend = AppleIntelligenceAIBackend(
            contextBudget: AIBackendContextBudget(maxSourceMessages: 2, maxTotalContextBytes: 120),
            availability: { .available },
            generator: generator
        )
        let oversizedDraft = String(repeating: "Long paragraph content. ", count: 20)
        await #expect(throws: AIBackendError.contextWindowExceeded) {
            _ = try await backend.shortcut(.shorten, on: oversizedDraft)
        }
        #expect(await generator.recordedPrompts.isEmpty)
    }

    @Test("Apple Intelligence route stays installed while model is preparing and works once ready")
    func modelNotReadyRecoversInSameSession() async throws {
        let suiteName = "AppleIntelligenceRecoveryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try AIProviderConfigurationStore(defaults: defaults).save([
            AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: true)
        ])

        final class ReadinessBox: @unchecked Sendable {
            var status: AppleIntelligenceAvailability = .modelNotReady
        }
        let box = ReadinessBox()
        let generator = MockAppleIntelligenceGenerator()
        let resolver = AIProviderBackendResolver(
            defaults: defaults,
            secretStore: EmptySecretStore(),
            appleIntelligenceAvailability: { box.status },
            appleIntelligenceGenerator: generator
        )

        let resolved = await resolver.backends(forAccountIDs: ["acct-1"], builtInBackends: [:])
        let backend = try #require(resolved["acct-1"])
        await #expect(throws: AIBackendError.self) {
            _ = try await backend.shortcut(.shorten, on: "Hello world")
        }
        #expect(await generator.recordedPrompts.isEmpty)

        box.status = .available
        let response = try await backend.shortcut(.shorten, on: "Hello world")
        #expect(response.text == "On-device draft response.")
    }

    @Test("Apple Intelligence provider configuration needs no API key or HTTP endpoint and reports On this Mac")
    func providerConfigurationAndResolver() async throws {
        let config = AIProviderConfiguration.appleIntelligence(isEnabled: true, isDefault: true)
        #expect(config.kind == .appleIntelligence)
        #expect(config.kind.isOnDevice)
        #expect(!config.requiresAPIKey)
        #expect(config.validationIssues.isEmpty)
        #expect(config.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)

        let suiteName = "AppleIntelligenceResolverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try AIProviderConfigurationStore(defaults: defaults).save([config])

        let generator = MockAppleIntelligenceGenerator()
        let availableResolver = AIProviderBackendResolver(
            defaults: defaults,
            secretStore: EmptySecretStore(),
            appleIntelligenceAvailability: { .available },
            appleIntelligenceGenerator: generator
        )
        let resolved = await availableResolver.backends(forAccountIDs: ["acct-1"], builtInBackends: [:])
        let backend = try #require(resolved["acct-1"])
        #expect(backend.identifier == "apple-intelligence")
        #expect(backend.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(backend.contextBudget == .onDevice)

        let unavailableResolver = AIProviderBackendResolver(
            defaults: defaults,
            secretStore: EmptySecretStore(),
            appleIntelligenceAvailability: { .unsupportedOS },
            appleIntelligenceGenerator: generator
        )
        let blocked = await unavailableResolver.backends(forAccountIDs: ["acct-1"], builtInBackends: [:])
        #expect(blocked["acct-1"] == nil)
    }

    @Test("On-device AI strings have Norwegian catalog translations")
    func norwegianCatalogCoverage() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrevAI/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])

        for key in [
            "On this Mac",
            "On this iPhone",
            "On this iPad",
            "On this Mac (Apple Intelligence)",
            "On this iPhone (Apple Intelligence)",
            "On this iPad (Apple Intelligence)",
            "Ready on this device. Text stays local and works offline.",
            "Requires macOS 26 or later.",
            "Requires iOS 26 or later.",
            "This device does not support Apple Intelligence.",
            "Turn on Apple Intelligence in System Settings to use on-device AI.",
            "Apple Intelligence is still preparing its on-device model. Try again shortly.",
            "Apple Intelligence is currently unavailable on this device.",
            "This message is too long for the on-device model. Try a shorter selection or thread."
        ] {
            let entry = try #require(strings[key] as? [String: Any], "Missing BrevAI key: \(key)")
            let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = nb?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String)?.isEmpty == false, "Missing nb translation for: \(key)")
        }
    }
}
