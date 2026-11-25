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
import Darwin
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
            // Curated upstream URLs must pin an immutable 40-char commit revision, never mutable /resolve/main/.
            #expect(!model.downloadURL.path.contains("/resolve/main/"))
            let components = model.downloadURL.pathComponents
            let resolveIndex = components.firstIndex(of: "resolve")
            #expect(resolveIndex != nil)
            if let resolveIndex, components.indices.contains(resolveIndex + 1) {
                let revision = components[resolveIndex + 1]
                #expect(revision.count == 40)
                #expect(revision.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
            }
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
        #expect(backend.isOnDeviceZeroNetwork)

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
        #expect(backend.isOnDeviceZeroNetwork)

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

    @Test("Startup cleans up abandoned .part staging files while leaving locked active staging files intact")
    func startupCleansAbandonedPartFilesOnly() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let abandonedDir = tempRoot.appendingPathComponent("abandoned-model", isDirectory: true)
        let activeDir = tempRoot.appendingPathComponent("active-model", isDirectory: true)
        try FileManager.default.createDirectory(at: abandonedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeDir, withIntermediateDirectories: true)

        let abandonedPart = abandonedDir.appendingPathComponent("abandoned.gguf.part")
        try Data("stale-partial-bytes".utf8).write(to: abandonedPart)

        let lockedPart = activeDir.appendingPathComponent("active.gguf.part")
        let fd = open(lockedPart.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }

        _ = LocalModelDownloadManager(storageDirectory: tempRoot, catalog: [])

        #expect(!FileManager.default.fileExists(atPath: abandonedPart.path))
        #expect(FileManager.default.fileExists(atPath: lockedPart.path))
    }

    @Test("Platform capability reports macOS runtime support and localized unsupported copy")
    func platformCapabilityReporting() {
        #if os(macOS)
        #expect(DefaultLocalModelInferenceRuntime.isPlatformSupported)
        #else
        #expect(!DefaultLocalModelInferenceRuntime.isPlatformSupported)
        #endif
        #expect(!DefaultLocalModelInferenceRuntime.platformUnsupportedMessage.isEmpty)
    }

    #if os(macOS)
    @Test("Subprocess drains >128 KiB on stdout and stderr concurrently without deadlocking")
    func subprocessDrainsLargeStdoutAndStderrWithoutDeadlock() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = try Self.makeExecutableScript(
            in: tempRoot,
            name: "large-output.sh",
            body: """
            #!/bin/sh
            # Emit >160 KiB to stderr and >160 KiB to stdout simultaneously to exceed macOS 64 KiB pipe buffers.
            awk 'BEGIN { for (i = 0; i < 4096; i++) printf "EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE\\n" }' >&2
            awk 'BEGIN { for (i = 0; i < 4096; i++) printf "OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO\\n" }'
            """
        )

        let descriptor = Self.makeDescriptor(id: "pipe-test", payload: Data("w".utf8))
        let runtime = DefaultLocalModelInferenceRuntime(executableSearchPaths: [scriptURL.path])
        let output = try await runtime.generate(
            modelURL: tempRoot.appendingPathComponent("model.gguf"),
            descriptor: descriptor,
            instructions: "System rules",
            prompt: "Mail text"
        )
        #expect(output.utf8.count > 131_072)
        #expect(output.hasPrefix("OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO"))
    }

    @Test("Cancelling Swift Task terminates subprocess promptly and throws CancellationError")
    func cancellingTaskTerminatesSubprocessAndThrowsCancellationError() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let scriptURL = try Self.makeExecutableScript(
            in: tempRoot,
            name: "slow-model.sh",
            body: """
            #!/bin/sh
            sleep 30
            echo "STALE_OUTPUT_SHOULD_NEVER_RETURN"
            """
        )

        let descriptor = Self.makeDescriptor(id: "cancel-proc", payload: Data("w".utf8))
        let runtime = DefaultLocalModelInferenceRuntime(executableSearchPaths: [scriptURL.path])
        let startedAt = Date()

        let generationTask = Task {
            try await runtime.generate(
                modelURL: tempRoot.appendingPathComponent("model.gguf"),
                descriptor: descriptor,
                instructions: "System rules",
                prompt: "Mail text"
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        generationTask.cancel()

        do {
            _ = try await generationTask.value
            Issue.record("Expected CancellationError when cancelling local inference task")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(startedAt) < 5.0)
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("Subprocess passes prompt via private 0600 files (never CLI arguments) and cleans them up")
    func subprocessKeepsMailTextOutOfCLIArgumentsAndCleansTempFiles() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let secretInstruction = "SECRET_SYSTEM_INSTRUCTION_TOKEN_98765"
        let secretMail = "CONFIDENTIAL_MAIL_BODY_TOKEN_12345"
        let scriptURL = try Self.makeExecutableScript(
            in: tempRoot,
            name: "inspect-args.sh",
            body: """
            #!/bin/sh
            SYS_FILE=""
            PROMPT_FILE=""
            PREV=""
            for arg in "$@"; do
                if [ "$PREV" = "--system-prompt-file" ]; then
                    SYS_FILE="$arg"
                elif [ "$PREV" = "-f" ]; then
                    PROMPT_FILE="$arg"
                fi
                PREV="$arg"
            done
            echo "ARGS:$*"
            echo "SYS_PATH:$SYS_FILE"
            echo "PROMPT_PATH:$PROMPT_FILE"
            echo "SYS_PERM:$(stat -f %Lp "$SYS_FILE")"
            echo "PROMPT_PERM:$(stat -f %Lp "$PROMPT_FILE")"
            echo "SYS_CONTENT:$(cat "$SYS_FILE")"
            echo "PROMPT_CONTENT:$(cat "$PROMPT_FILE")"
            """
        )

        let descriptor = Self.makeDescriptor(id: "args-check", payload: Data("w".utf8))
        let runtime = DefaultLocalModelInferenceRuntime(executableSearchPaths: [scriptURL.path])
        let output = try await runtime.generate(
            modelURL: tempRoot.appendingPathComponent("model.gguf"),
            descriptor: descriptor,
            instructions: secretInstruction,
            prompt: secretMail
        )

        let lines = Dictionary(uniqueKeysWithValues: output.split(separator: "\n").compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            return (key, value)
        })

        let argsLine = try #require(lines["ARGS"])
        #expect(!argsLine.contains(secretInstruction))
        #expect(!argsLine.contains(secretMail))
        #expect(lines["SYS_PERM"] == "600")
        #expect(lines["PROMPT_PERM"] == "600")
        #expect(lines["SYS_CONTENT"] == secretInstruction)
        #expect(lines["PROMPT_CONTENT"] == secretMail)

        let sysPath = try #require(lines["SYS_PATH"])
        let promptPath = try #require(lines["PROMPT_PATH"])
        #expect(!FileManager.default.fileExists(atPath: sysPath))
        #expect(!FileManager.default.fileExists(atPath: promptPath))
    }

    @Test("Prompt temp directory sweep removes abandoned directories while preserving actively locked invocations")
    func promptTempSweepRemovesAbandonedAndPreservesLocked() throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let abandonedDir = tempRoot.appendingPathComponent("abandoned-session", isDirectory: true)
        let activeDir = tempRoot.appendingPathComponent("active-session", isDirectory: true)
        try FileManager.default.createDirectory(at: abandonedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeDir, withIntermediateDirectories: true)

        try Data("leftover-mail-body".utf8).write(to: abandonedDir.appendingPathComponent("prompt.txt"))
        try Data("active-mail-body".utf8).write(to: activeDir.appendingPathComponent("prompt.txt"))

        let activeLockURL = activeDir.appendingPathComponent(LocalModelPromptTempStorage.lockFileName)
        let fd = open(activeLockURL.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }

        LocalModelPromptTempStorage.cleanupAbandonedPromptDirectories(in: tempRoot)

        #expect(!FileManager.default.fileExists(atPath: abandonedDir.path))
        #expect(FileManager.default.fileExists(atPath: activeDir.path))
        #expect(FileManager.default.fileExists(atPath: activeDir.appendingPathComponent("prompt.txt").path))
    }

    @Test("Downloaded local model with stub helper script produces parsed ThreadTriageInsight via ProactiveOnDeviceTriageEngine")
    func downloadedLocalModelProducesParsedProactiveTriageInsight() async throws {
        let tempRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let promptRoot = tempRoot.appendingPathComponent("prompts", isDirectory: true)
        let helperScript = try Self.makeExecutableScript(
            in: tempRoot,
            name: "stub-llama-cli.sh",
            body: """
            #!/bin/sh
            set -e
            MODEL=""
            SYS=""
            PROMPT=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -m) MODEL="$2"; shift 2 ;;
                    --system-prompt-file) SYS="$2"; shift 2 ;;
                    -f) PROMPT="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            test -f "$MODEL"
            test -f "$SYS"
            test -f "$PROMPT"
            printf '{"summary":"Alex needs budget approval before Friday afternoon.","priority":"urgent"}\\n'
            """
        )

        let payload = Data("verified-triage-model-weights".utf8)
        let descriptor = Self.makeDescriptor(id: "triage-model", payload: payload)
        let manager = LocalModelDownloadManager(
            storageDirectory: tempRoot.appendingPathComponent("models", isDirectory: true),
            catalog: [descriptor],
            transport: CountingDownloadTransport(mode: .chunks([payload]))
        )
        _ = try await manager.download(modelID: descriptor.id)

        let installedRuntime = DefaultLocalModelInferenceRuntime(
            executableSearchPaths: [helperScript.path],
            promptTempRoot: promptRoot
        )
        #expect(installedRuntime.isInferenceRuntimeInstalled)
        #expect(!DefaultLocalModelInferenceRuntime(executableSearchPaths: ["/nonexistent/brev-llama-cli"])
            .isInferenceRuntimeInstalled)

        let backend = LocalDownloadedModelAIBackend(
            modelID: descriptor.id,
            downloadManager: manager,
            runtime: installedRuntime
        )
        #expect(backend.isOnDeviceZeroNetwork)

        let engine = ProactiveOnDeviceTriageEngine()
        let settings = AIWriterSettings(
            isEnabled: true,
            consentGiven: true,
            proactiveOnDeviceTriageEnabled: true
        )
        let thread = ProactiveTriageThreadInput(
            cacheKey: "acct:triage-thread",
            sourceFingerprint: "fp-v1",
            isExcludedFolder: false,
            messages: [
                ProactiveTriageMessageInput(
                    sender: "Alex <alex@example.org>",
                    subject: "Q4 Budget Approval",
                    text: "Please approve the updated Q4 budget before Friday afternoon so finance can lock it.",
                    date: Date(timeIntervalSince1970: 1_760_000_000),
                    isRead: false
                )
            ]
        )

        let insight = try #require(await engine.insight(for: thread, settings: settings, backend: backend))
        #expect(insight.summary == "Alex needs budget approval before Friday afternoon.")
        #expect(insight.priority == .urgent)
        #expect(insight.attribution == OnDeviceAIPlatformLabel.transparencyLabel)
        #expect(insight.sourceFingerprint == "fp-v1")
    }
    #endif

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
            "Balanced multilingual drafting, rewriting, and thread summaries.",
            "Fast everyday replies, tone adjustments, and concise summaries.",
            "Strong structured reasoning for longer mail threads and action extraction.",
            "Download a local model in Settings before running on-device AI.",
            "Downloaded local models currently require a Mac. Use Apple Intelligence or a configured provider on this device.",
            "The downloaded model file failed SHA-256 verification and was removed.",
            "Model downloads require an HTTPS URL.",
            "The model download was cancelled.",
            "Unexpected non-HTTP response.",
            "Invalid expected SHA-256 digest in catalog.",
            "Could not create temporary download file.",
            "Could not lock temporary download file.",
            "Could not prepare private temporary prompt files for local inference.",
            "exit status %lld"
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

    #if os(macOS)
    private static func makeExecutableScript(
        in directory: URL,
        name: String,
        body: String
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name, isDirectory: false)
        try Data(body.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
    #endif

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
