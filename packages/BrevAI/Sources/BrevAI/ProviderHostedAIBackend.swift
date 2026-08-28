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

/// Provider-hosted AI backend.
///
/// This backend does not use data for training and does not
/// retain conversations beyond the response.
///
/// This backend calls a provider AI endpoint scoped to a
/// mailbox. It is the only `AIBackend` in v1; `BYOKBackend`
/// arrives in v2.
public actor ProviderHostedAIBackend: AIBackend {
    public nonisolated let identifier = AIProviderResolver.defaultProviderID.rawValue
    public nonisolated let displayName = AIWriterDisclosure.defaultProvider.displayName
    public nonisolated let transparencyLabel = AIWriterDisclosure.defaultProvider.transparencyLabel

    private let baseURL: URL
    private let mailboxUUIDProvider: @Sendable () async throws -> String
    private let tokenProvider: @Sendable () async throws -> String
    private let urlSession: URLSession

    /// - Parameters:
    ///   - baseURL: AI API base for the active provider.
    ///   - mailboxUUID: The UUID of the active mailbox.
    ///   - tokenProvider: Closure that returns a fresh access token.
    public init(
        baseURL: URL,
        mailboxUUID: String,
        tokenProvider: @escaping @Sendable () async throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.init(
            baseURL: baseURL,
            mailboxUUIDProvider: { mailboxUUID },
            tokenProvider: tokenProvider,
            urlSession: urlSession
        )
    }

    /// - Parameters:
    ///   - baseURL: AI API base for the active provider.
    ///   - mailboxUUIDProvider: Closure that returns the active
    ///     mailbox UUID for each user-initiated AI request.
    ///   - tokenProvider: Closure that returns a fresh access token.
    public init(
        baseURL: URL,
        mailboxUUIDProvider: @escaping @Sendable () async throws -> String,
        tokenProvider: @escaping @Sendable () async throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.mailboxUUIDProvider = mailboxUUIDProvider
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    public func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse {
        let bounded = try AISafetyPolicy.validatedMessages(messages)
        let body = AIProviderRequest(
            action: "reply",
            messages: bounded.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            instruction: [
                AISafetyPolicy.untrustedMailSystemInstruction,
                instruction
            ].compactMap { $0 }.joined(separator: " ")
        )
        return try await post(body)
    }

    public func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        let bounded = try AISafetyPolicy.validatedMessages([
            AIMessage(role: .user, content: text)
        ])
        let body = AIProviderRequest(
            action: action.rawValue,
            messages: bounded.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            instruction: AISafetyPolicy.untrustedMailSystemInstruction
        )
        return try await post(body)
    }

    // MARK: - Private

    private func post(_ body: AIProviderRequest) async throws -> AIResponse {
        let mailboxUUID = try await mailboxUUIDProvider()
        let token = try await tokenProvider()
        let url = baseURL
            .appendingPathComponent("api/mail/\(mailboxUUID)/ai")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIBackendError.networkError("Invalid response")
        }

        switch http.statusCode {
        case 200 ..< 300:
            let decoded = try JSONDecoder().decode(AIProviderEnvelope.self, from: data)
            return AIResponse(text: decoded.data.content)
        case 429:
            throw AIBackendError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIBackendError.serverError(statusCode: http.statusCode, message: message)
        }
    }
}

// MARK: - Wire types

private struct AIProviderRequest: Encodable {
    let action: String
    let messages: [AIProviderMessage]
    let instruction: String?

    struct AIProviderMessage: Encodable {
        let role: String
        let content: String
    }
}

private struct AIProviderEnvelope: Decodable {
    let data: AIProviderResponseData

    struct AIProviderResponseData: Decodable {
        let content: String
    }
}
