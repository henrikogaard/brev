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
import SwiftUI
import WebKit

/// A file or folder the user picked through the Google Picker (#14).
public struct GoogleDrivePick: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let mimeType: String
    /// The Drive web link for the attach-as-link flow.
    public let url: String?
    /// True when the picker was in folder mode and the pick names a
    /// destination folder rather than a file.
    public let isFolder: Bool

    public init(
        id: String,
        name: String,
        mimeType: String,
        url: String? = nil,
        isFolder: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.url = url
        self.isFolder = isFolder
    }
}

/// What the picker is selecting — files to attach, or a folder to
/// save into.
public enum GoogleDrivePickerMode: Sendable {
    case files
    case folder
}

/// Hosts the Google Picker inside a WebKit view (#14, ADR-0006).
///
/// The `drive.file` scope cannot list the user's Drive — the
/// Google-hosted picker is the supported way to let the user choose
/// files under that narrow grant. The page loads `api.js` from
/// Google, receives the account's OAuth token and the build's
/// developer key, and posts picked documents back through a script
/// message handler. Tokens never leave the page's JavaScript context
/// or the log.
public struct GoogleDrivePickerView {
    /// Page configuration for one picker presentation.
    public struct Configuration: Sendable {
        public let accessToken: String
        public let developerKey: String
        public let appID: String
        public let mode: GoogleDrivePickerMode

        public init(
            accessToken: String,
            developerKey: String,
            appID: String,
            mode: GoogleDrivePickerMode
        ) {
            self.accessToken = accessToken
            self.developerKey = developerKey
            self.appID = appID
            self.mode = mode
        }
    }

    /// The script-message handler name the page posts results to.
    static let messageHandlerName = "brevDrivePicker"

    private let configuration: Configuration
    private let onPicked: ([GoogleDrivePick]) -> Void
    private let onCancel: () -> Void
    private let onError: (String) -> Void

    public init(
        configuration: Configuration,
        onPicked: @escaping ([GoogleDrivePick]) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.onPicked = onPicked
        self.onCancel = onCancel
        self.onError = onError
    }

    /// The self-contained picker page. Secrets are JSON-encoded so a
    /// quote inside a token cannot break the script.
    static func html(configuration: Configuration) -> String {
        let token = jsonLiteral(configuration.accessToken)
        let key = jsonLiteral(configuration.developerKey)
        let appID = jsonLiteral(configuration.appID)
        let viewJS: String
        switch configuration.mode {
        case .files:
            viewJS =
                "new google.picker.DocsView(google.picker.ViewId.DOCS)"
                    + ".setIncludeFolders(false).setSelectFolderEnabled(false)"
        case .folder:
            viewJS =
                "new google.picker.DocsView(google.picker.ViewId.FOLDERS)"
                    + ".setIncludeFolders(true).setSelectFolderEnabled(true)"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,.picker { height:100%; margin:0; }</style>
        </head>
        <body>
        <script>
        var oauthToken = \(token);
        var developerKey = \(key);
        var appId = \(appID);
        function report(message) {
          window.webkit.messageHandlers.\(messageHandlerName)
            .postMessage({ action: 'error', message: message });
        }
        function onApiLoad() {
          try {
            gapi.load('picker', { callback: createPicker });
          } catch (e) { report(String(e)); }
        }
        function createPicker() {
          try {
            var view = \(viewJS);
            new google.picker.PickerBuilder()
              .addView(view)
              .setOAuthToken(oauthToken)
              .setDeveloperKey(developerKey)
              .setAppId(appId)
              .setCallback(pickerCallback)
              .build()
              .setVisible(true);
          } catch (e) { report(String(e)); }
        }
        function pickerCallback(data) {
          if (data.action === google.picker.Action.PICKED) {
            var docs = (data.docs || []).map(function (d) {
              return { id: d.id, name: d.name, mimeType: d.mimeType, url: d.url };
            });
            window.webkit.messageHandlers.\(messageHandlerName)
              .postMessage({ action: 'picked', docs: docs });
          } else if (data.action === google.picker.Action.CANCEL) {
            window.webkit.messageHandlers.\(messageHandlerName)
              .postMessage({ action: 'cancel' });
          }
        }
        </script>
        <script src="https://apis.google.com/js/api.js?onload=onApiLoad"></script>
        </body>
        </html>
        """
    }

    /// JSON-encodes a Swift string for safe inline JavaScript.
    static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return literal
    }

    /// What a picker script message means for the sheet.
    enum MessageOutcome: Equatable {
        case picked([GoogleDrivePick])
        case cancelled
        case failed(String)
    }

    /// Parses a script message into picks, cancel, or an error string.
    static func handle(
        message: [String: Any]
    ) -> MessageOutcome {
        guard let action = message["action"] as? String else {
            return .failed("unreadable picker message")
        }
        switch action {
        case "picked":
            let docs = (message["docs"] as? [[String: Any]]) ?? []
            let picks = docs.compactMap { doc -> GoogleDrivePick? in
                guard let id = doc["id"] as? String,
                      let name = doc["name"] as? String,
                      let mimeType = doc["mimeType"] as? String
                else { return nil }
                return GoogleDrivePick(
                    id: id,
                    name: name,
                    mimeType: mimeType,
                    url: doc["url"] as? String
                )
            }
            return .picked(picks)
        case "cancel":
            return .cancelled
        case "error":
            return .failed(
                (message["message"] as? String)
                    ?? "The Google picker failed."
            )
        default:
            return .failed("unreadable picker message")
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onPicked: onPicked,
            onCancel: onCancel,
            onError: onError
        )
    }

    /// Routes script messages to the view's callbacks.
    public final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onPicked: ([GoogleDrivePick]) -> Void
        private let onCancel: () -> Void
        private let onError: (String) -> Void

        init(
            onPicked: @escaping ([GoogleDrivePick]) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onPicked = onPicked
            self.onCancel = onCancel
            self.onError = onError
        }

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == GoogleDrivePickerView.messageHandlerName,
                  let body = message.body as? [String: Any]
            else { return }
            switch GoogleDrivePickerView.handle(message: body) {
            case .picked(let picks):
                onPicked(picks)
            case .cancelled:
                onCancel()
            case .failed(let error):
                onError(error)
            }
        }
    }

    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            context.coordinator,
            name: Self.messageHandlerName
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        #if canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        webView.loadHTMLString(
            Self.html(configuration: configuration),
            // The picker requires a real HTTPS origin to resolve its
            // resources and honor the OAuth token.
            baseURL: URL(string: "https://drive.google.com")
        )
        return webView
    }
}

#if canImport(AppKit)
extension GoogleDrivePickerView: NSViewRepresentable {
    public typealias Context = NSViewRepresentableContext<GoogleDrivePickerView>

    public func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
extension GoogleDrivePickerView: UIViewRepresentable {
    public typealias Context = UIViewRepresentableContext<GoogleDrivePickerView>

    public func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
