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

@testable import BrevAI
import Foundation
import Testing

@Suite("OpenAICompatibleBackend — identity and validation")
struct OpenAICompatibleBackendTests {
    @Test("openAI factory sets correct display name and identifier")
    func openAIFactoryIdentity() {
        let backend = OpenAICompatibleBackend.openAI(apiKey: "sk-test")
        #expect(backend.displayName == "OpenAI")
        #expect(backend.transparencyLabel.contains("OpenAI"))
        #expect(backend.identifier.contains("openai"))
    }

    @Test("ollama factory sets local display name")
    func ollamaFactoryIdentity() {
        let backend = OpenAICompatibleBackend.ollama()
        #expect(backend.displayName.contains("Ollama"))
        #expect(backend.transparencyLabel.contains("Ollama"))
    }

    @Test("custom backend has provider name in transparency label")
    func customBackendTransparencyLabel() {
        let backend = OpenAICompatibleBackend(
            providerName: "My Private Server",
            baseURL: URL(string: "https://ai.mycompany.example")!,
            apiKey: "key",
            modelID: "mixtral"
        )
        #expect(backend.transparencyLabel == "Sent to: My Private Server")
    }
}

@Suite("OpenAICompatibleBackend — endpoint validation")
struct OpenAIEndpointValidationTests {
    @Test("empty URL is invalid")
    func emptyURLIsInvalid() {
        let result = OpenAICompatibleBackend.validateEndpoint("", isLocal: false)
        #expect(!result.isValid)
    }

    @Test("non-HTTP scheme is invalid")
    func nonHTTPSchemeIsInvalid() {
        let result = OpenAICompatibleBackend.validateEndpoint("ftp://example.com/v1", isLocal: false)
        #expect(!result.isValid)
    }

    @Test("valid HTTPS URL is accepted")
    func validHTTPSURLAccepted() {
        let result = OpenAICompatibleBackend.validateEndpoint("https://api.openai.com/v1", isLocal: false)
        #expect(result.isValid)
    }

    @Test("localhost URL is accepted for local Ollama")
    func localhostAcceptedForLocal() {
        let result = OpenAICompatibleBackend.validateEndpoint("http://localhost:11434/v1", isLocal: true)
        #expect(result.isValid)
    }

    @Test("public internet URL is rejected for local Ollama")
    func publicInternetRejectedForLocal() {
        let result = OpenAICompatibleBackend.validateEndpoint("http://203.0.113.1:11434/v1", isLocal: true)
        #expect(!result.isValid)
    }

    @Test("valid result carries the parsed URL")
    func validResultCarriesURL() {
        let result = OpenAICompatibleBackend.validateEndpoint("https://api.openai.com/v1", isLocal: false)
        if case .valid(let url) = result {
            #expect(url.host == "api.openai.com")
        } else {
            Issue.record("Expected .valid but got invalid")
        }
    }
}
