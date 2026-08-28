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

import BrevDesign
import BrevThemes
import SwiftUI
import WebKit

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Owns the WebKit instance used by a reading surface so selecting another
/// message updates an already-warm renderer instead of constructing WebKit
/// again on the critical path.
@MainActor
final class HTMLBodyWebViewStore: ObservableObject {
    private var storedWebView: WKWebView?
    private(set) var isPrewarmed = false
    private var hasScheduledContentLoad = false
    /// Whether WebKit has been instantiated for this store.
    var isWebViewCreated: Bool { storedWebView != nil }

    init() {}

    var webView: WKWebView {
        if let storedWebView {
            return storedWebView
        }
        #if canImport(AppKit)
        let webView = ScrollForwardingWebView(frame: .zero, configuration: Self.configuration())
        #else
        let webView = WKWebView(frame: .zero, configuration: Self.configuration())
        #endif
        Self.prepare(webView)
        storedWebView = webView
        return webView
    }

    /// Starts WebKit with a local empty document. This performs no network
    /// access and is safe to call repeatedly.
    func prewarm() {
        guard !isPrewarmed, !hasScheduledContentLoad else { return }
        isPrewarmed = true
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }

    /// Prevents a late warm-up task from replacing real message content.
    func prepareForContentLoad() {
        hasScheduledContentLoad = true
    }

    private static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        config.suppressesIncrementalRendering = false
        return config
    }

    private static func prepare(_ webView: WKWebView) {
        #if canImport(AppKit)
        // `underPageBackgroundColor` is WebKit's supported macOS API. The
        // former KVC write to the private `drawsBackground` property broke
        // under hardened runtime and could fail silently across OS releases.
        webView.underPageBackgroundColor = .clear
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        #endif
    }
}

#if canImport(AppKit)
/// The reader self-sizes the web view to its document and hands scrolling to
/// the enclosing SwiftUI `ScrollView` — but WebKit consumes `scrollWheel`
/// events even when it has nothing left to scroll, which left a freshly
/// opened message frozen under the wheel until a window resize happened to
/// nudge WebKit into passing events through. Forward the events to the next
/// responder (the outer scroll view) instead; WebKit keeps them only when
/// the document is taller than the self-size cap and needs its own scrolling
/// to reach the tail.
final class ScrollForwardingWebView: WKWebView {
    var forwardsScrollWheel = true

    override func scrollWheel(with event: NSEvent) {
        if forwardsScrollWheel {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#endif

/// Decides who owns wheel events over a self-sized mail body: the enclosing
/// scroll view (the document fits its frame, nothing to scroll internally)
/// or WebKit itself (the document outgrew the self-size cap and the fixed
/// frame cannot show the tail).
enum HTMLBodyScrollForwardingPolicy {
    static func forwardsToEnclosingScrollView(
        contentHeight: CGFloat,
        selfSizingCap: CGFloat
    ) -> Bool {
        contentHeight <= selfSizingCap
    }
}

/// SwiftUI wrapper around a sandboxed `WKWebView` that renders a
/// single mail body. Privacy posture (ADR-0006):
///
/// - JavaScript is disabled.
/// - Top-level navigations from the document are blocked; only the
///   initial `loadHTMLString(…)` is accepted. Tapped links are
///   surfaced via `onOpenURL`.
/// - When `allowRemoteContent` is `false` (the default), a
///   `WKContentRuleList` blocks every subresource load. The
///   document is rendered with whatever is inlined; remote images,
///   CSS, web fonts, and tracking pixels do not fire.
struct HTMLBodyWebView: View {
    @ObservedObject var store: HTMLBodyWebViewStore
    let html: String
    let allowRemoteContent: Bool
    let fontFamily: MailboxFontFamily
    let textSize: MailboxTextSize
    let renderingMode: HTMLBodyRenderingMode
    var bodyInsetPoints: CGFloat = 0
    let onOpenURL: (URL) -> Void
    var onDidFinishRendering: () -> Void = {}

    @Environment(\.brevTheme) private var theme
    @Environment(\.htmlBodyRenderTarget) private var renderTarget
    @State private var measuredHeight: CGFloat = 200

    var body: some View {
        let style = MessageBodyStyle.resolve(
            theme: theme,
            fontFamily: fontFamily,
            textSize: textSize,
            renderingMode: renderingMode,
            bodyInsetPoints: bodyInsetPoints
        )
        Group {
            switch renderTarget {
            case .webView:
                WebViewRepresentable(
                    store: store,
                    html: html,
                    allowRemoteContent: allowRemoteContent,
                    style: style,
                    measuredHeight: $measuredHeight,
                    onOpenURL: onOpenURL,
                    onDidFinishRendering: onDidFinishRendering
                )
                .frame(height: measuredHeight)
            case .staticSnapshot:
                Text(HTMLBodyStaticSnapshot.plainText(from: html))
                    .font(style.swiftUIBodyFont)
                    .foregroundStyle(theme.textPrimary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BrevSpacing.xs)
                    .onAppear(perform: onDidFinishRendering)
            }
        }
    }
}

enum HTMLBodyRenderTarget: Sendable {
    case webView
    case staticSnapshot
}

private enum HTMLBodyRenderTargetKey: EnvironmentKey {
    static let defaultValue: HTMLBodyRenderTarget = .webView
}

extension EnvironmentValues {
    var htmlBodyRenderTarget: HTMLBodyRenderTarget {
        get { self[HTMLBodyRenderTargetKey.self] }
        set { self[HTMLBodyRenderTargetKey.self] = newValue }
    }
}

extension View {
    /// Selects a deterministic body renderer for snapshot chrome tests.
    func htmlBodyRenderTarget(_ target: HTMLBodyRenderTarget) -> some View {
        environment(\.htmlBodyRenderTarget, target)
    }
}

enum HTMLBodyStaticSnapshot {
    static func plainText(from html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Representable

private struct WebViewRepresentable {
    let store: HTMLBodyWebViewStore
    let html: String
    let allowRemoteContent: Bool
    let style: MessageBodyStyle
    @Binding var measuredHeight: CGFloat
    let onOpenURL: (URL) -> Void
    let onDidFinishRendering: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    fileprivate func configure(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.parent = self
        webView.navigationDelegate = coordinator
        store.prepareForContentLoad()
        coordinator.load(
            into: webView,
            html: html,
            allowRemoteContent: allowRemoteContent,
            style: style
        )
    }

    @MainActor
    fileprivate func update(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.parent = self
        if coordinator.lastHTML != html
            || coordinator.lastAllowRemote != allowRemoteContent
            || coordinator.lastStyle != style {
            coordinator.load(
                into: webView,
                html: html,
                allowRemoteContent: allowRemoteContent,
                style: style
            )
        }
    }
}

#if canImport(AppKit)
extension WebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = store.webView
        configure(webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#else
extension WebViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = store.webView
        configure(webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#endif

// MARK: - Coordinator

extension WebViewRepresentable {
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var lastHTML: String?
        var lastAllowRemote: Bool?
        var lastStyle: MessageBodyStyle?
        private var loadGeneration = 0

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func load(
            into webView: WKWebView,
            html: String,
            allowRemoteContent: Bool,
            style: MessageBodyStyle
        ) {
            loadGeneration &+= 1
            let generation = loadGeneration
            lastHTML = html
            lastAllowRemote = allowRemoteContent
            lastStyle = style
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            Task { [weak self, weak webView] in
                let blocker: WKContentRuleList?
                if !allowRemoteContent,
                   let compiledBlocker = await HTMLBlocker.shared.list() {
                    // Rule-list installation and the document load must be
                    // ignored when a newer message replaced this request.
                    // Otherwise a slower blocker compilation can load stale
                    // HTML over the currently selected message.
                    blocker = compiledBlocker
                } else {
                    blocker = nil
                }
                let plan = HTMLBodyLoadPlan.resolve(
                    allowRemoteContent: allowRemoteContent,
                    blockerAvailable: blocker != nil
                )
                // Wrapping is pure string/regex work over the whole body;
                // keep it off the main actor so paint isn't blocked on it.
                let document = HTMLBodyDocument.wrap(
                    plan.bodyHTML(originalHTML: html),
                    style: style
                )
                await MainActor.run {
                    guard let self, self.loadGeneration == generation,
                          let webView
                    else { return }
                    let controller = webView.configuration.userContentController
                    controller.removeAllContentRuleLists()
                    if let blocker {
                        controller.add(blocker)
                    }
                    _ = webView.loadHTMLString(document, baseURL: nil)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // `loadHTMLString` uses about:blank for each programmatic document.
            // Permit repeated local document loads so an early prewarm cannot
            // consume a one-shot allowance and cancel the real message body.
            // External top-level navigations remain blocked.
            if navigationAction.navigationType == .other,
               HTMLBodyNavigationPolicy.isLocalDocumentURL(navigationAction.request.url) {
                decisionHandler(.allow)
                return
            }
            // Route taps on links back to the host so the OS can open
            // them in the user's browser. Cancel inside the webview. Drop
            // dangerous-scheme links (javascript:, data:, file:, …) before the
            // host opener ever sees them — message HTML is untrusted.
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               MessageLinkSchemePolicy.isOpenable(url) {
                parent.onOpenURL(url)
            }
            decisionHandler(.cancel)
        }

        /// Upper bound on the self-sized frame height. A pathological document
        /// can't create an unbounded view; content taller than this falls back to
        /// the web view's own scrolling (see below) so nothing is lost.
        static let maxContentHeight: CGFloat = 20000

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure the *body* content height, not the documentElement's —
            // `documentElement.scrollHeight` is floored at the web view's own
            // viewport height, so short emails would never shrink below the
            // initial frame and left a large empty area in the message card.
            webView.evaluateJavaScript(
                "document.body.scrollHeight"
            ) { [weak self] result, _ in
                guard let height = result as? CGFloat, height > 0 else { return }
                Task { @MainActor in
                    self?.parent.measuredHeight = min(max(height, 80), Self.maxContentHeight)
                    #if canImport(AppKit)
                    // Same self-size-cap rule as iOS below: the outer scroll
                    // view owns the wheel unless the tail is only reachable
                    // through WebKit's own scrolling.
                    (webView as? ScrollForwardingWebView)?.forwardsScrollWheel =
                        HTMLBodyScrollForwardingPolicy.forwardsToEnclosingScrollView(
                            contentHeight: height,
                            selfSizingCap: Self.maxContentHeight
                        )
                    #endif
                    #if canImport(UIKit)
                    // When the body is taller than the self-sized cap, the fixed
                    // frame can't show all of it, so re-enable the web view's own
                    // scrolling to keep the tail reachable. Below the cap it stays
                    // off so it doesn't fight the message's outer ScrollView.
                    // Without this, long iOS bodies were silently truncated.
                    webView.scrollView.isScrollEnabled = height > Self.maxContentHeight
                    #endif
                }
            }
            parent.onDidFinishRendering()
        }
    }
}

enum HTMLBodyNavigationPolicy {
    static func isLocalDocumentURL(_ url: URL?) -> Bool {
        url?.absoluteString == "about:blank"
    }
}

enum HTMLBodyLoadPlan: Equatable {
    case original(blocksRemoteSubresources: Bool)
    case blockedFallback

    static func resolve(
        allowRemoteContent: Bool,
        blockerAvailable: Bool
    ) -> HTMLBodyLoadPlan {
        if allowRemoteContent {
            return .original(blocksRemoteSubresources: false)
        }
        if blockerAvailable {
            return .original(blocksRemoteSubresources: true)
        }
        return .blockedFallback
    }

    func bodyHTML(originalHTML: String) -> String {
        switch self {
        case .original:
            return originalHTML
        case .blockedFallback:
            return HTMLBodyDocument.remoteContentBlockedFallback()
        }
    }
}

enum HTMLBodyDocument {
    static func remoteContentBlockedFallback() -> String {
        """
        <section role="note" aria-label="Remote content blocked">\
        <strong>Remote content is blocked.</strong> Brev could not prepare \
        its WebKit privacy blocker, so it did not render this HTML body. \
        Use the plain-text view or explicitly allow remote content for this \
        message if you trust the sender.\
        </section>
        """
    }

    static func wrap(
        _ inner: String,
        style: MessageBodyStyle
    ) -> String {
        let bodyHTML = normalizedBodyHTML(inner)
        return """
        <!doctype html><html><head>\
        <meta charset="utf-8">\
        <meta name="viewport" content="width=device-width,initial-scale=1">\
        <meta name="color-scheme" content="\(style.colorSchemeMeta)">\
        <style>\
        \(style.documentCSS)\
        </style></head><body>\(bodyHTML)</body></html>
        """
    }

    /// Compatibility wrapper used by older call sites/tests.
    static func wrap(
        _ inner: String,
        linkColorHex: String,
        textColorHex: String = "currentColor",
        fontFamily: MailboxFontFamily = .system,
        textSize: MailboxTextSize = .medium,
        renderingMode: HTMLBodyRenderingMode = .original,
        bodyInsetPoints: CGFloat = 0
    ) -> String {
        let text = MessageBodyStyle.cssColor(textColorHex)
        let link = MessageBodyStyle.cssColor(linkColorHex)
        let forcesLightCanvas = renderingMode == .original && MessageBodyStyle.isLightColor(text)
        let style = MessageBodyStyle(
            fontFamily: fontFamily,
            textSize: textSize,
            textColorHex: text,
            linkColorHex: link,
            backgroundColorHex: forcesLightCanvas ? "#FFFFFF" : nil,
            mutedTextColorCSS: "rgba(127,127,127,1)",
            borderColorCSS: "rgba(127,127,127,.4)",
            metadataBackgroundCSS: "rgba(17,24,39,.04)",
            metadataTextColorCSS: "rgba(75,85,99,1)",
            codeBackgroundCSS: "transparent",
            bodyInsetPoints: bodyInsetPoints,
            lineHeight: MessageBodyStyle.defaultLineHeight,
            renderingMode: renderingMode,
            colorSchemeMeta: renderingMode == .dark ? "dark light" : "light",
            forcesOriginalLightCanvas: forcesLightCanvas
        )
        return wrap(inner, style: style)
    }

    private static func normalizedBodyHTML(_ inner: String) -> String {
        let normalized = inner
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !containsHTMLMarkup(normalized) else {
            return cleanQuotedMetadataHTML(normalized)
        }
        return escapeHTML(normalized).replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func cleanQuotedMetadataHTML(_ html: String) -> String {
        guard let hrRange = html.range(
            of: #"<\s*hr\b[^>]*>"#,
            options: [.caseInsensitive, .regularExpression]
        ) else {
            return html
        }

        var metadataStart = hrRange.upperBound
        while metadataStart < html.endIndex,
              html[metadataStart].isWhitespace {
            metadataStart = html.index(after: metadataStart)
        }

        var cursor = metadataStart
        var metadataEnd = cursor
        var metadataLineCount = 0
        while cursor < html.endIndex,
              let breakRange = html[cursor...].range(
                  of: #"<\s*br\s*/?\s*>"#,
                  options: [.caseInsensitive, .regularExpression]
              ) {
            let lineHTML = String(html[cursor ..< breakRange.lowerBound])
            let lineText = stripTags(lineHTML).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isQuotedMetadataLine(lineText) else { break }
            metadataLineCount += 1
            metadataEnd = breakRange.upperBound
            cursor = breakRange.upperBound
        }

        guard metadataLineCount >= 2, metadataEnd > metadataStart else { return html }

        return String(html[..<metadataStart])
            + #"<section class="brev-mail-metadata">"#
            + String(html[metadataStart ..< metadataEnd])
            + "</section>"
            + String(html[metadataEnd...])
    }

    private static func isQuotedMetadataLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return ["from:", "sent:", "date:", "to:", "cc:", "bcc:", "subject:"]
            .contains { lowercased.hasPrefix($0) }
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func containsHTMLMarkup(_ value: String) -> Bool {
        let knownHTMLTagPattern = #"<\s*/?\s*(?:a|b|blockquote|br|div|em|font|h[1-6]|head|html|hr|i|img|li|meta|ol|p|span|strong|style|table|tbody|td|th|thead|title|tr|u|ul|body)\b[^>]*>"#
        return value.range(of: knownHTMLTagPattern, options: [.caseInsensitive, .regularExpression]) != nil
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Blocker

/// Lazy-compiled `WKContentRuleList` that blocks every subresource
/// load. Re-used across web views to avoid the compilation cost on
/// every message open.
private actor HTMLBlocker {
    static let shared = HTMLBlocker()

    private var cached: WKContentRuleList?

    func list() async -> WKContentRuleList? {
        if let cached { return cached }
        let list = await MainActor.run { () -> WKContentRuleListStore? in
            WKContentRuleListStore.default()
        }
        guard let store = list else { return nil }
        let compiled = try? await store.compileContentRuleList(
            forIdentifier: "brev.block-all-subresources",
            encodedContentRuleList: HTMLRemoteContentBlockerRule.encodedContentRuleList
        )
        cached = compiled
        return compiled
    }
}

enum HTMLRemoteContentBlockerRule {
    static let encodedContentRuleList = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
    """
}
