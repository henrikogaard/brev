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
import CryptoKit
import Foundation
import Testing

private actor CountingDownloadTransport: LocalModelDownloadTransport {
    enum Mode: Sendable {
        case chunks([Data], delayNanoseconds: UInt64 = 0)
        case failure(Error)
    }

    var requestURLs: [URL] = []
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func download(
        from url: URL,
        onChunk: @escaping @Sendable (_ chunk: Data, _ expectedTotalBytes: Int64) async throws -> Void
    ) async throws {
        requestURLs.append(url)
        switch mode {
        case .chunks(let chunks, let delayNanoseconds):
            let total = Int64(chunks.reduce(0) { $0 + $1.count })
            for chunk in chunks {
                try Task.checkCancellation()
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                try await onChunk(chunk, total)
            }
        case .failure(let error):
            throw error
        }
    }
}

private actor MockLocalInferenceRuntime: LocalModelInferenceRuntime {
    struct Invocation: Equatable, Sendable {
        let modelURL: URL
        let modelID: String
        let instructions: String
        let prompt: String
    }

    var invocations: [Invocation] = []
    var stubbedResponse: Result<String, Error> = .success("Local model reply.")

    func generate(
        modelURL: URL,
        descriptor: LocalModelDescriptor,
        instructions: String,
        prompt: String
    ) async throws -> String {
        invocations.append(
            Invocation(
                modelURL: modelURL,
                modelID: descriptor.id,
                instructions: instructions,
                prompt: prompt
            )
        )
        return try stubbedResponse.get()
    }
}

private actor EmptyLocalSecretStore: AIProviderSecretStore {
    func apiKey(for _: AIProviderID) async throws -> String? { nil }
    func setAPIKey(_: String, for _: AIProviderID) async throws {}
    func deleteAPIKey(for _: AIProviderID) async throws {}
}

@Suite("Downloaded local AI models (#304)")
struct LocalModelDownloadAndBackendTests {
    @Test("Curated catalog exposes open-licensed models with HTTPS URLs and valid SHA-256 digests")
    func curatedCatalogMetadata() {
        let models = LocalModelCatalog.curatedModels
        #expect(models.count >= 3)
        #expect(LocalModelCatalog.model(id: LocalModelCatalog.defaultModelID) != nil)

        let ids = Set(models.map(\.id))
        #expect(ids.count == models.count)

        for model in models {
            #expect(!model.displayName.isEmpty)
            #expect(!model.summary.isEmpty)
            #expect(!model.parameterCountLabel.isEmpty)
            #expect(!model.quantization.isEmpty)
            #expect(!model.licenseSPDX.isEmpty)
            #expect(!model.fileName.isEmpty)
            #expect(model.expectedByteCount > 0)
            #expect(model.minimumMemoryGiB >= 4)
            #expect(model.hasValidHTTPSDownloadURL)
            #expect(model.downloadURL.scheme == "https")
            #expect(LocalModelDescriptor.isValidSHA256Hex(model.sha256Hex))
        }
    }

    @Test("Platform labels report On this Mac / iPhone / iPad (download a model)")
    func downloadedModelPlatformLabels() {
        #expect(OnDeviceAIPlatformLabel.downloadedModelDisplayName(for: .mac) == "On this Mac (download a model)")
        #expect(OnDeviceAIPlatformLabel.downloadedModelDisplayName(for: .iPhone) == "On this iPhone (download a model)")
        #expect(OnDeviceAIPlatformLabel.downloadedModelDisplayName(for: .iPad) == "On this iPad (download a model)")
    }

    @Test("Zero network calls occur until explicit download(modelID:) is invoked")
    func zeroNetworkCallsBeforeExplicitDownload() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = Data("verified-local-model-weights".utf8)
        let descriptor = Self.makeDescriptor(id: "test-model", payload: payload)
        let transport = CountingDownloadTransport(mode: .chunks([payload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        #expect(await manager.state(for: descriptor.id) == .notDownloaded)
        #expect(await manager.allStates()[descriptor.id] == .notDownloaded)
        #expect(await manager.installedModelURL(for: descriptor.id) == nil)
        #expect(await manager.totalInstalledBytes() == 0)
        #expect(await transport.requestURLs.isEmpty)
    }

    @Test("Streaming download verifies SHA-256, installs atomically, and excludes storage from backups")
    func verifiedDownloadInstallsAtomicallyWithBackupExclusion() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let chunk1 = Data(repeating: 0x41, count: 4096)
        let chunk2 = Data(repeating: 0x42, count: 4096)
        let fullPayload = chunk1 + chunk2
        let descriptor = Self.makeDescriptor(id: "qwen-test", payload: fullPayload)
        let transport = CountingDownloadTransport(mode: .chunks([chunk1, chunk2]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        let installedURL = try await manager.download(modelID: descriptor.id)
        #expect(await transport.requestURLs == [descriptor.downloadURL])
        #expect(FileManager.default.fileExists(atPath: installedURL.path))
        #expect(try Data(contentsOf: installedURL) == fullPayload)

        let partURL = installedURL.deletingLastPathComponent().appendingPathComponent("\(descriptor.fileName).part")
        #expect(!FileManager.default.fileExists(atPath: partURL.path))

        let rootValues = try tempRoot.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let modelDirValues = try installedURL.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        let fileValues = try installedURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(rootValues.isExcludedFromBackup == true)
        #expect(modelDirValues.isExcludedFromBackup == true)
        #expect(fileValues.isExcludedFromBackup == true)

        let state = await manager.state(for: descriptor.id)
        guard case .installed(_, let fileSizeBytes) = state else {
            Issue.record("Expected .installed state, got \(state)")
            return
        }
        #expect(fileSizeBytes == Int64(fullPayload.count))
        #expect(await manager.totalInstalledBytes() == Int64(fullPayload.count))
        #expect(await manager.installedModelURL(for: descriptor.id) == installedURL)

        let manifest = try #require(await manager.manifest(for: descriptor.id))
        #expect(manifest.modelID == descriptor.id)
        #expect(manifest.sha256Hex == descriptor.sha256Hex)
        #expect(manifest.fileSizeBytes == Int64(fullPayload.count))

        // Reloading a fresh manager from disk recognizes the installed model without network calls.
        let idleTransport = CountingDownloadTransport(mode: .chunks([]))
        let reloaded = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: idleTransport
        )
        #expect(await reloaded.installedModelURL(for: descriptor.id) == installedURL)
        #expect(await idleTransport.requestURLs.isEmpty)
    }

    @Test("Tampered bytes fail closed on SHA-256 mismatch and immediately delete the temp file")
    func tamperedDownloadDeletesTempFile() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let expectedPayload = Data("legitimate-weights".utf8)
        let tamperedPayload = Data("tampered-weights!!".utf8)
        let descriptor = Self.makeDescriptor(id: "tampered-model", payload: expectedPayload)
        let transport = CountingDownloadTransport(mode: .chunks([tamperedPayload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        do {
            _ = try await manager.download(modelID: descriptor.id)
            Issue.record("Expected checksum mismatch error")
        } catch let error as LocalModelDownloadError {
            guard case .checksumMismatch(let expected, let actual) = error else {
                Issue.record("Unexpected LocalModelDownloadError: \(error)")
                return
            }
            #expect(expected == descriptor.sha256Hex)
            #expect(actual == Self.sha256Hex(tamperedPayload))
        }

        let modelDir = tempRoot.appendingPathComponent(descriptor.id, isDirectory: true)
        let partURL = modelDir.appendingPathComponent("\(descriptor.fileName).part")
        let finalURL = modelDir.appendingPathComponent(descriptor.fileName)
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(!FileManager.default.fileExists(atPath: finalURL.path))
        #expect(await manager.installedModelURL(for: descriptor.id) == nil)
        if case .failed(let message) = await manager.state(for: descriptor.id) {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected .failed state after checksum mismatch")
        }
    }

    @Test("Non-HTTPS download URLs are rejected before touching the network")
    func nonHTTPSURLRejected() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = Data("model-data".utf8)
        let httpDescriptor = Self.makeDescriptor(
            id: "http-model",
            payload: payload,
            url: URL(string: "http://example.test/model.gguf")!
        )
        let transport = CountingDownloadTransport(mode: .chunks([payload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [httpDescriptor],
            transport: transport
        )

        await #expect(throws: LocalModelDownloadError.insecureDownloadURL(httpDescriptor.downloadURL.absoluteString)) {
            _ = try await manager.download(modelID: httpDescriptor.id)
        }
        #expect(await transport.requestURLs.isEmpty)
    }

    @Test("Redirect policy blocks HTTP downgrade and cross-origin when configured")
    func redirectPolicyEnforcesHTTPSAndOrigin() {
        let original = URL(string: "https://huggingface.co/model.gguf")!
        let httpsSameHost = URL(string: "https://huggingface.co/cdn/model.gguf")!
        let httpsCDN = URL(string: "https://cdn-lfs.hf.co/model.gguf")!
        let httpDowngrade = URL(string: "http://huggingface.co/model.gguf")!

        #expect(URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsOnly.allowsRedirect(from: original, to: httpsSameHost))
        #expect(URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsOnly.allowsRedirect(from: original, to: httpsCDN))
        #expect(!URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsOnly.allowsRedirect(from: original, to: httpDowngrade))

        #expect(URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsSameOriginOnly.allowsRedirect(
            from: original,
            to: httpsSameHost
        ))
        #expect(!URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsSameOriginOnly.allowsRedirect(
            from: original,
            to: httpsCDN
        ))
        #expect(!URLSessionLocalModelDownloadTransport.RedirectPolicy.httpsSameOriginOnly.allowsRedirect(
            from: original,
            to: httpDowngrade
        ))
    }

    @Test("Cancelling an in-flight download removes the temp file and resets state")
    func cancellationCleansUpPartFile() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let chunks = (0 ..< 20).map { _ in Data(repeating: 0x55, count: 1024) }
        let fullPayload = chunks.reduce(Data(), +)
        let descriptor = Self.makeDescriptor(id: "cancel-model", payload: fullPayload)
        let transport = CountingDownloadTransport(mode: .chunks(chunks, delayNanoseconds: 30_000_000))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        let downloadTask = Task {
            try await manager.download(modelID: descriptor.id)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await manager.cancelDownload(modelID: descriptor.id)

        do {
            _ = try await downloadTask.value
            Issue.record("Expected download cancellation error")
        } catch let error as LocalModelDownloadError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            // Also acceptable if outer task caught Swift CancellationError.
        }

        let partURL = tempRoot
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .appendingPathComponent("\(descriptor.fileName).part")
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(await manager.state(for: descriptor.id) == .notDownloaded)
    }

    @Test("Oversized downloads fail closed and delete the partial file")
    func oversizedDownloadFailsClosed() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let smallPayload = Data("small-expected".utf8)
        let oversizedPayload = Data(repeating: 0x7A, count: 1_200_000)
        let descriptor = Self.makeDescriptor(id: "oversized-model", payload: smallPayload)
        let transport = CountingDownloadTransport(mode: .chunks([oversizedPayload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        do {
            _ = try await manager.download(modelID: descriptor.id)
            Issue.record("Expected sizeLimitExceeded error")
        } catch let error as LocalModelDownloadError {
            guard case .sizeLimitExceeded = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        let partURL = tempRoot
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .appendingPathComponent("\(descriptor.fileName).part")
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(await manager.installedModelURL(for: descriptor.id) == nil)
    }

    @Test("deleteModel removes installed weights and frees local storage")
    func deleteModelFreesDiskSpace() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = Data(repeating: 0x33, count: 2048)
        let descriptor = Self.makeDescriptor(id: "delete-me", payload: payload)
        let transport = CountingDownloadTransport(mode: .chunks([payload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )

        let installedURL = try await manager.download(modelID: descriptor.id)
        #expect(FileManager.default.fileExists(atPath: installedURL.path))
        #expect(await manager.totalInstalledBytes() == 2048)

        try await manager.deleteModel(modelID: descriptor.id)
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
        #expect(await manager.installedModelURL(for: descriptor.id) == nil)
        #expect(await manager.totalInstalledBytes() == 0)
        #expect(await manager.state(for: descriptor.id) == .notDownloaded)
    }

    @Test("LocalDownloadedModelAIBackend refuses inference before download and runs strictly locally after download")
    func backendGatingAndLocalExecution() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = Data("verified-model-bytes".utf8)
        let descriptor = Self.makeDescriptor(id: "local-exec-model", payload: payload)
        let transport = CountingDownloadTransport(mode: .chunks([payload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )
        let runtime = MockLocalInferenceRuntime()
        let backend = LocalDownloadedModelAIBackend(
            modelID: descriptor.id,
            downloadManager: manager,
            runtime: runtime
        )

        #expect(backend.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(backend.contextBudget == .onDevice)

        // Before download: fails closed with zero runtime invocations and zero network calls.
        await #expect(throws: AIBackendError.self) {
            _ = try await backend.generateReply(
                to: [AIMessage(role: .user, content: "Hello")],
                instruction: "Reply politely."
            )
        }
        #expect(await runtime.invocations.isEmpty)
        #expect(await transport.requestURLs.isEmpty)

        // Explicit user download succeeds.
        let modelURL = try await manager.download(modelID: descriptor.id)

        // Inference now runs strictly locally with untrusted-mail wrapping and no further network calls.
        let reply = try await backend.generateReply(
            to: [AIMessage(role: .user, content: "Can we meet tomorrow?")],
            instruction: "Accept briefly."
        )
        #expect(reply.text == "Local model reply.")
        #expect(await transport.requestURLs.count == 1)

        let invocations = await runtime.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0].modelURL == modelURL)
        #expect(invocations[0].modelID == descriptor.id)
        #expect(invocations[0].instructions.contains(AISafetyPolicy.untrustedMailSystemInstruction))
        #expect(invocations[0].instructions.contains("Accept briefly."))
        #expect(invocations[0].prompt.contains("<<<UNTRUSTED_EMAIL_CONTENT>>>"))

        // Oversized shortcut fails closed with contextWindowExceeded.
        let tightBackend = LocalDownloadedModelAIBackend(
            modelID: descriptor.id,
            contextBudget: AIBackendContextBudget(maxSourceMessages: 2, maxTotalContextBytes: 120),
            downloadManager: manager,
            runtime: runtime
        )
        let oversized = String(repeating: "Long paragraph text. ", count: 20)
        await #expect(throws: AIBackendError.contextWindowExceeded) {
            _ = try await tightBackend.shortcut(.shorten, on: oversized)
        }
    }

    @Test("Default local runtime fails closed when no local runtime binary is installed")
    func defaultRuntimeFailsClosedWithoutBinary() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = Data("weights".utf8)
        let descriptor = Self.makeDescriptor(id: "no-binary", payload: payload)
        let runtime = DefaultLocalModelInferenceRuntime(executableSearchPaths: ["/nonexistent/brev-llama-cli"])

        await #expect(throws: AIBackendError.self) {
            _ = try await runtime.generate(
                modelURL: tempRoot.appendingPathComponent(descriptor.fileName),
                descriptor: descriptor,
                instructions: "System",
                prompt: "Hello"
            )
        }
    }

    @Test("AIProviderConfiguration and AIProviderBackendResolver route downloaded local models without API keys or HTTP URLs")
    func configurationPersistenceAndResolverRouting() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let config = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: LocalModelCatalog.defaultModelID,
            isEnabled: true,
            isDefault: true
        )
        #expect(config.kind == .onDeviceDownloadedModel)
        #expect(config.kind.isOnDevice)
        #expect(!config.requiresAPIKey)
        #expect(config.validationIssues.isEmpty)
        #expect(config.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)

        let suiteName = "LocalModelResolverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AIProviderConfigurationStore(defaults: defaults)
        try store.save([config])
        #expect(try store.load() == [config])

        let payload = Data("model-bytes".utf8)
        let descriptor = Self.makeDescriptor(id: LocalModelCatalog.defaultModelID, payload: payload)
        let transport = CountingDownloadTransport(mode: .chunks([payload]))
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot,
            catalog: [descriptor],
            transport: transport
        )
        let runtime = MockLocalInferenceRuntime()

        let resolver = AIProviderBackendResolver(
            defaults: defaults,
            secretStore: EmptyLocalSecretStore(),
            localModelDownloadManager: manager,
            localModelRuntime: runtime
        )

        let resolvedDefault = await resolver.backends(
            forAccountIDs: ["personal-acct"],
            builtInBackends: [:]
        )
        let backend = try #require(resolvedDefault["personal-acct"])
        #expect(backend.identifier == LocalDownloadedModelAIBackend.backendIdentifier)
        #expect(backend.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(backend.contextBudget == .onDevice)

        // Per-account override routes specifically to the assigned account.
        let hostedDefault = try #require(AIProviderConfiguration(
            id: AIProviderID("hosted-default"),
            kind: .openAICompatible,
            displayName: "Hosted AI",
            endpointURL: URL(string: "https://ai.example.test/v1"),
            modelID: "gpt-4.1-mini",
            isEnabled: true,
            isDefault: true,
            assignedAccountID: nil
        ))
        let localOverride = AIProviderConfiguration.onDeviceDownloadedModel(
            modelID: descriptor.id,
            isEnabled: true,
            isDefault: false,
            assignedAccountID: "private-acct"
        )
        try store.save([hostedDefault, localOverride])
        var assignments = AIProviderAccountAssignments()
        assignments.assign(providerID: localOverride.id, toAccountID: "private-acct")
        try AIProviderAccountAssignmentStore(defaults: defaults).save(assignments)

        let resolvedPerAccount = await resolver.backends(
            forAccountIDs: ["private-acct"],
            builtInBackends: [:]
        )
        let overrideBackend = try #require(resolvedPerAccount["private-acct"])
        #expect(overrideBackend.identifier == LocalDownloadedModelAIBackend.backendIdentifier)
        #expect(overrideBackend.transparencyLabel == OnDeviceAIPlatformLabel.transparencyLabel)
    }

    @Test("Downloaded local model strings have Norwegian catalog translations")
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
            "On this Mac (download a model)",
            "On this iPhone (download a model)",
            "On this iPad (download a model)",
            "Download a local model in Settings before running on-device AI.",
            "The downloaded model file failed SHA-256 verification and was removed.",
            "Model downloads require an HTTPS URL.",
            "The model download was cancelled."
        ] {
            let entry = try #require(strings[key] as? [String: Any], "Missing BrevAI key: \(key)")
            let nb = (entry["localizations"] as? [String: Any])?["nb"] as? [String: Any]
            let unit = nb?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String)?.isEmpty == false, "Missing nb translation for: \(key)")
        }
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevLocalModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeDescriptor(
        id: String,
        payload: Data,
        url: URL = URL(string: "https://models.example.test/\(UUID().uuidString).gguf")!
    ) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: id,
            displayName: "Test Model \(id)",
            summary: "Compact test model for offline unit tests.",
            parameterCountLabel: "3B",
            quantization: "Q4_K_M",
            expectedByteCount: Int64(payload.count),
            licenseSPDX: "Apache-2.0",
            downloadURL: url,
            sha256Hex: sha256Hex(payload),
            minimumMemoryGiB: 8,
            fileName: "\(id).gguf"
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
