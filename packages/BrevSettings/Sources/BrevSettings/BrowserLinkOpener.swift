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

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens external links in the browser selected in `BrowserSettings`.
///
/// The app shell injects this as `openURL` so links in mail bodies and
/// about/settings surfaces all follow the same preference.
@MainActor
public struct BrowserLinkOpener {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func open(_ url: URL) -> OpenURLAction.Result {
        open(url, using: BrowserSettings.load(from: defaults).preferredBrowser)
    }

    public func open(_ url: URL, using browser: BrowserChoice) -> OpenURLAction.Result {
        #if os(macOS)
        return openOnMac(url, using: browser)
        #else
        return openOnIOS(url, using: browser)
        #endif
    }

    #if os(macOS)
    private func openOnMac(_ url: URL, using browser: BrowserChoice) -> OpenURLAction.Result {
        guard let bundleIdentifier = browser.macOSBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return openInDefaultBrowser(url)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if error != nil {
                _ = NSWorkspace.shared.open(url)
            }
        }
        return .handled
    }

    private func openInDefaultBrowser(_ url: URL) -> OpenURLAction.Result {
        _ = NSWorkspace.shared.open(url)
        return .handled
    }
    #else
    private func openOnIOS(_ url: URL, using browser: BrowserChoice) -> OpenURLAction.Result {
        guard let browserURL = browser.iOSOpenURL(for: url) else {
            return openInDefaultBrowser(url)
        }

        UIApplication.shared.open(browserURL, options: [:]) { success in
            if !success {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        return .handled
    }

    private func openInDefaultBrowser(_ url: URL) -> OpenURLAction.Result {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .handled
    }
    #endif
}
