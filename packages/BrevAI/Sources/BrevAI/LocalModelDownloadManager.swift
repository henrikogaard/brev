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

import CryptoKit
import Darwin
import Foundation

/// Observable download and installation state for a curated local AI model (#304).
public enum LocalModelDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case verifying
    case installed(installedAt: Date, fileSizeBytes: Int64)
    case failed(message: String)

    /// Whether verified weights are currently installed on disk.
    public var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    /// Whether a download or checksum verification is currently active.
    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying:
            return true
        case .notDownloaded, .installed, .failed:
            return false
        }
    }
}

/// On-disk manifest recorded alongside verified local model weights.
public struct LocalModelInstallManifest: Codable, Equatable, Sendable {
    public let modelID: String
    public let fileName: String
    public let sha256Hex: String
    public let fileSizeBytes: Int64
    public let installedAt: Date
    public let licenseSPDX: String
    public let sourceURL: URL

    /// Creates a manifest describing an installed, verified local model file.
    public init(
        modelID: String,
        fileName: String,
        sha256Hex: String,
        fileSizeBytes: Int64,
        installedAt: Date,
        licenseSPDX: String,
        sourceURL: URL
    ) {
        self.modelID = modelID
        self.fileName = fileName
        self.sha256Hex = sha256Hex
        self.fileSizeBytes = fileSizeBytes
        self.installedAt = installedAt
        self.licenseSPDX = licenseSPDX
        self.sourceURL = sourceURL
    }
}

/// Errors thrown while downloading, verifying, or storing local model weights.
public enum LocalModelDownloadError: Error, LocalizedError, Equatable, Sendable {
    case unknownModel(String)
    case insecureDownloadURL(String)
    case redirectBlocked(String)
    case httpError(statusCode: Int)
    case sizeLimitExceeded(written: Int64, limit: Int64)
    case checksumMismatch(expected: String, actual: String)
    case cancelled
    case storageError(String)
    case transportError(String)

    public var errorDescription: String? {
        switch self {
        case .unknownModel:
            return String(localized: "The requested local model is not in Brev’s catalog.", bundle: .module)
        case .insecureDownloadURL:
            return String(localized: "Model downloads require an HTTPS URL.", bundle: .module)
        case .redirectBlocked:
            return String(
                localized: "Blocked a non-HTTPS or disallowed redirect while downloading the model.",
                bundle: .module
            )
        case .httpError(let statusCode):
            return String(localized: "Model download failed with HTTP status \(statusCode).", bundle: .module)
        case .sizeLimitExceeded:
            return String(
                localized: "The model download exceeded the expected file size and was cancelled.",
                bundle: .module
            )
        case .checksumMismatch:
            return String(
                localized: "The downloaded model file failed SHA-256 verification and was removed.",
                bundle: .module
            )
        case .cancelled:
            return String(localized: "The model download was cancelled.", bundle: .module)
        case .storageError(let detail):
            return String(localized: "Could not save the local model on this device: \(detail)", bundle: .module)
        case .transportError(let detail):
            return String(localized: "Could not download the local model: \(detail)", bundle: .module)
        }
    }
}

/// Injectable streaming download transport so local model verification can be tested offline.
public protocol LocalModelDownloadTransport: Sendable {
    /// Streams chunks from an explicit user-initiated model download URL.
    func download(
        from url: URL,
        onChunk: @escaping @Sendable (_ chunk: Data, _ expectedTotalBytes: Int64) async throws -> Void
    ) async throws
}

/// Live `URLSession` streaming transport that enforces HTTPS strictly and blocks non-HTTPS redirects.
public struct URLSessionLocalModelDownloadTransport: LocalModelDownloadTransport {
    /// Redirect policy enforced during user-initiated model downloads.
    public enum RedirectPolicy: Equatable, Sendable {
        /// Allows redirects only to HTTPS URLs with a non-empty host (supports HTTPS CDN mirrors).
        case httpsOnly
        /// Allows redirects only to HTTPS URLs matching the original scheme, host, and port.
        case httpsSameOriginOnly

        /// Evaluates whether redirecting from `originalURL` to `targetURL` is permitted.
        public func allowsRedirect(from originalURL: URL, to targetURL: URL) -> Bool {
            guard let targetScheme = targetURL.scheme?.lowercased(),
                  targetScheme == "https",
                  let targetHost = targetURL.host?.lowercased(),
                  !targetHost.isEmpty
            else { return false }

            switch self {
            case .httpsOnly:
                return true
            case .httpsSameOriginOnly:
                guard let originalHost = originalURL.host?.lowercased() else { return false }
                return originalHost == targetHost && originalURL.port == targetURL.port
            }
        }
    }

    private let redirectPolicy: RedirectPolicy
    private let chunkSizeBytes: Int

    /// Creates a live HTTPS streaming transport with an ephemeral session configuration.
    public init(
        redirectPolicy: RedirectPolicy = .httpsOnly,
        chunkSizeBytes: Int = 65536
    ) {
        self.redirectPolicy = redirectPolicy
        self.chunkSizeBytes = max(4096, chunkSizeBytes)
    }

    public func download(
        from url: URL,
        onChunk: @escaping @Sendable (_ chunk: Data, _ expectedTotalBytes: Int64) async throws -> Void
    ) async throws {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            throw LocalModelDownloadError.insecureDownloadURL(url.absoluteString)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil

        let delegate = StrictHTTPSRedirectDelegate(originalURL: url, policy: redirectPolicy)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        } catch is CancellationError {
            throw LocalModelDownloadError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            if let blockedURL = delegate.blockedRedirectURL {
                throw LocalModelDownloadError.redirectBlocked(blockedURL)
            }
            throw LocalModelDownloadError.cancelled
        } catch {
            if let blockedURL = delegate.blockedRedirectURL {
                throw LocalModelDownloadError.redirectBlocked(blockedURL)
            }
            throw LocalModelDownloadError.transportError(error.localizedDescription)
        }

        if let blockedURL = delegate.blockedRedirectURL {
            throw LocalModelDownloadError.redirectBlocked(blockedURL)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalModelDownloadError.transportError(
                String(localized: "Unexpected non-HTTP response.", bundle: .module)
            )
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw LocalModelDownloadError.httpError(statusCode: httpResponse.statusCode)
        }

        let expectedTotal = httpResponse.expectedContentLength
        var buffer = Data()
        buffer.reserveCapacity(chunkSizeBytes)

        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= chunkSizeBytes {
                    try await onChunk(buffer, expectedTotal)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                try Task.checkCancellation()
                try await onChunk(buffer, expectedTotal)
            }
        } catch let error as LocalModelDownloadError {
            throw error
        } catch is CancellationError {
            throw LocalModelDownloadError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw LocalModelDownloadError.cancelled
        } catch {
            throw LocalModelDownloadError.transportError(error.localizedDescription)
        }
    }
}

private final class StrictHTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originalURL: URL
    private let policy: URLSessionLocalModelDownloadTransport.RedirectPolicy
    private let lock = NSLock()
    private var _blockedRedirectURL: String?

    var blockedRedirectURL: String? {
        lock.lock()
        defer { lock.unlock() }
        return _blockedRedirectURL
    }

    init(
        originalURL: URL,
        policy: URLSessionLocalModelDownloadTransport.RedirectPolicy
    ) {
        self.originalURL = originalURL
        self.policy = policy
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let targetURL = request.url,
              policy.allowsRedirect(from: originalURL, to: targetURL)
        else {
            lock.lock()
            _blockedRedirectURL = request.url?.absoluteString ?? "unknown"
            lock.unlock()
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Manages user-initiated downloads, streaming SHA-256 verification, and backup-excluded storage for local models (#304).
///
/// Initialization and state queries never make network requests. Network access occurs exclusively
/// when the user explicitly triggers `download(modelID:)`.
public actor LocalModelDownloadManager {
    private static let manifestFileName = "manifest.json"

    /// Shared default manager storing verified weights under `Application Support/Brev/LocalModels`.
    public static let shared = LocalModelDownloadManager()

    private let storageDirectory: URL
    private let catalog: [LocalModelDescriptor]
    private let transport: any LocalModelDownloadTransport
    private let now: @Sendable () -> Date

    private var states: [String: LocalModelDownloadState] = [:]
    private var activeTasks: [String: Task<URL, Error>] = [:]
    private var observers: [UUID: AsyncStream<[String: LocalModelDownloadState]>.Continuation] = [:]

    /// Creates a local model download manager.
    ///
    /// Cleans up abandoned `.part` staging files on startup (skipping any file locked by an active download)
    /// without making any network requests.
    ///
    /// - Parameters:
    ///   - storageDirectory: Backup-excluded root directory (defaults to `Application Support/Brev/LocalModels`).
    ///   - catalog: Curated model catalog (defaults to `LocalModelCatalog.curatedModels`).
    ///   - transport: Injectable download transport (defaults to `URLSessionLocalModelDownloadTransport`).
    ///   - now: Clock provider for deterministic tests.
    public init(
        storageDirectory: URL = LocalModelDownloadManager.defaultStorageDirectory(),
        catalog: [LocalModelDescriptor] = LocalModelCatalog.curatedModels,
        transport: any LocalModelDownloadTransport = URLSessionLocalModelDownloadTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storageDirectory = storageDirectory
        self.catalog = catalog
        self.transport = transport
        self.now = now
        Self.cleanupAbandonedStagingFiles(in: storageDirectory)
        states = Self.scanInstalledStates(in: storageDirectory, catalog: catalog)
    }

    /// Returns the default backup-excluded storage root (`~/Library/Application Support/Brev/LocalModels`).
    public static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Brev", isDirectory: true)
            .appendingPathComponent("LocalModels", isDirectory: true)
    }

    /// Returns the catalog models managed by this instance.
    public func catalogModels() -> [LocalModelDescriptor] {
        catalog
    }

    /// Returns the catalog descriptor matching `modelID`, if any.
    public func descriptor(for modelID: String) -> LocalModelDescriptor? {
        catalog.first { $0.id == modelID }
    }

    /// Returns the current local download/install state for `modelID` without making network calls.
    public func state(for modelID: String) -> LocalModelDownloadState {
        if let current = states[modelID] {
            if case .installed = current, installedModelURL(for: modelID) == nil {
                states[modelID] = .notDownloaded
                return .notDownloaded
            }
            return current
        }
        return .notDownloaded
    }

    /// Returns a snapshot of states for every model in the catalog without making network calls.
    public func allStates() -> [String: LocalModelDownloadState] {
        var snapshot: [String: LocalModelDownloadState] = [:]
        for model in catalog {
            snapshot[model.id] = state(for: model.id)
        }
        return snapshot
    }

    /// Streams state snapshots whenever any model's download or install state changes.
    public func stateUpdates() -> AsyncStream<[String: LocalModelDownloadState]> {
        let id = UUID()
        let initial = allStates()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    /// Returns the verified local file URL for `modelID` if both manifest and weight file exist on disk.
    public func installedModelURL(for modelID: String) -> URL? {
        guard let manifest = manifest(for: modelID) else { return nil }
        let fileURL = modelDirectory(for: modelID).appendingPathComponent(manifest.fileName, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return fileURL
    }

    /// Reads the stored install manifest for `modelID`, if present and valid.
    public func manifest(for modelID: String) -> LocalModelInstallManifest? {
        Self.readManifest(in: modelDirectory(for: modelID))
    }

    /// Returns every catalog model currently installed on disk.
    public func installedModels() -> [LocalModelDescriptor] {
        catalog.filter { installedModelURL(for: $0.id) != nil }
    }

    /// Calculates total disk usage in bytes across all installed local model weights.
    public func totalInstalledBytes() -> Int64 {
        var total: Int64 = 0
        for model in catalog {
            guard let fileURL = installedModelURL(for: model.id),
                  let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Starts or awaits an explicit user-initiated model download with streaming SHA-256 verification.
    @discardableResult
    public func download(modelID: String) async throws -> URL {
        if let existingTask = activeTasks[modelID] {
            return try await existingTask.value
        }

        guard let descriptor = descriptor(for: modelID) else {
            throw LocalModelDownloadError.unknownModel(modelID)
        }
        guard descriptor.downloadURL.scheme?.lowercased() == "https",
              let host = descriptor.downloadURL.host,
              !host.isEmpty
        else {
            let error = LocalModelDownloadError.insecureDownloadURL(descriptor.downloadURL.absoluteString)
            setState(.failed(message: error.localizedDescription), for: modelID)
            throw error
        }
        guard LocalModelDescriptor.isValidSHA256Hex(descriptor.sha256Hex) else {
            let error = LocalModelDownloadError.storageError(
                String(localized: "Invalid expected SHA-256 digest in catalog.", bundle: .module)
            )
            setState(.failed(message: error.localizedDescription), for: modelID)
            throw error
        }

        let task = Task<URL, Error> {
            try await self.performDownload(descriptor: descriptor)
        }
        activeTasks[modelID] = task
        defer { activeTasks[modelID] = nil }
        return try await task.value
    }

    /// Cancels an active download for `modelID`, cleaning up any partial file.
    public func cancelDownload(modelID: String) {
        activeTasks[modelID]?.cancel()
    }

    /// Deletes downloaded weights and manifest for `modelID`, resetting its state to `.notDownloaded`.
    public func deleteModel(modelID: String) throws {
        activeTasks[modelID]?.cancel()
        activeTasks[modelID] = nil

        let directory = modelDirectory(for: modelID)
        if FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                throw LocalModelDownloadError.storageError(error.localizedDescription)
            }
        }
        setState(.notDownloaded, for: modelID)
    }

    // MARK: - Private download pipeline

    private func performDownload(descriptor: LocalModelDescriptor) async throws -> URL {
        let modelID = descriptor.id
        let modelDir = modelDirectory(for: modelID)
        let partURL = modelDir.appendingPathComponent("\(descriptor.fileName).part", isDirectory: false)
        let finalURL = modelDir.appendingPathComponent(descriptor.fileName, isDirectory: false)
        let manifestURL = modelDir.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let maxAllowedBytes = Self.maximumAllowedBytes(for: descriptor)

        let streamState: StreamingWriteState
        do {
            try prepareBackupExcludedDirectory(storageDirectory)
            try prepareBackupExcludedDirectory(modelDir)
            try? FileManager.default.removeItem(at: partURL)
            streamState = try StreamingWriteState(
                fileURL: partURL,
                expectedByteCount: descriptor.expectedByteCount,
                maxAllowedBytes: maxAllowedBytes
            )
            try applyBackupExclusion(to: partURL)
        } catch let error as LocalModelDownloadError {
            setState(.failed(message: error.localizedDescription), for: modelID)
            throw error
        } catch {
            let wrapped = LocalModelDownloadError.storageError(error.localizedDescription)
            setState(.failed(message: wrapped.localizedDescription), for: modelID)
            throw wrapped
        }

        setState(
            .downloading(progress: 0, bytesWritten: 0, totalBytes: descriptor.expectedByteCount),
            for: modelID
        )

        do {
            try await transport.download(from: descriptor.downloadURL) { chunk, reportedTotal in
                try Task.checkCancellation()
                let progressSnapshot = try streamState.append(chunk: chunk, reportedTotalBytes: reportedTotal)
                await self.updateProgress(
                    modelID: modelID,
                    progress: progressSnapshot.progress,
                    bytesWritten: progressSnapshot.bytesWritten,
                    totalBytes: progressSnapshot.totalBytes
                )
            }

            try Task.checkCancellation()
            setState(.verifying, for: modelID)
            let result = try streamState.finalizeHashKeepingLock()

            guard result.sha256Hex == descriptor.sha256Hex.lowercased() else {
                streamState.abortAndDeletePartFile()
                let error = LocalModelDownloadError.checksumMismatch(
                    expected: descriptor.sha256Hex.lowercased(),
                    actual: result.sha256Hex
                )
                setState(.failed(message: error.localizedDescription), for: modelID)
                throw error
            }

            // Hold the advisory `.part` flock across atomic rename/replace so startup cleanup
            // in another process cannot race between hash verification and installation.
            do {
                defer { streamState.releaseLockAndClose() }
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: partURL)
                } else {
                    try FileManager.default.moveItem(at: partURL, to: finalURL)
                }
            }
            try applyBackupExclusion(to: finalURL)

            let installedAt = now()
            let manifest = LocalModelInstallManifest(
                modelID: descriptor.id,
                fileName: descriptor.fileName,
                sha256Hex: result.sha256Hex,
                fileSizeBytes: result.bytesWritten,
                installedAt: installedAt,
                licenseSPDX: descriptor.licenseSPDX,
                sourceURL: descriptor.downloadURL
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)
            try applyBackupExclusion(to: manifestURL)

            setState(.installed(installedAt: installedAt, fileSizeBytes: result.bytesWritten), for: modelID)
            return finalURL
        } catch let error as LocalModelDownloadError {
            streamState.abortAndDeletePartFile()
            if error == .cancelled {
                resetStateAfterCancellation(for: modelID)
            } else {
                setState(.failed(message: error.localizedDescription), for: modelID)
            }
            throw error
        } catch is CancellationError {
            streamState.abortAndDeletePartFile()
            resetStateAfterCancellation(for: modelID)
            throw LocalModelDownloadError.cancelled
        } catch {
            streamState.abortAndDeletePartFile()
            let wrapped = LocalModelDownloadError.storageError(error.localizedDescription)
            setState(.failed(message: wrapped.localizedDescription), for: modelID)
            throw wrapped
        }
    }

    private func updateProgress(
        modelID: String,
        progress: Double,
        bytesWritten: Int64,
        totalBytes: Int64
    ) {
        setState(
            .downloading(progress: progress, bytesWritten: bytesWritten, totalBytes: totalBytes),
            for: modelID
        )
    }

    private func resetStateAfterCancellation(for modelID: String) {
        if let manifest = manifest(for: modelID), installedModelURL(for: modelID) != nil {
            setState(.installed(installedAt: manifest.installedAt, fileSizeBytes: manifest.fileSizeBytes), for: modelID)
        } else {
            setState(.notDownloaded, for: modelID)
        }
    }

    private func setState(_ newState: LocalModelDownloadState, for modelID: String) {
        states[modelID] = newState
        let snapshot = allStates()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func modelDirectory(for modelID: String) -> URL {
        Self.modelDirectory(for: modelID, in: storageDirectory)
    }

    private func prepareBackupExcludedDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try applyBackupExclusion(to: url)
    }

    private func applyBackupExclusion(to url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private static func maximumAllowedBytes(for descriptor: LocalModelDescriptor) -> Int64 {
        let tolerance = max(descriptor.expectedByteCount / 20, 1_048_576)
        return descriptor.expectedByteCount.addingReportingOverflow(tolerance).partialValue
    }

    private static func modelDirectory(for modelID: String, in root: URL) -> URL {
        let sanitized = modelID.map { character -> Character in
            if character
                .isASCII &&
                (character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".") {
                return character
            }
            return "_"
        }
        return root.appendingPathComponent(String(sanitized), isDirectory: true)
    }

    private static func readManifest(in directory: URL) -> LocalModelInstallManifest? {
        let manifestURL = directory.appendingPathComponent(manifestFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(LocalModelInstallManifest.self, from: data)
    }

    /// Removes abandoned `.part` staging files left behind by crashed or terminated sessions.
    ///
    /// Uses a non-blocking advisory `flock(LOCK_EX | LOCK_NB)` so an active download in another
    /// Brev process holding an exclusive lock on its `.part` file is left untouched.
    private static func cleanupAbandonedStagingFiles(in root: URL) {
        guard let modelDirectories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for directory in modelDirectories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let entries = try? FileManager.default.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }

            for entry in entries where entry.pathExtension == "part" {
                let fd = open(entry.path, O_RDWR)
                guard fd >= 0 else { continue }
                if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                    try? FileManager.default.removeItem(at: entry)
                    _ = flock(fd, LOCK_UN)
                }
                close(fd)
            }
        }
    }

    private static func scanInstalledStates(
        in root: URL,
        catalog: [LocalModelDescriptor]
    ) -> [String: LocalModelDownloadState] {
        var scanned: [String: LocalModelDownloadState] = [:]
        for model in catalog {
            let directory = modelDirectory(for: model.id, in: root)
            if let manifest = readManifest(in: directory) {
                let fileURL = directory.appendingPathComponent(manifest.fileName, isDirectory: false)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    scanned[model.id] = .installed(
                        installedAt: manifest.installedAt,
                        fileSizeBytes: manifest.fileSizeBytes
                    )
                    continue
                }
            }
            scanned[model.id] = .notDownloaded
        }
        return scanned
    }
}

private final class StreamingWriteState: @unchecked Sendable {
    struct ProgressSnapshot: Sendable {
        let progress: Double
        let bytesWritten: Int64
        let totalBytes: Int64
    }

    struct FinalizedResult: Sendable {
        let bytesWritten: Int64
        let sha256Hex: String
    }

    private let lock = NSLock()
    private let fileURL: URL
    private let expectedByteCount: Int64
    private let maxAllowedBytes: Int64
    private var fileHandle: FileHandle?
    private var hasher = SHA256()
    private var bytesWritten: Int64 = 0

    init(fileURL: URL, expectedByteCount: Int64, maxAllowedBytes: Int64) throws {
        self.fileURL = fileURL
        self.expectedByteCount = expectedByteCount
        self.maxAllowedBytes = maxAllowedBytes

        let fd = open(fileURL.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw LocalModelDownloadError.storageError(
                String(localized: "Could not create temporary download file.", bundle: .module)
            )
        }
        // Hold an advisory exclusive lock while the download is active so startup cleanup
        // in another process never deletes an in-flight `.part` file.
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw LocalModelDownloadError.storageError(
                String(localized: "Could not lock temporary download file.", bundle: .module)
            )
        }
        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    func append(chunk: Data, reportedTotalBytes: Int64) throws -> ProgressSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let nextTotal = bytesWritten + Int64(chunk.count)
        if nextTotal > maxAllowedBytes {
            throw LocalModelDownloadError.sizeLimitExceeded(written: nextTotal, limit: maxAllowedBytes)
        }

        guard let handle = fileHandle else {
            throw LocalModelDownloadError.storageError(
                String(localized: "Could not create temporary download file.", bundle: .module)
            )
        }
        try handle.write(contentsOf: chunk)
        hasher.update(data: chunk)
        bytesWritten = nextTotal

        let denominator = max(reportedTotalBytes > 0 ? reportedTotalBytes : expectedByteCount, 1)
        let progress = min(1.0, max(0.0, Double(bytesWritten) / Double(denominator)))
        return ProgressSnapshot(progress: progress, bytesWritten: bytesWritten, totalBytes: denominator)
    }

    /// Flushes data and finalizes the SHA-256 digest while keeping the advisory `flock` held
    /// until the caller atomically installs the `.part` file and invokes `releaseLockAndClose()`.
    func finalizeHashKeepingLock() throws -> FinalizedResult {
        lock.lock()
        defer { lock.unlock() }

        if let handle = fileHandle {
            try handle.synchronize()
        }
        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return FinalizedResult(bytesWritten: bytesWritten, sha256Hex: hex)
    }

    /// Releases the advisory `flock` and closes the descriptor after atomic installation.
    func releaseLockAndClose() {
        lock.lock()
        defer { lock.unlock() }

        if let handle = fileHandle {
            _ = flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
            fileHandle = nil
        }
    }

    func abortAndDeletePartFile() {
        lock.lock()
        defer { lock.unlock() }

        try? FileManager.default.removeItem(at: fileURL)
        if let handle = fileHandle {
            _ = flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
            fileHandle = nil
        }
    }
}
