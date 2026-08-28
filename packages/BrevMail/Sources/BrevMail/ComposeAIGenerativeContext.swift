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
import BrevBackend
import Foundation

struct ComposeAIGenerativeContext: Equatable, Sendable {
    let messages: [AIMessage]
    let instruction: String

    static func promptDraft(prompt: String) -> Self? {
        let prompt = trimmed(prompt)
        guard !prompt.isEmpty else { return nil }
        return ComposeAIGenerativeContext(
            messages: [AIMessage(role: .user, content: prompt)],
            instruction: "Draft a new email from the user's prompt."
        )
    }

    static func replyDraft(
        replyingTo: MessageHeader?,
        draftBody: String
    ) -> Self? {
        guard let replyingTo else { return nil }
        var messages = [
            AIMessage(role: .user, content: replyContext(from: replyingTo))
        ]
        let draftBody = trimmed(draftBody)
        if !draftBody.isEmpty {
            messages.append(AIMessage(role: .user, content: "Current draft: \(draftBody)"))
        }
        return ComposeAIGenerativeContext(
            messages: messages,
            instruction: "Draft an email reply from the provided compose context."
        )
    }

    static func subjectSuggestion(
        bodyText: String,
        currentSubject: String
    ) -> Self? {
        let bodyText = trimmed(bodyText)
        guard !bodyText.isEmpty else { return nil }
        let subject = trimmed(currentSubject)
        let content: String
        if subject.isEmpty {
            content = "Draft body: \(bodyText)"
        } else {
            content = "Current subject: \(subject)\nDraft body: \(bodyText)"
        }
        return ComposeAIGenerativeContext(
            messages: [AIMessage(role: .user, content: content)],
            instruction: "Suggest one concise email subject line. Return only the subject text."
        )
    }

    private static func replyContext(from header: MessageHeader) -> String {
        [
            "From: \(header.from.displayString)",
            "Subject: \(trimmed(header.subject))",
            "Snippet: \(trimmed(header.snippet))"
        ]
        .filter { !$0.hasSuffix(": ") }
        .joined(separator: "\n")
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Correspondent {
    var displayString: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return email
        }
        return "\(name) <\(email)>"
    }
}
