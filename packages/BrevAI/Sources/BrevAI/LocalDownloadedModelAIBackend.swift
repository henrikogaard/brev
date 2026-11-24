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

import Foundation

/// Local inference runtime seam for running verified on-device GGUF weights strictly offline (#304).
public protocol LocalModelInferenceRuntime: Sendable {
    /// Generates plain text locally using the verified model file at `modelURL`.
    func generate(
        modelURL: URL,
        descriptor: LocalModelDescriptor,
        instructions: String,
        prompt: String
    ) async throws -> String
}

/// Default local inference runtime that discovers a local GGUF CLI runtime on macOS or fails closed offline.
///
/// This runtime performs zero network calls. On macOS it checks configured local paths for an installed
/// `llama-cli` / `llama-completion` helper; if none is present (or on iOS), it fails closed with an
/// actionable localized error while keeping verified weights intact.
public struct DefaultLocalModelInferenceRuntime: LocalModelInferenceRuntime {
    private let executableSearchPaths: [String]
    private let maxResponseTokens: Int

    /// Creates a local runtime checking `executableSearchPaths` strictly on the local filesystem.
    public init(
        executableSearchPaths: [String] = DefaultLocalModelInferenceRuntime.defaultExecutableSearchPaths(),
        maxResponseTokens: Int = 512
    ) {
        self.executableSearchPaths = executableSearchPaths
        self.maxResponseTokens = max(64, maxResponseTokens)
    }

    /// Standard local paths inspected on macOS without making any network requests.
    public static func defaultExecutableSearchPaths() -> [String] {
        #if os(macOS)
        var paths: [String] = []
        if let helperDir = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true).path
            .nilIfEmpty {
            paths.append("\(helperDir)/llama-cli")
            paths.append("\(helperDir)/llama-completion")
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli"
        ])
        return paths
        #else
        return []
        #endif
    }

    public func generate(
        modelURL: URL,
        descriptor _: LocalModelDescriptor,
        instructions: String,
        prompt: String
    ) async throws -> String {
        #if os(macOS)
        guard let executablePath = executableSearchPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw AIBackendError.unavailable(
                String(
                    localized: "The downloaded model weights are verified on this device, but no compatible local inference runtime is installed yet.",
                    bundle: .module
                )
            )
        }

        return try await runLocalSubprocess(
            executablePath: executablePath,
            modelURL: modelURL,
            instructions: instructions,
            prompt: prompt
        )
        #else
        _ = (modelURL, instructions, prompt)
        throw AIBackendError.unavailable(
            String(
                localized: "The downloaded model weights are verified on this device, but no compatible local inference runtime is installed yet.",
                bundle: .module
            )
        )
        #endif
    }

    #if os(macOS)
    private func runLocalSubprocess(
        executablePath: String,
        modelURL: URL,
        instructions: String,
        prompt: String
    ) async throws -> String {
        let tokenBudget = maxResponseTokens
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "-m", modelURL.path,
                "-sys", instructions,
                "-p", prompt,
                "-n", String(tokenBudget),
                "--no-display-prompt",
                "--single-turn"
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw AIBackendError.unavailable(
                    String(
                        localized: "The local model runtime failed to generate a response: \(error.localizedDescription)",
                        bundle: .module
                    )
                )
            }

            process.waitUntilExit()
            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stderrText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit status \(process.terminationStatus)"
                throw AIBackendError.unavailable(
                    String(
                        localized: "The local model runtime failed to generate a response: \(stderrText)",
                        bundle: .module
                    )
                )
            }

            return (String(data: outputData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
    #endif
}

/// On-device `AIBackend` backed by user-downloaded, SHA-256-verified local model weights (#304, Slice 2).
///
/// Inference runs strictly offline with zero network calls and zero API keys. Before every
/// invocation, the backend verifies that the selected model's weights and manifest exist locally
/// and enforces `AISafetyPolicy` untrusted-mail wrapping plus a conservative on-device context budget.
public struct LocalDownloadedModelAIBackend: AIBackend {
    /// Stable provider configuration ID for downloaded local models.
    public static let providerID = AIProviderID("on-device-local-model")

    /// Stable machine backend identifier.
    public static let backendIdentifier = "on-device-local-model"

    public let identifier = LocalDownloadedModelAIBackend.backendIdentifier
    public let displayName: String
    public let transparencyLabel: String
    public let contextBudget: AIBackendContextBudget?

    /// Catalog model ID configured for this backend.
    public let modelID: String

    private let effectiveBudget: AIBackendContextBudget
    private let downloadManager: LocalModelDownloadManager
    private let runtime: any LocalModelInferenceRuntime

    /// Creates an on-device downloaded-model backend.
    ///
    /// - Parameters:
    ///   - modelID: Catalog model identifier to execute locally.
    ///   - displayName: Localized settings display name (defaults to platform downloaded-model label).
    ///   - transparencyLabel: Localized output label (defaults to `"On this Mac"` / `"On this iPhone"` / `"On this iPad"`).
    ///   - contextBudget: Message and context-byte cap (defaults to `.onDevice`).
    ///   - downloadManager: Backup-excluded local weight manager (defaults to `.shared`).
    ///   - runtime: Local inference runtime seam (defaults to `DefaultLocalModelInferenceRuntime`).
    public init(
        modelID: String = LocalModelCatalog.defaultModelID,
        displayName: String = OnDeviceAIPlatformLabel.downloadedModelDisplayName,
        transparencyLabel: String = OnDeviceAIPlatformLabel.transparencyLabel,
        contextBudget: AIBackendContextBudget = .onDevice,
        downloadManager: LocalModelDownloadManager = .shared,
        runtime: any LocalModelInferenceRuntime = DefaultLocalModelInferenceRuntime()
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.transparencyLabel = transparencyLabel
        self.contextBudget = contextBudget
        effectiveBudget = contextBudget
        self.downloadManager = downloadManager
        self.runtime = runtime
    }

    public func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse {
        let (modelURL, descriptor) = try await verifiedInstalledModel()
        let bounded = try AISafetyPolicy.validatedMessages(messages, budget: effectiveBudget)

        var instructionsParts = [AISafetyPolicy.untrustedMailSystemInstruction]
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            instructionsParts.append(instruction)
        }
        let instructions = instructionsParts.joined(separator: "\n\n")
        let prompt = Self.formatPrompt(from: bounded.messages)
        let text = try await runtime.generate(
            modelURL: modelURL,
            descriptor: descriptor,
            instructions: instructions,
            prompt: prompt
        )
        return AIResponse(text: text)
    }

    public func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        let (modelURL, descriptor) = try await verifiedInstalledModel()
        let bounded = try AISafetyPolicy.validatedMessages(
            [AIMessage(role: .user, content: text)],
            budget: effectiveBudget
        )
        guard !bounded.wasTruncated else {
            throw AIBackendError.contextWindowExceeded
        }

        let instructions = [
            AISafetyPolicy.untrustedMailSystemInstruction,
            Self.shortcutInstruction(for: action)
        ].joined(separator: "\n\n")
        let prompt = Self.formatPrompt(from: bounded.messages)
        let result = try await runtime.generate(
            modelURL: modelURL,
            descriptor: descriptor,
            instructions: instructions,
            prompt: prompt
        )
        return AIResponse(text: result)
    }

    private func verifiedInstalledModel() async throws -> (URL, LocalModelDescriptor) {
        guard let descriptor = await downloadManager.descriptor(for: modelID),
              let modelURL = await downloadManager.installedModelURL(for: modelID),
              let manifest = await downloadManager.manifest(for: modelID),
              manifest.sha256Hex.lowercased() == descriptor.sha256Hex.lowercased()
        else {
            throw AIBackendError.unavailable(
                String(
                    localized: "Download a local model in Settings before running on-device AI.",
                    bundle: .module
                )
            )
        }
        return (modelURL, descriptor)
    }

    private static func formatPrompt(from messages: [AIMessage]) -> String {
        messages.map { message in
            switch message.role {
            case .system:
                return message.content
            case .assistant:
                return "Assistant:\n\(message.content)"
            case .user:
                return message.content
            }
        }
        .joined(separator: "\n\n")
    }

    private static func shortcutInstruction(for action: AIShortcutAction) -> String {
        switch action {
        case .shorten:
            return "Rewrite the email draft more concisely while preserving its meaning. Return only the rewritten text."
        case .expand:
            return "Expand the email draft with clear, helpful detail while preserving its intent. Return only the rewritten text."
        case .formal:
            return "Rewrite the email draft in a formal, professional tone. Return only the rewritten text."
        case .casual:
            return "Rewrite the email draft in a relaxed, conversational tone. Return only the rewritten text."
        case .friendly:
            return "Rewrite the email draft in a warm, friendly tone. Return only the rewritten text."
        case .improveWriting:
            return "Improve the clarity and flow of the email draft without changing its facts. Return only the rewritten text."
        case .fixSpelling:
            return "Fix spelling and grammar mistakes in the email draft while keeping the author's voice. Return only the corrected text."
        case .translate:
            return "Translate the email draft clearly and naturally into English (or the requested target language). Return only the translation."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
