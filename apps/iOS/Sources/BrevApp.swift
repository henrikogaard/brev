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

import AuthenticationServices
import BackgroundTasks
import BrevBackend
import BrevExamplePlugin
import BrevGmail
import BrevMail
import BrevPlugins
import BrevSettings
import BrevSyncEngine
import BrevThemes
import os
import SwiftUI
import UIKit
import UserNotifications

/// Brev's iOS app entry point.
///
/// Holds the `AppSession` (ADR-0066). When no account is signed in
/// the user sees `LoginView`; otherwise the mail UI. Account setup
/// uses the standards-first IMAP/SMTP backend per ADR-0028/ADR-0029.
@main
struct BrevApp: App {
    @UIApplicationDelegateAdaptor(BrevIOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = AppSession.makeDefault()
    @State private var showSettings = false
    @State private var appIconVariant = AppIconPreferences.load()
    @State private var networkMonitor = NetworkReachabilityMonitor()
    @State private var pendingComposePrefill: ComposePrefill?
    @State private var pendingNotificationRoute: NotificationMailRoute?
    @State private var sessionRestoreAttempted = false
    @State private var settingsMailboxContext = SettingsMailboxContext()
    @State private var isShowingAddAccountSheet = false
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
                    if showSettings {
                        SettingsView(
                            accountStore: session.accountStore,
                            activeTheme: $session.theme,
                            activeAppIcon: appIconBinding,
                            initialAccounts: session.visibleBackends.map(\.account),
                            initialCurrentAccountID: session.backend?.account.id,
                            mailboxContext: settingsMailboxContext,
                            backendProvider: { accountID in session.backends[accountID] },
                            onAddAccount: { isShowingAddAccountSheet = true },
                            onSignOut: { account in await session.signOut(account: account) },
                            onRemoveAccount: { account in await session.removeAccount(account) },
                            onAIProviderConfigurationChanged: {
                                await session.reloadConfiguredAIBackends()
                            },
                            onClose: { showSettings = false }
                        )
                        .brevTheme(session.theme)
                        .environment(\.openURL, browserOpenURLAction)
                    } else {
                        BrevMailRootView(
                            backends: session.visibleBackends,
                            aiBackends: session.aiBackends,
                            onSignOut: { await session.signOut() },
                            onChangeTheme: { newTheme in
                                session.theme = newTheme
                            },
                            onOpenSettings: {
                                showSettings = true
                            },
                            onSettingsMailboxContextChange: { settingsMailboxContext = $0 },
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
                        .environment(\.openURL, browserOpenURLAction)
                        .networkMonitor(networkMonitor)
                    }
                } else if AppSessionRestorePresentationPolicy.shouldShowRestoreProgress(
                    visibleBackendCount: session.visibleBackends.count,
                    isRestoringSession: session.isRestoringSession,
                    sessionRestoreAttempted: sessionRestoreAttempted
                ) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LoginView(session: session)
                }
            }
            .brevRootAppearance(session: session)
            .alert(
                String(localized: "Account error"),
                isPresented: $showRestoreErrorAlert
            ) {
                Button(String(localized: "Open Settings")) {
                    session.clearAccountRestoreErrors()
                    showSettings = true
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
                MailAccountSetupSheet(
                    session: session,
                    initialEmailAddress: session.authFailedIMAPAccountEmail ?? ""
                ) {
                    isShowingAddAccountSheet = false
                }
                .brevTheme(session.theme)
            }
            .task {
                await RetiredSecurityMaterialMigration.run()
                // Re-assert the persisted icon choice: after an update that
                // retires the previously active alternate icon, the system
                // silently falls back to the primary while the preference
                // still names the migrated variant. No-op when in sync.
                applyIOSAppIcon(appIconVariant)
                await session.restoreAllAccounts()
                sessionRestoreAttempted = true
                BrevIOSAppDelegate.currentBackends = session.visibleBackends
                if session.visibleBackends.isEmpty {
                    installUnavailableNotificationReplyHandler()
                }
                if !session.accountRestoreErrors.isEmpty,
                   !session.visibleBackends.isEmpty {
                    showRestoreErrorAlert = true
                }
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
            .onChange(of: session.visibleBackends.map(\.account.id)) { _, _ in
                BrevIOSAppDelegate.currentBackends = session.visibleBackends
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    // Foreground: cancel any pending background-refresh request and
                    // let the foreground MailFetchScheduler drive refreshes instead.
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BrevBackgroundRefreshCoordinator.taskIdentifier)
                case .background:
                    // Background: keep the delegate's backend list current, then
                    // schedule the next system-granted background refresh window.
                    BrevIOSAppDelegate.currentBackends = session.visibleBackends
                    BrevBackgroundRefreshCoordinator.scheduleNextRefresh()
                default:
                    break
                }
            }
        }
        .commands { MailCommands() }

        // iPad detached reader window — opened via openWindow(value:) in
        // MessageDetailView when the user taps "Open in New Window" on a
        // regular-width iPad scene (ADR-0033).
        WindowGroup(for: DetachedReaderWindowPayload.self) { $payload in
            if let payload {
                DetachedReaderWindowView(payload: payload, backends: session.visibleBackends)
                    .brevTheme(session.theme)
                    .environment(\.openURL, browserOpenURLAction)
            }
        }

        // iPad detached compose window — opened via openWindow(value:) in
        // BrevMailRootView when the user composes/replies/forwards on a
        // regular-width iPad scene (ADR-0033).
        WindowGroup(for: ComposeWindowPayload.self) { $payload in
            if let payload {
                DetachedComposeWindowView(
                    payload: payload,
                    backends: session.visibleBackends,
                    aiBackends: session.aiBackends,
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
                    }
                )
                .brevTheme(session.theme)
            }
        }
    }

    private var browserOpenURLAction: OpenURLAction {
        OpenURLAction { url in
            if url.scheme?.lowercased() == "mailto",
               let prefill = ComposePrefill(mailtoURL: url) {
                pendingComposePrefill = prefill
                return .handled
            }
            return browserLinkOpener.open(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if let prefill = SharedComposePayload.prefill(from: url) {
            pendingComposePrefill = prefill
            return
        }
        // Brev as the default mail app (iOS Settings > Default Mail App).
        if let prefill = ComposePrefill(mailtoURL: url) {
            pendingComposePrefill = prefill
            return
        }
        if let route = NotificationRoutingPolicy.route(from: url) {
            pendingNotificationRoute = route
        }
    }

    private var appIconBinding: Binding<AppIconVariant> {
        Binding(
            get: { appIconVariant },
            set: { variant in
                appIconVariant = variant
                AppIconPreferences.save(variant)
                applyIOSAppIcon(variant)
            }
        )
    }

    @MainActor
    private func installUnavailableNotificationReplyHandler() {
        let notificationCenter = BrevLocalNotificationCenter()
        appDelegate.notificationDelegate.onReply = { route, _ in
            await notificationCenter.postReplyFailureNotification(
                route: route,
                draftWasSaved: false
            )
        }
    }
}

final class BrevIOSAppDelegate: NSObject, UIApplicationDelegate {
    /// The most-recently-known set of connected backends.
    ///
    /// Updated by `BrevApp` when the scene transitions to `.background`
    /// so the `BGAppRefreshTask` handler can reach live backend instances
    /// without needing a direct reference to the SwiftUI `@State`.
    /// Nonisolated storage is safe here: writes always happen on the main
    /// actor (scene-phase callbacks), and reads happen inside a `Task`
    /// that the BGTask handler dispatches to `@MainActor`.
    @MainActor
    static var currentBackends: [any MailBackend] = []

    /// Installed as `UNUserNotificationCenter.current().delegate` at launch
    /// so notification actions delivered during startup are not silently
    /// dropped. `BrevMailRootView.setupNotifications()` detects this instance
    /// and wires its callbacks onto it rather than replacing it.
    let notificationDelegate = BrevNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        BrevPluginRegistry.shared.register(BrevExamplePlugin())
        BrevBackgroundRefreshCoordinator.register()
        return true
    }
}

/// Encapsulates the `BGAppRefreshTask` identifier, registration, and scheduling
/// for Brev's background mailbox refresh.
///
/// Registration must happen during `application(_:didFinishLaunchingWithOptions:)`,
/// before the system has a chance to launch the app for a background fetch. The
/// handler reaches the live backends through `BrevIOSAppDelegate.currentBackends`,
/// which `BrevApp` updates on every foreground→background scene-phase transition.
enum BrevBackgroundRefreshCoordinator {
    /// The task identifier registered in `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = "no.brev.app.mailRefresh"

    /// Registers the `BGAppRefreshTask` handler with the system.
    ///
    /// Must be called before the app finishes launching. Safe to call multiple
    /// times; subsequent calls after the first are no-ops because
    /// `BGTaskScheduler` ignores re-registration of the same identifier.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleRefresh(refreshTask)
        }
    }

    /// Submits a `BGAppRefreshTaskRequest` with a 15-minute earliest-begin date.
    ///
    /// Call this when the app transitions to the background so the system can
    /// grant a background execution window after the specified minimum delay.
    /// If scheduling fails (e.g. the identifier is not registered), the error
    /// is logged and silently swallowed — a missed background refresh is not a
    /// critical failure.
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger().warning(
                "BGTaskScheduler: failed to schedule mailRefresh: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: Private

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        // `setTaskCompleted` must be called exactly once; calling it twice
        // terminates the app. The work Task and the expirationHandler both want
        // to complete the task, and `performBackgroundRefresh` swallows
        // cancellation (so the work still finishes "successfully" after an
        // expiration), so funnel both through a one-shot guard.
        let completion = OneShotBGCompletion(task)
        // Reschedule for the next cycle before doing the work.
        scheduleNextRefresh()

        let work = Task {
            let backends = await MainActor.run {
                BrevIOSAppDelegate.currentBackends
            }
            guard !backends.isEmpty else {
                completion.complete(success: true)
                return
            }
            // Also flushes overdue "send later" drafts (`ScheduledSendManaging`),
            // since a suspended app's 30s scheduled-send poller does not run.
            await MailFetchScheduler.performBackgroundRefresh(backends: backends)
            completion.complete(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }
}

/// Ensures `BGTask.setTaskCompleted` is invoked at most once, whichever of the
/// work or the expiration handler reaches it first. A second call would raise
/// the system's "marked complete multiple times" exception and crash the app.
private final class OneShotBGCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private let task: BGTask

    init(_ task: BGTask) { self.task = task }

    func complete(success: Bool) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

@MainActor
private func applyIOSAppIcon(_ variant: AppIconVariant) {
    guard UIApplication.shared.supportsAlternateIcons else { return }
    guard UIApplication.shared.alternateIconName != variant.alternateIconName else { return }

    UIApplication.shared.setAlternateIconName(variant.alternateIconName) { error in
        if let error {
            let message = error.localizedDescription
            Logger().error(
                "Failed to set app icon to \(variant.rawValue, privacy: .public): \(message, privacy: .public)"
            )
        }
    }
}

extension AppSession {
    /// Default session for the iOS app.
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
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0.keyWindow ?? $0.windows.first }
            .first
        guard let window else {
            throw MailBackendError.backendSpecific(message: String(localized: "OAuth sign-in needs an active window."))
        }
        return window
    }
}

private var applicationSupportURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}
