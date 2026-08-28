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

import UIKit
import UniformTypeIdentifiers

private final class ShareHandoffReservation: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var bytes = 0
    private let maximumCount: Int
    private let maximumBytes: Int

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    func reserve(bytes: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < maximumCount, self.bytes + bytes <= maximumBytes else { return false }
        count += 1
        self.bytes += bytes
        return true
    }
}

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.eu.brevmail.brev"
    private nonisolated static let maximumAttachmentCount = 20
    private nonisolated static let maximumAttachmentBytes = 25 * 1024 * 1024
    private nonisolated static let maximumSingleAttachmentBytes = 10 * 1024 * 1024
    private nonisolated static let staleHandoffAge: TimeInterval = 24 * 60 * 60

    private var sharedText: String?
    private var sharedURLs: [URL] = []
    private var sharedAttachmentURLs: [URL] = []
    private var unsupportedItemCount = 0
    private var extractionErrorMessage: String?

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let composeButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractSharedContent()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.86)

        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        titleLabel.text = String(localized: "Compose in Brev")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        subtitleLabel.text = String(localized: "Loading shared content...")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 3
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(subtitleLabel)

        composeButton.setTitle(String(localized: "Open Brev"), for: .normal)
        composeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        composeButton.backgroundColor = .systemGreen
        composeButton.setTitleColor(.white, for: .normal)
        composeButton.layer.cornerRadius = 12
        composeButton.translatesAutoresizingMaskIntoConstraints = false
        composeButton.addTarget(self, action: #selector(openBrev), for: .touchUpInside)
        composeButton.isEnabled = false
        containerView.addSubview(composeButton)

        cancelButton.setTitle(String(localized: "Cancel"), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        containerView.addSubview(cancelButton)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            activityIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            composeButton.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            composeButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            composeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            composeButton.heightAnchor.constraint(equalToConstant: 48),

            cancelButton.topAnchor.constraint(equalTo: composeButton.bottomAnchor, constant: 8),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])
    }

    private func extractSharedContent() {
        activityIndicator.startAnimating()

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishExtraction()
            return
        }

        let group = DispatchGroup()
        let resultQueue = DispatchQueue(label: "eu.brevmail.brev.share-extension.results")
        let handoffDirectory: URL?
        do {
            handoffDirectory = try prepareHandoffDirectory()
        } catch {
            handoffDirectory = nil
            extractionErrorMessage = String(localized: "Brev could not prepare shared storage for attachments.")
        }
        var collectedText: [String] = []
        var collectedURLs: [URL] = []
        var collectedAttachments: [URL] = []
        var unsupportedCount = 0
        let reservation = ShareHandoffReservation(
            maximumCount: Self.maximumAttachmentCount,
            maximumBytes: Self.maximumAttachmentBytes
        )

        for item in extensionItems {
            guard let providers = item.attachments else { continue }

            for provider in providers {
                var didHandleProvider = false

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    didHandleProvider = true
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                        defer { group.leave() }
                        if let text = item as? String {
                            resultQueue.sync {
                                collectedText.append(text)
                            }
                        }
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    didHandleProvider = true
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                        defer { group.leave() }
                        if let url = item as? URL {
                            if url.isFileURL,
                               let self,
                               let handoffDirectory {
                                do {
                                    let copiedURL = try copySharedFile(
                                        from: url,
                                        suggestedName: provider.suggestedName,
                                        into: handoffDirectory,
                                        reservation: reservation
                                    )
                                    resultQueue.sync {
                                        collectedAttachments.append(copiedURL)
                                    }
                                } catch {
                                    resultQueue.sync {
                                        unsupportedCount += 1
                                    }
                                }
                            } else {
                                resultQueue.sync {
                                    collectedURLs.append(url)
                                }
                            }
                        } else if let urlData = item as? Data,
                                  let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            resultQueue.sync {
                                collectedURLs.append(url)
                            }
                        }
                    }
                }

                if let handoffDirectory,
                   let fileTypeIdentifier = fileTypeIdentifier(for: provider) {
                    didHandleProvider = true
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: fileTypeIdentifier) { [weak self] url, _ in
                        defer { group.leave() }
                        guard let self, let url else { return }
                        do {
                            let copiedURL = try copySharedFile(
                                from: url,
                                suggestedName: provider.suggestedName,
                                into: handoffDirectory,
                                reservation: reservation
                            )
                            resultQueue.sync {
                                collectedAttachments.append(copiedURL)
                            }
                        } catch {
                            resultQueue.sync {
                                unsupportedCount += 1
                            }
                        }
                    }
                }

                if !didHandleProvider {
                    resultQueue.sync {
                        unsupportedCount += 1
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            resultQueue.sync {
                let text = collectedText.joined(separator: "\n")
                self?.sharedText = text.isEmpty ? nil : text
                self?.sharedURLs = collectedURLs
                self?.sharedAttachmentURLs = collectedAttachments
                self?.unsupportedItemCount = unsupportedCount
            }
            self?.finishExtraction()
        }
    }

    private func finishExtraction() {
        activityIndicator.stopAnimating()
        composeButton.isEnabled = true

        var parts: [String] = []
        if let text = sharedText, !text.isEmpty {
            parts.append(text)
        }
        if !sharedURLs.isEmpty {
            parts.append(String(localized: "\(sharedURLs.count) URL(s)"))
        }
        if !sharedAttachmentURLs.isEmpty {
            let count = sharedAttachmentURLs.count
            parts.append(count == 1 ? String(localized: "1 attachment") : String(localized: "\(count) attachments"))
        }
        if unsupportedItemCount > 0 {
            parts.append(String(localized: "\(unsupportedItemCount) unsupported"))
        }

        if let extractionErrorMessage {
            subtitleLabel.text = extractionErrorMessage
            composeButton.isEnabled = sharedText != nil || !sharedURLs.isEmpty
        } else if sharedText == nil, sharedURLs.isEmpty, sharedAttachmentURLs.isEmpty {
            subtitleLabel.text = unsupportedItemCount > 0
                ? String(localized: "This content type is not supported yet.")
                : String(localized: "No content to share")
            composeButton.isEnabled = false
        } else {
            subtitleLabel.text = parts.joined(separator: " · ")
        }
    }

    @objc private func openBrev() {
        guard let url = buildShareURL() else {
            cancelShare()
            return
        }

        var responder: UIResponder? = self
        while let next = responder?.next {
            if let application = next as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    // The open completion is delivered on a non-isolated
                    // `@Sendable` closure; hop to the main actor to touch the
                    // extension context and UI.
                    Task { @MainActor in
                        guard let self else { return }
                        if success {
                            self.extensionContext?.completeRequest(returningItems: nil)
                        } else {
                            self.showHandoffFailure()
                        }
                    }
                }
                return
            }
            responder = next
        }

        cancelShare()
    }

    private func showHandoffFailure() {
        subtitleLabel.text = String(localized: "Brev could not open this shared draft. Please try again.")
        composeButton.isEnabled = true
        composeButton.setTitle(String(localized: "Try Again"), for: .normal)
    }

    private func buildShareURL() -> URL? {
        let sharedPayload = buildSharePayload()
        guard !sharedPayload.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "brev"
        components.host = "compose"
        components.queryItems = [
            URLQueryItem(name: "shared", value: sharedPayload)
        ]
        return components.url
    }

    private func buildSharePayload() -> String {
        var queryItems: [URLQueryItem] = []

        if let text = sharedText, !text.isEmpty {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }

        for url in sharedURLs {
            queryItems.append(URLQueryItem(name: "url", value: url.absoluteString))
        }

        for url in sharedAttachmentURLs {
            queryItems.append(URLQueryItem(name: "attachment", value: url.absoluteString))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    private func prepareHandoffDirectory() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = containerURL
            .appendingPathComponent("ShareHandoff", isDirectory: true)
        purgeStaleHandoffDirectories(in: directory)
        let shareDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: shareDirectory,
            withIntermediateDirectories: true
        )
        return shareDirectory
    }

    private func fileTypeIdentifier(for provider: NSItemProvider) -> String? {
        let preferredTypes: [UTType] = [.pdf, .image, .movie, .data]
        for type in preferredTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            return type.identifier
        }
        return provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .item)
                && !type.conforms(to: .plainText)
                && !type.conforms(to: .url)
        }
    }

    // `nonisolated` because these are pure file operations invoked from the
    // `NSItemProvider` load completion closures, which are `@Sendable` and run
    // off the main actor under strict concurrency.
    private nonisolated func copySharedFile(
        from sourceURL: URL,
        suggestedName: String?,
        into directory: URL,
        reservation: ShareHandoffReservation
    ) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= Self.maximumSingleAttachmentBytes
        else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        guard reservation.reserve(bytes: fileSize) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let filename = uniqueFilename(
            suggestedName: suggestedName ?? sourceURL.lastPathComponent,
            in: directory
        )
        let destinationURL = directory.appendingPathComponent(filename)
        // Defense in depth: even with a sanitized name, never copy outside the
        // per-share directory.
        guard destinationURL.standardizedFileURL.path
            .hasPrefix(directory.standardizedFileURL.path + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private nonisolated func purgeStaleHandoffDirectories(in root: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Self.staleHandoffAge)
        for entry in entries {
            guard let directoryValues = try? entry.resourceValues(forKeys: [.isDirectoryKey]),
                  directoryValues.isDirectory == true,
                  let modifiedValues = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = modifiedValues.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private nonisolated func uniqueFilename(suggestedName: String, in directory: URL) -> String {
        let fallback = "attachment"
        // The share source controls suggestedName, so reduce it to a single safe
        // path component: take only the last component (drops any "../" prefix),
        // strip stray separators, and reject "."/".." so copyItem can never
        // escape the per-share directory (path traversal).
        let lastComponent = (suggestedName as NSString).lastPathComponent
        let trimmed = lastComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = (trimmed.isEmpty || trimmed == "." || trimmed == "..") ? fallback : trimmed
        var candidate = safeName
        var index = 1
        let fileExtension = (safeName as NSString).pathExtension
        let baseName = (safeName as NSString).deletingPathExtension
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = fileExtension.isEmpty
                ? "\(baseName) (\(index))"
                : "\(baseName) (\(index)).\(fileExtension)"
            index += 1
        }
        return candidate
    }

    @objc private func cancelShare() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
