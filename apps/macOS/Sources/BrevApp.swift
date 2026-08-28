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

import AppKit
import AuthenticationServices
import BrevBackend
import BrevDesign
import BrevExamplePlugin
import BrevGmail
import BrevMail
import BrevPlugins
import BrevSettings
import BrevSyncEngine
import BrevThemes
import SwiftUI
import UserNotifications

/// Brev's macOS app entry point.
///
/// Uses the IMAP/SMTP backend (ADR-0001). The app holds an `AppSession`
/// that swaps between `LoginView` and `BrevMailRootView` once a
/// real `MailBackend` is connected.
@main
struct BrevApp: App {
    @NSApplicationDelegateAdaptor(BrevMacOSAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var session = AppSession.makeDefault()
    @State private var appIconVariant = AppIconPreferences.load()
    @State private var updateController = MacUpdateController()
    @State private var networkMonitor = NetworkReachabilityMonitor()
    @State private var sessionRestoreAttempted = false
    @State private var isShowingAddAccountSheet = false
    @State private var pendingComposePrefill: ComposePrefill?
    @State private var pendingNotificationRoute: NotificationMailRoute?
    @State private var showRestoreErrorAlert = false
    private let browserLinkOpener = BrowserLinkOpener()

    init() {
        ContactsAccessPolicy.applyProcessWidePolicy()
        // Opt-in iCloud preference sync (ADR-0056); a no-op until the
        // user enables it in Settings → Privacy.
        PreferenceSyncController.standard.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppSessionRestorePresentationPolicy.shouldShowMailboxRoot(
                    visibleBackendCount: session.visibleBackends.count,
                    isRestoringSession: session.isRestoringSession
                ) {
                    BrevMailRootView(
                        backends: session.visibleBackends,
                        aiBackends: session.aiBackends,
                        onSignOut: { await session.signOut() },
                        onChangeTheme: { newTheme in
                            session.theme = newTheme
                        },
                        onOpenSettings: {
                            openWindow(id: BrevWindowID.settings)
                        },
                        signatureContextProvider: { account in
                            AppSessionFactory.composeSignatureContext(for: account)
                        },
                        composeSecurityDefaultsProvider: { account in
                            AppSessionFactory.composeSecurityDefaults(for: account)
                        },
                        trustedSigningIdentityCountProvider: { account in
                            AppSessionFactory.trustedSigningIdentityCount(for: account)
                        },
                        trustedEncryptionIdentityCountProvider: { account in
                            AppSessionFactory.trustedEncryptionIdentityCount(for: account)
                        },
                        pendingComposePrefill: $pendingComposePrefill,
                        pendingNotificationRoute: $pendingNotificationRoute,
                        initialMailboxSelectionAccountID: session.pendingInitialMailboxSelectionAccountID,
                        onFinishInitialMailboxSelection: session.finishInitialMailboxSelection(for:)
                    )
                    .frame(minWidth: 960, minHeight: 600)
                    .environment(\.openURL, browserOpenURLAction)
                    .networkMonitor(networkMonitor)
                    .id(mailRootIdentity)
                } else if AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
                    visibleBackendCount: session.visibleBackends.count,
                    isRestoringSession: session.isRestoringSession,
                    sessionRestoreAttempted: sessionRestoreAttempted
                ) {
                    BrevProgressSurface(label: "Restoring mailbox...")
                        .frame(minWidth: 960, minHeight: 600)
                } else {
                    LoginView(session: session)
                        .frame(minWidth: 960, minHeight: 600)
                }
            }
            .brevRootAppearance(session: session)
            .brevRestoresWindowFrame(named: "BrevMainWindow")
            .background(BrevWindowSurfaceBackground(role: .mainWindow).ignoresSafeArea())
            .brevWindowTranslucency(windowRole: .mainWindow)
            .brevTransparentWindowToolbarBackground()
            .brevHiddenWindowTitle()
            .alert(
                String(localized: "Account error"),
                isPresented: $showRestoreErrorAlert
            ) {
                Button(String(localized: "Open Settings")) {
                    session.clearAccountRestoreErrors()
                    openWindow(id: BrevWindowID.settings)
                }
                Button(String(localized: "Dismiss"), role: .cancel) {
                    session.clearAccountRestoreErrors()
                }
            } message: {
                Text(
                    "One or more accounts couldn't be restored. Open Settings → Accounts to update credentials or remove the affected account."
                )
            }
            .sheet(isPresented: $isShowingAddAccountSheet) {
                MailAccountSetupSheet(session: session) {
                    isShowingAddAccountSheet = false
                }
                .brevTheme(session.theme)
            }
            .task {
                await RetiredSecurityMaterialMigration.run()
                updateController.startIfConfigured()
                // A mailto: launch URL can arrive in the app delegate before
                // this view subscribes to the notification below; drain it here.
                consumePendingMailtoURL()
                consumePendingBrevURL()
                await session.restoreAllAccounts()
                sessionRestoreAttempted = true
                BrevMacOSAppDelegate.currentSession = session
                if !session.accountRestoreErrors.isEmpty,
                   !session.visibleBackends.isEmpty {
                    showRestoreErrorAlert = true
                }
            }
            .onChange(of: session.visibleBackends.map(\.account.id)) { _, _ in
                BrevMacOSAppDelegate.currentSession = session
            }
            .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
                guard isOnline, !wasOnline else { return }
                let backends = session.visibleBackends
                Task {
                    for backend in backends {
                        await backend.replayOfflineMutations()
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brevDidReceiveMailtoURL)
            ) { _ in
                consumePendingMailtoURL()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brevDidReceiveDeepLinkURL)
            ) { _ in
                consumePendingBrevURL()
            }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) {
                    openWindow(id: BrevWindowID.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button(String(localized: "Check for Updates…")) {
                    updateController.settingsActions.performManualCheckIfAvailable()
                }
                .disabled(!updateController.settingsActions.isManualCheckAvailable)
            }
            BrevMailCommands()
        }

        Window("Brev Settings", id: BrevWindowID.settings) {
            SettingsView(
                accountStore: session.accountStore,
                activeTheme: $session.theme,
                activeAppIcon: appIconBinding,
                sectionAvailability: settingsSectionAvailability,
                initialAccounts: session.visibleBackends.map(\.account),
                initialCurrentAccountID: session.backend?.account.id,
                updateActions: updateController.settingsActions,
                developerActions: DeveloperSettingsActions { _ in
                    restartForDeveloperModeChange()
                },
                backendProvider: { accountID in session.backends[accountID] },
                onAddAccount: { isShowingAddAccountSheet = true },
                onSignOut: { account in await session.signOut(account: account) },
                onRemoveAccount: { account in await session.removeAccount(account) },
                onAIProviderConfigurationChanged: {
                    await session.reloadConfiguredAIBackends()
                }
            )
            .brevTheme(session.theme)
            .brevWindowTranslucency(windowRole: .settings)
            .brevTransparentWindowToolbarBackground()
            .brevHiddenWindowTitle()
            .environment(\.openURL, browserOpenURLAction)
        }
        .windowResizability(.contentMinSize)

        Window("Keyboard Shortcuts", id: BrevWindowID.keyboardShortcuts) {
            KeyboardShortcutsHelpView()
                .brevTheme(session.theme)
        }
        .windowResizability(.contentSize)
    }

    private var browserOpenURLAction: OpenURLAction {
        OpenURLAction { url in
            if url.scheme?.lowercased() == "brev" {
                return handleIncomingURL(url) ? .handled : .discarded
            }
            if url.scheme?.lowercased() == "mailto",
               let prefill = ComposePrefill(mailtoURL: url) {
                pendingComposePrefill = prefill
                return .handled
            }
            return browserLinkOpener.open(url)
        }
    }

    private var mailRootIdentity: String {
        session.visibleBackends
            .map(\.account.id)
            .sorted()
            .joined(separator: "|")
    }

    /// Turns a `mailto:` URL handed to the app delegate (Brev as default
    /// email reader, or `open mailto:...`) into a pending compose prefill.
    private func consumePendingMailtoURL() {
        guard let url = BrevMacOSAppDelegate.takePendingMailtoURL(),
              let prefill = ComposePrefill(mailtoURL: url) else {
            return
        }
        pendingComposePrefill = prefill
    }

    /// Parses a Brev deep link using the same shared compose/message routing
    /// policy as iOS. Invalid or unsupported routes are ignored safely.
    @discardableResult
    private func handleIncomingURL(_ url: URL) -> Bool {
        if let prefill = SharedComposePayload.prefill(from: url) {
            pendingComposePrefill = prefill
            return true
        }
        if let prefill = ComposePrefill(mailtoURL: url) {
            pendingComposePrefill = prefill
            return true
        }
        if let route = NotificationRoutingPolicy.route(from: url) {
            pendingNotificationRoute = route
            return true
        }
        return false
    }

    private func consumePendingBrevURL() {
        guard let url = BrevMacOSAppDelegate.takePendingBrevURL() else { return }
        handleIncomingURL(url)
    }

    private var appIconBinding: Binding<AppIconVariant> {
        Binding(
            get: { appIconVariant },
            set: { variant in
                appIconVariant = variant
                AppIconPreferences.save(variant)
                applyMacOSAppIcon(variant)
            }
        )
    }

    private var settingsSectionAvailability: SettingsSectionAvailability {
        #if DEBUG
        .macOSDeveloperDirectDownload
        #else
        .macOSDirectDownload
        #endif
    }

    @MainActor
    private func restartForDeveloperModeChange() {
        let clearEnvironment = Process()
        clearEnvironment.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        clearEnvironment.arguments = ["unsetenv", "BREV_USE_MOCK"]
        try? clearEnvironment.run()
        clearEnvironment.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}

enum BrevWindowID {
    static let settings = "brev-settings"
    static let keyboardShortcuts = "brev-keyboard-shortcuts"
}

final class BrevMacOSAppDelegate: NSObject, NSApplicationDelegate {
    /// Updated by `BrevApp` whenever the session or its visible backends change.
    /// Used by the background activity scheduler to know which accounts to poll.
    @MainActor static var currentSession: AppSession?

    /// Most recent `mailto:` URL delivered by Launch Services and not yet
    /// consumed by `BrevApp`. Held statically because the URL can arrive
    /// during a cold launch before the SwiftUI scene has subscribed to
    /// `.brevDidReceiveMailtoURL`.
    @MainActor private static var pendingMailtoURL: URL?
    @MainActor private static var pendingBrevURL: URL?

    /// Returns and clears the pending `mailto:` URL, if any.
    @MainActor static func takePendingMailtoURL() -> URL? {
        defer { pendingMailtoURL = nil }
        return pendingMailtoURL
    }

    /// Returns and clears a pending `brev://` URL, including one delivered
    /// before SwiftUI subscribed during a cold launch.
    @MainActor static func takePendingBrevURL() -> URL? {
        defer { pendingBrevURL = nil }
        return pendingBrevURL
    }

    private var backgroundScheduler: NSBackgroundActivityScheduler?

    /// Installed as `UNUserNotificationCenter.current().delegate` at launch so
    /// notification actions delivered during app startup are not silently dropped.
    /// `BrevMailRootView.setupNotifications()` detects this instance and wires
    /// its callbacks on it rather than replacing it.
    let notificationDelegate = BrevNotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyMacOSAppIcon(AppIconPreferences.load())
        UNUserNotificationCenter.current().delegate = notificationDelegate
        BrevPluginRegistry.shared.register(BrevExamplePlugin())
        startBackgroundScheduler()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await BrevMacOSNotificationLifecycle.handleAppDidBecomeActive()
        }
    }

    // `applicationDidEnterBackground` is a UIKit method that AppKit never calls;
    // `applicationDidResignActive` is the NSApplicationDelegate counterpart to
    // `applicationDidBecomeActive` above. Wiring the handoff here is what
    // actually schedules the inbox-refresh reminder when the app stops being
    // active on macOS.
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            await BrevMacOSNotificationLifecycle.handleAppDidEnterBackground()
        }
    }

    // MARK: URL handling

    /// Receives external URLs and keeps the existing main window in charge
    /// instead of letting SwiftUI spawn a new `WindowGroup` instance.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last(where: { url in
            let scheme = url.scheme?.lowercased()
            return scheme == "mailto" || scheme == "brev"
        }) else { return }
        Task { @MainActor in
            switch url.scheme?.lowercased() {
            case "mailto":
                Self.pendingMailtoURL = url
                NotificationCenter.default.post(name: .brevDidReceiveMailtoURL, object: nil)
            case "brev":
                Self.pendingBrevURL = url
                NotificationCenter.default.post(name: .brevDidReceiveDeepLinkURL, object: nil)
            default:
                return
            }
            NSApplication.shared.activate()
        }
    }

    // Scheduled ("send later") drafts are delivered by an in-process poller, so
    // quitting with pending entries silently defers them until the next launch.
    // Ask before quitting instead of losing the send window unnoticed.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pendingCount = MainActor.assumeIsolated {
            let backends: [any MailBackend] = Self.currentSession.map { Array($0.backends.values) } ?? []
            return backends
                .compactMap { $0.extensionService(ScheduledSendManaging.self) }
                .reduce(0) { $0 + $1.pendingScheduledSends().count }
        }
        guard let message = ScheduleSendReliabilityPresentation.quitWarningMessage(pendingCount: pendingCount) else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Brev?")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Background refresh

    private func startBackgroundScheduler() {
        // NSBackgroundActivityScheduler fires while the app is running
        // (including when it is not the frontmost app), but macOS does not
        // suspend apps the way iOS does, so this fires roughly every 15 min
        // while Brev is open. Closed-app delivery remains best effort (ADR-0037).
        let scheduler = NSBackgroundActivityScheduler(identifier: "eu.brevmail.background-refresh")
        scheduler.repeats = true
        scheduler.interval = 15 * 60
        scheduler.tolerance = 5 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            guard self != nil else {
                completion(.finished)
                return
            }
            Task { @MainActor in
                let backends = BrevMacOSAppDelegate.currentSession?.visibleBackends ?? []
                await MailFetchScheduler.performBackgroundRefresh(backends: backends)
                completion(.finished)
            }
        }
        backgroundScheduler = scheduler
    }
}

/// macOS-only bridge between the app delegate's lifecycle hooks and the
/// BrevMail notification surface.
@MainActor
enum BrevMacOSNotificationLifecycle {
    static func handleAppDidBecomeActive() async {
        let center = BrevLocalNotificationCenter()
        await center.currentAuthorizationStatus()
        center.clearAllDelivered()
        // Cancel any queued background "Checking for new mail…" reminder so it
        // doesn't fire as a banner while the user is actively in the app.
        center.cancelInboxRefreshReminder()
    }

    static func handleAppDidEnterBackground() async {
        let settings = NotificationSettings.load()
        guard settings.notificationsEnabled else { return }
        let center = BrevLocalNotificationCenter()
        await center.scheduleInboxRefreshReminder()
    }
}

extension Notification.Name {
    /// Posted by `BrevMacOSAppDelegate` after storing an incoming `mailto:` URL.
    static let brevDidReceiveMailtoURL = Notification.Name("eu.brevmail.mailto.didReceive")
    /// Posted by `BrevMacOSAppDelegate` after storing an incoming `brev://` URL.
    static let brevDidReceiveDeepLinkURL = Notification.Name("eu.brevmail.deepLink.didReceive")
}

@MainActor
private func applyMacOSAppIcon(_ variant: AppIconVariant) {
    // The default variant is the bundle icon itself; resetting to nil keeps
    // its light/dark appearance switching, which a static NSImage would lose.
    guard variant != .defaultVariant else {
        NSApplication.shared.applicationIconImage = nil
        return
    }
    if let image = NSImage(named: variant.previewAssetName) {
        NSApplication.shared.applicationIconImage = image
    }
}

private extension View {
    @ViewBuilder
    func brevTransparentWindowToolbarBackground() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    @ViewBuilder
    func brevHiddenWindowTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            background(BrevWindowTitleVisibilityBridge())
        }
    }
}

private struct BrevWindowTitleVisibilityBridge: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        WindowTitleVisibilityView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? WindowTitleVisibilityView)?.hideWindowTitle()
    }

    private final class WindowTitleVisibilityView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideWindowTitle()
        }

        func hideWindowTitle() {
            window?.titleVisibility = .hidden
        }
    }
}

extension AppSession {
    /// Default session for the macOS app.
    @MainActor
    static func makeDefault() -> AppSession {
        let gmailConnector = GmailAccountConnector.standard(
            applicationSupportURL: applicationSupportURL,
            configurationStore: UserDefaultsGmailAccountConfigurationStore(),
            tokenStore: KeychainTokenStore()
        )
        return AppSessionFactory.makeDefault(
            configuration: AppSessionFactory.Configuration(
                applicationSupportURL: applicationSupportURL,
                oauthPresentationAnchor: oauthPresentationAnchor,
                localSearchIndex: { accountID in
                    try? BrevSyncEngine(
                        databaseURL: BrevSyncEngine.defaultDatabaseURL(accountID: accountID)
                    )
                },
                googleOAuthAccountProvisioningCoordinator: { result in
                    let connected = try await gmailConnector.provision(result)
                    return AppSession.LoginResult(
                        backend: connected.backend,
                        account: connected.account
                    )
                },
                googleOAuthRestoreCoordinator: { account in
                    guard let connected = try await gmailConnector.restore(account) else { return nil }
                    return AppSession.LoginResult(
                        backend: connected.backend,
                        account: connected.account
                    )
                },
                googleOAuthRemovalCoordinator: { accountID in
                    try await gmailConnector.remove(accountID: accountID)
                }
            )
        )
    }

    @MainActor
    private static func oauthPresentationAnchor() throws -> ASPresentationAnchor {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw MailBackendError.backendSpecific(message: String(localized: "OAuth sign-in needs an active window."))
        }
        return window
    }
}

private var applicationSupportURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}
