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

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    private let model = ShareSheetModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractSharedContent()
    }

    /// Hosts the SwiftUI share sheet edge to edge, so the system sheet supplies
    /// the size, background and Dynamic Type behavior.
    private func setupUI() {
        let host = UIHostingController(
            rootView: ShareSheetView(
                model: model,
                onCancel: { [weak self] in self?.cancelShare() },
                onOpen: { [weak self] in self?.openBrev() }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func extractSharedContent() {
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

                // A provider can conform to both public.url and a file type
                // for the same payload; the URL path already copies file
                // URLs, so the file representation only runs when the URL
                // path did not produce a file (web URL, missing item).
                let fileTypeIdentifier = fileTypeIdentifier(for: provider)

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    didHandleProvider = true
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                        defer { group.leave() }
                        var handledFilePayload = false
                        if let url = item as? URL {
                            if url.isFileURL,
                               let self,
                               let handoffDirectory {
                                handledFilePayload = true
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
                        if !handledFilePayload,
                           let self,
                           let handoffDirectory,
                           let fileTypeIdentifier {
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
                    }
                } else if let handoffDirectory,
                          let fileTypeIdentifier {
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
        let content = ShareSheetContent.resolve(
            text: sharedText,
            urls: sharedURLs,
            attachmentURLs: sharedAttachmentURLs,
            unsupportedCount: unsupportedItemCount,
            extractionError: extractionErrorMessage,
            canHandoffText: ShareHandoffURL.canHandoff(text:)
        )
        // Oversized text is dropped from the handoff, not truncated.
        if content.text == nil { sharedText = nil }
        model.content = content
    }

    private func openBrev() {
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
        model.handoffFailed = true
    }

    private func buildShareURL() -> URL? {
        ShareHandoffURL.url(
            text: sharedText,
            urls: sharedURLs,
            attachments: sharedAttachmentURLs
        )
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

    private func cancelShare() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
