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

import BrevAI
@testable import BrevMail
import Foundation
import Testing

@Suite("Compose AI v1 coverage")
struct ComposeAICoverageTests {
    @Test("consent provider and unsupported states expose deterministic copy")
    func consentProviderAndUnsupportedStatesExposeDeterministicCopy() {
        let consentRequired = ComposeAIActionAvailability.disabledReason(
            for: .shortcut(.improveWriting, scope: .wholeDraft),
            in: ComposeAIAvailabilityState(
                settings: AIWriterSettings(isEnabled: true, consentGiven: false),
                hasProviderBackend: true,
                backendSupportsAIWriter: true,
                isBusy: false,
                hasActiveRequest: false
            ).context(bodyText: "Draft")
        )
        let preview = ComposeAIPreviewState(
            id: 1,
            action: .draftFromPrompt,
            request: ComposeAIShortcutRequest(
                action: .improveWriting,
                bodyText: "Draft",
                target: .wholeDraft
            ),
            providerLabel: AIWriterDisclosure.defaultProvider.transparencyLabel,
            phase: .loading
        )
        let unsupported = ComposeAIActionAvailability.disabledReason(
            for: .draftFromPrompt,
            in: ComposeAIAvailabilityState(
                settings: AIWriterSettings(isEnabled: true, consentGiven: true),
                hasProviderBackend: false,
                backendSupportsAIWriter: false,
                isBusy: false,
                hasActiveRequest: false
            ).context(bodyText: "", promptText: "Draft")
        )

        #expect(consentRequired == .consentRequired)
        #expect(ComposeAIActionDisabledReason.consentRequired.title.contains("consent"))
        #expect(preview.providerLabel == AIWriterDisclosure.defaultProvider.transparencyLabel)
        #expect(unsupported == .unsupportedAccount)
        #expect(AIWriterDisclosure.unsupportedAccountMessage.contains("server-side AI support"))
    }

    @Test("manual smoke checklist covers v1 AI writer QA")
    func manualSmokeChecklistCoversV1AIWriterQA() throws {
        let checklist = try String(contentsOf: smokeChecklistURL(), encoding: .utf8)
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
        let requiredPhrases = [
            "AI Writer is off by default",
            "Enabling AI Writer requires explicit consent",
            "provider transparency label",
            "selected-text rewrite actions",
            "AI Writer output appears in the composer preview panel",
            "disabled unsupported-account explanation"
        ]

        for phrase in requiredPhrases {
            #expect(checklist.contains(phrase))
        }
    }

    private func smokeChecklistURL() throws -> URL {
        // Resolve from the source file first so SwiftPM/Xcode runners do not
        // need to start in the repository root. The CWD fallback keeps this
        // usable when the test source is checked out through a generated path.
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        var candidates: [URL] = []
        var directory = sourceDirectory
        for _ in 0 ..< 7 {
            candidates.append(
                directory
                    .appendingPathComponent("docs")
                    .appendingPathComponent("qa")
                    .appendingPathComponent("desktop-smoke.md")
            )
            directory.deleteLastPathComponent()
        }

        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 7 {
            candidates.append(
                directory
                    .appendingPathComponent("docs")
                    .appendingPathComponent("qa")
                    .appendingPathComponent("desktop-smoke.md")
            )
            directory.deleteLastPathComponent()
        }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw SmokeChecklistError.notFound
    }

    private enum SmokeChecklistError: Error {
        case notFound
    }
}
