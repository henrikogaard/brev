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

/// Protocol for AI writing assistance backends. v1 ships with
/// `ProviderHostedAIBackend` only; v2 adds `BYOKBackend` for user-provided
/// API keys. See ADR-0008.
///
/// Every invocation is user-initiated — AI never acts on content
/// without explicit action (invariant 6, ADR-0028).
public protocol AIBackend: Sendable {
    /// Machine identifier for persistence.
    var identifier: String { get }

    /// Human-readable name shown in settings.
    var displayName: String { get }

    /// Full transparency label displayed per-action in the UI, e.g.
    /// "Sent to: Provider-hosted AI" or "On this Mac".
    var transparencyLabel: String { get }

    /// Optional provider-neutral message and context-byte cap for smaller
    /// on-device context windows (ADR-0094). `nil` uses each surface's
    /// standard cloud cap.
    var contextBudget: AIBackendContextBudget? { get }

    /// Whether this backend executes strictly on-device with zero network egress.
    ///
    /// Only zero-network on-device backends (such as Apple Intelligence via
    /// `FoundationModels` or future user-downloaded local weights) return `true`.
    /// Cloud, BYOK, provider-hosted, and localhost HTTP endpoints return `false`
    /// so proactive background triage fails closed to explicit manual clicks.
    var isOnDeviceZeroNetwork: Bool { get }

    /// Generate a reply or draft from a conversation context with an
    /// optional instruction like "write a polite decline".
    func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse

    /// Apply a shortcut action to existing text (shorten, expand,
    /// translate, etc.).
    func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse
}

// MARK: - Default context budget

public extension AIBackend {
    /// Cloud and external OpenAI-compatible backends keep each surface's default cap.
    var contextBudget: AIBackendContextBudget? {
        nil
    }

    /// Backends default to non-zero-network so proactive background triage fails closed.
    var isOnDeviceZeroNetwork: Bool {
        false
    }
}

// MARK: - Supporting types

/// Provider-neutral message-count and serialized-byte limits for AI requests (ADR-0094).
public struct AIBackendContextBudget: Equatable, Sendable {
    /// Maximum number of source messages included in one request.
    public let maxSourceMessages: Int

    /// Maximum UTF-8 bytes of serialized context passed to the backend.
    public let maxTotalContextBytes: Int

    /// Standard cap used by cloud and external OpenAI-compatible backends.
    public static let standard = AIBackendContextBudget(
        maxSourceMessages: AISafetyPolicy.maxSourceMessages,
        maxTotalContextBytes: AISafetyPolicy.maxTotalContextBytes
    )

    /// Conservative cap for on-device ~4k-token language-model sessions.
    public static let onDevice = AIBackendContextBudget(
        maxSourceMessages: 6,
        maxTotalContextBytes: 8000
    )

    /// Creates a positive context budget clamped to at least one message and 256 bytes.
    public init(maxSourceMessages: Int, maxTotalContextBytes: Int) {
        self.maxSourceMessages = max(1, maxSourceMessages)
        self.maxTotalContextBytes = max(256, maxTotalContextBytes)
    }
}

/// Role in a conversation context passed to the AI backend.
public enum AIRole: String, Sendable, Hashable, Codable {
    case user
    case assistant
    case system
}

/// A single message in the conversation context.
public struct AIMessage: Sendable, Hashable {
    public let role: AIRole
    public let content: String

    public init(role: AIRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// Shortcut actions available from the compose toolbar.
public enum AIShortcutAction: String, Sendable, Hashable, Codable, CaseIterable {
    case shorten
    case expand
    case formal
    case casual
    case friendly
    case improveWriting
    case fixSpelling
    case translate

    /// Label shown in the shortcut menu.
    public var displayLabel: String {
        switch self {
        case .shorten: "Shorten"
        case .expand: "Expand"
        case .formal: "Make formal"
        case .casual: "Make casual"
        case .friendly: "Make friendly"
        case .improveWriting: "Improve writing"
        case .fixSpelling: "Fix spelling & grammar"
        case .translate: "Translate"
        }
    }

    /// SF Symbol name for the menu item.
    public var symbolName: String {
        switch self {
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .formal: "building.columns"
        case .casual: "face.smiling"
        case .friendly: "hand.wave"
        case .improveWriting: "wand.and.stars"
        case .fixSpelling: "textformat.abc"
        case .translate: "globe"
        }
    }
}

/// Response from an AI backend.
public struct AIResponse: Sendable, Hashable {
    /// The generated or transformed text.
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// Errors that AI backends can throw.
public enum AIBackendError: Error, LocalizedError, Sendable, Equatable {
    case notEnabled
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case rateLimited
    case contentFiltered
    case unavailable(String)
    case contextWindowExceeded

    public var errorDescription: String? {
        switch self {
        case .notEnabled:
            String(localized: "AI Writer is not enabled. Enable it in Settings.", bundle: .module)
        case .networkError(let msg):
            String(localized: "Network error: \(msg)", bundle: .module)
        case .serverError(let code, let msg):
            String(localized: "Server error (\(code)): \(msg)", bundle: .module)
        case .rateLimited:
            String(localized: "Too many requests. Please wait a moment and try again.", bundle: .module)
        case .contentFiltered:
            String(localized: "The content was filtered by the AI provider.", bundle: .module)
        case .unavailable(let reason):
            reason
        case .contextWindowExceeded:
            String(
                localized: "This message is too long for the on-device model. Try a shorter selection or thread.",
                bundle: .module
            )
        }
    }
}
