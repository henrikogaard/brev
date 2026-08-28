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

import BrevSettings

enum ComposeTemplateBodyPolicy {
    static func body(
        applying template: MessageTemplate,
        to currentBody: String,
        selection: ComposeBodyTextSelection?,
        insertionPoint: ComposeBodyInsertionPoint?,
        currentSignatureBody: String?,
        previousSignatureBody: String?
    ) -> String {
        let bodyWithoutPreviousSignature = ComposeSignatureBodyPolicy.body(
            removing: previousSignatureBody,
            from: currentBody
        )
        let templateBody = template.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedBody: String
        if !templateBody.isEmpty {
            if let selection,
               let replaced = selection.replacingSelection(in: bodyWithoutPreviousSignature, with: template.body) {
                updatedBody = replaced
            } else if let insertionPoint,
                      let inserted = insertionPoint.insertingText(
                          bodyWithoutPreviousSignature.isEmpty ? template.body : "\n\n\(template.body)",
                          in: bodyWithoutPreviousSignature
                      ) {
                updatedBody = inserted
            } else if bodyWithoutPreviousSignature.isEmpty {
                updatedBody = template.body
            } else {
                updatedBody = bodyWithoutPreviousSignature + "\n\n" + template.body
            }
        } else {
            updatedBody = bodyWithoutPreviousSignature
        }

        return ComposeSignatureBodyPolicy.body(
            afterSelecting: currentSignatureBody,
            in: updatedBody,
            replacing: previousSignatureBody
        )
    }

    static func subject(
        applying template: MessageTemplate,
        to currentSubject: String
    ) -> String {
        guard let templateSubject = template.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
              !templateSubject.isEmpty else {
            return currentSubject
        }
        return templateSubject
    }
}
