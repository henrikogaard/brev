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

public struct BrowserSettings: Equatable, Sendable {
    public enum Key {
        public static func preferredBrowser(scope: String? = nil) -> String {
            guard let scope, !scope.isEmpty else {
                return "browser.preferredBrowser"
            }
            return "browser.preferredBrowser.\(scope)"
        }
    }

    public var preferredBrowser: BrowserChoice

    public static let defaults = BrowserSettings(preferredBrowser: .systemDefault)

    public init(preferredBrowser: BrowserChoice = Self.defaults.preferredBrowser) {
        self.preferredBrowser = preferredBrowser
    }

    public static func load(
        from defaults: UserDefaults = .standard,
        scope: String? = nil
    ) -> BrowserSettings {
        let preferredBrowser = enumValue(
            BrowserChoice.self,
            for: Key.preferredBrowser(scope: scope),
            default: Self.defaults.preferredBrowser,
            defaults: defaults
        )
        return BrowserSettings(
            preferredBrowser: BrowserChoice.availableChoices.contains(preferredBrowser)
                ? preferredBrowser
                : Self.defaults.preferredBrowser
        )
    }

    public func save(to defaults: UserDefaults = .standard, scope: String? = nil) {
        defaults.set(preferredBrowser.rawValue, forKey: Key.preferredBrowser(scope: scope))
    }

    private static func enumValue<T>(
        _ type: T.Type,
        for key: String,
        default defaultValue: T,
        defaults: UserDefaults
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}

public enum BrowserChoice: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case safari
    case chrome
    case firefox
    case edge
    case brave

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .systemDefault: return String(localized: "Default browser", bundle: .module)
        case .safari: return String(localized: "Safari", bundle: .module)
        case .chrome: return String(localized: "Google Chrome", bundle: .module)
        case .firefox: return String(localized: "Firefox", bundle: .module)
        case .edge: return String(localized: "Microsoft Edge", bundle: .module)
        case .brave: return String(localized: "Brave", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .systemDefault:
            return String(localized: "Use the default browser set in the operating system.", bundle: .module)
        case .safari:
            return String(localized: "Open links in Safari where the platform supports it.", bundle: .module)
        case .chrome:
            return String(localized: "Open links in Google Chrome.", bundle: .module)
        case .firefox:
            return String(localized: "Open links in Firefox.", bundle: .module)
        case .edge:
            return String(localized: "Open links in Microsoft Edge.", bundle: .module)
        case .brave:
            return String(localized: "Open links in Brave.", bundle: .module)
        }
    }

    public static var availableChoices: [BrowserChoice] {
        #if os(iOS)
        return allCases.filter { $0 != .safari }
        #else
        return allCases
        #endif
    }
}

public extension BrowserChoice {
    #if os(macOS)
    var macOSBundleIdentifier: String? {
        switch self {
        case .systemDefault:
            return nil
        case .safari:
            return "com.apple.Safari"
        case .chrome:
            return "com.google.Chrome"
        case .firefox:
            return "org.mozilla.firefox"
        case .edge:
            return "com.microsoft.edgemac"
        case .brave:
            return "com.brave.Browser"
        }
    }
    #endif

    #if os(iOS)
    func iOSOpenURL(for url: URL) -> URL? {
        guard let browserURL = iOSBrowserURL(for: url) else { return nil }
        return browserURL
    }
    #endif
}

private extension BrowserChoice {
    #if os(iOS)
    func iOSBrowserURL(for url: URL) -> URL? {
        switch self {
        case .systemDefault, .safari:
            return nil
        case .chrome:
            return iOSURLByReplacingScheme(url, httpScheme: "googlechrome", httpsScheme: "googlechromes")
        case .firefox:
            return iOSURLWithOpenQuery(url, scheme: "firefox", path: "open-url")
        case .edge:
            return iOSURLByReplacingScheme(url, httpScheme: "microsoft-edge-http", httpsScheme: "microsoft-edge-https")
        case .brave:
            return iOSURLWithOpenQuery(url, scheme: "brave", path: "open-url")
        }
    }

    func iOSURLByReplacingScheme(
        _ url: URL,
        httpScheme: String,
        httpsScheme: String
    ) -> URL? {
        var absoluteString = url.absoluteString
        if absoluteString.hasPrefix("https://") {
            absoluteString.replaceSubrange(
                absoluteString.startIndex ..< absoluteString.index(absoluteString.startIndex, offsetBy: 8),
                with: "\(httpsScheme)://"
            )
            return URL(string: absoluteString)
        }
        if absoluteString.hasPrefix("http://") {
            absoluteString.replaceSubrange(
                absoluteString.startIndex ..< absoluteString.index(absoluteString.startIndex, offsetBy: 7),
                with: "\(httpScheme)://"
            )
            return URL(string: absoluteString)
        }
        return nil
    }

    func iOSURLWithOpenQuery(
        _ url: URL,
        scheme: String,
        path: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = path
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString)
        ]
        return components.url
    }
    #endif
}
