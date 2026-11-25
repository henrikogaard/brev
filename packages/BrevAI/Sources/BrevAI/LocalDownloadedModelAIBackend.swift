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

import Darwin
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
/// `llama-cli` / `llama-completion` helper, passes prompts via private `0600` temporary files (never in
/// command-line arguments visible to `ps`), drains stdout and stderr concurrently to avoid pipe deadlocks,
/// and terminates/reaps the child process promptly on Swift `Task` cancellation.
public struct DefaultLocalModelInferenceRuntime: LocalModelInferenceRuntime {
    /// Whether this platform currently supports executing downloaded local models natively.
    public static var isPlatformSupported: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Plain-language localized message explaining why local model downloads are gated on unsupported platforms.
    public static var platformUnsupportedMessage: String {
        String(
            localized: "Downloaded local models currently require a Mac. Use Apple Intelligence or a configured provider on this device.",
            bundle: .module
        )
    }

    private let executableSearchPaths: [String]
    private let maxResponseTokens: Int
    private let promptTempRoot: URL

    /// Creates a local runtime checking `executableSearchPaths` strictly on the local filesystem.
    public init(
        executableSearchPaths: [String] = DefaultLocalModelInferenceRuntime.defaultExecutableSearchPaths(),
        maxResponseTokens: Int = 512,
        promptTempRoot: URL = LocalModelPromptTempStorage.defaultRootDirectory
    ) {
        self.executableSearchPaths = executableSearchPaths
        self.maxResponseTokens = max(64, maxResponseTokens)
        self.promptTempRoot = promptTempRoot
        LocalModelPromptTempStorage.cleanupAbandonedPromptDirectories(in: promptTempRoot)
    }

    /// Removes abandoned unlocked local-AI prompt temp directories left behind by terminated sessions.
    public static func cleanupAbandonedPromptDirectories(
        in root: URL = LocalModelPromptTempStorage.defaultRootDirectory
    ) {
        LocalModelPromptTempStorage.cleanupAbandonedPromptDirectories(in: root)
    }

    /// Synchronously terminates any active local-AI subprocesses and removes their private prompt directories.
    public static func terminateActiveAndCleanupAll(
        in root: URL = LocalModelPromptTempStorage.defaultRootDirectory
    ) {
        LocalModelPromptTempStorage.terminateActiveAndCleanupAll(in: root)
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

    /// Returns whether a compatible local inference helper executable is currently installed on disk.
    public static func isInferenceRuntimeInstalled(
        in searchPaths: [String] = defaultExecutableSearchPaths()
    ) -> Bool {
        #if os(macOS)
        return searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
        #else
        _ = searchPaths
        return false
        #endif
    }

    /// Whether this runtime instance finds a compatible local inference executable on disk.
    public var isInferenceRuntimeInstalled: Bool {
        Self.isInferenceRuntimeInstalled(in: executableSearchPaths)
    }

    public func generate(
        modelURL: URL,
        descriptor _: LocalModelDescriptor,
        instructions: String,
        prompt: String
    ) async throws -> String {
        try Task.checkCancellation()

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
        throw AIBackendError.unavailable(Self.platformUnsupportedMessage)
        #endif
    }

    #if os(macOS)
    private func runLocalSubprocess(
        executablePath: String,
        modelURL: URL,
        instructions: String,
        prompt: String
    ) async throws -> String {
        try Task.checkCancellation()

        let promptFiles = try PrivatePromptFiles.create(
            in: promptTempRoot,
            instructions: instructions,
            prompt: prompt
        )
        defer { promptFiles.cleanup() }

        let cancellationBox = SubprocessCancellationBox()
        let tokenBudget = maxResponseTokens

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executablePath)
                    // Pass mail and instruction text exclusively through private 0600 temp files
                    // (never as CLI arguments visible to other same-user processes via `ps`).
                    process.arguments = [
                        "-m", modelURL.path,
                        "--system-prompt-file", promptFiles.instructionsURL.path,
                        "-f", promptFiles.promptURL.path,
                        "-n", String(tokenBudget),
                        "--no-display-prompt",
                        "--single-turn"
                    ]

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    process.standardInput = FileHandle.nullDevice

                    guard cancellationBox.registerBeforeLaunch(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    LocalModelPromptTempStorage.attachProcess(process, to: promptFiles.sessionID)

                    do {
                        try process.run()
                    } catch {
                        LocalModelPromptTempStorage.detachProcess(for: promptFiles.sessionID)
                        cancellationBox.clearProcess()
                        continuation.resume(
                            throwing: AIBackendError.unavailable(
                                String(
                                    localized: "The local model runtime failed to generate a response: \(error.localizedDescription)",
                                    bundle: .module
                                )
                            )
                        )
                        return
                    }

                    // Close the parent's copies of the write ends so reading reaches EOF once the child exits.
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()

                    // Drain stdout and stderr concurrently while the subprocess runs so large diagnostics
                    // or generated replies cannot fill either pipe buffer and deadlock waitUntilExit().
                    let readGroup = DispatchGroup()
                    let outputBox = PipeOutputBox()

                    readGroup.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        outputBox.setStdout(data)
                        readGroup.leave()
                    }

                    readGroup.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        outputBox.setStderr(data)
                        readGroup.leave()
                    }

                    readGroup.wait()
                    process.waitUntilExit()
                    LocalModelPromptTempStorage.detachProcess(for: promptFiles.sessionID)
                    cancellationBox.clearProcess()

                    if cancellationBox.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    guard process.terminationStatus == 0 else {
                        let stderrText = String(data: outputBox.stderrData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let detail = (stderrText?.isEmpty == false ? stderrText : nil)
                            ?? String(localized: "exit status \(process.terminationStatus)", bundle: .module)
                        continuation.resume(
                            throwing: AIBackendError.unavailable(
                                String(
                                    localized: "The local model runtime failed to generate a response: \(detail)",
                                    bundle: .module
                                )
                            )
                        )
                        return
                    }

                    let output = (String(data: outputBox.stdoutData, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                }
            }
        } onCancel: {
            cancellationBox.cancelAndTerminate()
        }
    }
    #endif
}

/// Manages the dedicated `0700` temporary directory holding private local-AI prompt files (#304).
///
/// Active invocations hold an advisory `flock(LOCK_EX | LOCK_NB)` on `.lock` inside their per-call
/// directory and register for synchronous cleanup on app termination. Startup sweeps remove any
/// unlocked/abandoned prompt directories without touching a live invocation in another process.
public enum LocalModelPromptTempStorage {
    static let lockFileName = ".lock"

    /// Dedicated root folder under the system temporary directory for private local-AI prompts.
    public static var defaultRootDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-local-ai-prompts", isDirectory: true)
    }

    /// Sweeps unlocked/abandoned per-invocation prompt directories under `root`.
    public static func cleanupAbandonedPromptDirectories(
        in root: URL = defaultRootDirectory
    ) {
        #if os(macOS)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let lockURL = entry.appendingPathComponent(lockFileName, isDirectory: false)
            let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
            guard fd >= 0 else { continue }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                try? FileManager.default.removeItem(at: entry)
                _ = flock(fd, LOCK_UN)
            }
            close(fd)
        }
        #else
        _ = root
        #endif
    }

    /// Synchronously terminates any active local-AI subprocesses and removes their private prompt directories.
    public static func terminateActiveAndCleanupAll(
        in root: URL = defaultRootDirectory
    ) {
        #if os(macOS)
        ActivePromptRegistry.shared.terminateAllAndCleanup()
        cleanupAbandonedPromptDirectories(in: root)
        #else
        _ = root
        #endif
    }

    #if os(macOS)
    static func registerActiveSession(id: UUID, directoryURL: URL, lockFD: Int32) {
        ActivePromptRegistry.shared.register(id: id, directoryURL: directoryURL, lockFD: lockFD)
    }

    static func attachProcess(_ process: Process, to sessionID: UUID) {
        ActivePromptRegistry.shared.attachProcess(process, to: sessionID)
    }

    static func detachProcess(for sessionID: UUID) {
        ActivePromptRegistry.shared.detachProcess(for: sessionID)
    }

    static func cleanupActiveSession(id: UUID) {
        ActivePromptRegistry.shared.cleanup(id: id)
    }
    #endif
}

#if os(macOS)
private final class ActivePromptRegistry: @unchecked Sendable {
    struct Entry {
        let directoryURL: URL
        let lockFD: Int32
        var process: Process?
    }

    static let shared = ActivePromptRegistry()

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func register(id: UUID, directoryURL: URL, lockFD: Int32) {
        lock.lock()
        entries[id] = Entry(directoryURL: directoryURL, lockFD: lockFD, process: nil)
        lock.unlock()
    }

    func attachProcess(_ process: Process, to id: UUID) {
        lock.lock()
        entries[id]?.process = process
        lock.unlock()
    }

    func detachProcess(for id: UUID) {
        lock.lock()
        entries[id]?.process = nil
        lock.unlock()
    }

    func cleanup(id: UUID) {
        lock.lock()
        let entry = entries.removeValue(forKey: id)
        lock.unlock()

        guard let entry else { return }
        removeAndUnlock(entry)
    }

    func terminateAllAndCleanup() {
        lock.lock()
        let snapshot = Array(entries.values)
        entries.removeAll()
        lock.unlock()

        for entry in snapshot {
            if let process = entry.process, process.isRunning {
                process.terminate()
            }
            removeAndUnlock(entry)
        }
    }

    private func removeAndUnlock(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.directoryURL)
        _ = flock(entry.lockFD, LOCK_UN)
        close(entry.lockFD)
    }
}

private struct PrivatePromptFiles: Sendable {
    let sessionID: UUID
    let directoryURL: URL
    let instructionsURL: URL
    let promptURL: URL

    static func create(
        in root: URL = LocalModelPromptTempStorage.defaultRootDirectory,
        instructions: String,
        prompt: String
    ) throws -> PrivatePromptFiles {
        if mkdir(root.path, 0o700) != 0 && errno != EEXIST {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        _ = chmod(root.path, 0o700)

        let sessionID = UUID()
        let directoryURL = root.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard mkdir(directoryURL.path, 0o700) == 0 else {
            throw AIBackendError.unavailable(
                String(
                    localized: "Could not prepare private temporary prompt files for local inference.",
                    bundle: .module
                )
            )
        }

        let lockURL = directoryURL.appendingPathComponent(LocalModelPromptTempStorage.lockFileName, isDirectory: false)
        let lockFD = open(lockURL.path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD) }
            try? FileManager.default.removeItem(at: directoryURL)
            throw AIBackendError.unavailable(
                String(
                    localized: "Could not prepare private temporary prompt files for local inference.",
                    bundle: .module
                )
            )
        }

        let instructionsURL = directoryURL.appendingPathComponent("instructions.txt", isDirectory: false)
        let promptURL = directoryURL.appendingPathComponent("prompt.txt", isDirectory: false)
        do {
            try writePrivateFile(instructions, to: instructionsURL)
            try writePrivateFile(prompt, to: promptURL)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            _ = flock(lockFD, LOCK_UN)
            close(lockFD)
            throw error
        }

        LocalModelPromptTempStorage.registerActiveSession(
            id: sessionID,
            directoryURL: directoryURL,
            lockFD: lockFD
        )

        return PrivatePromptFiles(
            sessionID: sessionID,
            directoryURL: directoryURL,
            instructionsURL: instructionsURL,
            promptURL: promptURL
        )
    }

    func cleanup() {
        LocalModelPromptTempStorage.cleanupActiveSession(id: sessionID)
    }

    private static func writePrivateFile(_ text: String, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            throw AIBackendError.unavailable(
                String(
                    localized: "Could not prepare private temporary prompt files for local inference.",
                    bundle: .module
                )
            )
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(text.utf8))
    }
}

private final class PipeOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _stdout = Data()
    private var _stderr = Data()

    var stdoutData: Data {
        lock.lock()
        defer { lock.unlock() }
        return _stdout
    }

    var stderrData: Data {
        lock.lock()
        defer { lock.unlock() }
        return _stderr
    }

    func setStdout(_ data: Data) {
        lock.lock()
        _stdout = data
        lock.unlock()
    }

    func setStderr(_ data: Data) {
        lock.lock()
        _stderr = data
        lock.unlock()
    }
}

private final class SubprocessCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var runningProcess: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func registerBeforeLaunch(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_isCancelled else { return false }
        runningProcess = process
        return true
    }

    func clearProcess() {
        lock.lock()
        runningProcess = nil
        lock.unlock()
    }

    func cancelAndTerminate() {
        lock.lock()
        _isCancelled = true
        let process = runningProcess
        lock.unlock()

        if let process, process.isRunning {
            process.terminate()
        }
    }
}
#endif

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

    /// Returns whether a compatible local inference helper executable is installed in the default search paths.
    public static var isInferenceRuntimeInstalled: Bool {
        DefaultLocalModelInferenceRuntime.isInferenceRuntimeInstalled()
    }

    public let identifier = LocalDownloadedModelAIBackend.backendIdentifier
    public let displayName: String
    public let transparencyLabel: String
    public let contextBudget: AIBackendContextBudget?
    public let isOnDeviceZeroNetwork = true

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
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        return AIResponse(text: text)
    }

    public func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        try Task.checkCancellation()
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
        try Task.checkCancellation()
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
