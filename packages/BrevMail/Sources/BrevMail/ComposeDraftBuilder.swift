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

import BrevBackend
import Foundation

public struct ComposePrefill: Equatable, Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var bodyText: String
    public var attachmentFileURLs: [URL]

    public init(
        to: [String] = [],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String = "",
        bodyText: String = "",
        attachmentFileURLs: [URL] = []
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.attachmentFileURLs = attachmentFileURLs
    }

    public var isEmpty: Bool {
        to.isEmpty
            && cc.isEmpty
            && bcc.isEmpty
            && subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachmentFileURLs.isEmpty
    }

    /// Parses a `mailto:` URL per RFC 6068 (see `MailtoURL`).
    ///
    /// Returns `nil` if the URL scheme is not `mailto`.
    public init?(mailtoURL url: URL) {
        guard let mailto = MailtoURL(url: url) else { return nil }
        self.init(
            to: mailto.to,
            cc: mailto.cc,
            bcc: mailto.bcc,
            subject: mailto.subject ?? "",
            bodyText: mailto.body ?? ""
        )
    }
}

public enum SharedComposePayload {
    public static func prefill(from url: URL) -> ComposePrefill? {
        prefill(from: url, allowedAttachmentRoot: shareHandoffRoot())
    }

    /// Core parser. `allowedAttachmentRoot` confines which file URLs may be
    /// attached: only files inside that directory are accepted, and `nil`
    /// rejects all attachments (fail safe). The `brev://` scheme is public, so
    /// any other app or a web page can invoke
    /// `brev://compose?...&attachment=file://…`; without this confinement a
    /// crafted URL could attach an arbitrary file from the app sandbox.
    static func prefill(from url: URL, allowedAttachmentRoot: URL?) -> ComposePrefill? {
        guard url.scheme?.lowercased() == "brev",
              url.host == "compose",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encodedPayload = components.queryItems?.first(where: { $0.name == "shared" })?.value else {
            return nil
        }

        var payloadComponents = URLComponents()
        payloadComponents.percentEncodedQuery = encodedPayload

        var parts: [String] = []
        var attachmentFileURLs: [URL] = []
        for queryItem in payloadComponents.queryItems ?? [] {
            switch queryItem.name {
            case "text":
                if let value = queryItem.value, !value.isEmpty {
                    parts.append(value)
                }
            case "url":
                if let value = queryItem.value, !value.isEmpty {
                    parts.append(value)
                }
            case "attachment":
                if let value = queryItem.value,
                   !value.isEmpty,
                   let fileURL = URL(string: value),
                   fileURL.isFileURL,
                   isFileURL(fileURL, within: allowedAttachmentRoot) {
                    attachmentFileURLs.append(fileURL)
                }
            default:
                break
            }
        }

        let prefill = ComposePrefill(
            bodyText: parts.joined(separator: "\n\n"),
            attachmentFileURLs: attachmentFileURLs
        )
        return prefill.isEmpty ? nil : prefill
    }

    /// App group shared with the iOS share extension.
    private static let shareHandoffAppGroupIdentifier = "group.eu.brevmail.brev"

    /// The share extension's app-group handoff directory, or `nil` if the
    /// container can't be resolved (then no attachment is accepted — fail safe).
    private static func shareHandoffRoot() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: shareHandoffAppGroupIdentifier)?
            .appendingPathComponent("ShareHandoff", isDirectory: true)
    }

    /// Whether `url` resolves to a path inside `root` (symlinks resolved). A nil
    /// root rejects everything.
    static func isFileURL(_ url: URL, within root: URL?) -> Bool {
        guard let root else { return false }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var rootPath = resolvedRoot.path
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        return resolved.hasPrefix(rootPath)
    }

    /// Removes imported share-extension staging directories once their files
    /// have been copied into compose state. URLs outside Brev's app-group
    /// handoff root are ignored, so arbitrary file URLs cannot be deleted.
    static func purgeImportedHandoffDirectories(for urls: [URL]) {
        guard let root = shareHandoffRoot() else { return }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        for url in urls {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard isFileURL(resolved, within: resolvedRoot),
                  resolved.pathComponents.count > resolvedRoot.pathComponents.count
            else { continue }
            let relativeComponents = Array(resolved.pathComponents.dropFirst(resolvedRoot.pathComponents.count))
            guard let handoffID = relativeComponents.first,
                  !handoffID.isEmpty,
                  relativeComponents.count >= 2
            else { continue }
            let directory = resolvedRoot.appendingPathComponent(handoffID, isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

// swiftlint:disable function_parameter_count
enum ComposeBodyFormat: Equatable, Sendable {
    case plainText
    case richTextHTML
}

enum ComposeDraftBuilder {
    static func draft(
        id: String,
        remoteID: String? = nil,
        identityID: String? = nil,
        replyingTo: MessageHeader?,
        forwardingFrom: MessageHeader?,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        bodyText: String,
        bodyHTML: String? = nil,
        bodyFormat: ComposeBodyFormat = .plainText,
        signatureBody: String? = nil,
        attachmentIDs: [String] = [],
        scheduledFor: Date? = nil,
        readReceiptNotificationTo: String? = nil,
        securityMode: OutboundMessageSecurityMode = .none
    ) -> Draft {
        let htmlBody: String
        switch bodyFormat {
        case .plainText:
            htmlBody = ComposeHTMLBodyPolicy.html(fromEditorText: bodyText)
        case .richTextHTML:
            htmlBody = ComposeHTMLBodyPolicy.richHTML(fromEditorHTML: bodyHTML ?? bodyText)
        }
        let finalBody = injectSignature(
            into: htmlBody,
            signatureBody: signatureBody,
            isReplyOrForward: replyingTo != nil || forwardingFrom != nil
        )
        let readReceiptAddress = readReceiptNotificationTo?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Draft(
            id: id,
            remoteID: remoteID,
            identityID: identityID,
            threadID: replyingTo?.threadID,
            // Use the RFC Message-ID (not the internal folderID:uid id) so the
            // recipient's client can thread the reply/forward.
            inReplyToMessageID: replyingTo?.rfcMessageID,
            forwardedMessageID: forwardingFrom?.rfcMessageID,
            to: recipients(from: to),
            cc: recipients(from: cc),
            bcc: recipients(from: bcc),
            subject: subject,
            htmlBody: finalBody,
            attachmentIDs: attachmentIDs,
            scheduledFor: scheduledFor,
            readReceiptRequest: readReceiptAddress.flatMap {
                $0.isEmpty ? nil : ReadReceiptRequest(notificationTo: $0)
            },
            securityMode: securityMode
        )
    }

    static func injectSignature(
        into body: String,
        signatureBody: String?,
        isReplyOrForward: Bool
    ) -> String {
        guard let signatureBody,
              !signatureBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return body
        }
        let separator = "<br><hr size=\"1\" noshade=\"noshade\">"
        let signatureBlock = "<div class=\"signature\">\(ComposeHTMLBodyPolicy.signatureHTML(from: signatureBody))</div>"
        return body + separator + signatureBlock
    }

    /// Reconciles the inline-image registry against the HTML body and returns
    /// the images that are still referenced.
    ///
    /// Call this before staging inline images with the backend. Images whose
    /// `cid:` references were deleted from the body are pruned from the registry
    /// so they are not sent.
    ///
    /// - Parameters:
    ///   - registry: The per-compose registry that owns staged inline images.
    ///   - draftID: The draft ID (informational; not used to mutate the draft here).
    ///   - bodyHTML: The current serialised HTML body of the compose.
    /// - Returns: The inline images that remain in the registry after reconcile.
    static func inlineAttachments(
        fromRegistry registry: ComposeInlineImageRegistry,
        draftID: String,
        bodyHTML: String
    ) -> [ComposeInlineImage] {
        let referencedCIDs = ComposeInlineImageRegistry.contentIDs(inHTML: bodyHTML)
        registry.reconcile(keepingContentIDs: referencedCIDs)
        return registry.staged
    }

    static func canSave(
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        bodyText: String,
        hasAttachments: Bool
    ) -> Bool {
        hasAttachments
            || !recipientAddresses(from: to + cc + bcc).isEmpty
            || !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canSend(to: [String], cc: [String] = [], bcc: [String] = []) -> Bool {
        !recipientAddresses(from: to + cc + bcc).isEmpty
    }

    static func recipientAddresses(from values: [String]) -> [String] {
        values
            .flatMap { value in
                value.split(omittingEmptySubsequences: true) { $0 == "," || $0 == ";" }
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func recipients(from values: [String]) -> [Correspondent] {
        recipientAddresses(from: values).map { Correspondent(email: $0) }
    }
}

// swiftlint:enable function_parameter_count

enum ComposeHTMLBodyPolicy {
    static func html(fromEditorText text: String) -> String {
        let normalized = normalizeLineEndings(text)
        return escapeHTML(normalized).replacingOccurrences(of: "\n", with: "<br>")
    }

    static func richHTML(fromEditorHTML editorHTML: String) -> String {
        let normalized = normalizeLineEndings(editorHTML)
        let withoutUnsafeBlocks = removingUnsafeHTMLBlocks(from: normalized)
        let tagPattern = #"<[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else {
            return Self.html(fromEditorText: withoutUnsafeBlocks)
        }

        let nsRange = NSRange(withoutUnsafeBlocks.startIndex..., in: withoutUnsafeBlocks)
        var result = ""
        var lastIndex = withoutUnsafeBlocks.startIndex
        for match in regex.matches(in: withoutUnsafeBlocks, range: nsRange) {
            guard let range = Range(match.range, in: withoutUnsafeBlocks) else { continue }
            appendEscapedRichText(
                String(withoutUnsafeBlocks[lastIndex ..< range.lowerBound]),
                to: &result
            )
            if let sanitizedTag = sanitizedRichHTMLTag(String(withoutUnsafeBlocks[range])) {
                result.append(sanitizedTag)
            }
            lastIndex = range.upperBound
        }
        appendEscapedRichText(String(withoutUnsafeBlocks[lastIndex...]), to: &result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func signatureHTML(from signatureBody: String) -> String {
        if containsHTMLMarkup(signatureBody) {
            return signatureBody
        }
        return html(fromEditorText: signatureBody)
    }

    static func editorText(fromStoredHTML html: String) -> String {
        let normalized = normalizeLineEndings(html)
        let withLineBreaks = normalized
            .replacingOccurrences(
                of: #"(?i)<\s*br\s*/?\s*>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)<\s*hr\b[^>]*>"#,
                with: "\n--------------------\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</\s*(p|div|li|tr|h[1-6])\s*>"#,
                with: "\n",
                options: .regularExpression
            )
        let withoutTags = withLineBreaks.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags).trimmingCharacters(in: .newlines)
    }

    private static func normalizeLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func removingUnsafeHTMLBlocks(from value: String) -> String {
        value.replacingOccurrences(
            of: #"(?is)<\s*(script|style|iframe|object|embed|meta|link)\b[^>]*>.*?</\s*\1\s*>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func appendEscapedRichText(_ text: String, to result: inout String) {
        guard !text.isEmpty else { return }
        result.append(html(fromEditorText: decodeHTMLEntities(text)))
    }

    private static func sanitizedRichHTMLTag(_ rawTag: String) -> String? {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), !trimmed.hasPrefix("<!--") else {
            return nil
        }

        if trimmed.dropFirst().trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            let tagName = tagName(in: trimmed, closing: true)
            switch canonicalTagName(tagName) {
            case "a", "blockquote", "div", "em", "li", "ol", "p", "strong", "u", "ul":
                return "</\(canonicalTagName(tagName))>"
            default:
                return nil
            }
        }

        let tagName = canonicalTagName(tagName(in: trimmed, closing: false))
        switch tagName {
        case "br":
            return "<br>"
        case "a":
            guard let href = attribute("href", in: trimmed),
                  isSafeLinkURL(href) else {
                return "<a>"
            }
            return "<a href=\"\(escapeHTML(decodeHTMLEntities(href)))\">"
        case "img":
            guard let src = attribute("src", in: trimmed),
                  isSafeInlineImageSource(src) else {
                return nil
            }
            let alt = attribute("alt", in: trimmed).map { " alt=\"\(escapeHTML(decodeHTMLEntities($0)))\"" } ?? ""
            return "<img src=\"\(escapeHTML(decodeHTMLEntities(src)))\"\(alt)>"
        case "blockquote", "div", "em", "li", "ol", "p", "strong", "u", "ul":
            return "<\(tagName)>"
        default:
            return nil
        }
    }

    private static func tagName(in tag: String, closing: Bool) -> String {
        let prefix = closing ? #"<\s*/\s*([A-Za-z0-9]+)"# : #"<\s*([A-Za-z0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: prefix),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: tag) else {
            return ""
        }
        return String(tag[range]).lowercased()
    }

    private static func canonicalTagName(_ tagName: String) -> String {
        switch tagName.lowercased() {
        case "b": return "strong"
        case "i": return "em"
        default: return tagName.lowercased()
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for index in 1 ..< match.numberOfRanges {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: tag) else {
                continue
            }
            return String(tag[range])
        }
        return nil
    }

    private static func isSafeLinkURL(_ value: String) -> Bool {
        let lowercased = decodeHTMLEntities(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("mailto:")
    }

    private static func isSafeInlineImageSource(_ value: String) -> Bool {
        decodeHTMLEntities(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("cid:")
    }

    private static func containsHTMLMarkup(_ value: String) -> Bool {
        let knownHTMLTagPattern = #"<\s*/?\s*(?:a|b|blockquote|br|div|em|font|hr|i|img|li|ol|p|span|strong|table|tbody|td|th|thead|tr|u|ul)\b[^>]*>"#
        return value.range(of: knownHTMLTagPattern, options: [.caseInsensitive, .regularExpression]) != nil
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

enum ComposeAutoSavePolicy {
    static let inactivityDelayNanoseconds: UInt64 = 30_000_000_000

    static func shouldScheduleAutoSave(
        canSave: Bool,
        isBusy: Bool,
        isBlocked: Bool
    ) -> Bool {
        canSave && !isBusy && !isBlocked
    }

    static func shouldAutoSaveOnDismiss(
        canSave: Bool,
        isBusy: Bool,
        hasCompletedExplicitOperation: Bool
    ) -> Bool {
        canSave && !isBusy && !hasCompletedExplicitOperation
    }
}

public struct ComposeDraftRecoverySnapshot: Codable, Equatable, Sendable {
    let draftID: String
    let remoteID: String?
    let to: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String
    let bodyText: String

    static func recoverableNewMessageDraft(from draft: Draft) -> Self? {
        guard draft.inReplyToMessageID == nil,
              draft.forwardedMessageID == nil else {
            return nil
        }
        return Self(
            draftID: draft.id,
            remoteID: draft.remoteID,
            to: draft.to.map(\.email),
            cc: draft.cc.map(\.email),
            bcc: draft.bcc.map(\.email),
            subject: draft.subject,
            bodyText: ComposeHTMLBodyPolicy.editorText(fromStoredHTML: draft.htmlBody)
        )
    }
}

enum ComposeDraftRecoveryStore {
    static func save(
        _ snapshot: ComposeDraftRecoverySnapshot,
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(accountID: accountID, sourceID: sourceID))
    }

    static func load(
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?,
        defaults: UserDefaults = .standard
    ) -> ComposeDraftRecoverySnapshot? {
        guard let data = defaults.data(forKey: storageKey(accountID: accountID, sourceID: sourceID)) else {
            return nil
        }
        return try? JSONDecoder().decode(ComposeDraftRecoverySnapshot.self, from: data)
    }

    static func clear(
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: storageKey(accountID: accountID, sourceID: sourceID))
    }

    private static func storageKey(accountID: BrevAccount.ID, sourceID: MailSourceID?) -> String {
        let mailboxID = sourceID?.mailboxID ?? "primary"
        return "compose.recovery.v1.\(accountID).\(mailboxID)"
    }
}

/// Updates the `ComposeDraftRecoveryStore` for a new-message compose session.
///
/// Call this from any code path that receives a `ComposeCompletion` for a
/// new-message (non-reply, non-forward) compose — both the sheet path in
/// `BrevMailRootView` and the detached-window path in
/// `DetachedComposeWindowView`. Reply/forward completions are silently
/// ignored because `ComposeDraftRecoverySnapshot.recoverableNewMessageDraft`
/// returns `nil` for those drafts.
///
/// - Parameters:
///   - completion: The completion value reported by `ComposeView`.
///   - accountID: The account that owns the draft.
///   - sourceID: The mailbox source the draft belongs to.
func updateComposeDraftRecovery(
    for completion: ComposeCompletion,
    accountID: BrevAccount.ID,
    sourceID: MailSourceID?
) {
    switch completion {
    case .savedDraft(let draft):
        guard let snapshot = ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: draft) else {
            return
        }
        ComposeDraftRecoveryStore.save(snapshot, accountID: accountID, sourceID: sourceID)
    case .sentMessage(let draft, _, _):
        guard ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: draft) != nil else {
            return
        }
        ComposeDraftRecoveryStore.clear(accountID: accountID, sourceID: sourceID)
    }
}
