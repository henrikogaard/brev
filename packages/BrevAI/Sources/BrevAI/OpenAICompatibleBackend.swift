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

/// OpenAI-compatible AI backend for BYOK (Bring Your Own Key) and
/// local Ollama-style endpoints. Conforms to `AIBackend` and is
/// transparent about the destination provider in every UI label.
///
/// Supports:
/// - Hosted BYOK: user-supplied API key + OpenAI/Anthropic/etc.
/// - Custom base URLs: any endpoint that speaks the OpenAI chat API.
/// - Local Ollama: `http://localhost:11434/v1` with no API key.
///
/// ADR-0008 requires: disabled by default, explicit per-action opt-in,
/// transparency label visible before content is sent, no training data
/// sent, no telemetry beyond what the chosen provider's API receives.
public actor OpenAICompatibleBackend: AIBackend {
    // MARK: - AIBackend identity

    public nonisolated let identifier: String
    public nonisolated let displayName: String
    public nonisolated let transparencyLabel: String

    // MARK: - Private state

    private let baseURL: URL
    private let apiKey: String?
    private let modelID: String
    private let urlSession: URLSession

    // MARK: - Init

    /// Creates a BYOK backend for a hosted provider.
    ///
    /// - Parameters:
    ///   - providerName: Human-readable name (e.g. `"OpenAI"`).
    ///   - transparencyLabel: User-facing destination disclosure, if more
    ///     specific than the provider name alone.
    ///   - baseURL: API base, e.g. `https://api.openai.com/v1`.
    ///   - apiKey: Bearer token. `nil` for local endpoints that need
    ///     no auth (Ollama).
    ///   - modelID: Model to use, e.g. `"gpt-4o"` or `"llama3"`.
    public init(
        providerName: String,
        transparencyLabel: String? = nil,
        baseURL: URL,
        apiKey: String?,
        modelID: String,
        urlSession: URLSession = .shared
    ) {
        identifier = "openai-compatible-\(baseURL.host ?? "unknown")"
        displayName = providerName
        self.transparencyLabel = transparencyLabel ?? "Sent to: \(providerName)"
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.urlSession = urlSession
    }

    // MARK: - Convenience factories

    /// Standard OpenAI backend with user-supplied API key.
    public static func openAI(apiKey: String, modelID: String = "gpt-4o") -> OpenAICompatibleBackend {
        OpenAICompatibleBackend(
            providerName: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: apiKey,
            modelID: modelID
        )
    }

    /// Local Ollama endpoint (no auth required).
    public static func ollama(
        baseURL: URL = URL(string: "http://localhost:11434/v1")!,
        modelID: String = "llama3"
    ) -> OpenAICompatibleBackend {
        OpenAICompatibleBackend(
            providerName: "Ollama (local)",
            baseURL: baseURL,
            apiKey: nil,
            modelID: modelID
        )
    }

    // MARK: - AIBackend implementation

    public func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse {
        let bounded = try AISafetyPolicy.validatedMessages(messages)
        var systemMessages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: AISafetyPolicy.untrustedMailSystemInstruction)
        ]
        if let instruction {
            systemMessages.append(OpenAIMessage(role: "system", content: instruction))
        }
        let chatMessages = systemMessages + bounded.messages.map {
            OpenAIMessage(role: $0.role.rawValue, content: $0.content)
        }
        return try await complete(messages: chatMessages)
    }

    public func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        let bounded = try AISafetyPolicy.validatedMessages([
            AIMessage(role: .user, content: text)
        ])
        let systemPrompt: String
        switch action {
        case .shorten: systemPrompt = "Shorten the following text. Return only the shortened text."
        case .expand: systemPrompt = "Expand the following text with more detail. Return only the expanded text."
        case .formal: systemPrompt = "Make the following text more formal and professional. Return only the rewritten text."
        case .casual: systemPrompt = "Make the following text more casual and conversational. Return only the rewritten text."
        case .friendly: systemPrompt = "Make the following text warmer and more friendly. Return only the rewritten text."
        case .improveWriting: systemPrompt = "Improve the clarity and flow of the following text. Return only the improved text."
        case .fixSpelling: systemPrompt = "Fix any spelling and grammar errors in the following text. Return only the corrected text."
        case .translate: systemPrompt = "Translate the following text to English. If it is already in English, translate to French. Return only the translation."
        }
        let messages = [
            OpenAIMessage(role: "system", content: systemPrompt),
            OpenAIMessage(role: "user", content: bounded.messages[0].content)
        ]
        return try await complete(messages: messages)
    }

    // MARK: - Network

    private func complete(messages: [OpenAIMessage]) async throws -> AIResponse {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = OpenAIChatRequest(
            model: modelID,
            messages: messages,
            maxTokens: 2048,
            temperature: 0.7
        )
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(status) else {
                // Redact API key and Authorization header from all error messages.
                // Never surface raw server bodies that might echo back credentials.
                let safePreview = redacted(
                    String(data: data.prefix(256), encoding: .utf8) ?? "<binary>"
                )
                if status == 429 {
                    throw AIBackendError.rateLimited
                }
                if status == 401 || status == 403 {
                    throw AIBackendError.serverError(
                        statusCode: status,
                        message: "Authorization failed. Check your API key."
                    )
                }
                throw AIBackendError.serverError(statusCode: status, message: safePreview)
            }
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let text = decoded.choices.first?.message.content else {
                throw AIBackendError.serverError(statusCode: status, message: "Empty response")
            }
            return AIResponse(text: text)
        } catch let error as AIBackendError {
            throw error
        } catch {
            // Redact any mention of the API key from transport errors.
            throw AIBackendError.networkError(redacted(error.localizedDescription))
        }
    }

    /// Replaces any occurrence of the API key in `message` with `[REDACTED]`.
    ///
    /// Also strips `Bearer ` prefixes so tokens echoed by error responses
    /// can never appear in a user-visible or logged error message.
    private func redacted(_ message: String) -> String {
        guard let key = apiKey, !key.isEmpty else { return message }
        return message
            .replacingOccurrences(of: key, with: "[REDACTED]")
            .replacingOccurrences(of: "Bearer \(key)", with: "Bearer [REDACTED]")
    }
}

// MARK: - Endpoint validation

public extension OpenAICompatibleBackend {
    /// Validates a candidate base URL for safety.
    ///
    /// Rejects blank URLs, non-HTTP(S) schemes, and public-internet
    /// addresses for Ollama (which should only listen on localhost).
    static func validateEndpoint(
        _ urlString: String,
        isLocal: Bool
    ) -> OpenAIEndpointValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(reason: "Endpoint URL cannot be empty.") }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .invalid(reason: "Endpoint URL must start with http:// or https://.")
        }
        if isLocal {
            let host = url.host?.lowercased() ?? ""
            guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
                return .invalid(
                    reason: "Local AI endpoints must use localhost. "
                        + "Public-internet Ollama endpoints are not supported."
                )
            }
        }
        return .valid(url: url)
    }
}

public enum OpenAIEndpointValidationResult: Equatable, Sendable {
    case valid(url: URL)
    case invalid(reason: String)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Private DTOs

private struct OpenAIMessage: Codable, Sendable {
    let role: String
    let content: String
}

private struct OpenAIChatRequest: Encodable, Sendable {
    let model: String
    let messages: [OpenAIMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct OpenAIChatResponse: Decodable, Sendable {
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let message: OpenAIMessage
    }
}
