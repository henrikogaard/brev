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
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(iOS)
import UIKit
#endif

/// Runtime availability of Apple's on-device `FoundationModels` system model (ADR-0094).
public enum AppleIntelligenceAvailability: Equatable, Sendable {
    case available
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable(reason: String)

    /// Whether the user can select and run Apple Intelligence on this device right now.
    public var isSelectable: Bool {
        self == .available
    }

    /// Plain-language status shown in Settings → AI when checking or disabling the option.
    public var settingsStatusMessage: String {
        switch self {
        case .available:
            return String(
                localized: "Ready on this device. Text stays local and works offline.",
                bundle: .module
            )
        case .unsupportedOS:
            #if os(macOS)
            return String(
                localized: "Requires macOS 26 or later.",
                bundle: .module
            )
            #else
            return String(
                localized: "Requires iOS 26 or later.",
                bundle: .module
            )
            #endif
        case .deviceNotEligible:
            return String(
                localized: "This device does not support Apple Intelligence.",
                bundle: .module
            )
        case .appleIntelligenceNotEnabled:
            return String(
                localized: "Turn on Apple Intelligence in System Settings to use on-device AI.",
                bundle: .module
            )
        case .modelNotReady:
            return String(
                localized: "Apple Intelligence is still preparing its on-device model. Try again shortly.",
                bundle: .module
            )
        case .unavailable(let reason):
            return reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Apple Intelligence is currently unavailable on this device.", bundle: .module)
                : reason
        }
    }

    /// Inspects `SystemLanguageModel.default.availability` without making any network request.
    public static func current() -> AppleIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .unavailable(reason: "")
                }
            }
        }
        #endif
        return .unsupportedOS
    }
}

/// Platform-appropriate localized labels for on-device AI (ADR-0094).
public enum OnDeviceAIPlatformLabel {
    /// Device kind used to form `"On this Mac"`, `"On this iPhone"`, or `"On this iPad"`.
    public enum DeviceKind: Equatable, Sendable {
        case mac
        case iPhone
        case iPad

        /// Resolves the current platform's device kind.
        public static var current: DeviceKind {
            #if os(macOS)
            return .mac
            #elseif os(iOS)
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
                }
            }
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            if size > 0 {
                var machine = [CChar](repeating: 0, count: size)
                if sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0,
                   String(cString: machine).hasPrefix("iPad") {
                    return .iPad
                }
            }
            return .iPhone
            #else
            return .mac
            #endif
        }
    }

    /// Short transparency label shown on every AI output surface (`"On this Mac"` / `"On this iPhone"` / `"On this iPad"`).
    public static var transparencyLabel: String {
        transparencyLabel(for: .current)
    }

    /// Short transparency label for a specific device kind.
    public static func transparencyLabel(for device: DeviceKind) -> String {
        switch device {
        case .mac:
            return String(localized: "On this Mac", bundle: .module)
        case .iPhone:
            return String(localized: "On this iPhone", bundle: .module)
        case .iPad:
            return String(localized: "On this iPad", bundle: .module)
        }
    }

    /// Settings display name for Apple Intelligence (`"On this Mac (Apple Intelligence)"`, etc.).
    public static var appleIntelligenceDisplayName: String {
        appleIntelligenceDisplayName(for: .current)
    }

    /// Settings display name for Apple Intelligence on a specific device kind.
    public static func appleIntelligenceDisplayName(for device: DeviceKind) -> String {
        switch device {
        case .mac:
            return String(localized: "On this Mac (Apple Intelligence)", bundle: .module)
        case .iPhone:
            return String(localized: "On this iPhone (Apple Intelligence)", bundle: .module)
        case .iPad:
            return String(localized: "On this iPad (Apple Intelligence)", bundle: .module)
        }
    }

    /// Settings display name for a user-downloaded local model (`"On this Mac (download a model)"`, etc.).
    public static var downloadedModelDisplayName: String {
        downloadedModelDisplayName(for: .current)
    }

    /// Settings display name for a user-downloaded local model on a specific device kind.
    public static func downloadedModelDisplayName(for device: DeviceKind) -> String {
        switch device {
        case .mac:
            return String(localized: "On this Mac (download a model)", bundle: .module)
        case .iPhone:
            return String(localized: "On this iPhone (download a model)", bundle: .module)
        case .iPad:
            return String(localized: "On this iPad (download a model)", bundle: .module)
        }
    }
}

/// Seam wrapping on-device `FoundationModels` generation for deterministic unit testing.
public protocol AppleIntelligenceTextGenerating: Sendable {
    /// Generates plain text strictly on-device given system instructions and a bounded user prompt.
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Live `FoundationModels` generator backed by `SystemLanguageModel.default` strictly on-device.
public struct SystemAppleIntelligenceGenerator: AppleIntelligenceTextGenerating {
    /// Creates a system Apple Intelligence generator.
    public init() {}

    public func respond(instructions: String, prompt: String) async throws -> String {
        let availability = AppleIntelligenceAvailability.current()
        guard availability.isSelectable else {
            throw AIBackendError.unavailable(availability.settingsStatusMessage)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: instructions
                )
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation:
                    throw AIBackendError.contentFiltered
                case .exceededContextWindowSize:
                    throw AIBackendError.contextWindowExceeded
                case .assetsUnavailable:
                    throw AIBackendError.unavailable(
                        AppleIntelligenceAvailability.modelNotReady.settingsStatusMessage
                    )
                default:
                    throw AIBackendError.unavailable(error.localizedDescription)
                }
            } catch {
                throw AIBackendError.unavailable(error.localizedDescription)
            }
        }
        #endif
        throw AIBackendError.unavailable(AppleIntelligenceAvailability.unsupportedOS.settingsStatusMessage)
    }
}

/// On-device `AIBackend` backed by Apple's `FoundationModels` framework (ADR-0094, Slice 1).
///
/// Runs strictly on-device with zero network requests, zero API keys, and a conservative
/// context budget suitable for ~4k-token system language-model sessions.
public struct AppleIntelligenceAIBackend: AIBackend {
    /// Stable provider configuration ID for Apple Intelligence.
    public static let providerID = AIProviderID("apple-intelligence")

    public let identifier = "apple-intelligence"
    public let displayName: String
    public let transparencyLabel: String
    public let contextBudget: AIBackendContextBudget?
    public let isOnDeviceZeroNetwork = true

    private let effectiveBudget: AIBackendContextBudget
    private let availability: @Sendable () -> AppleIntelligenceAvailability
    private let generator: any AppleIntelligenceTextGenerating

    /// Creates an on-device Apple Intelligence backend.
    ///
    /// - Parameters:
    ///   - displayName: Localized settings display name (defaults to platform Apple Intelligence label).
    ///   - transparencyLabel: Localized output label (defaults to `"On this Mac"` / `"On this iPhone"` / `"On this iPad"`).
    ///   - contextBudget: Message and context-byte cap (defaults to `.onDevice`).
    ///   - availability: Availability probe (defaults to `AppleIntelligenceAvailability.current`).
    ///   - generator: On-device text generator seam (defaults to `SystemAppleIntelligenceGenerator`).
    public init(
        displayName: String = OnDeviceAIPlatformLabel.appleIntelligenceDisplayName,
        transparencyLabel: String = OnDeviceAIPlatformLabel.transparencyLabel,
        contextBudget: AIBackendContextBudget = .onDevice,
        availability: @escaping @Sendable () -> AppleIntelligenceAvailability = { .current() },
        generator: any AppleIntelligenceTextGenerating = SystemAppleIntelligenceGenerator()
    ) {
        self.displayName = displayName
        self.transparencyLabel = transparencyLabel
        self.contextBudget = contextBudget
        effectiveBudget = contextBudget
        self.availability = availability
        self.generator = generator
    }

    public func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse {
        let status = availability()
        guard status.isSelectable else {
            throw AIBackendError.unavailable(status.settingsStatusMessage)
        }

        let bounded = try AISafetyPolicy.validatedMessages(messages, budget: effectiveBudget)
        var instructionsParts = [AISafetyPolicy.untrustedMailSystemInstruction]
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            instructionsParts.append(instruction)
        }
        let instructions = instructionsParts.joined(separator: "\n\n")
        let prompt = Self.formatPrompt(from: bounded.messages)
        let text = try await generator.respond(instructions: instructions, prompt: prompt)
        return AIResponse(text: text)
    }

    public func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        let status = availability()
        guard status.isSelectable else {
            throw AIBackendError.unavailable(status.settingsStatusMessage)
        }

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
        let result = try await generator.respond(instructions: instructions, prompt: prompt)
        return AIResponse(text: result)
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
