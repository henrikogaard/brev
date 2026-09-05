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
import BrevAvatars
import BrevBackend
import BrevDesign
import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

private struct MailFolderActionTarget: Equatable {
    let folder: Folder
    let sourceID: MailSourceID?
}

private enum MailRootImportError: LocalizedError {
    case importingUnsupported
    case emptySource(String)

    var errorDescription: String? {
        switch self {
        case .importingUnsupported:
            String(localized: "This account does not support importing mail.", bundle: .module)
        case .emptySource(let name):
            String(localized: "No messages were found in \(name).", bundle: .module)
        }
    }
}

private enum MailFolderNamePrompt: Equatable {
    case createSubfolder(MailFolderActionTarget)
    case renameFolder(MailFolderActionTarget)
    case setLocalName(MailFolderActionTarget)

    var title: String {
        switch self {
        case .createSubfolder: return String(localized: "New Subfolder", bundle: .module)
        case .renameFolder: return String(localized: "Rename Folder", bundle: .module)
        case .setLocalName: return String(localized: "Set Local Name", bundle: .module)
        }
    }

    var actionTitle: String {
        switch self {
        case .createSubfolder: return String(localized: "Create", bundle: .module)
        case .renameFolder: return String(localized: "Rename", bundle: .module)
        case .setLocalName: return String(localized: "Save", bundle: .module)
        }
    }

    var textFieldTitle: String {
        switch self {
        case .createSubfolder: return String(localized: "Name", bundle: .module)
        case .renameFolder: return String(localized: "New name", bundle: .module)
        case .setLocalName: return String(localized: "Local name", bundle: .module)
        }
    }

    var message: String {
        switch self {
        case .createSubfolder(let target):
            return String(localized: "Parent folder: \(target.folder.name)", bundle: .module)
        case .renameFolder(let target):
            return String(localized: "Folder: \(target.folder.name)", bundle: .module)
        case .setLocalName(let target):
            return String(
                localized: "A local name only changes how \"\(target.folder.name)\" appears in Brev. The server folder is untouched.",
                bundle: .module
            )
        }
    }
}

private enum MailFolderConfirmation: Equatable {
    case deleteFolder(MailFolderActionTarget)
    case flushFolder(MailFolderActionTarget)

    var title: String {
        switch self {
        case .deleteFolder: return String(localized: "Delete Folder?", bundle: .module)
        case .flushFolder(let target):
            switch target.folder.role {
            case .trash:
                return String(localized: "folder.emptyTrash.title", defaultValue: "Empty Trash?", bundle: .module)
            case .spam:
                return String(localized: "folder.deleteJunk.title", defaultValue: "Delete Junk Mail?", bundle: .module)
            default:
                return String(localized: "folder.empty.title", defaultValue: "Empty Folder?", bundle: .module)
            }
        }
    }

    var actionTitle: String {
        switch self {
        case .deleteFolder: return String(localized: "Delete", bundle: .module)
        case .flushFolder(let target):
            switch target.folder.role {
            case .trash: return String(localized: "Empty Trash", bundle: .module)
            case .spam: return String(localized: "Delete Junk Mail", bundle: .module)
            default: return String(localized: "Empty Folder", bundle: .module)
            }
        }
    }

    var message: String {
        switch self {
        case .deleteFolder(let target):
            return String(localized: "Delete \"\(target.folder.name)\" and all subfolders?", bundle: .module)
        case .flushFolder(let target):
            switch target.folder.role {
            case .trash:
                return String(localized: "Permanently remove all messages from \"\(target.folder.name)\".", bundle: .module)
            case .spam:
                return String(localized: "Delete all junk messages from \"\(target.folder.name)\".", bundle: .module)
            default:
                return String(localized: "Delete all messages from \"\(target.folder.name)\".", bundle: .module)
            }
        }
    }
}

private struct MailExternalInputConsumerModifier: ViewModifier {
    let pendingComposePrefill: Binding<ComposePrefill?>?
    let pendingNotificationRoute: Binding<NotificationMailRoute?>?
    let onComposePrefill: (ComposePrefill?) -> Void
    let onNotificationRoute: (NotificationMailRoute?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: pendingComposePrefill?.wrappedValue) { _, prefill in
                onComposePrefill(prefill)
            }
            .onChange(of: pendingNotificationRoute?.wrappedValue) { _, route in
                onNotificationRoute(route)
            }
            .onAppear {
                onComposePrefill(pendingComposePrefill?.wrappedValue)
                onNotificationRoute(pendingNotificationRoute?.wrappedValue)
            }
    }
}

/// Top-level mail view. Apps mount this inside their scene.
///
/// Layout is platform-adaptive:
/// - macOS: three-column split or sidebar plus bottom reading pane.
/// - iOS: stacked `NavigationSplitView` with a compact-width reader presentation.
///
/// Theme is read from the environment — the parent scene is
/// responsible for `.brevTheme(_:)`. This view exposes the theme
/// picker as an `onChangeTheme` closure so the parent owns the
/// `@State` for the active theme.
#if os(macOS)
private final class ReaderPaneWidthSettleTaskBox {
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
#endif

public struct BrevMailRootView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.networkMonitor) private var monitor
    #if os(iOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var navigation = MailNavigationState()
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    /// Whether the macOS AI Sidebar column is open. Persisted so relaunching
    /// restores the sidebar exactly as the user left it, in step with the
    /// restored window frame (see `brevRestoresWindowFrame`).
    @AppStorage("mail.aiSidebar.presented")
    private var isMailContextColumnPresented = false
    /// User's explicit open/close of the toolbar search control. The rendered
    /// state also accounts for an active query, via `isSearchFieldExpanded`.
    @State private var isSearchFieldToggledOpen = false
    #if os(macOS)
    /// Measured width of the reader column, which sizes the toolbar's search
    /// field. Seeded from the last session's measurement so the first toolbar
    /// build already matches the restored window — a wrong seed makes the
    /// cluster visibly re-form item by item at every launch once the real
    /// geometry arrives.
    @AppStorage("mail.reader.lastPaneWidth")
    private var lastKnownReaderPaneWidth = Double(
        MailPaneColumnWidthPolicy.readerMinimumWidth(platform: .macOS) ?? 420
    )
    @State private var measuredReaderPaneWidth: CGFloat?
    @State private var readerPaneWidthSettleTaskBox = ReaderPaneWidthSettleTaskBox()
    private var readerPaneWidth: CGFloat {
        measuredReaderPaneWidth ?? CGFloat(lastKnownReaderPaneWidth)
    }

    /// Hands a measured reader width to the toolbar only once it stops
    /// moving. See `MailRootDetailToolbarPolicy.readerWidthSettleDuration`
    /// for why the intermediate widths have to be dropped rather than
    /// merely de-animated.
    private func settleReaderPaneWidth(_ width: CGFloat) {
        guard width != measuredReaderPaneWidth else {
            // A drag can cross the condensation threshold and return to the
            // already-settled width before the delay expires. Cancel the stale
            // excursion instead of committing it after the divider is released.
            readerPaneWidthSettleTaskBox.task?.cancel()
            readerPaneWidthSettleTaskBox.task = nil
            return
        }
        readerPaneWidthSettleTaskBox.task?.cancel()
        readerPaneWidthSettleTaskBox.task = Task { @MainActor in
            try? await Task.sleep(for: MailRootDetailToolbarPolicy.readerWidthSettleDuration)
            guard !Task.isCancelled else { return }
            // Non-animated: this width drives the toolbar's condensation,
            // and an animated write makes NSToolbar re-form the cluster
            // visibly.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                measuredReaderPaneWidth = width
                lastKnownReaderPaneWidth = Double(width)
            }
            readerPaneWidthSettleTaskBox.task = nil
        }
    }
    #else
    /// iOS never condenses the reader toolbar by width; the shared call
    /// sites only need the symbol, and the policy returns early off macOS.
    private let readerPaneWidth: CGFloat? = nil
    #endif
    @State private var compactReaderHeader: MessageHeader?
    @State private var sourceSections: [MailSourceSection] = []
    @State private var folders: [Folder] = []
    /// Provider-native search syntax for the currently selected source, when
    /// that source exposes a help contract through `MailBackend`.
    @State private var selectedSearchSyntaxDescription: ServerSearchSyntaxDescription?
    /// Guards the once-per-session retention enforcement pass so it runs
    /// after the first workspace load rather than on every folder reload.
    @State private var didRunInitialRetentionSweep = false
    /// Startup phase controller: cold → cachedUsable → interactive → background.
    @State private var startupPhase = MailStartupPhaseController()
    @State private var deferredStartupAccountIDs: Set<ObjectIdentifier> = []
    /// Determinate progress of the visible account's multi-folder refresh,
    /// or `nil` when no sync is in flight. Drives the download indicator.
    @State private var syncProgress: MailSyncProgress?
    @State private var importSyncHealth: AccountSyncHealth?
    @State private var importSyncHealthPollingTask: Task<Void, Never>?
    @State private var folderLoadError: FolderLoadError?
    @State private var mailboxes: [Mailbox] = []
    @State private var activeMailboxID: String?
    @State private var rootStatus: MailRootStatus?
    @State private var ephemeralToast: MailRootEphemeralToast?
    @State private var ephemeralToastDismissTask: Task<Void, Never>?
    @State private var mailboxSwitchRetryID: String?
    @State private var shouldRetryMailboxLoad = false
    @State private var shouldRetrySourceSections = false
    @State private var shouldRetryFolderLoad = false
    @State private var nextFolderLoadRequestID = 0
    @State private var activeFolderLoadRequest: MailRootFolderLoadRequest?
    @State private var nextMailboxLoadRequestID = 0
    @State private var activeMailboxLoadRequest: MailRootMailboxLoadRequest?
    @State private var nextCommandMutationRequestID = 0
    @State private var activeCommandMutationRequest: MailRootCommandMutationRequest?
    /// Safety-net timer that recovers the UI if a command mutation never reports
    /// back. Without it, a mutation whose backend call hangs leaves
    /// `activeCommandMutationRequest` non-nil forever, which keeps the message
    /// list work-blocked and frozen until relaunch (#192).
    @State private var commandMutationWatchdog: Task<Void, Never>?
    @State private var nextRefreshRequestID = 0
    @State private var activeRefreshRequest: MailRootRefreshRequest?
    @State private var nextMailboxSwitchRequestID = 0
    @State private var activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?
    @State private var nextComposeCompletionRequestID = 0
    @State private var activeComposeCompletionRequest: MailRootComposeCompletionRequest?
    @State private var pendingBackendEventRefresh = MailRootBackendEventRefreshBatch()
    @State private var backendEventRefreshTask: Task<Void, Never>?
    @State private var pendingBackgroundAccountIDs: Set<BrevAccount.ID> = []
    @State private var backgroundAccountRefreshTask: Task<Void, Never>?
    @State private var nextBackgroundAccountRefreshRequestID = 0
    @State private var activeBackgroundAccountRefreshRequestID: Int?
    @State private var sourceSectionsRevision = 0
    @State private var sourceLoadOwnership = MailListLoadOwnership()
    @State private var isLoadingSources = false
    @State private var sourceLoadWorkTask: Task<Void, Never>?
    @State private var sourceLoadTimeoutTask: Task<Void, Never>?
    /// Monotonic heartbeat: bumped whenever outstanding root work makes progress
    /// (a backend event arrives, an operation hits a milestone). The stale-work
    /// watchdog watches this so a slow-but-progressing operation isn't recovered.
    @State private var rootWorkProgressTick = 0
    @State private var shouldRefreshAfterSheetDismissal = false
    @State private var undoQueue = UndoQueue()
    @State private var showOfflineBanner = false
    @State private var outboxPendingCount = 0
    @State private var folderNamePrompt: MailFolderNamePrompt?
    @State private var folderConfirmation: MailFolderConfirmation?
    @State private var folderNameDraft = ""
    @State private var notificationCenter = BrevLocalNotificationCenter()
    @State private var badgeUpdater = UnreadBadgeUpdater()
    @State private var notificationDelegate = BrevNotificationDelegate()
    @State private var isInitialMailboxSelectionPresented = false
    @AppStorage("mail.profiles.custom.v1") private var customProfileStorage = ""
    @AppStorage("mail.profiles.activeID.v1") private var activeProfileID = MailProfile.allMailboxesID
    @AppStorage(MailboxSourcePreferencesStorage.storageKey) private var mailboxSourcePreferencesData = Data()
    @AppStorage(FolderVisibilityPreferencesStorage.storageKey) private var folderVisibilityPreferencesData = Data()
    @AppStorage(FolderAliasPreferencesStorage.storageKey) private var folderAliasPreferencesData = Data()
    @AppStorage(LocalMessageWorkflowStateStorage.storageKey) private var localMessageWorkflowStateData = Data()
    @AppStorage(SmartMailboxSettings.storageKey) private var smartMailboxData = Data()
    @AppStorage(VIPSenderSettings.Key.senders) private var vipSenderData = Data()
    /// Decoded once per persisted-data change. These values are read by many
    /// sidebar/list subtrees during one SwiftUI update; decoding JSON in each
    /// computed property multiplied the work with the number of body passes.
    @State private var cachedMailboxSourcePreferences = MailboxSourcePreferencesStorage.load()
    @State private var cachedFolderVisibilityPreferences = FolderVisibilityPreferencesStorage.load()
    @State private var cachedFolderAliasPreferences = FolderAliasPreferencesStorage.load()
    @State private var cachedLocalMessageWorkflowState = LocalMessageWorkflowStateStorage.load()
    @AppStorage(MailboxViewPreferenceKey.readingPanePlacement)
    private var readingPanePlacementRaw = MailboxReadingPanePlacement.side.rawValue
    // Same key the list views read, so the toolbar's Sort By section and the
    // list agree without threading a binding down the column.
    @AppStorage(MailboxViewPreferenceKey.sortOrder)
    private var mailboxSortOrderRaw = MailboxSortOrder.newestFirst.rawValue
    @AppStorage("folders.showStarred") private var showStarredFolders = true
    @AppStorage("folders.showSnoozed") private var showSnoozedFolders = true
    @AppStorage("folders.showScheduled") private var showScheduledFolders = true
    @AppStorage("folders.showAllMail") private var showAllMailFolders = false
    @AppStorage("folders.showSpam") private var showSpamFolders = true
    @AppStorage("folders.showTrash") private var showTrashFolders = true
    @AppStorage("folders.showArchive") private var showArchiveFolders = true
    @AppStorage(FetchScheduleSettings.Key.interval) private var fetchIntervalRaw =
        FetchInterval.manual.rawValue

    private let backend: any MailBackend
    private let backends: [any MailBackend]
    private let aiBackend: (any AIBackend)?
    private let aiBackends: [BrevAccount.ID: any AIBackend]
    private let settingsStore: SettingsPersistenceStore
    private let onSignOut: (() async -> Void)?
    private let onChangeTheme: (BrevTheme) -> Void
    private let onOpenSettings: (() -> Void)?
    private let onSettingsMailboxContextChange: ((SettingsMailboxContext) -> Void)?
    private let signatureContextProvider: ((BrevAccount) -> ComposeSignatureContext)?
    private let composeSecurityDefaultsProvider: ((BrevAccount) -> ComposeSecurityDefaultState)?
    private let trustedSigningIdentityCountProvider: ((BrevAccount) -> Int)?
    private let trustedEncryptionIdentityCountProvider: ((BrevAccount) -> Int)?
    private let pendingComposePrefill: Binding<ComposePrefill?>?
    private let pendingNotificationRoute: Binding<NotificationMailRoute?>?
    private let isExternalModalPresented: Bool
    private let initialMailboxSelectionAccountID: BrevAccount.ID?
    private let onFinishInitialMailboxSelection: ((BrevAccount.ID) -> Void)?

    private let unreadCountReconciler = UnreadCountReconciler()

    public init(
        backend: any MailBackend,
        aiBackend: (any AIBackend)? = nil,
        settingsStore: SettingsPersistenceStore = .standard,
        onSignOut: (() async -> Void)? = nil,
        onChangeTheme: @escaping (BrevTheme) -> Void = { _ in },
        onOpenSettings: (() -> Void)? = nil,
        onSettingsMailboxContextChange: ((SettingsMailboxContext) -> Void)? = nil,
        signatureContextProvider: ((BrevAccount) -> ComposeSignatureContext)? = nil,
        composeSecurityDefaultsProvider: ((BrevAccount) -> ComposeSecurityDefaultState)? = nil,
        trustedSigningIdentityCountProvider: ((BrevAccount) -> Int)? = nil,
        trustedEncryptionIdentityCountProvider: ((BrevAccount) -> Int)? = nil,
        pendingComposePrefill: Binding<ComposePrefill?>? = nil,
        pendingNotificationRoute: Binding<NotificationMailRoute?>? = nil,
        isExternalModalPresented: Bool = false,
        initialMailboxSelectionAccountID: BrevAccount.ID? = nil,
        onFinishInitialMailboxSelection: ((BrevAccount.ID) -> Void)? = nil
    ) {
        self.init(
            backends: [backend],
            aiBackend: aiBackend,
            settingsStore: settingsStore,
            onSignOut: onSignOut,
            onChangeTheme: onChangeTheme,
            onOpenSettings: onOpenSettings,
            onSettingsMailboxContextChange: onSettingsMailboxContextChange,
            signatureContextProvider: signatureContextProvider,
            composeSecurityDefaultsProvider: composeSecurityDefaultsProvider,
            trustedSigningIdentityCountProvider: trustedSigningIdentityCountProvider,
            trustedEncryptionIdentityCountProvider: trustedEncryptionIdentityCountProvider,
            pendingComposePrefill: pendingComposePrefill,
            pendingNotificationRoute: pendingNotificationRoute,
            isExternalModalPresented: isExternalModalPresented,
            initialMailboxSelectionAccountID: initialMailboxSelectionAccountID,
            onFinishInitialMailboxSelection: onFinishInitialMailboxSelection
        )
    }

    public init(
        backends: [any MailBackend],
        aiBackend: (any AIBackend)? = nil,
        aiBackends: [BrevAccount.ID: any AIBackend] = [:],
        settingsStore: SettingsPersistenceStore = .standard,
        onSignOut: (() async -> Void)? = nil,
        onChangeTheme: @escaping (BrevTheme) -> Void = { _ in },
        onOpenSettings: (() -> Void)? = nil,
        onSettingsMailboxContextChange: ((SettingsMailboxContext) -> Void)? = nil,
        signatureContextProvider: ((BrevAccount) -> ComposeSignatureContext)? = nil,
        composeSecurityDefaultsProvider: ((BrevAccount) -> ComposeSecurityDefaultState)? = nil,
        trustedSigningIdentityCountProvider: ((BrevAccount) -> Int)? = nil,
        trustedEncryptionIdentityCountProvider: ((BrevAccount) -> Int)? = nil,
        pendingComposePrefill: Binding<ComposePrefill?>? = nil,
        pendingNotificationRoute: Binding<NotificationMailRoute?>? = nil,
        isExternalModalPresented: Bool = false,
        initialMailboxSelectionAccountID: BrevAccount.ID? = nil,
        onFinishInitialMailboxSelection: ((BrevAccount.ID) -> Void)? = nil
    ) {
        let firstBackend = backends[0]
        backend = firstBackend
        self.backends = backends
        self.aiBackend = aiBackend
        if aiBackends.isEmpty, let aiBackend {
            self.aiBackends = [firstBackend.account.id: aiBackend]
        } else {
            self.aiBackends = aiBackends
        }
        self.settingsStore = settingsStore
        self.onSignOut = onSignOut
        self.onChangeTheme = onChangeTheme
        self.onOpenSettings = onOpenSettings
        self.onSettingsMailboxContextChange = onSettingsMailboxContextChange
        self.signatureContextProvider = signatureContextProvider
        self.composeSecurityDefaultsProvider = composeSecurityDefaultsProvider
        self.trustedSigningIdentityCountProvider = trustedSigningIdentityCountProvider
        self.trustedEncryptionIdentityCountProvider = trustedEncryptionIdentityCountProvider
        self.pendingComposePrefill = pendingComposePrefill
        self.pendingNotificationRoute = pendingNotificationRoute
        self.isExternalModalPresented = isExternalModalPresented
        self.initialMailboxSelectionAccountID = initialMailboxSelectionAccountID
        self.onFinishInitialMailboxSelection = onFinishInitialMailboxSelection
    }

    public var body: some View {
        #if os(iOS)
        MailCompactReaderStack(
            isReaderPresented: compactReaderHeader != nil,
            background: { mailRootContent },
            reader: compactReaderHeader.map { header in
                AnyView(
                    NavigationStack {
                        compactReadingPaneDetailPane(fallbackHeader: header)
                    }
                )
            }
        )
        #else
        mailRootContent
        #endif
    }

    private var mailRootContent: some View {
        mailRootCommandContextContent
    }

    /// The status rail with its transitions animated in isolation. These
    /// animations must stay scoped to the rail: attached to the whole
    /// workspace they animate every coincident change in the window, which
    /// showed up as a full-window cross-fade at launch (network monitor
    /// coming online while the first folder load applies) and again at quit.
    private var animatedTopChromeStatusRail: some View {
        topChromeStatusRail
            .animation(.default, value: importSyncHealth)
            .animation(.default, value: syncProgress)
            .animation(.default, value: rootStatus)
            .animation(.default, value: monitor.isOnline)
    }

    @ViewBuilder
    private var topChromeStatusRail: some View {
        let chrome = MailRootChromeStatusPolicy.resolve(
            rootStatus: rootStatus,
            isOnline: monitor.isOnline,
            importHealth: importSyncHealth,
            folderSyncProgress: syncProgress
        )
        switch chrome {
        case .rootStatus(let status):
            BrevInlineStatus(
                message: status.message,
                tone: status.tone.inlineStatusTone,
                actionTitle: status.actionTitle,
                onAction: {
                    Task { await retryRootStatusAction() }
                },
                onDismiss: {
                    clearRootStatus()
                }
            )
        case .offline:
            BrevInlineStatus(
                message: String(localized: "You're offline. Changes are queued.", bundle: .module),
                tone: .warning,
                actionTitle: String(localized: "Retry", bundle: .module),
                onAction: {
                    Task { await refreshVisibleMail() }
                },
                onDismiss: nil
            )
        case .importProgress(let presentation):
            ImportProgressBanner(
                presentation: presentation,
                onRetry: presentation.showsRetryAction
                    ? { Task { await retryImportSync() } }
                    : nil
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }

    private var mailRootCacheContent: some View {
        mailRootStatusLayout
            .task(id: visibleSelectedSourceID) {
                await observeImportSyncHealth()
                await loadSelectedSearchSyntax()
            }
            .onDisappear {
                stopImportSyncHealthPolling()
                sourceLoadTimeoutTask?.cancel()
                sourceLoadWorkTask?.cancel()
                backendEventRefreshTask?.cancel()
                backendEventRefreshTask = nil
                backgroundAccountRefreshTask?.cancel()
                backgroundAccountRefreshTask = nil
                activeBackgroundAccountRefreshRequestID = nil
                pendingBackgroundAccountIDs.removeAll()
            }
            .onChange(of: mailboxSourcePreferencesData) { _, data in
                cachedMailboxSourcePreferences = MailboxSourcePreferencesStorage.decode(data) ?? .defaults
            }
            .onChange(of: folderVisibilityPreferencesData) { _, data in
                cachedFolderVisibilityPreferences = FolderVisibilityPreferencesStorage.decode(data) ?? .defaults
            }
            .onChange(of: folderAliasPreferencesData) { _, data in
                cachedFolderAliasPreferences = FolderAliasPreferencesStorage.decode(data) ?? .defaults
            }
            .onChange(of: localMessageWorkflowStateData) { _, data in
                cachedLocalMessageWorkflowState = LocalMessageWorkflowStateStorage.decode(data) ?? .defaults
            }
    }

    private var mailRootLoadingContent: some View {
        mailRootCacheContent
            .task { monitor.start() }
            .onChange(of: backendSessionIDs) { previous, _ in handleBackendSessionChange(previousIDs: previous) }
            .task(id: backendSessionIDs) { await loadWorkspace(supersedingActiveLoads: true) }
            .task(id: fetchIntervalRaw) { await runPeriodicFetchScheduler() }
            .task(id: rootWorkBlockSnapshot) {
                await recoverFromStaleRootWorkBlockIfNeeded(snapshot: rootWorkBlockSnapshot)
            }
            // Live IMAP change streams start only after first usable content.
            .task(id: backendTaskID) {
                guard startupPhase.allows(.interactive) else { return }
                await startLiveChangeSubscriptionIfNeeded()
            }
            // Non-critical startup work waits for background phase.
            .task(id: backendTaskID) {
                guard startupPhase.allows(.background) else { return }
                await bootstrapAvatarPreferences()
                await setupNotifications()
                await refreshOutboxCount()
                await startDeferredBackendStartupWorkIfNeeded()
                await observeMailboxSyncSettingsChanges()
            }
    }

    private func handleBackendSessionChange(previousIDs: [ObjectIdentifier]) {
        if !Set(previousIDs).isSubset(of: Set(backendSessionIDs)) { undoQueue.discardAll() }
        sourceSectionsRevision += 1
        invalidateSourceLoading()
        backgroundAccountRefreshTask?.cancel()
        backgroundAccountRefreshTask = nil
        activeBackgroundAccountRefreshRequestID = nil
        pendingBackgroundAccountIDs.removeAll()
        let available = Set(sourceSections.filter { backendAccountIDs.contains($0.account.id) }.map(\.id))
        if let source = navigation.selectedSourceID, !backendAccountIDs.contains(source.accountID) {
            navigation.presentedSheet = nil
        }
        navigation.reconcileReaderSources(available)
        sourceSections.removeAll { !backendAccountIDs.contains($0.account.id) }
        if let section = selectedSourceSection {
            applySelectedSourceSection(section)
        } else {
            folders = []
            mailboxes = []
            activeMailboxID = nil
        }
    }

    private var mailRootObservedContent: some View {
        mailRootLoadingContent
            .onChange(of: sourceSectionsRevision, initial: true) { _, _ in
                onSettingsMailboxContextChange?(settingsMailboxContext)
            }
            .modifier(externalInputConsumer)
            .onChange(of: navigation.composePresentationID) {
                handleComposePresentationChange()
            }
            .onChange(of: folderVisibility) {
                handleFolderVisibilityChange()
            }
            .onChange(of: navigation.presentedSheet) { oldSheet, newSheet in
                handlePresentedSheetChange(oldSheet: oldSheet, newSheet: newSheet)
            }
            .onReceive(NotificationCenter.default.publisher(for: .brevFollowUpDidChange)) { _ in
                Task {
                    await notificationCenter.cancelInactiveFollowUpReminders(
                        settings: settingsStore.followUpSettings()
                    )
                }
            }
            .onChange(of: navigation.selectedSourceID) {
                handleSelectedSourceChange()
                onSettingsMailboxContextChange?(settingsMailboxContext)
            }
            .onChange(of: monitor.isOnline) { wasOnline, isOnline in
                handleNetworkStatusChange(wasOnline: wasOnline, isOnline: isOnline)
            }
            .onChange(of: scenePhase) { previousPhase, newPhase in
                handleScenePhaseChange(previousPhase: previousPhase, newPhase: newPhase)
            }
            .onChange(of: navigation.selectedFolderID) { _, selectedFolderID in
                #if os(iOS)
                if selectedFolderID != nil {
                    openSelectedMessagesOnCompact()
                } else {
                    preferredCompactColumn = .sidebar
                    splitViewVisibility = .all
                }
                #endif
            }
    }

    private var mailRootPresentationContent: some View {
        mailRootObservedContent
            .accessibilityHidden(isMailBackgroundAccessibilityHidden)
            .modifier(
                MailAuxiliaryPresentationModifier(sheet: sheetBinding) { sheet, close in
                    AnyView(sheetContent(for: sheet, onClose: close))
                }
            )
            .modifier(
                InitialMailboxSelectionPresentationModifier(
                    isPresented: $isInitialMailboxSelectionPresented,
                    sourceSections: initialMailboxSelectionSourceSections,
                    initialPreferences: mailboxSourcePreferences,
                    theme: theme,
                    onSave: saveInitialMailboxSelection
                )
            )
            .alert(folderNamePromptTitle, isPresented: isFolderNamePromptPresented) {
                TextField(folderNameTextFieldTitle, text: $folderNameDraft)
                Button(folderNamePromptActionTitle) {
                    guard let prompt = folderNamePrompt else { return }
                    let name = folderNameDraft
                    folderNamePrompt = nil
                    folderNameDraft = ""
                    Task {
                        await runFolderNamePrompt(prompt, name: name)
                    }
                }
                .disabled(folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                    folderNamePrompt = nil
                    folderNameDraft = ""
                }
            } message: {
                Text(folderNamePromptMessage)
            }
            .alert(folderConfirmationTitle, isPresented: isFolderConfirmationPresented) {
                Button(folderConfirmationActionTitle, role: .destructive) {
                    guard let confirmation = folderConfirmation else { return }
                    folderConfirmation = nil
                    Task {
                        await runFolderConfirmation(confirmation)
                    }
                }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                    folderConfirmation = nil
                }
            } message: {
                Text(folderConfirmationMessage)
            }
    }

    @ViewBuilder
    private var mailRootStatusLayout: some View {
        #if os(macOS)
        // NavigationSplitView does not consistently propagate a top safe-area
        // inset to every desktop column. Stack the rail so it reserves space.
        VStack(spacing: 0) {
            animatedTopChromeStatusRail
            mailWorkspaceChrome
        }
        #else
        mailWorkspaceChrome
            .safeAreaInset(edge: .top, spacing: 0) {
                animatedTopChromeStatusRail
            }
        #endif
    }

    private var mailRootCommandContextContent: some View {
        mailRootPresentationContent
            .focusedSceneValue(\.mailNavigation, navigation)
            .focusedSceneValue(\.mailBackend, selectedBackend)
            .focusedSceneValue(\.mailFolders, folders)
            .focusedSceneValue(\.refreshSelectedMailFolder, mailRefreshAction)
            .focusedSceneValue(\.mailMessageCommandActions, mailMessageCommandActions)
            .focusedSceneValue(\.mailComposePresentationActions, composePresentationActions)
            .focusedSceneValue(\.mailImportAction, mailImportAction)
            .focusedSceneValue(\.mailContextColumnAction, mailContextCommandAction)
            .environment(\.undoQueue, undoQueue)
        #if os(macOS)
            .focusedSceneValue(\.mailUndoActions, MailUndoCommandActions(
                canUndo: { undoQueue.canUndo && !isCommandMutationBlocked && activeCommandMutationRequest == nil },
                onUndo: { performUndo() }
            ))
        #endif
            .modifier(DetachedMessageCommandReceiver(handle: handleDetachedMessageCommand))
            .overlay(alignment: .bottom) {
                undoToastOverlay
            }
    }

    private func performUndo(retry: Bool = false) {
        guard !isCommandMutationBlocked, activeCommandMutationRequest == nil else { return }
        let task = retry ? undoQueue.retry() : undoQueue.undo()
        guard let task else { return }
        Task {
            if await task.value {
                navigation.requestReload()
                await loadFolders()
            }
        }
    }

    @ViewBuilder
    private var undoToastOverlay: some View {
        if undoQueue.isUndoing || undoQueue.errorMessage != nil || undoQueue.current != nil {
            MailUndoToast(
                queue: undoQueue,
                isBlocked: isCommandMutationBlocked || activeCommandMutationRequest != nil || undoQueue.isMutationInFlight,
                onUndo: { performUndo() },
                onRetry: { performUndo(retry: true) }
            )
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.bottom, BrevSpacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let ephemeralToast {
            BrevToast(
                message: ephemeralToast.message,
                tone: ephemeralToast.tone.inlineStatusTone,
                onDismiss: { clearEphemeralToast() }
            )
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.bottom, BrevSpacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: ephemeralToast.id)
        }
    }

    @ViewBuilder
    private var mailWorkspaceChrome: some View {
        #if os(macOS)
        mailContextWorkspace
            .background {
                nativeToolbarBridge
            }
            .modifier(MailContextInspectorModifier(
                isPresented: $isMailContextColumnPresented,
                platform: mailPanePlatform,
                selectedHeader: navigation.selectedHeader,
                sourceID: navigation.selectedSourceID,
                backend: selectedBackend,
                aiBackend: selectedAIBackend,
                actionFolders: mailboxActionFolders(for: navigation.selectedSourceID),
                focusedFolder: selectedFolder,
                actionSourceScope: mailboxActionSourceScope(for: navigation.selectedSourceID),
                executeAction: { plan in
                    try await executeMailboxAction(plan: plan)
                },
                folderNameByID: mailContextFolderNameByID,
                composeActions: composePresentationActions,
                onOpenMessage: openMailContextMessage,
                onShowAllFromSender: showAllMailFromSender,
                onOpenSettings: onOpenSettings
            ))
        #else
        mailSplitView
            .background {
                nativeToolbarBridge
            }
            .sheet(isPresented: $isMailContextSheetPresented) {
                // iOS has no trailing column to host the Mail Context; the
                // mailbox chat half of the shared column presents as a sheet
                // instead, with the same scope/search wiring the macOS
                // inspector uses.
                MailboxChatPanel(
                    scope: MailContextColumnScopePolicy.chatScope(
                        selectedHeader: navigation.selectedHeader,
                        focusedFolder: selectedFolder
                    ),
                    sourceID: navigation.selectedSourceID,
                    aiBackend: selectedAIBackend,
                    actionFolders: mailboxActionFolders(for: navigation.selectedSourceID),
                    focusedFolder: selectedFolder,
                    actionSourceScope: mailboxActionSourceScope(for: navigation.selectedSourceID),
                    executeAction: { plan in
                        try await executeMailboxAction(plan: plan)
                    },
                    search: { query, sourceID in
                        if let sourceID {
                            return try await selectedBackend.search(query, sourceID: sourceID)
                        }
                        return try await selectedBackend.search(query)
                    },
                    onOpenCitation: { citation in
                        openMailContextMessage(citation.recentItem)
                    },
                    onOpenSettings: onOpenSettings
                )
                .brevMailPaneSurface(.sidebar)
                .brevTheme(theme)
            }
        #endif
    }

    #if os(iOS)
    /// iOS presents the Mail Context column as a sheet (no trailing column).
    @State private var isMailContextSheetPresented = false
    #endif

    private var mailContextCommandAction: MailContextColumnAction {
        MailContextColumnAction(isPresented: isMailContextColumnPresented) {
            isMailContextColumnPresented.toggle()
        }
    }

    private var mailRefreshAction: MailRefreshAction {
        MailRefreshAction(
            isRefreshing: activeRefreshRequest != nil,
            isBlocked: isRefreshBlocked || visibleRefreshTarget == nil
        ) {
            await refreshVisibleMail()
        }
    }

    private var mailMessageCommandActions: MailMessageCommandActions {
        MailMessageCommandActions(
            isPerformingMutation: activeCommandMutationRequest != nil,
            isBlocked: isCommandMutationBlocked,
            toggleRead: { header in
                await toggleRead(for: header)
            },
            toggleStar: { header in
                await toggleStar(for: header)
            },
            archive: { header in
                await archive(header: header)
            },
            move: { header, destination in
                await move(header: header, to: destination)
            },
            setJunk: { header, isJunk in
                await setJunk(isJunk, for: header)
            },
            delete: { header in
                await trash(header: header)
            }
        )
    }

    private var mailImportAction: MailImportAction {
        MailImportAction(isBlocked: isCommandMutationBlocked) { request in
            Task {
                await importMail(request)
            }
        }
    }

    private func handleComposePresentationChange() {
        guard navigation.presentedSheet == .compose else { return }
        startComposeCompletionRequest(composePresentationID: navigation.composePresentationID)
    }

    private func handleFolderVisibilityChange() {
        syncSelectedFolderForCurrentSource()
    }

    private func handlePresentedSheetChange(
        oldSheet: MailNavigationState.Sheet?,
        newSheet: MailNavigationState.Sheet?
    ) {
        if newSheet != .compose {
            activeComposeCompletionRequest = nil
        }
        if newSheet == nil {
            Task { await refreshAfterSheetDismissalIfNeeded() }
            Task { await refreshOutboxCount() }
        }
    }

    private func handleSelectedSourceChange() {
        if activeFolderLoadRequest?.sourceID != navigation.selectedSourceID { activeFolderLoadRequest = nil }
        if activeMailboxLoadRequest?.sourceID != navigation.selectedSourceID { activeMailboxLoadRequest = nil }
        if let request = activeCommandMutationRequest, request.sourceID != navigation.selectedSourceID {
            finishCommandMutation(request)
        }
        // Drop any in-flight sync indicator from the previous account so it
        // doesn't linger over the newly selected one.
        syncProgress = nil
        selectedSearchSyntaxDescription = nil
        syncSelectedSourceState()
    }

    private func handleNetworkStatusChange(wasOnline: Bool, isOnline: Bool) {
        if wasOnline == false, isOnline == true {
            Task { await refreshVisibleMail() }
            Task { await refreshOutboxCount() }
        }
    }

    private func handleScenePhaseChange(previousPhase: ScenePhase, newPhase: ScenePhase) {
        guard MailRootForegroundRefreshPolicy.shouldRefresh(
            wasActive: previousPhase == .active,
            isActive: newPhase == .active
        ) else {
            return
        }
        Task { await refreshVisibleMail() }
    }

    @ViewBuilder
    private var mailSplitView: some View {
        switch readingPanePresentation {
        case .splitDetailColumn:
            NavigationSplitView(
                columnVisibility: $splitViewVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                sidebarPane
            } content: {
                messageListPane
            } detail: {
                // The detail column's band lives here, not in the pane: in the
                // bottom-stack presentation the same pane is the lower half of
                // the `VSplitView`, mid-window, where no band belongs.
                readingPaneDetailPane
                    .brevMailPaneScrollEdgeBlur()
            }
        case .bottomStack:
            NavigationSplitView(
                columnVisibility: $splitViewVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                sidebarPane
            } detail: {
                bottomReadingPane
            }
        }
    }

    private var readingPanePresentation: MailRootReadingPanePresentation {
        MailRootReadingPanePresentationPolicy.presentation(for: readingPanePlacementRaw)
    }

    private var mailContextWorkspace: some View {
        // The scroll edge blur is mounted per pane (see
        // `brevMailPaneScrollEdgeBlur`), not as one overlay here: a full-width
        // band backdrop-sampled the split divider too and blurred away its top.
        mailSplitView
            .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
    }

    private var sidebarPane: some View {
        FolderSidebar(
            navigation: navigation,
            folders: sidebarFolders,
            loadError: folderLoadError,
            sourceSections: sidebarSourceSections,
            profiles: profiles,
            activeProfileID: normalizedActiveProfileID,
            mailboxes: mailboxes,
            activeMailboxID: activeMailboxID,
            isSwitchingMailbox: activeMailboxSwitchRequest != nil,
            isMailboxSwitchBlocked: isMailboxSwitchBlocked,
            capabilitiesForSource: { sourceID in
                backend(for: sourceID).capabilities
            },
            isFolderActionBlocked: isCommandMutationBlocked,
            folderAliasPreferences: folderAliasPreferences,
            onSelectProfile: { profileID in
                selectMailProfile(profileID)
            },
            onManageProfiles: {
                navigation.presentedSheet = .profiles
            },
            onSwitchMailbox: { id in
                Task { await switchMailbox(to: id) }
            },
            onDropMessages: { messageIDs, folder in
                let sourceFolder = selectedFolder
                Task {
                    await handleDroppedMessages(
                        messageIDs: messageIDs,
                        sourceFolder: sourceFolder,
                        to: folder
                    )
                }
            },
            onDropSourceMessages: { messageIDs, sourceID, folder in
                let sourceFolder = selectedFolder
                Task {
                    await handleDroppedMessages(
                        messageIDs: messageIDs,
                        sourceID: sourceID,
                        sourceFolder: sourceFolder,
                        to: folder
                    )
                }
            },
            onCreateSubfolder: { folder, sourceID in
                presentCreateSubfolderPrompt(for: folder, sourceID: sourceID)
            },
            onMarkFolderAsRead: { folder, sourceID in
                Task {
                    await markFolderAsRead(folder, sourceID: sourceID)
                }
            },
            onSetFolderLocalName: { folder, sourceID in
                presentSetFolderLocalNamePrompt(for: folder, sourceID: sourceID)
            },
            onClearFolderLocalName: { folder, sourceID in
                clearFolderLocalName(folder, sourceID: sourceID)
            },
            onRenameFolder: { folder, sourceID in
                presentRenameFolderPrompt(for: folder, sourceID: sourceID)
            },
            onDeleteFolder: { folder, sourceID in
                presentDeleteFolderConfirmation(for: folder, sourceID: sourceID)
            },
            onFlushFolder: { folder, sourceID in
                presentFlushFolderConfirmation(for: folder, sourceID: sourceID)
            },
            onHideFolder: { folder, sourceID in
                hideFolderFromSidebar(folder, sourceID: sourceID)
            },
            onRefreshFolder: { folder, sourceID in
                Task {
                    await refreshFolderFromSidebar(folder, sourceID: sourceID)
                }
            },
            onRetryLoad: {
                Task {
                    await loadWorkspace()
                }
            },
            folderVisibility: folderVisibility,
            outboxPendingCount: outboxPendingCount,
            onOpenOutbox: {
                navigation.presentedSheet = .outbox
            },
            onOpenSettings: {
                presentSettings()
            },
            onOpenMessages: {
                openSelectedMessagesOnCompact()
            }
        )
        .brevMailPaneSurface(.sidebar)
        .brevMailFallbackToolbar { toolbarSidebar }
        .brevMailPaneScrollEdgeBlur()
        // Outermost, after the surface wrapper. `navigationSplitViewColumnWidth`
        // configures the enclosing `NSSplitViewItem`, and the surface wrapper
        // puts the column inside a `.frame(maxWidth: .infinity)` — applied
        // underneath that frame the bounds never reached the split view, so
        // the divider dragged past the minimum and the content stretched.
        .brevMailPaneColumnWidth(folderSidebarColumnWidth)
    }

    private func threadHeadersForSelection(fallbackHeader: MessageHeader? = nil) -> [MessageHeader] {
        guard let threadID = navigation.selectedHeader?.threadID ?? fallbackHeader?.threadID else {
            return []
        }
        return ThreadMessageDerivation.threadHeaders(
            from: navigation.currentFolderHeaders,
            threadID: threadID
        )
    }

    @ViewBuilder
    private func readingPaneContent(fallbackHeader: MessageHeader? = nil) -> some View {
        Group {
            let threadHeaders = threadHeadersForSelection(fallbackHeader: fallbackHeader)
            if !hasValidSelectedSourceBackend {
                Text("This mailbox is no longer connected.", bundle: .module)
                    .foregroundStyle(theme.textSecondary.color)
            } else if selectedBackend.groupsMessagesIntoThreads,
                      threadHeaders.count > 1 {
                ThreadConversationView(
                    threadHeaders: threadHeaders,
                    backend: selectedBackend,
                    sourceID: navigation.selectedSourceID,
                    mailboxLabel: selectedSourceSection?.mailbox.email,
                    navigation: navigation,
                    isWorkBlocked: isCommandMutationBlocked
                )
            } else {
                MessageDetailView(
                    backend: selectedBackend,
                    sourceID: navigation.selectedSourceID,
                    header: navigation.selectedHeader ?? fallbackHeader,
                    navigation: navigation,
                    allFolders: folders,
                    isWorkBlocked: isMessageWorkBlocked,
                    isMutationWorkBlocked: isCommandMutationBlocked
                )
            }
        }
    }

    private var readingPaneDetailPane: some View {
        backgroundReadingPaneContent
        #if !os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(minWidth: readerMinimumWidth)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // Teardown reports collapsing widths; acting on them would flip
            // the toolbar mid-quit. The pane's own minimum (less rounding
            // slack) is the floor of every width worth remembering.
            guard width >= (readerMinimumWidth ?? 420) - 1 else { return }
            settleReaderPaneWidth(width)
        }
        #endif
        .brevMailPaneSurface(.content)
        .brevMailFallbackToolbar { toolbarDetail }
    }

    @ViewBuilder
    private var backgroundReadingPaneContent: some View {
        #if os(iOS)
        if compactReaderHeader == nil {
            readingPaneContent()
        } else {
            Color.clear
        }
        #else
        readingPaneContent()
        #endif
    }

    #if os(iOS)
    private func compactReadingPaneDetailPane(fallbackHeader: MessageHeader) -> some View {
        readingPaneContent(fallbackHeader: fallbackHeader)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .brevMailPaneSurface(.content)
            .brevMailFallbackToolbar { compactReaderToolbar }
    }
    #endif

    @ViewBuilder
    private var bottomReadingPane: some View {
        #if os(macOS)
        VSplitView {
            messageListPane
                .frame(minHeight: 220)
            readingPaneDetailPane
                .frame(minHeight: 260)
        }
        #else
        VStack(spacing: 0) {
            messageListPane
                .frame(minHeight: 220)
            Divider()
            readingPaneDetailPane
                .frame(minHeight: 260)
        }
        #endif
    }

    private func openSelectedMessageOnCompact(header: MessageHeader) {
        #if os(iOS)
        switch MailRootReadingPanePresentationPolicy.messageSelectionPresentation(
            horizontalSizeClass: horizontalSizeClass
        ) {
        case .compactOverlay:
            compactReaderHeader = header
        case .splitInPlace:
            break
        }
        #endif
    }

    /// The enabled persisted saved search currently selected in the sidebar, if any.
    /// Reads `smartMailboxData` so edits to the saved-search store re-resolve.
    private var selectedSavedSearch: SmartMailbox? {
        _ = smartMailboxData
        guard let id = navigation.selectedSavedSearchID else { return nil }
        return SmartMailboxSettings.load().mailboxes.first { $0.id == id && $0.isEnabled }
    }

    /// Executes a selected saved search: attachment searches open the All
    /// Attachments surface seeded with the saved filter; message searches reuse
    /// the unified list filtered by the saved query (ADR-0041).
    @ViewBuilder
    private func savedSearchPane(_ mailbox: SmartMailbox) -> some View {
        switch mailbox.kind {
        case .attachmentSearch:
            AllAttachmentsView(
                provider: CachedAttachmentSearchRecordProvider(
                    enumerator: BackendCachedAttachmentEnumerator(
                        backends: backends,
                        sourceSections: visibleSourceSections
                    )
                ),
                navigation: navigation,
                initialFilter: AttachmentSearchFilter(
                    query: mailbox.query.text,
                    sender: mailbox.query.from,
                    folderID: mailbox.query.folderID
                ),
                onOpen: { route in openAttachmentRoute(route) }
            )
        case .messageSearch:
            UnifiedInboxListView(
                navigation: navigation,
                backends: backends,
                sourceSections: visibleSourceSections,
                savedSearchID: mailbox.id,
                savedSearchTitle: mailbox.name,
                savedSearchQuery: mailbox.query,
                localMessageWorkflowState: localMessageWorkflowStateBinding,
                isWorkBlocked: isMessageWorkBlocked,
                isMutationWorkBlocked: isCommandMutationBlocked,
                composeActions: composePresentationActions,
                onSelectMessage: { header in
                    #if os(iOS)
                    openSelectedMessageOnCompact(header: header)
                    #endif
                }
            ) { event in
                await handleMessageListMutation(event)
            }
        }
    }

    @ViewBuilder
    private var messageListPane: some View {
        Group {
            if navigation.isAllAttachmentsSelected {
                AllAttachmentsView(
                    provider: CachedAttachmentSearchRecordProvider(
                        enumerator: BackendCachedAttachmentEnumerator(
                            backends: backends,
                            sourceSections: visibleSourceSections
                        )
                    ),
                    navigation: navigation,
                    onOpen: { route in openAttachmentRoute(route) }
                )
            } else if let savedSearch = selectedSavedSearch {
                savedSearchPane(savedSearch)
            } else if navigation.isUnifiedInboxSelected || navigation.isSmartViewSelected {
                UnifiedInboxListView(
                    navigation: navigation,
                    backends: backends,
                    sourceSections: visibleSourceSections,
                    accountOwnedMailboxEmailsByAccountID: accountOwnedMailboxEmailsByAccountID,
                    smartView: selectedSmartView,
                    localMessageWorkflowState: localMessageWorkflowStateBinding,
                    isWorkBlocked: isMessageWorkBlocked,
                    isMutationWorkBlocked: isCommandMutationBlocked,
                    composeActions: composePresentationActions,
                    onSelectMessage: { header in
                        #if os(iOS)
                        openSelectedMessageOnCompact(header: header)
                        #endif
                    },
                    onMutation: { event in
                        await handleMessageListMutation(event)
                    }
                )
            } else {
                MessageListView(
                    navigation: navigation,
                    backend: selectedBackend,
                    sourceID: navigation.selectedSourceID,
                    accountOwnedMailboxEmails: accountOwnedMailboxEmailsByAccountID[
                        selectedBackend.account.id
                    ] ?? [],
                    folder: selectedFolder,
                    allFolders: folders,
                    searchSyntaxDescription: selectedSearchSyntaxDescription,
                    localMessageWorkflowState: localMessageWorkflowStateBinding,
                    isWorkBlocked: isMessageWorkBlocked,
                    isMutationWorkBlocked: isCommandMutationBlocked,
                    composeActions: composePresentationActions,
                    onSelectMessage: { header in
                        #if os(iOS)
                        openSelectedMessageOnCompact(header: header)
                        #endif
                    },
                    onMutation: { event in
                        await handleMessageListMutation(event)
                    },
                    onUnreadCountChanged: { folderID, delta in
                        applyUnreadCountChange(folderID: folderID, delta: delta)
                    },
                    onOpenInNewWindow: openMessageInNewWindow
                )
            }
        }
        .frame(minWidth: 320, idealWidth: 420)
        .brevMailPaneSurface(.content)
        // iOS gives search its own full-width band above the list (see
        // `MessageListSearchBand`, rendered by the list views), so the field
        // gets the whole column and
        // the navigation bar keeps only the back button and the mailbox
        // actions. macOS puts its own `NSSearchField` in this column's toolbar
        // section (see `toolbarList`), not via `.searchable`, whose
        // window-level item re-lays out and collapses to a magnifying glass on
        // its own whenever the AI Sidebar column appears.
        .brevMailFallbackToolbar { toolbarList }
        // No pane-level scroll edge blur here: the message list mounts the
        // band on its own scroll viewport (see MessageListView), which sits
        // below the inbox category and action bars when those are present. A
        // pane-top band would float above where rows actually clip.
        #if os(macOS)
            // Edit > Search Mail has to open the collapsed control, not just
            // ask an unrendered field for focus.
            .onChange(of: navigation.searchFocusRequestID) {
                isSearchFieldToggledOpen = true
            }
        #endif
            // Outermost, for the same reason as the folder sidebar's bounds.
            .brevMailPaneColumnWidth(messageListColumnWidth)
    }

    @ViewBuilder
    private var nativeToolbarBridge: some View {
        #if os(macOS)
        if BrevMailToolbarRuntime.usesNativeToolbar {
            BrevMailNativeToolbarBridge(
                state: BrevMailNativeToolbarState(
                    selectedHeader: navigation.selectedHeader,
                    hasSelectedFolder: selectedFolder != nil,
                    canArchive: folder(role: .archive) != nil,
                    hasPresentedSheet: navigation.presentedSheet != nil,
                    isRefreshing: activeRefreshRequest != nil,
                    isSwitchingMailbox: activeMailboxSwitchRequest != nil,
                    isPerformingCommandMutation: activeCommandMutationRequest != nil,
                    isComposeBlocked: isComposePresentationBlocked,
                    isSettingsBlocked: !canPresentSettings(),
                    usesExternalSettingsWindow: onOpenSettings != nil,
                    isMailContextPresented: isMailContextColumnPresented
                ),
                actions: BrevMailNativeToolbarActions(
                    compose: {
                        presentNewMessage()
                    },
                    refresh: {
                        await refreshVisibleMail()
                    },
                    reply: { header in
                        presentReply(to: header)
                    },
                    replyAll: { header in
                        presentReplyAll(to: header)
                    },
                    forward: { header in
                        presentForward(of: header)
                    },
                    toggleRead: { header in
                        await toggleRead(for: header)
                    },
                    toggleStar: { header in
                        await toggleStar(for: header)
                    },
                    archive: { header in
                        await archive(header: header)
                    },
                    delete: { header in
                        await trash(header: header)
                    },
                    settings: {
                        presentSettings()
                    },
                    toggleMailContext: {
                        isMailContextColumnPresented.toggle()
                    }
                )
            )
            .frame(width: 0, height: 0)
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarSidebar: some ToolbarContent {
        #if os(iOS)
        if MailRootSidebarToolbarPolicy.showsMessageListButton(
            platform: toolbarPlatform,
            horizontalSizeClass: horizontalSizeClass,
            hasSelectedDestination: hasSelectedMessageDestination
        ) {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    openSelectedMessagesOnCompact()
                } label: {
                    Label(
                        selectedMessageDestinationTitle,
                        systemImage: "chevron.forward"
                    )
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                }
                .accessibilityLabel(String(localized: "Show messages", bundle: .module))
                .accessibilityHint(String(localized: "Return to the selected mailbox.", bundle: .module))
            }
        }
        #endif

        if MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .sidebar,
            platform: toolbarPlatform
        ) {
            ToolbarItem(placement: .primaryAction) {
                settingsToolbarButton
            }
        }
    }

    /// Presents the selected mailbox list without collapsing regular-width iPad columns.
    private func openSelectedMessagesOnCompact() {
        #if os(iOS)
        guard hasSelectedMessageDestination,
              MailRootReadingPanePresentationPolicy.usesCompactReaderPresentation(
                  horizontalSizeClass: horizontalSizeClass
              )
        else { return }
        Task { @MainActor in
            // Compact NavigationSplitView can ignore a column mutation made in
            // the same update as a row selection. Yield once before requesting
            // the selected mailbox so both a new selection and reselecting the
            // active row always escape the sidebar.
            await Task.yield()
            preferredCompactColumn =
                MailRootReadingPanePresentationPolicy.compactColumnAfterSelectingFolder(
                    presentation: readingPanePresentation
                )
            splitViewVisibility = .detailOnly
        }
        #endif
    }

    private var hasSelectedMessageDestination: Bool {
        navigation.selectedFolderID != nil
            || navigation.isUnifiedInboxSelected
            || navigation.isSmartViewSelected
            || navigation.selectedSavedSearchID != nil
            || navigation.isAllAttachmentsSelected
    }

    private var selectedMessageDestinationTitle: String {
        if navigation.isUnifiedInboxSelected {
            return String(localized: "All Inboxes", bundle: .module)
        }
        if let smartView = MailboxSmartView.selected(for: navigation) {
            return smartView.title
        }
        if navigation.isAllAttachmentsSelected {
            return String(localized: "All Attachments", bundle: .module)
        }
        if let selectedSavedSearch {
            return selectedSavedSearch.name
        }
        return selectedFolder?.name ?? String(localized: "Messages", bundle: .module)
    }

    @ToolbarContentBuilder
    private var toolbarList: some ToolbarContent {
        #if os(macOS)
        // Get Mail and New Message live in the detail section on macOS — see
        // `MailRootMailboxActionToolbarPolicy`. What is left here acts on the
        // list's presentation, not on mail.
        if MailboxFilterControlPolicy.usesToolbarControl(platform: toolbarPlatform),
           showsMailboxFilterControl {
            ToolbarItem(placement: .primaryAction) {
                mailboxFilterToolbarControl
            }
        }
        // Keeps the section occupied so the detail column's action cluster does
        // not slide left across the message list.
        ToolbarItem(placement: .primaryAction) {
            Spacer()
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            if showsMailboxFilterControl {
                mailboxFilterToolbarControl
            }

            if MailRootMailboxActionToolbarPolicy.showsMailboxActions(
                on: .messageList,
                platform: toolbarPlatform
            ) {
                refreshToolbarButton
                composeToolbarButton
            }

            if MailRootSettingsToolbarPolicy.showsSettingsButton(
                on: .messageList,
                platform: toolbarPlatform
            ) {
                settingsToolbarButton
            }
        }
        #endif
    }

    /// Get Mail. Placed by `MailRootMailboxActionToolbarPolicy`.
    private var refreshToolbarButton: some View {
        Button {
            Task { await refreshVisibleMail() }
        } label: {
            // `Label` + `.iconOnly`, not a bare `Image`: iPhone toolbars drop
            // the accessibility element of image-only buttons, so VoiceOver
            // and UI automation saw an unlabeled button even with an explicit
            // `accessibilityLabel` (the related feature request). The label's title is the
            // accessibility name; the explicit label stays for the state note.
            Label(String(localized: "Refresh", bundle: .module), systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .disabled(visibleRefreshTarget == nil || !canStartRefresh())
        .accessibilityLabel(String(localized: "Refresh", bundle: .module))
    }

    #if os(macOS)
    /// The search field while open, otherwise the button that opens it.
    @ViewBuilder
    private var searchToolbarControl: some View {
        if isSearchFieldToggledOpen {
            MessageListSearchField(
                text: $navigation.searchText,
                prompt: "Search messages",
                focusRequestID: navigation.searchFocusRequestID,
                onEndEditing: { isSearchFieldToggledOpen = false }
            )
            // Sized to the reader, not free-growing: the field shares the
            // reader's toolbar section with its action cluster, and a field
            // that takes its full 240pt on a narrow reader takes that width
            // from the icons — which then spill back over the message list.
            .frame(width: expandedSearchFieldWidth)
        } else {
            Button(action: expandSearchField) {
                // The filled glyph marks a query the collapsed control still
                // holds, so a filtered list never looks unexplained.
                Image(
                    systemName: showsRetainedSearchQuery
                        ? "magnifyingglass.circle.fill"
                        : "magnifyingglass"
                )
            }
            .accessibilityLabel(showsRetainedSearchQuery ? "Search messages, filter active" : "Search messages")
            .help(showsRetainedSearchQuery ? "Search Mail (filter active)" : "Search Mail")
        }
    }

    /// Whether the reader is too narrow for the full action cluster, in which
    /// case Reply All, Forward, and Flag fold into the overflow menu instead
    /// of spilling left across the divider into the message list.
    private var usesCondensedDetailActions: Bool {
        !MailRootDetailToolbarPolicy.showsExtendedResponseActions(
            platform: toolbarPlatform,
            readerWidth: readerPaneWidth
        ) && toolbarPlatform == .macOS
    }

    private var expandedSearchFieldWidth: CGFloat {
        MessageListSearchExpansionPolicy.expandedFieldWidth(
            readerWidth: readerPaneWidth,
            reservedClusterWidth: MessageListSearchExpansionPolicy.reservedClusterWidth(
                isCondensed: usesCondensedDetailActions
            )
        )
    }

    private var showsRetainedSearchQuery: Bool {
        MessageListSearchExpansionPolicy.showsRetainedQuery(
            isToggledOpen: isSearchFieldToggledOpen,
            query: navigation.searchText
        )
    }

    private func expandSearchField() {
        isSearchFieldToggledOpen = true
        navigation.requestSearchFocus()
    }
    #endif

    /// Sort and filter for the visible message list. macOS hosts it in the
    /// window toolbar above the column it filters — where Mail puts it; iOS
    /// hosts it in the navigation bar's action cluster beside refresh and
    /// compose, where it replaced the in-pane filter strip.
    private var mailboxFilterToolbarControl: some View {
        MailboxFilterMenu(
            activeFilter: $navigation.mailboxFilter,
            sortOrder: mailboxSortOrderBinding,
            lockedFilters: selectedSmartView?.query.activeFilters ?? []
        )
    }

    /// The attachment surfaces are not message lists, so nothing there responds
    /// to a quick filter and the control would be inert.
    private var showsMailboxFilterControl: Bool {
        !navigation.isAllAttachmentsSelected
            && selectedSavedSearch?.kind != .attachmentSearch
    }

    private var mailboxSortOrderBinding: Binding<MailboxSortOrder> {
        Binding(
            get: { MailboxSortOrder(rawValue: mailboxSortOrderRaw) ?? .newestFirst },
            set: { mailboxSortOrderRaw = $0.rawValue }
        )
    }

    /// New Message. Placed by `MailRootMailboxActionToolbarPolicy`.
    private var composeToolbarButton: some View {
        Button {
            presentNewMessage()
        } label: {
            Label(String(localized: "Compose", bundle: .module), systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
        }
        .disabled(!canPresentCompose())
        .accessibilityLabel(String(localized: "Compose", bundle: .module))
    }

    @ToolbarContentBuilder
    private var toolbarDetail: some ToolbarContent {
        // Mail leads the reader's cluster with New Message and Get Mail, and
        // they stay available with nothing selected — unlike everything after
        // them, which needs a message to act on.
        if MailRootMailboxActionToolbarPolicy.showsMailboxActions(
            on: .detail,
            platform: toolbarPlatform
        ) {
            // The first item of this section starts a little before the column
            // boundary, and macOS 26's bordered container makes that overhang
            // visible: the split-view divider ran straight through Get Mail's
            // circle. This holds the cluster clear of it.
            #if os(macOS) && compiler(>=6.2)
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                refreshToolbarButton
            }
            // macOS 26 draws adjacent items inside one shared bordered
            // container, so without this the mailbox actions and the message
            // actions read as a single undifferentiated chunk of chrome.
            #if os(macOS) && compiler(>=6.2)
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                composeToolbarButton
            }
            #if os(macOS) && compiler(>=6.2)
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            #endif
        }

        if let header = navigation.selectedHeader {
            if MailRootDetailToolbarPolicy.usesCondensedLayout(platform: toolbarPlatform) {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        presentReply(to: header)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                    .disabled(!canPresentCompose())
                    .accessibilityLabel(String(localized: "Reply", bundle: .module))

                    if MailRootDetailToolbarPolicy.showsExtendedResponseActions(
                        platform: toolbarPlatform,
                        readerWidth: readerPaneWidth
                    ) {
                        Button {
                            presentReplyAll(to: header)
                        } label: {
                            Image(systemName: "arrowshape.turn.up.left.2")
                        }
                        .disabled(!canPresentCompose())
                        .accessibilityLabel(String(localized: "Reply All", bundle: .module))

                        Button {
                            presentForward(of: header)
                        } label: {
                            Image(systemName: "arrowshape.turn.up.right")
                        }
                        .disabled(!canPresentCompose())
                        .accessibilityLabel(String(localized: "Forward", bundle: .module))
                    }

                    Button {
                        Task { await archive(header: header) }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .disabled(folder(role: .archive) == nil || !canStartCommandMutation())
                    .accessibilityLabel(String(localized: "Archive", bundle: .module))

                    Button {
                        Task { await trash(header: header) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!canStartCommandMutation())
                    .accessibilityLabel(String(localized: "Delete", bundle: .module))

                    if MailRootDetailToolbarPolicy.showsFlagButton(
                        platform: toolbarPlatform,
                        readerWidth: readerPaneWidth
                    ) {
                        Button {
                            Task { await toggleStar(for: header) }
                        } label: {
                            Image(systemName: MessageCommandPresentation.flagToggleSymbolName(for: header))
                        }
                        .disabled(!canStartCommandMutation())
                        .accessibilityLabel(MessageCommandPresentation.flagToggleTitle(for: header))
                        .help(MessageCommandPresentation.flagToggleTitle(for: header))
                    } else {
                        Menu {
                            Button {
                                Task { await toggleStar(for: header) }
                            } label: {
                                Label(
                                    MessageCommandPresentation.flagToggleTitle(for: header),
                                    systemImage: MessageCommandPresentation.flagToggleSymbolName(for: header)
                                )
                            }
                            .disabled(!canStartCommandMutation())

                            if !MailRootDetailToolbarPolicy.showsExtendedResponseActions(
                                platform: toolbarPlatform,
                                readerWidth: readerPaneWidth
                            ) {
                                // Reply All has its own button on macOS until
                                // the cluster condenses; iOS never shows it in
                                // the toolbar, so the menu stays as it was.
                                if toolbarPlatform == .macOS {
                                    Button {
                                        presentReplyAll(to: header)
                                    } label: {
                                        Label(
                                            String(localized: "Reply All", bundle: .module),
                                            systemImage: "arrowshape.turn.up.left.2"
                                        )
                                    }
                                    .disabled(!canPresentCompose())
                                }

                                Button {
                                    presentForward(of: header)
                                } label: {
                                    Label(String(localized: "Forward", bundle: .module), systemImage: "arrowshape.turn.up.right")
                                }
                                .disabled(!canPresentCompose())
                            }

                            #if os(iOS)
                            // The macOS AI Sidebar column presents as a sheet
                            // on iOS; same shared Mail Context surface.
                            Button {
                                isMailContextSheetPresented = true
                            } label: {
                                Label(
                                    MailContextColumnVisibility.toolbarLabel,
                                    systemImage: MailContextColumnVisibility.toolbarSymbolName
                                )
                            }
                            #endif

                            if toolbarPlatform == .macOS,
                               !MailRootDetailToolbarPolicy.showsMessageOrganizerActions(
                                   platform: toolbarPlatform,
                                   readerWidth: readerPaneWidth
                               ) {
                                // Create Task and Move have their own buttons on
                                // macOS until the cluster condenses; iOS keeps
                                // them in the reader's tools menu.
                                Button {
                                    presentCreateTask(for: header)
                                } label: {
                                    Label(String(localized: "Create Task", bundle: .module), systemImage: "checklist")
                                }
                                .disabled(isMessageWorkBlocked || navigation.presentedSheet != nil)

                                Button {
                                    presentFollowUp(for: header)
                                } label: {
                                    Label(String(localized: "Follow Up", bundle: .module), systemImage: "flag")
                                }
                                .disabled(navigation.presentedSheet != nil)

                                if !folders.isEmpty {
                                    Button {
                                        presentMoveToFolder(for: header)
                                    } label: {
                                        Label(String(localized: "Move", bundle: .module), systemImage: "folder")
                                    }
                                    .disabled(isMessageWorkBlocked)
                                }
                            }

                            if MailRootSettingsToolbarPolicy.showsSettingsButton(
                                on: .detail,
                                platform: toolbarPlatform
                            ) {
                                Button {
                                    presentSettings()
                                } label: {
                                    Label(String(localized: "Settings", bundle: .module), systemImage: "gearshape")
                                }
                                .disabled(!canPresentSettings())
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(String(localized: "More message actions", bundle: .module))
                    }
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await toggleStar(for: header) }
                    } label: {
                        Image(systemName: MessageCommandPresentation.flagToggleSymbolName(for: header))
                    }
                    .disabled(!canStartCommandMutation())
                    .accessibilityLabel(MessageCommandPresentation.flagToggleTitle(for: header))

                    Button {
                        presentReply(to: header)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                    .disabled(!canPresentCompose())
                    .accessibilityLabel(String(localized: "Reply", bundle: .module))

                    Button {
                        presentForward(of: header)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.right")
                    }
                    .disabled(!canPresentCompose())
                    .accessibilityLabel(String(localized: "Forward", bundle: .module))

                    Button {
                        Task { await archive(header: header) }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .disabled(folder(role: .archive) == nil || !canStartCommandMutation())
                    .accessibilityLabel(String(localized: "Archive", bundle: .module))

                    Button {
                        Task { await trash(header: header) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!canStartCommandMutation())
                    .accessibilityLabel(String(localized: "Delete", bundle: .module))
                }
            }

            // Create Task and Move are root items so they condense with the
            // cluster and sit before the AI Sidebar toggle. Contributed from
            // `MessageDetailView`'s own `.toolbar`, they appended after
            // everything here — to the right of the toggle, outside the
            // width condensation, leaking across the divider when narrow.
            #if os(macOS)
            if MailRootDetailToolbarPolicy.showsMessageOrganizerActions(
                platform: toolbarPlatform,
                readerWidth: readerPaneWidth
            ) {
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentCreateTask(for: header)
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .disabled(isMessageWorkBlocked || navigation.presentedSheet != nil)
                    .accessibilityLabel(String(localized: "Create Task", bundle: .module))
                    .help(String(localized: "Create task", bundle: .module))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentFollowUp(for: header)
                    } label: {
                        Image(systemName: "flag")
                    }
                    .disabled(navigation.presentedSheet != nil)
                    .accessibilityLabel(String(localized: "Follow Up", bundle: .module))
                    .help(String(localized: "Follow Up", bundle: .module))
                }
                if !folders.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            presentMoveToFolder(for: header)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .disabled(isMessageWorkBlocked)
                        .accessibilityLabel(String(localized: "Move", bundle: .module))
                        .help(String(localized: "Move to folder", bundle: .module))
                    }
                }
            }
            #endif
        }

        if MailRootSettingsToolbarPolicy.showsSettingsButton(
            on: .detail,
            platform: toolbarPlatform
        ), navigation.selectedHeader == nil
            || !MailRootDetailToolbarPolicy.usesCondensedLayout(platform: toolbarPlatform) {
            ToolbarItem(placement: .primaryAction) {
                settingsToolbarButton
            }
        }

        #if os(macOS)
        // Search rides with the reader's actions rather than being pinned to the
        // window's trailing edge. `.primaryAction` is one group that runs to the
        // window edge, over the AI Sidebar when it is open, and no spacer can
        // hold an item off that edge by a fixed amount — macOS 26 ignores a
        // toolbar spacer's requested width. Placed here, ahead of the flexible
        // spacer, search stays inside the reader whether the sidebar is open or
        // not.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
        #endif
        ToolbarItem(placement: .primaryAction) {
            searchToolbarControl
        }
        // Keeps the reader's own actions off the message list's section.
        ToolbarItem(placement: .primaryAction) {
            Spacer()
        }
        // The AI Sidebar toggle, as a toolbar item like every other control.
        // It used to be an `NSTitlebarAccessoryViewController` pinned to the
        // window's right edge, which is why it sat apart from the cluster with a
        // gap in front of it and did not pick up the toolbar's own item styling.
        // It is the one item that belongs at the window's trailing edge above
        // the sidebar, since it is what opens and closes it.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
        #endif
        ToolbarItem(placement: .primaryAction) {
            mailContextToolbarButton
        }
        // Nothing may follow the toggle: it is the item that owns the
        // window's trailing edge, above the sidebar it opens. Create Task
        // and Move moved up into this section (before search) for exactly
        // that reason.
        #endif
    }

    #if os(macOS)
    /// AI Sidebar toggle.
    private var mailContextToolbarButton: some View {
        Button {
            isMailContextColumnPresented.toggle()
        } label: {
            Image(systemName: MailContextColumnVisibility.toolbarSymbolName)
        }
        .accessibilityLabel(
            isMailContextColumnPresented
                ? "Hide AI Sidebar"
                : MailContextColumnVisibility.toolbarLabel
        )
        .help(MailContextColumnVisibility.toolbarLabel)
    }
    #endif

    #if os(iOS)
    @ToolbarContentBuilder
    private var compactReaderToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                compactReaderHeader = nil
            } label: {
                // `Label` + `.iconOnly`: image-only toolbar buttons lose
                // their accessibility element on iPhone (the related feature request).
                Label(String(localized: "Back to messages", bundle: .module), systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(String(localized: "Back to messages", bundle: .module))
        }

        toolbarDetail
    }
    #endif

    private var settingsToolbarButton: some View {
        Button {
            presentSettings()
        } label: {
            Label(String(localized: "Settings", bundle: .module), systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .disabled(!canPresentSettings())
        .accessibilityLabel(String(localized: "Settings", bundle: .module))
    }

    private var toolbarPlatform: MailRootToolbarPlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }

    private var externalInputConsumer: MailExternalInputConsumerModifier {
        MailExternalInputConsumerModifier(
            pendingComposePrefill: pendingComposePrefill,
            pendingNotificationRoute: pendingNotificationRoute,
            onComposePrefill: consumePendingComposePrefill,
            onNotificationRoute: consumePendingNotificationRoute
        )
    }

    private var sheetBinding: Binding<MailNavigationState.Sheet?> {
        Binding(
            get: { navigation.presentedSheet },
            set: { newValue in
                if newValue == nil {
                    navigation.composeReplyTo = nil
                    navigation.composeReplyMode = .sender
                    navigation.composeForwardOf = nil
                    navigation.composePrefill = nil
                }
                navigation.presentedSheet = newValue
            }
        )
    }

    private var selectedBackend: any MailBackend {
        let sourceID = navigation.selectedSourceID ?? preferredDefaultSection(in: visibleSourceSections)?.id
        return backends.first { $0.account.id == sourceID?.accountID } ?? backend
    }

    private var selectedAIBackend: (any AIBackend)? {
        aiBackend(for: selectedBackend.account)
    }

    private func aiBackend(for account: BrevAccount) -> (any AIBackend)? {
        AIBackendAccountRouter(
            backendsByAccountID: aiBackends,
            fallback: backends.count == 1 ? aiBackend : nil
        )
        .backend(for: account)
    }

    private func backend(for sourceID: MailSourceID?) -> any MailBackend {
        guard let sourceID,
              let match = backends.first(where: { $0.account.id == sourceID.accountID })
        else { return selectedBackend }
        return match
    }

    private var selectedSourceSection: MailSourceSection? {
        guard let sourceID = navigation.selectedSourceID else { return nil }
        return visibleSourceSections.first { $0.id == sourceID }
    }

    private var visibleSelectedSourceID: MailSourceID? {
        selectedSourceSection?.id
    }

    private var selectedSmartView: MailboxSmartView? {
        _ = vipSenderData
        guard let view = MailboxSmartView.selected(for: navigation) else { return nil }
        let vipEmails = Set(VIPSenderSettings.load().senders.map(\.email))
        return view.resolvingVIPEmails(vipEmails)
    }

    private var localMessageWorkflowStateBinding: Binding<LocalMessageWorkflowState> {
        Binding(
            get: { cachedLocalMessageWorkflowState },
            set: { state in
                cachedLocalMessageWorkflowState = state
                localMessageWorkflowStateData = LocalMessageWorkflowStateStorage.encode(state) ?? Data()
            }
        )
    }

    private var customProfiles: [MailProfile] {
        MailProfileStorage.decode(customProfileStorage)
    }

    private var profiles: [MailProfile] {
        MailProfileSelectionPolicy.resolvedProfiles(
            customProfiles: customProfiles,
            availableSourceIDs: enabledSourceSections.map(\.id)
        )
    }

    private var normalizedActiveProfileID: MailProfile.ID {
        MailProfileSelectionPolicy.selectedProfileID(activeProfileID, profiles: profiles)
    }

    private var visibleSourceSections: [MailSourceSection] {
        MailProfileSelectionPolicy.visibleSections(
            from: enabledSourceSections,
            activeProfileID: activeProfileID,
            profiles: profiles
        )
    }

    private var accountOwnedMailboxEmailsByAccountID: [BrevAccount.ID: Set<String>] {
        Dictionary(grouping: sourceSections, by: { $0.account.id })
            .mapValues { sections in Set(sections.map(\.mailbox.email)) }
    }

    private var sidebarSourceSections: [MailSourceSection] {
        visibleSourceSections.map { section in
            MailSourceSection(
                id: section.id,
                account: section.account,
                mailbox: section.mailbox,
                folders: visibleFolders(section.folders, sourceID: section.id),
                loadError: section.loadError
            )
        }
    }

    private var sidebarFolders: [Folder] {
        visibleFolders(folders, sourceID: navigation.selectedSourceID)
    }

    private var mailContextFolderNameByID: [String: String] {
        Dictionary(moveFolders(for: navigation.selectedSourceID).map { ($0.id, $0.name) }) { _, latest in latest }
    }

    private func mailboxActionFolders(for sourceID: MailSourceID?) -> [Folder] {
        moveFolders(for: sourceID)
    }

    private func mailboxActionSourceScope(for sourceID: MailSourceID?) -> MailboxActionAgentSourceScope {
        MailboxMailContextScopeWiring.actionSourceScope(
            sourceID: sourceID,
            sourceSections: sourceSections
        )
    }

    private func moveFolders(for sourceID: MailSourceID?) -> [Folder] {
        guard let sourceID,
              let sourceSection = sourceSections.first(where: { $0.id == sourceID })
        else { return folders }
        return sourceSection.folders
    }

    private var enabledSourceSections: [MailSourceSection] {
        let enabledSourceIDs = Set(MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: sourceSections.map(\.id),
            preferences: mailboxSourcePreferences
        ))
        return sourceSections.filter { enabledSourceIDs.contains($0.id) }
    }

    private var initialMailboxSelectionSourceSections: [MailSourceSection] {
        guard let initialMailboxSelectionAccountID else { return [] }
        return sourceSections.filter { $0.account.id == initialMailboxSelectionAccountID }
    }

    private var mailboxSourcePreferences: MailboxSourcePreferences {
        cachedMailboxSourcePreferences
    }

    private var folderVisibilityPreferences: FolderVisibilityPreferences {
        cachedFolderVisibilityPreferences
    }

    private var folderAliasPreferences: FolderAliasPreferences {
        cachedFolderAliasPreferences
    }

    private var selectedFolder: Folder? {
        guard let id = navigation.selectedFolderID else { return nil }
        if let selectedSourceSection {
            return selectedSourceSection.folders.first { $0.id == id }
        }
        return folders.first { $0.id == id }
    }

    private var visibleRefreshTarget: MailRootVisibleRefreshTarget? {
        MailRootVisibleRefreshPolicy.target(
            selectedFolderID: selectedFolder?.id,
            isUnifiedInbox: navigation.isUnifiedInboxSelected
        )
    }

    private var folderVisibility: FolderSidebarVisibilityPreferences {
        FolderSidebarVisibilityPreferences(
            showStarred: showStarredFolders,
            showSnoozed: showSnoozedFolders,
            showScheduled: showScheduledFolders,
            showAllMail: showAllMailFolders,
            showSpam: showSpamFolders,
            showTrash: showTrashFolders,
            showArchive: showArchiveFolders
        )
    }

    private var folderNamePromptTitle: String {
        folderNamePrompt?.title ?? "Folder"
    }

    private var folderNamePromptActionTitle: String {
        folderNamePrompt?.actionTitle ?? "Save"
    }

    private var folderNameTextFieldTitle: String {
        folderNamePrompt?.textFieldTitle ?? "Folder name"
    }

    private var folderNamePromptMessage: String {
        folderNamePrompt?.message ?? ""
    }

    private var isFolderNamePromptPresented: Binding<Bool> {
        Binding(
            get: { folderNamePrompt != nil },
            set: { isPresented in
                if !isPresented {
                    folderNamePrompt = nil
                    folderNameDraft = ""
                }
            }
        )
    }

    private var folderConfirmationTitle: String {
        folderConfirmation?.title ?? "Folder"
    }

    private var folderConfirmationActionTitle: String {
        folderConfirmation?.actionTitle ?? "Continue"
    }

    private var folderConfirmationMessage: String {
        folderConfirmation?.message ?? ""
    }

    private var isFolderConfirmationPresented: Binding<Bool> {
        Binding(
            get: { folderConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    folderConfirmation = nil
                }
            }
        )
    }

    private var isRefreshBlocked: Bool {
        activeFolderLoadRequest != nil
            || activeMailboxLoadRequest != nil
            || activeCommandMutationRequest != nil
            || activeMailboxSwitchRequest != nil
            || activeComposeCompletionRequest != nil
            || navigation.presentedSheet != nil
    }

    private var hasMailContext: Bool {
        MailRootWorkBlockPolicy.hasMailContext(
            visibleSourceCount: visibleSourceSections.count,
            hasAnySources: !sourceSections.isEmpty,
            hasFallbackFolders: !folders.isEmpty,
            isAllMailboxesProfile: normalizedActiveProfileID == MailProfile.allMailboxesID
        )
    }

    private var isCommandMutationBlocked: Bool {
        if !hasMailContext { return true }
        return undoQueue.isUndoing
            || activeFolderLoadRequest != nil
            || activeMailboxLoadRequest != nil
            || activeRefreshRequest != nil
            || activeMailboxSwitchRequest != nil
            || activeComposeCompletionRequest != nil
            || navigation.presentedSheet != nil
    }

    private var isMailboxSwitchBlocked: Bool {
        activeFolderLoadRequest != nil
            || activeMailboxLoadRequest != nil
            || activeRefreshRequest != nil
            || activeCommandMutationRequest != nil
            || activeComposeCompletionRequest != nil
    }

    private var rootWorkBlockSnapshot: MailRootWorkBlockSnapshot {
        MailRootWorkBlockSnapshot(
            folderLoadID: activeFolderLoadRequest?.id,
            mailboxLoadID: activeMailboxLoadRequest?.id,
            refreshID: activeRefreshRequest?.id,
            mailboxSwitchID: activeMailboxSwitchRequest?.id,
            commandMutationID: activeCommandMutationRequest?.id,
            composeCompletionID: activeComposeCompletionRequest?.id
        )
    }

    private var isMessageWorkBlocked: Bool {
        if !hasMailContext { return true }
        return MailRootWorkBlockPolicy.isMessageWorkBlocked(
            hasPresentedSheet: navigation.presentedSheet != nil,
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeCommandMutationRequest: activeCommandMutationRequest,
            hasUsableContent: !navigation.currentFolderHeaders.isEmpty || !visibleSourceSections.isEmpty
        )
    }

    private var isComposePresentationBlocked: Bool {
        !canPresentCompose()
    }

    private var isMailBackgroundAccessibilityHidden: Bool {
        return MailRootSheetPresentationPolicy.hidesBackgroundAccessibility(
            hasPresentedSheet: navigation.presentedSheet != nil,
            hasInitialMailboxSelection: isInitialMailboxSelectionPresented,
            hasFolderPrompt: folderNamePrompt != nil,
            hasFolderConfirmation: folderConfirmation != nil,
            hasExternalModal: isExternalModalPresented
        )
    }

    private var messageListColumnWidth: MailPaneColumnWidth? {
        MailPaneColumnWidthPolicy.messageList(platform: mailPanePlatform)
    }

    private var folderSidebarColumnWidth: MailPaneColumnWidth? {
        MailPaneColumnWidthPolicy.folderSidebar(platform: mailPanePlatform)
    }

    private var readerMinimumWidth: CGFloat? {
        MailPaneColumnWidthPolicy.readerMinimumWidth(platform: mailPanePlatform)
    }

    private var mailPanePlatform: MailPanePlatform {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #else
        .macOS
        #endif
    }

    private var composePresentationActions: MailComposePresentationActions {
        MailComposePresentationActions(
            isBlocked: isComposePresentationBlocked,
            newMessage: {
                presentNewMessage()
            },
            reply: { header in
                presentReply(to: header)
            },
            replyAll: { header in
                presentReplyAll(to: header)
            },
            forward: { header in
                presentForward(of: header)
            }
        )
    }

    private var isComposeWorkBlocked: Bool {
        if !hasMailContext { return true }
        return MailRootWorkBlockPolicy.isComposeWorkBlocked(
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeCommandMutationRequest: activeCommandMutationRequest
        )
    }

    private func canPresentCompose() -> Bool {
        guard hasMailContext else { return false }
        return MailRootComposePresentationPolicy.canPresentCompose(
            hasPresentedSheet: navigation.presentedSheet != nil,
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeCommandMutationRequest: activeCommandMutationRequest,
            activeComposeCompletionRequest: activeComposeCompletionRequest
        )
    }

    private func canPresentSettings() -> Bool {
        MailRootSheetPresentationPolicy.canOpenSettings(
            hasPresentedSheet: navigation.presentedSheet != nil,
            usesExternalSettingsWindow: onOpenSettings != nil
        )
    }

    private func presentNewMessage() {
        guard canPresentCompose() else { return }
        #if os(iOS)
        if shouldDetachCompose {
            // Compose from the selected account/mailbox, not just backends.first.
            openWindow(value: ComposeWindowPayload(kind: .new(sourceID: navigation.selectedSourceID)))
            return
        }
        #endif
        navigation.presentNewMessage()
    }

    private var settingsMailboxContext: SettingsMailboxContext {
        SettingsMailboxContext(
            selectedSourceID: navigation.selectedSourceID,
            mailboxes: sourceSections.map {
                SettingsMailbox(account: $0.account, mailbox: $0.mailbox, folders: $0.folders)
            }
        )
    }

    private func presentSettings() {
        guard canPresentSettings() else { return }
        onOpenSettings?()
    }

    private func presentCreateTask(for header: MessageHeader) {
        guard !isMessageWorkBlocked, navigation.presentedSheet == nil else { return }
        navigation.presentedSheet = .createTask(
            header: header,
            sourceID: navigation.selectedSourceID
        )
    }

    private func presentFollowUp(for header: MessageHeader) {
        guard navigation.presentedSheet == nil else { return }
        navigation.presentedSheet = .followUp(
            header: header,
            sourceID: navigation.selectedSourceID
        )
    }

    private func presentMoveToFolder(for header: MessageHeader) {
        guard !isMessageWorkBlocked, navigation.presentedSheet == nil else { return }
        navigation.presentedSheet = .moveTo(
            messageIDs: [header.id],
            sourceID: navigation.selectedSourceID,
            currentFolderID: header.folderID
        )
    }

    private func presentReply(to header: MessageHeader) {
        guard canPresentCompose() else { return }
        #if os(iOS)
        if shouldDetachCompose {
            openWindow(value: ComposeWindowPayload(
                kind: .reply(messageID: header.id, sourceID: navigation.selectedSourceID)
            ))
            return
        }
        #endif
        navigation.presentReply(to: header)
    }

    private func presentReplyAll(to header: MessageHeader) {
        guard canPresentCompose() else { return }
        #if os(iOS)
        if shouldDetachCompose {
            openWindow(value: ComposeWindowPayload(
                kind: .replyAll(messageID: header.id, sourceID: navigation.selectedSourceID)
            ))
            return
        }
        #endif
        navigation.presentReplyAll(to: header)
    }

    private func presentForward(of header: MessageHeader) {
        guard canPresentCompose() else { return }
        #if os(iOS)
        if shouldDetachCompose {
            openWindow(value: ComposeWindowPayload(
                kind: .forward(messageID: header.id, sourceID: navigation.selectedSourceID)
            ))
            return
        }
        #endif
        navigation.presentForward(of: header)
    }

    #if os(iOS)
    /// Returns `true` when the current device + width warrants a detached
    /// compose window instead of a modal sheet (iPad at regular width only).
    private var shouldDetachCompose: Bool {
        MailDetachWindowPolicy.shouldDetach(
            idiom: UIDevice.current.userInterfaceIdiom,
            horizontalSizeClass: horizontalSizeClass
        )
    }
    #endif

    private func consumePendingComposePrefill(_ prefill: ComposePrefill?) {
        guard let prefill, !prefill.isEmpty, canPresentCompose() else { return }
        navigation.presentNewMessage(prefill: prefill)
        pendingComposePrefill?.wrappedValue = nil
    }

    private func consumePendingNotificationRoute(_ route: NotificationMailRoute?) {
        guard let route else { return }
        openNotificationRoute(route)
        pendingNotificationRoute?.wrappedValue = nil
    }

    private func presentCreateSubfolderPrompt(for folder: Folder, sourceID: MailSourceID?) {
        guard canStartCommandMutation() else { return }
        clearRootStatus()
        folderConfirmation = nil
        folderNamePrompt = .createSubfolder(MailFolderActionTarget(folder: folder, sourceID: sourceID))
        folderNameDraft = ""
    }

    private func presentRenameFolderPrompt(for folder: Folder, sourceID: MailSourceID?) {
        guard canStartCommandMutation() else { return }
        clearRootStatus()
        folderConfirmation = nil
        folderNamePrompt = .renameFolder(MailFolderActionTarget(folder: folder, sourceID: sourceID))
        folderNameDraft = folder.name
    }

    /// Presents the prompt for a Brev-local folder alias. Unlike rename, this
    /// never touches the provider, so it is not gated on command-mutation
    /// state. Prefills with the existing alias or the current display name.
    private func presentSetFolderLocalNamePrompt(for folder: Folder, sourceID: MailSourceID) {
        clearRootStatus()
        folderConfirmation = nil
        folderNamePrompt = .setLocalName(MailFolderActionTarget(folder: folder, sourceID: sourceID))
        folderNameDraft = FolderAliasPreferencesPolicy.alias(
            for: folder.id,
            sourceID: sourceID,
            preferences: folderAliasPreferences
        ) ?? FolderSidebarPresentation.displayName(
            for: folder,
            sourceID: sourceID,
            aliasPreferences: folderAliasPreferences
        )
    }

    /// Stores a Brev-local display alias for a folder.
    private func setFolderLocalName(_ target: MailFolderActionTarget, name: String) {
        guard let sourceID = target.sourceID else { return }
        persistFolderAliasPreferences(
            FolderAliasPreferencesPolicy.settingAlias(
                name,
                folderID: target.folder.id,
                sourceID: sourceID,
                in: folderAliasPreferences
            )
        )
    }

    /// Removes a folder's Brev-local display alias, reverting to the server name.
    private func clearFolderLocalName(_ folder: Folder, sourceID: MailSourceID) {
        clearRootStatus()
        persistFolderAliasPreferences(
            FolderAliasPreferencesPolicy.settingAlias(
                nil,
                folderID: folder.id,
                sourceID: sourceID,
                in: folderAliasPreferences
            )
        )
    }

    private func persistFolderAliasPreferences(_ preferences: FolderAliasPreferences) {
        cachedFolderAliasPreferences = preferences
        FolderAliasPreferencesStorage.save(preferences)
        folderAliasPreferencesData = FolderAliasPreferencesStorage.encode(preferences) ?? Data()
    }

    private func presentDeleteFolderConfirmation(for folder: Folder, sourceID: MailSourceID?) {
        guard canStartCommandMutation() else { return }
        clearRootStatus()
        folderNamePrompt = nil
        folderNameDraft = ""
        folderConfirmation = .deleteFolder(MailFolderActionTarget(folder: folder, sourceID: sourceID))
    }

    private func presentFlushFolderConfirmation(for folder: Folder, sourceID: MailSourceID?) {
        guard canStartCommandMutation() else { return }
        clearRootStatus()
        folderNamePrompt = nil
        folderNameDraft = ""
        folderConfirmation = .flushFolder(MailFolderActionTarget(folder: folder, sourceID: sourceID))
    }

    private func runFolderNamePrompt(_ prompt: MailFolderNamePrompt, name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        switch prompt {
        case .createSubfolder(let target):
            await performFolderMutation(sourceFolderID: target.folder.id) {
                let created = try await createFolder(
                    name: trimmedName,
                    parentID: target.folder.id,
                    sourceID: target.sourceID
                )
                if let sourceID = target.sourceID {
                    navigation.selectFolder(created.id, in: sourceID)
                } else {
                    navigation.selectFolder(created.id, in: nil)
                    navigation.selectedMessageID = nil
                    navigation.currentFolderHeaders = []
                    navigation.bulkSelection.removeAll()
                }
            }
        case .renameFolder(let target):
            await performFolderMutation(sourceFolderID: target.folder.id) {
                _ = try await renameFolder(
                    id: target.folder.id,
                    name: trimmedName,
                    sourceID: target.sourceID
                )
            }
        case .setLocalName(let target):
            setFolderLocalName(target, name: trimmedName)
        }
    }

    private func runFolderConfirmation(_ confirmation: MailFolderConfirmation) async {
        switch confirmation {
        case .deleteFolder(let target):
            await performFolderMutation(sourceFolderID: target.folder.id) {
                try await deleteFolder(id: target.folder.id, sourceID: target.sourceID)
            }
        case .flushFolder(let target):
            await performFolderMutation(sourceFolderID: target.folder.id) {
                try await flushFolder(id: target.folder.id, sourceID: target.sourceID)
                if navigation.selectedFolderID == target.folder.id,
                   navigation.selectedSourceID == target.sourceID {
                    navigation.requestReload()
                }
            }
        }
    }

    private func refreshFolderFromSidebar(_ folder: Folder, sourceID: MailSourceID?) async {
        await performFolderMutation(sourceFolderID: folder.id) {
            try await refresh(folder: folder, sourceID: sourceID)
        }
    }

    private func markFolderAsRead(_ folder: Folder, sourceID: MailSourceID?) async {
        await performFolderMutation(sourceFolderID: folder.id) {
            let unreadMessageIDs = try await unreadMessageIDs(in: folder, sourceID: sourceID)
            guard !unreadMessageIDs.isEmpty else { return }
            for messageID in unreadMessageIDs {
                navigation.updateHeader(id: messageID) { $0.isRead = true }
            }
            try await setRead(true, for: unreadMessageIDs, sourceID: sourceID)
            if navigation.selectedFolderID == folder.id,
               navigation.selectedSourceID == sourceID {
                navigation.requestReload()
            }
        }
    }

    private func performFolderMutation(
        sourceFolderID: Folder.ID,
        operation: @escaping () async throws -> Void
    ) async {
        guard canStartCommandMutation() else { return }
        let request = startCommandMutationRequest(sourceFolderID: sourceFolderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        clearRootStatus()
        do {
            try await operation()
            undoQueue.discardPendingUndo(lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            await reloadFoldersAfterSidebarMutation()
            finishCommandMutation(request)
        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleFolderMutationFailure(error)
            finishCommandMutation(request)
        }
    }

    private func importMail(_ importRequest: MailImportRequest) async {
        guard canStartCommandMutation() else { return }
        let mutationRequest = startCommandMutationRequest(sourceFolderID: navigation.selectedFolderID)
        clearRootStatus()

        do {
            let sourceID = visibleSelectedSourceID
            let targetBackend = selectedBackend
            guard let importer = targetBackend.extensionService(MailImporting.self) else {
                throw MailRootImportError.importingUnsupported
            }
            let destination = try await createFolder(
                name: uniqueImportFolderName(for: importRequest),
                parentID: nil,
                sourceID: sourceID
            )
            let summary = try await importMessages(
                from: importRequest,
                into: destination,
                using: importer
            )
            guard activeCommandMutationRequest == mutationRequest else {
                finishCommandMutation(mutationRequest)
                return
            }
            if summary.messageCount == 0 {
                throw MailRootImportError.emptySource(importRequest.url.lastPathComponent)
            }
            navigation.selectFolder(destination.id, in: navigation.selectedSourceID)
            navigation.requestReload()
            await reloadFoldersAfterSidebarMutation()
            rootStatus = MailRootStatus(
                message: importStatusMessage(
                    count: summary.messageCount,
                    destinationName: destination.name,
                    parseErrorCount: summary.parseErrors.count
                ),
                tone: summary.parseErrors.isEmpty ? .success : .warning
            )
            finishCommandMutation(mutationRequest)
        } catch {
            guard activeCommandMutationRequest == mutationRequest else {
                finishCommandMutation(mutationRequest)
                return
            }
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            rootStatus = MailRootStatus(
                message: message.isEmpty ? String(localized: "Couldn't import mail.", bundle: .module) : message,
                actionTitle: String(localized: "Refresh", bundle: .module)
            )
            shouldRetryMailboxLoad = false
            shouldRetryFolderLoad = false
            finishCommandMutation(mutationRequest)
        }
    }

    private func importMessages(
        from request: MailImportRequest,
        into folder: Folder,
        using importer: any MailImporting
    ) async throws -> MailImportStreamSummary {
        switch request.format {
        case .mbox:
            var importedCount = 0
            var importErrors: [String] = []
            let parseSummary = try await MBOXParser().parseBatches(contentsOf: request.url) { batch in
                let summary = try await importer.importMessages(batch, into: folder)
                importedCount += summary.importedCount
                importErrors.append(contentsOf: summary.errors)
            }
            return MailImportStreamSummary(
                messageCount: importedCount,
                parseErrors: parseSummary.parseErrors + importErrors,
                sourceURL: request.url
            )
        case .eml:
            let result = EMLReader().read(contentsOf: request.url)
            guard !result.messages.isEmpty else {
                return MailImportStreamSummary(
                    messageCount: 0,
                    parseErrors: result.parseErrors,
                    sourceURL: request.url
                )
            }
            let summary = try await importer.importMessages(result.messages, into: folder)
            return MailImportStreamSummary(
                messageCount: summary.importedCount,
                parseErrors: result.parseErrors + summary.errors,
                sourceURL: request.url
            )
        case .maildir:
            var importedCount = 0
            var importErrors: [String] = []
            let parseSummary = try await MaildirReader().readBatches(contentsOf: request.url) { batch in
                let summary = try await importer.importMessages(batch, into: folder)
                importedCount += summary.importedCount
                importErrors.append(contentsOf: summary.errors)
            }
            return MailImportStreamSummary(
                messageCount: importedCount,
                parseErrors: parseSummary.parseErrors + importErrors,
                sourceURL: request.url
            )
        }
    }

    private func uniqueImportFolderName(for request: MailImportRequest) -> String {
        let rawName = request.format == .maildir
            ? request.url.lastPathComponent
            : request.url.deletingPathExtension().lastPathComponent
        let sourceName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = "Imported \(sourceName.isEmpty ? "Mail" : sourceName)"
        let existingNames = Set(folders.map { $0.name.lowercased() })
        var candidate = baseName
        var suffix = 2
        while existingNames.contains(candidate.lowercased()) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func importStatusMessage(
        count: Int,
        destinationName: String,
        parseErrorCount: Int
    ) -> String {
        let noun = count == 1 ? "message" : "messages"
        guard parseErrorCount > 0 else {
            return String(localized: "Imported \(count) \(noun) into \(destinationName).", bundle: .module)
        }
        let errorNoun = parseErrorCount == 1 ? "parse warning" : "parse warnings"
        return String(
            localized: "Imported \(count) \(noun) into \(destinationName) with \(parseErrorCount) \(errorNoun).",
            bundle: .module
        )
    }

    private func reloadFoldersAfterSidebarMutation() async {
        if !sourceSections.isEmpty {
            await loadSourceSections()
        } else {
            await loadFolders()
        }
    }

    private func handleFolderMutationFailure(_ error: any Error) {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        rootStatus = MailRootStatus(
            message: message.isEmpty ? String(localized: "Couldn't update folder.", bundle: .module) : message,
            actionTitle: String(localized: "Refresh", bundle: .module)
        )
        shouldRetryMailboxLoad = false
        shouldRetryFolderLoad = false
    }

    private func visibleFolders(
        _ folders: [Folder],
        sourceID: MailSourceID?
    ) -> [Folder] {
        let effectiveVisibility = FolderSidebarPresentation.effectiveVisibility(
            capabilities: backend(for: sourceID).capabilities,
            persisted: folderVisibility
        )
        let roleVisibleFolders = FolderSidebarPresentation.visibleFolders(
            folders,
            visibility: effectiveVisibility
        )
        return FolderVisibilityPreferencesPolicy.visibleFolders(
            roleVisibleFolders,
            sourceID: sourceID,
            preferences: folderVisibilityPreferences
        )
    }

    private func visibleFolderID(
        in folders: [Folder],
        sourceID: MailSourceID?,
        currentID: Folder.ID?
    ) -> Folder.ID? {
        FolderSelectionPolicy.selectedFolderID(
            afterLoading: visibleFolders(folders, sourceID: sourceID),
            currentID: currentID
        )
    }

    private func syncSelectedFolderID(
        for folders: [Folder],
        sourceID: MailSourceID?,
        currentID: Folder.ID?
    ) {
        guard !navigation.isUnifiedInboxSelected, !navigation.isSmartViewSelected,
              !navigation.isAllAttachmentsSelected else { return }
        let selectedFolderID = visibleFolderID(
            in: folders,
            sourceID: sourceID,
            currentID: currentID
        )
        guard selectedFolderID != navigation.selectedFolderID else { return }
        navigation.currentFolderHeaders = []
        navigation.selectedMessageID = nil
        navigation.bulkSelection.removeAll()
        navigation.selectedFolderID = selectedFolderID
    }

    private func syncSelectedFolderForCurrentSource() {
        guard !navigation.isUnifiedInboxSelected, !navigation.isSmartViewSelected,
              !navigation.isAllAttachmentsSelected else { return }
        if let section = selectedSourceSection {
            syncSelectedFolderID(
                for: section.folders,
                sourceID: section.id,
                currentID: navigation.selectedFolderID
            )
        } else if !sourceSections.isEmpty {
            syncSelectedFolderID(
                for: folders,
                sourceID: navigation.selectedSourceID,
                currentID: navigation.selectedFolderID
            )
        }
    }

    @ViewBuilder
    private func sheetContent(
        for sheet: MailNavigationState.Sheet,
        onClose: (() -> Void)? = nil
    ) -> some View {
        switch sheet {
        case .themePicker:
            ThemePickerView(onClose: onClose) { newTheme in
                onChangeTheme(newTheme)
            }
            .brevTheme(theme)
        case .compose:
            let completionRequest = activeComposeCompletionRequest
            let composePresentationID = navigation.composePresentationID
            let activeBackend = selectedBackend
            let selectedSourceID = navigation.selectedSourceID
            let senderSections = visibleSourceSections.filter { $0.account.id == activeBackend.account.id }
            let senderResolution = ComposeSenderIdentity.resolution(
                from: senderSections,
                fallbackAccount: activeBackend.account,
                selectedSourceID: selectedSourceID,
                defaultSourceID: preferredDefaultSection(in: senderSections)?.id
            )
            let sourceID = senderResolution.sourceID
            let composeBackend = backend(for: sourceID)
            let recoveredDraft = newMessageRecoverySnapshot(
                accountID: composeBackend.account.id,
                sourceID: sourceID
            )
            ComposeView(
                backend: composeBackend,
                sourceID: sourceID,
                from: senderResolution.initialSender?.correspondent ?? ComposeSenderIdentity.sender(
                    account: composeBackend.account,
                    mailboxes: mailboxes,
                    activeMailboxID: activeMailboxID
                ),
                senderOptions: senderResolution.options,
                initialSenderOption: senderResolution.initialSender,
                backendForSenderSource: { sourceID in
                    backend(for: sourceID)
                },
                replyingTo: navigation.composeReplyTo,
                replyMode: navigation.composeReplyMode,
                forwardingFrom: navigation.composeForwardOf,
                prefill: navigation.composePrefill,
                recoveredDraft: recoveredDraft,
                aiBackend: aiBackend(for: composeBackend.account),
                signatureContext: signatureContextProvider?(composeBackend.account),
                composeSecurityDefaults: composeSecurityDefaultsProvider?(composeBackend.account) ?? .disabled,
                hasTrustedSigningIdentity: (trustedSigningIdentityCountProvider?(composeBackend.account) ?? 0) > 0,
                hasTrustedEncryptionIdentity: (trustedEncryptionIdentityCountProvider?(composeBackend.account) ?? 0) > 0,
                isWorkBlocked: isComposeWorkBlocked,
                onClose: onClose,
                onCompletion: { completion in
                    await handleComposeCompletion(
                        completion,
                        request: completionRequest,
                        composePresentationID: composePresentationID,
                        accountID: composeBackend.account.id,
                        sourceID: sourceID
                    )
                }
            )
            .brevTheme(theme)
        case .profiles:
            MailProfileManagementSheet(
                availableSources: sourceSections,
                customProfiles: customProfiles,
                onSave: { profiles in
                    saveMailProfiles(profiles)
                },
                onClose: onClose
            )
            .brevTheme(theme)
        case .moveTo(let messageIDs, let sourceID, let currentFolderID):
            let resolvedSourceID = sourceID ?? navigation.selectedSourceID
            let currentFolderID = currentFolderID ?? (sourceID == nil ? navigation.selectedFolderID : nil)
            MoveToSheet(
                allFolders: moveFolders(for: resolvedSourceID),
                messageIDs: messageIDs,
                currentFolderID: currentFolderID,
                sourceID: resolvedSourceID,
                onMove: { ids, folder in
                    guard let resolvedSourceID else { return }
                    try await backend(for: resolvedSourceID).move(messageIDs: ids, to: folder, sourceID: resolvedSourceID)
                    navigation.presentedSheet = nil
                },
                onClose: onClose
            )
            .brevTheme(theme)
        case .copyTo(let messageIDs, let sourceID, let currentFolderID):
            let resolvedSourceID = sourceID ?? navigation.selectedSourceID
            let currentFolderID = currentFolderID ?? (sourceID == nil ? navigation.selectedFolderID : nil)
            MoveToSheet(
                allFolders: moveFolders(for: resolvedSourceID),
                messageIDs: messageIDs,
                title: String(localized: "Copy To", bundle: .module),
                currentFolderID: currentFolderID,
                sourceID: resolvedSourceID,
                onMove: { ids, folder in
                    guard let resolvedSourceID else { return }
                    try await copy(messageIDs: ids, to: folder, sourceID: resolvedSourceID)
                    navigation.presentedSheet = nil
                },
                onClose: onClose
            )
            .brevTheme(theme)
        case .outbox:
            let activeBackend = selectedBackend
            OutboxView(
                backend: activeBackend,
                onClose: onClose
            )
            .brevTheme(theme)
            .task { await refreshOutboxCount() }
        case .mailboxAssistant:
            MailboxActionAgentSheet(
                resolve: { request in
                    try await resolveMailboxActionRequest(request)
                },
                execute: { plan, phrase in
                    try await executeMailboxAction(plan: plan, confirmationPhrase: phrase)
                },
                onClose: onClose
            )
            .brevTheme(theme)
        case .createTask(let header, let sourceID):
            let accountID = sourceID?.accountID ?? selectedBackend.account.id
            if let draft = MessageTaskDraftBuilder.draft(for: header, accountID: accountID) {
                MessageTaskSheet(
                    draft: draft,
                    create: { try await AppleReminderTaskCreator().createTask(from: $0) },
                    onClose: { onClose?() }
                )
                .brevTheme(theme)
            } else {
                MessageTaskUnavailableSheet(onClose: { onClose?() })
                    .brevTheme(theme)
            }
        case .createRule(let header, _):
            // Prefilled LOCAL rule (ADR-0032); server sync stays the separate
            // opt-in in Settings → Rules.
            LocalRuleEditorSheet(
                draft: MessageRuleDraftBuilder.draft(for: header),
                onSave: { rule in
                    // Route through the injected store (consistent with every other
                    // settings write) and notify so an open Settings → Rules window
                    // refreshes its snapshot rather than later clobbering this rule.
                    var settings = settingsStore.localRulesSettings()
                    settings.add(rule)
                    settingsStore.save(settings)
                    NotificationCenter.default.post(name: .brevLocalRulesDidChange, object: nil)
                    onClose?()
                },
                onClose: { onClose?() }
            )
            .brevTheme(theme)
        case .createMeeting(let header, let sourceID):
            // One-off local calendar event via EventKit (ADR-0007): write-only on
            // explicit action, no calendar sync/browse.
            let accountID = sourceID?.accountID ?? selectedBackend.account.id
            if let draft = MessageEventDraftBuilder.draft(
                for: header,
                accountID: accountID,
                referenceDate: Date()
            ) {
                MessageEventSheet(
                    draft: draft,
                    create: { try await AppleCalendarEventCreator().createEvent(from: $0) },
                    onClose: { onClose?() }
                )
                .brevTheme(theme)
            } else {
                MessageEventUnavailableSheet(onClose: { onClose?() })
                    .brevTheme(theme)
            }
        case .messageNote(let header, let payloadSourceID):
            if let messageID = sourceMessageID(for: header, payloadSourceID: payloadSourceID) {
                let state = localMessageWorkflowStateBinding.wrappedValue
                MessageNoteSheet(
                    header: header,
                    note: state.note(for: messageID),
                    onSave: { body in
                        localMessageWorkflowStateBinding.wrappedValue =
                            LocalMessageWorkflowStatePolicy.savingNote(
                                for: messageID,
                                body: body,
                                in: localMessageWorkflowStateBinding.wrappedValue
                            )
                    },
                    onDelete: {
                        localMessageWorkflowStateBinding.wrappedValue =
                            LocalMessageWorkflowStatePolicy.savingNote(
                                for: messageID,
                                body: "",
                                in: localMessageWorkflowStateBinding.wrappedValue
                            )
                    },
                    onClose: { onClose?() }
                )
                .brevTheme(theme)
            } else {
                EmptyView()
            }
        case .followUp(let header, let payloadSourceID):
            let existingReminder = settingsStore.followUpSettings().reminder(
                for: header.id,
                sourceID: payloadSourceID
            )
            FollowUpDatePickerView(
                header: header,
                sourceID: payloadSourceID,
                existingReminder: existingReminder,
                onConfirm: { dueAt in
                    var settings = settingsStore.followUpSettings()
                    if let existingReminder {
                        notificationCenter.cancelFollowUpReminder(existingReminder)
                    } else {
                        notificationCenter.cancelFollowUpReminder(
                            messageID: header.id,
                            sourceID: payloadSourceID
                        )
                    }
                    let reminder = FollowUpReminderPresentation.reminder(
                        for: header,
                        sourceID: payloadSourceID,
                        dueAt: dueAt
                    )
                    settings.add(reminder)
                    settingsStore.save(settings)
                    NotificationCenter.default.post(name: .brevFollowUpDidChange, object: nil)
                    Task {
                        await notificationCenter.scheduleFollowUpReminder(reminder, subject: header.subject)
                    }
                    onClose?()
                },
                onRemove: {
                    var settings = settingsStore.followUpSettings()
                    settings.remove(id: existingReminder?.id ?? "")
                    settingsStore.save(settings)
                    if let existingReminder {
                        notificationCenter.cancelFollowUpReminder(existingReminder)
                    } else {
                        notificationCenter.cancelFollowUpReminder(
                            messageID: header.id,
                            sourceID: payloadSourceID
                        )
                    }
                    NotificationCenter.default.post(name: .brevFollowUpDidChange, object: nil)
                    onClose?()
                },
                onCancel: { onClose?() }
            )
            .brevTheme(theme)
        case .messageProperties(let header):
            MessagePropertiesSheet(header: header, onClose: { onClose?() })
                .brevTheme(theme)
        case .viewSource(let header, let payloadSourceID):
            let sourceID = payloadSourceID ?? navigation.selectedSourceID
            let backend = backend(for: sourceID)
            MessageRawSourceSheet(
                header: header,
                mode: .fullSource,
                loadSource: {
                    if let sourceID {
                        return try await backend.rawSource(for: header.id, sourceID: sourceID)
                    }
                    return try await backend.rawSource(for: header.id)
                },
                onClose: { onClose?() }
            )
            .brevTheme(theme)
        case .showHeaders(let header, let payloadSourceID):
            let sourceID = payloadSourceID ?? navigation.selectedSourceID
            let backend = backend(for: sourceID)
            MessageRawSourceSheet(
                header: header,
                mode: .headersOnly,
                loadSource: {
                    if let sourceID {
                        return try await backend.rawSource(for: header.id, sourceID: sourceID)
                    }
                    return try await backend.rawSource(for: header.id)
                },
                onClose: { onClose?() }
            )
            .brevTheme(theme)
        }
    }

    private func sourceMessageID(
        for header: MessageHeader,
        payloadSourceID: MailSourceID?
    ) -> SourceMessageID? {
        let sourceID = payloadSourceID ?? navigation.selectedSourceID
        guard let sourceID else { return nil }
        return SourceMessageID(sourceID: sourceID, messageID: header.id)
    }

    private var backendAccountIDs: [BrevAccount.ID] { backends.map(\.account.id).sorted() }

    private var backendSessionIDs: [ObjectIdentifier] { backends.map(ObjectIdentifier.init) }

    private var backendTaskID: String { "\(backendSessionIDs):\(startupPhase.phase)" }

    private func loadWorkspace(supersedingActiveLoads: Bool = false) async {
        let startedAt = Date()
        await MailRootWorkspaceLoader.load(
            loadSourceSections: { await loadSourceSections(supersedingActiveLoads: supersedingActiveLoads) },
            loadMailboxes: { await loadMailboxes() },
            loadFolders: { await loadFolders() },
            sourceSectionsEmpty: { sourceSections.isEmpty },
            runInitialRetentionIfNeeded: {
                if !didRunInitialRetentionSweep {
                    didRunInitialRetentionSweep = true
                    await applyRetentionSweep()
                }
            }
        )
        advanceStartupPhaseAfterWorkspaceLoad()
        MailUIPerformanceDiagnostics.logStartupReady(
            surface: .workspace,
            usableContent: !sourceSections.isEmpty || !folders.isEmpty || !mailboxes.isEmpty,
            durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: startedAt)
        )
    }

    private func advanceStartupPhaseAfterWorkspaceLoad() {
        // Only advance on a usable local snapshot (folders or source sections).
        let hasUsableContent = !sourceSections.isEmpty || !folders.isEmpty || !mailboxes.isEmpty
        guard hasUsableContent else { return }
        if startupPhase.advance(to: .cachedUsable) {
            // Immediately allow interactive streams once cache is usable.
            _ = startupPhase.advance(to: .interactive)
            // Then open background maintenance.
            _ = startupPhase.advance(to: .background)
        }
    }

    private func startLiveChangeSubscriptionIfNeeded() async {
        await subscribeToChanges()
    }

    private func startDeferredBackendStartupWorkIfNeeded() async {
        let pending = backends.filter { !deferredStartupAccountIDs.contains(ObjectIdentifier($0)) }
        deferredStartupAccountIDs.formIntersection(backendSessionIDs)
        deferredStartupAccountIDs.formUnion(pending.map(ObjectIdentifier.init))
        MailRootDeferredStartup.startBackendWork(backends: pending)
    }

    /// Re-run the retention sweep whenever a settings surface changes the
    /// offline-retention policy. Uses the async notification sequence rather
    /// than `.onReceive` to keep the (already large) view body within the
    /// type-checker's budget.
    private func observeMailboxSyncSettingsChanges() async {
        let changes = NotificationCenter.default.notifications(
            named: .brevMailboxSyncSettingsDidChange
        ).map { _ in () }
        for await _ in changes {
            await applyRetentionSweep()
        }
    }

    private func observeImportSyncHealth() async {
        stopImportSyncHealthPolling()
        guard let sourceID = visibleSelectedSourceID else {
            importSyncHealth = nil
            return
        }
        let activeBackend = backend(for: sourceID)
        guard activeBackend.extensionService(SyncHealthReporting.self) != nil else {
            importSyncHealth = nil
            return
        }
        await refreshImportSyncHealth(sourceID: sourceID, backend: activeBackend)
        startImportSyncHealthPolling(sourceID: sourceID, backend: activeBackend)
    }

    private func refreshImportSyncHealth(
        sourceID: MailSourceID,
        backend: any MailBackend
    ) async {
        guard let reporter = backend.extensionService(SyncHealthReporting.self) else {
            importSyncHealth = nil
            return
        }
        importSyncHealth = await reporter.syncHealth(for: sourceID)
    }

    private func loadSelectedSearchSyntax() async {
        selectedSearchSyntaxDescription = nil
        guard let sourceID = visibleSelectedSourceID,
              let provider = backend(for: sourceID)
              .extensionService(ServerSearchSyntaxProviding.self)
        else {
            return
        }
        selectedSearchSyntaxDescription = try? await provider.serverSearchSyntax(for: sourceID)
    }

    private func startImportSyncHealthPolling(
        sourceID: MailSourceID,
        backend: any MailBackend
    ) {
        importSyncHealthPollingTask?.cancel()
        importSyncHealthPollingTask = Task {
            while !Task.isCancelled {
                guard let intervalNanoseconds = ImportProgressPresentation.pollingIntervalNanoseconds(
                    health: importSyncHealth
                ) else { break }
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await refreshImportSyncHealth(sourceID: sourceID, backend: backend)
            }
        }
    }

    private func stopImportSyncHealthPolling() {
        importSyncHealthPollingTask?.cancel()
        importSyncHealthPollingTask = nil
    }

    private func retryImportSync() async {
        guard let sourceID = visibleSelectedSourceID else { return }
        let activeBackend = backend(for: sourceID)
        guard let repair = activeBackend.extensionService(SyncHealthRepairing.self) else { return }
        do {
            try await repair.retrySync(for: sourceID)
            await refreshImportSyncHealth(sourceID: sourceID, backend: activeBackend)
        } catch {
            rootStatus = MailRootStatus(
                message: error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? String(localized: "Couldn't retry sync.", bundle: .module) : error.localizedDescription,
                actionTitle: String(localized: "Retry", bundle: .module)
            )
        }
    }

    /// Enforce the saved offline-retention policy across every loaded
    /// folder by pruning cached message bodies that now fall outside the
    /// window. Runs once after the first workspace load and again whenever
    /// the retention setting changes (`.brevMailboxSyncSettingsDidChange`).
    /// Backends without a local body cache no-op; folders with a cold
    /// header cache no-op (no dates to compare). Idempotent.
    @MainActor
    private func applyRetentionSweep() async {
        let settings = settingsStore.accountMailboxSyncSettings()
        let fallbackSourceID = await fallbackRetentionSourceID()
        let targets = MailRetentionSweepPlan.targets(
            sourceSections: sourceSections,
            fallbackSourceID: fallbackSourceID,
            fallbackFolders: folders,
            settings: settings
        )
        for target in targets {
            guard let backend = connectedBackend(forAccountID: target.accountID) else { continue }
            if let reporter = backend.extensionService(SyncHealthReporting.self) {
                let health = await reporter.syncHealth(for: target.sourceID)
                guard MailRetentionSweepPlan.shouldApplyRetention(syncHealth: health) else {
                    continue
                }
            }
            try? await backend.applyRetention(
                folderID: target.folderID,
                sourceID: target.sourceID,
                retentionDays: target.retentionDays,
                keepsBodies: target.keepsBodies,
                keepingMessageIDs: MessageOfflineRetentionOverrideStore()
                    .keptOfflineMessageIDs(forSource: target.sourceID)
            )
        }
    }

    private func fallbackRetentionSourceID() async -> MailSourceID? {
        if let activeMailboxID {
            return MailSourceID(accountID: selectedBackend.account.id, mailboxID: activeMailboxID)
        }
        do {
            let mailbox = try await selectedBackend.currentMailbox()
            return selectedBackend.sourceID(for: mailbox)
        } catch {
            return nil
        }
    }

    private func invalidateSourceLoading() {
        sourceLoadWorkTask?.cancel()
        sourceLoadWorkTask = nil
        sourceLoadOwnership.invalidate()
        isLoadingSources = false
        sourceLoadTimeoutTask?.cancel()
        sourceLoadTimeoutTask = nil
    }

    private func loadSourceSections(supersedingActiveLoads: Bool = false) async {
        guard !isLoadingSources || supersedingActiveLoads else { return }
        let sourceRequest = sourceLoadOwnership.begin()
        isLoadingSources = true
        sourceLoadTimeoutTask?.cancel()
        sourceLoadTimeoutTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard sourceLoadOwnership.accepts(sourceRequest), isLoadingSources else { return }
            invalidateSourceLoading()
            shouldRetryMailboxLoad = true
            shouldRetrySourceSections = true
            rootStatus = MailRootStatus(
                message: String(localized: "Some mailboxes are taking longer than expected. Available mail is still usable.",
                                bundle: .module),
                tone: .warning,
                actionTitle: String(localized: "Try Again", bundle: .module)
            )
        }
        defer {
            if sourceLoadOwnership.current == sourceRequest {
                isLoadingSources = false
                sourceLoadTimeoutTask?.cancel()
                sourceLoadTimeoutTask = nil
            }
        }
        let wasRetryingMailboxLoad = shouldRetryMailboxLoad
        var loadedSections: [MailSourceSection] = []
        var firstError: (any Error)?

        var loadResults: [Int: MailRootSourceLoadResult] = [:]
        var sectionsByAccount = Dictionary(grouping: sourceSections, by: { $0.account.id })
        let work = Task { @MainActor in
            await MailConcurrentWork.forEachResult(backends) { backend -> MailRootSourceLoadResult in
                do {
                    let mailboxes = try await backend.mailboxes()
                    let sections = await MailConcurrentWork.map(mailboxes) { mailbox in
                        let sourceID = backend.sourceID(for: mailbox)
                        do {
                            let folders = try await backend.folders(in: sourceID)
                            return MailSourceSection(
                                id: sourceID,
                                account: backend.account,
                                mailbox: mailbox,
                                folders: Self.sorted(folders)
                            )
                        } catch {
                            return MailSourceSection(
                                id: sourceID,
                                account: backend.account,
                                mailbox: mailbox,
                                folders: [],
                                loadError: FolderSidebarPresentation.loadErrorInfo(for: error)
                            )
                        }
                    }
                    return MailRootSourceLoadResult.sections(sections)
                } catch {
                    return MailRootSourceLoadResult.failure(
                        accountEmail: backend.account.emailAddress,
                        message: error.localizedDescription
                    )
                }
            } receive: { index, result in
                guard sourceLoadOwnership.accepts(sourceRequest) else { return }
                loadResults[index] = result
                if case .failure(_, let message) = result {
                    let accountID = backends[index].account.id
                    sectionsByAccount[accountID] = (sectionsByAccount[accountID] ?? []).map { section in
                        MailSourceSection(id: section.id, account: section.account, mailbox: section.mailbox,
                                          folders: section.folders,
                                          loadError: FolderSidebarPresentation
                                              .loadErrorInfo(for: MailBackendError.backendSpecific(message: message)))
                    }
                }
                if case .sections(let sections) = result {
                    let oldSections = sectionsByAccount[backends[index].account.id] ?? []
                    sectionsByAccount[backends[index].account.id] = sections.map { section in
                        guard section.loadError != nil,
                              let old = oldSections.first(where: { $0.id == section.id }) else { return section }
                        return MailSourceSection(id: section.id, account: section.account, mailbox: section.mailbox,
                                                 folders: old.folders, loadError: section.loadError)
                    }
                }
                let available = backends.flatMap { sectionsByAccount[$0.account.id] ?? [] }
                applyLoadedSourceSections(available)
                advanceStartupPhaseAfterWorkspaceLoad()
            }
        }
        sourceLoadWorkTask = work
        await work.value
        guard sourceLoadOwnership.accepts(sourceRequest) else { return }
        let loadSummary = MailRootSourceLoadPresentation.summary(for: backends.indices.compactMap { loadResults[$0] })
        loadedSections = backends.flatMap { sectionsByAccount[$0.account.id] ?? [] }
        for section in loadedSections {
            if let loadError = section.loadError {
                firstError = firstError ?? MailBackendError.backendSpecific(message: loadError.message)
            }
        }
        if let failure = loadSummary.failures.first {
            firstError = firstError ?? MailBackendError.backendSpecific(message: failure.message)
        }

        guard sourceLoadOwnership.accepts(sourceRequest) else { return }

        if loadedSections.isEmpty, let firstError {
            sourceSectionsRevision += 1
            sourceSections = []
            mailboxes = []
            activeMailboxID = nil
            folders = []
            folderLoadError = FolderSidebarPresentation.loadErrorInfo(for: firstError)
            shouldRetryMailboxLoad = true
            shouldRetrySourceSections = !loadSummary.failures.isEmpty
            rootStatus = MailboxLoadPresentation.loadErrorStatus(for: firstError)
            updateUnreadBadge()
        } else {
            applyLoadedSourceSections(loadedSections)
            shouldRetryMailboxLoad = !loadSummary.failures.isEmpty
            shouldRetrySourceSections = !loadSummary.failures.isEmpty
            shouldRetryFolderLoad = false
            if let partialFailureStatus = MailRootSourceLoadPresentation.partialFailureStatus(for: loadSummary) {
                rootStatus = partialFailureStatus
            } else if let failure = loadSummary.failures.first {
                rootStatus = MailboxLoadPresentation
                    .loadErrorStatus(for: MailBackendError.backendSpecific(message: failure.message))
            } else if wasRetryingMailboxLoad {
                rootStatus = nil
            }
        }
    }

    /// Refresh folder counts for a non-selected account without replacing the
    /// selected account's visible folder/list state.
    private func enqueueBackgroundAccountRefresh(for accountID: BrevAccount.ID) {
        pendingBackgroundAccountIDs.insert(accountID)
        guard backgroundAccountRefreshTask == nil else { return }

        nextBackgroundAccountRefreshRequestID += 1
        let requestID = nextBackgroundAccountRefreshRequestID
        activeBackgroundAccountRefreshRequestID = requestID
        backgroundAccountRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled,
                  activeBackgroundAccountRefreshRequestID == requestID
            else { return }

            let accountIDs = pendingBackgroundAccountIDs
            pendingBackgroundAccountIDs.removeAll()
            for accountID in accountIDs {
                guard !Task.isCancelled,
                      let backend = connectedBackend(forAccountID: accountID)
                else { continue }
                await refreshBackgroundAccountState(
                    for: backend,
                    requestID: requestID,
                    expectedSourceSectionsRevision: sourceSectionsRevision
                )
            }

            guard activeBackgroundAccountRefreshRequestID == requestID else { return }
            activeBackgroundAccountRefreshRequestID = nil
            backgroundAccountRefreshTask = nil
            if !pendingBackgroundAccountIDs.isEmpty {
                scheduleBackgroundAccountRefreshIfNeeded()
            }
        }
    }

    private func scheduleBackgroundAccountRefreshIfNeeded() {
        guard backgroundAccountRefreshTask == nil,
              let accountID = pendingBackgroundAccountIDs.first
        else { return }
        enqueueBackgroundAccountRefresh(for: accountID)
    }

    private func refreshBackgroundAccountState(
        for backend: any MailBackend,
        requestID: Int,
        expectedSourceSectionsRevision: Int
    ) async {
        let refreshedSections: [MailSourceSection]
        do {
            var sections: [MailSourceSection] = []
            for mailbox in try await backend.mailboxes() {
                let sourceID = backend.sourceID(for: mailbox)
                guard let folders = try? await backend.folders(in: sourceID) else { continue }
                sections.append(MailSourceSection(
                    id: sourceID,
                    account: backend.account,
                    mailbox: mailbox,
                    folders: Self.sorted(folders)
                ))
            }
            refreshedSections = sections
        } catch {
            return
        }

        guard !refreshedSections.isEmpty else { return }
        guard !Task.isCancelled else { return }
        guard activeBackgroundAccountRefreshRequestID == requestID,
              sourceSectionsRevision == expectedSourceSectionsRevision,
              activeFolderLoadRequest == nil,
              activeMailboxLoadRequest == nil,
              activeMailboxSwitchRequest == nil
        else {
            pendingBackgroundAccountIDs.insert(backend.account.id)
            return
        }
        let refreshedByID = Dictionary(refreshedSections.map { ($0.id, $0) }) { _, latest in latest }
        let existingSectionIDs = Set(sourceSections.map(\.id))
        sourceSectionsRevision += 1
        sourceSections = sourceSections.map { refreshedByID[$0.id] ?? $0 }
            + refreshedSections.filter { section in
                !existingSectionIDs.contains(section.id)
            }
        updateUnreadBadge()
    }

    private func loadFolders() async {
        guard canStartFolderLoad() else { return }
        let request = startFolderLoadRequest()
        defer { finishFolderLoad(request) }
        do {
            let result: [Folder]
            let sourceID = visibleSelectedSourceID
            if let sourceID {
                result = try await selectedBackend.folders(in: sourceID)
            } else {
                result = try await selectedBackend.folders()
            }
            guard canApplyFolderLoadResponse(request) else { return }
            if sourceID == nil {
                navigation.selectedSourceID = nil
            }
            applyLoadedFolders(result)
            updateUnreadBadge()
            finishFolderLoad(request)
        } catch {
            guard canApplyFolderLoadResponse(request) else { return }
            folderLoadError = FolderSidebarPresentation.loadErrorInfo(for: error)
            folders = []
            shouldRetryFolderLoad = false
            updateUnreadBadge()
            finishFolderLoad(request)
        }
    }

    private func canStartFolderLoad() -> Bool {
        MailRootFolderLoadStartPolicy.canStartLoad(
            activeRequest: activeFolderLoadRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest
        )
    }

    private func startFolderLoadRequest() -> MailRootFolderLoadRequest {
        invalidateSourceLoading()
        nextFolderLoadRequestID += 1
        let request = MailRootFolderLoadRequest(id: nextFolderLoadRequestID, sourceID: navigation.selectedSourceID)
        activeFolderLoadRequest = request
        return request
    }

    private func canApplyFolderLoadResponse(_ request: MailRootFolderLoadRequest) -> Bool {
        MailRootFolderLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeFolderLoadRequest,
            currentSourceID: navigation.selectedSourceID
        )
    }

    private func finishFolderLoad(_ request: MailRootFolderLoadRequest) {
        guard activeFolderLoadRequest == request else { return }
        activeFolderLoadRequest = nil
    }

    private func applyLoadedFolders(_ result: [Folder]) {
        let sortedFolders = Self.sorted(result)
        sourceSectionsRevision += 1
        folders = sortedFolders
        if let sourceID = navigation.selectedSourceID,
           let index = sourceSections.firstIndex(where: { $0.id == sourceID }) {
            let section = sourceSections[index]
            sourceSections[index] = MailSourceSection(
                id: section.id,
                account: section.account,
                mailbox: section.mailbox,
                folders: sortedFolders
            )
        }
        folderLoadError = nil
        syncSelectedFolderID(
            for: sortedFolders,
            sourceID: navigation.selectedSourceID,
            currentID: navigation.selectedFolderID
        )
        if shouldRetryFolderLoad {
            rootStatus = nil
            shouldRetryFolderLoad = false
        }
    }

    private func loadMailboxes() async {
        guard canStartMailboxLoad() else { return }
        let request = startMailboxLoadRequest()
        defer { finishMailboxLoad(request) }
        let wasRetryingMailboxLoad = shouldRetryMailboxLoad
        do {
            let all = try await selectedBackend.mailboxes()
            let active = try await selectedBackend.currentMailbox()
            guard canApplyMailboxLoadResponse(request) else { return }
            mailboxes = all
            activeMailboxID = active.id
            shouldRetryMailboxLoad = false
            if wasRetryingMailboxLoad {
                rootStatus = nil
            }
            finishMailboxLoad(request)
        } catch {
            guard canApplyMailboxLoadResponse(request) else { return }
            mailboxes = []
            activeMailboxID = nil
            mailboxSwitchRetryID = nil
            shouldRetryMailboxLoad = true
            rootStatus = MailboxLoadPresentation.loadErrorStatus(for: error)
            finishMailboxLoad(request)
        }
    }

    private func canStartMailboxLoad() -> Bool {
        MailRootMailboxLoadStartPolicy.canStartLoad(
            activeRequest: activeMailboxLoadRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest
        )
    }

    private func startMailboxLoadRequest() -> MailRootMailboxLoadRequest {
        nextMailboxLoadRequestID += 1
        let request = MailRootMailboxLoadRequest(id: nextMailboxLoadRequestID, sourceID: navigation.selectedSourceID)
        activeMailboxLoadRequest = request
        return request
    }

    private func canApplyMailboxLoadResponse(_ request: MailRootMailboxLoadRequest) -> Bool {
        MailRootMailboxLoadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeMailboxLoadRequest,
            currentSourceID: navigation.selectedSourceID
        )
    }

    private func finishMailboxLoad(_ request: MailRootMailboxLoadRequest) {
        guard activeMailboxLoadRequest == request else { return }
        activeMailboxLoadRequest = nil
    }

    /// Conventional desktop-mail folder order: Inbox first, then
    /// other system roles in a stable order, then custom folders
    /// alphabetically.
    nonisolated static func sorted(_ folders: [Folder]) -> [Folder] {
        let priority: [FolderRole: Int] = [
            .inbox: 0,
            .starred: 1,
            .snoozed: 2,
            .drafts: 3,
            .scheduled: 4,
            .sent: 5,
            .spam: 6,
            .trash: 7,
            .archive: 8,
            .allMail: 9,
            .custom: 100
        ]
        return folders.sorted { a, b in
            let pa = priority[a.role] ?? 100
            let pb = priority[b.role] ?? 100
            if pa != pb { return pa < pb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func folder(role: FolderRole) -> Folder? {
        folders.first { $0.role == role }
    }

    private func applyLoadedSourceSections(_ sections: [MailSourceSection]) {
        sourceSectionsRevision += 1
        sourceSections = sections
        presentInitialMailboxSelectionIfNeeded(for: sections)
        activeProfileID = normalizedActiveProfileID
        let visibleSections = visibleSourceSections
        navigation.reconcileReaderSources(Set(visibleSections.map(\.id)))
        if let selectedSourceID = navigation.selectedSourceID,
           let selected = visibleSections.first(where: { $0.id == selectedSourceID }) {
            applySelectedSourceSection(selected)
            return
        }

        if navigation.isUnifiedInboxSelected {
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }

        if navigation.isSmartViewSelected {
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }

        if navigation.isAllAttachmentsSelected {
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }

        guard let fallback = preferredDefaultSection(in: visibleSections) ?? visibleSections.first(where: { section in
            section.folders.contains { $0.role == .inbox }
        }) ?? visibleSections.first else {
            folders = []
            folderLoadError = nil
            mailboxes = []
            activeMailboxID = nil
            navigation.resetForMailboxSwitch()
            return
        }

        let selectedFolderID = FolderSelectionPolicy.selectedFolderID(
            afterLoading: visibleFolders(fallback.folders, sourceID: fallback.id),
            currentID: nil
        )
        navigation.resetForMailboxSwitch()
        navigation.selectedSourceID = fallback.id
        navigation.selectedFolderID = selectedFolderID
        navigation.selectedMessageID = nil
        navigation.currentFolderHeaders = []
        navigation.bulkSelection.removeAll()
        applySelectedSourceSection(fallback)
        updateUnreadBadge()
    }

    private func syncSelectedSourceState() {
        switch MailRootSelectedSourceSyncPolicy.action(
            hasMatchingSection: selectedSourceSection != nil,
            isSpecificSourceSelected: navigation.selectedSourceID != nil
        ) {
        case .applySection:
            if let selectedSourceSection {
                applySelectedSourceSection(selectedSourceSection)
            }
        case .clearStaleFolders:
            // #193: the freshly selected source (e.g. a just-added account
            // mid-restore) has no loaded section yet. Clear the previous
            // account's folders instead of letting them show through; the
            // section load re-populates via applyLoadedSourceSections.
            folders = []
            folderLoadError = nil
        case .keep:
            break
        }
    }

    private func preferredDefaultSection(in sections: [MailSourceSection]) -> MailSourceSection? {
        let preferredProviderDefault = sections.first { $0.mailbox.isPrimary }?.id
        guard let defaultSourceID = MailboxSourcePreferencesPolicy.defaultSourceID(
            availableSourceIDs: sections.map(\.id),
            preferences: mailboxSourcePreferences,
            preferredDefaultSourceID: preferredProviderDefault
        ) else {
            return nil
        }
        return sections.first { $0.id == defaultSourceID }
    }

    private func applySelectedSourceSection(_ section: MailSourceSection) {
        folders = section.folders
        folderLoadError = section.loadError
        mailboxes = visibleSourceSections
            .filter { $0.account.id == section.account.id }
            .map(\.mailbox)
        activeMailboxID = section.mailbox.id
        syncSelectedFolderID(
            for: section.folders,
            sourceID: section.id,
            currentID: navigation.selectedFolderID
        )
        updateUnreadBadge()
    }

    private func updateUnreadBadge() {
        badgeUpdater.updateBadge(
            folders: folders,
            sourceSections: visibleSourceSections,
            settings: NotificationSettings.load()
        )
    }

    private func applyMailboxSourcePreferenceUpdate() {
        activeProfileID = normalizedActiveProfileID
        applyActiveProfileSelection()
        updateUnreadBadge()
    }

    private func applyFolderVisibilityPreferenceUpdate() {
        let preferences = FolderVisibilityPreferencesStorage.load()
        cachedFolderVisibilityPreferences = preferences
        folderVisibilityPreferencesData = FolderVisibilityPreferencesStorage.encode(preferences) ?? Data()
        syncSelectedFolderForCurrentSource()
        updateUnreadBadge()
    }

    private func hideFolderFromSidebar(_ folder: Folder, sourceID: MailSourceID) {
        let next = FolderVisibilityPreferencesPolicy.settingHidden(
            true,
            folderID: folder.id,
            sourceID: sourceID,
            in: folderVisibilityPreferences
        )
        FolderVisibilityPreferencesStorage.save(next)
        cachedFolderVisibilityPreferences = next
        folderVisibilityPreferencesData = FolderVisibilityPreferencesStorage.encode(next) ?? Data()
        syncSelectedFolderForCurrentSource()
        updateUnreadBadge()
    }

    private func presentInitialMailboxSelectionIfNeeded(for sections: [MailSourceSection]) {
        switch MailRootInitialMailboxSelectionPolicy.action(
            pendingAccountID: initialMailboxSelectionAccountID,
            sourceIDs: sections.map(\.id),
            preferences: mailboxSourcePreferences
        ) {
        case .ignore:
            return
        case .present:
            isInitialMailboxSelectionPresented = true
        case .finishWithoutPresentation:
            finishInitialMailboxSelection()
        }
    }

    private func saveInitialMailboxSelection(_ selection: MailboxSourcePreferences) {
        let preferences = mergedInitialMailboxSelection(selection)
        cachedMailboxSourcePreferences = preferences
        MailboxSourcePreferencesStorage.save(preferences)
        mailboxSourcePreferencesData = MailboxSourcePreferencesStorage.encode(preferences) ?? Data()
        finishInitialMailboxSelection()
        if let defaultSourceID = preferences.defaultSourceID,
           let backend = backends.first(where: { $0.account.id == defaultSourceID.accountID }) {
            Task {
                try? await backend.switchMailbox(id: defaultSourceID.mailboxID)
            }
        }
        applyMailboxSourcePreferenceUpdate()
    }

    private func finishInitialMailboxSelection() {
        isInitialMailboxSelectionPresented = false
        guard let initialMailboxSelectionAccountID else { return }
        onFinishInitialMailboxSelection?(initialMailboxSelectionAccountID)
    }

    private func mergedInitialMailboxSelection(_ selection: MailboxSourcePreferences) -> MailboxSourcePreferences {
        guard let initialMailboxSelectionAccountID else { return selection }

        let availableSourceIDs = sourceSections.map(\.id)
        let existingEnabledSourceIDs = MailboxSourcePreferencesPolicy.enabledSourceIDs(
            availableSourceIDs: availableSourceIDs,
            preferences: mailboxSourcePreferences
        )
        .filter { $0.accountID != initialMailboxSelectionAccountID }
        let selectedSetupSourceIDs = selection.enabledSourceIDs.filter {
            $0.accountID == initialMailboxSelectionAccountID
        }

        return MailboxSourcePreferencesPolicy.normalized(
            availableSourceIDs: availableSourceIDs,
            enabledSourceIDs: existingEnabledSourceIDs + selectedSetupSourceIDs,
            defaultSourceID: selection.defaultSourceID,
            preferredDefaultSourceID: sourceSections.first { $0.mailbox.isPrimary }?.id
        )
    }

    /// Optimistic unread-count reconciliation invoked by
    /// `MessageListView` after a successful bulk mutation
    /// (mark-read, mark-unread, bulk move). Adjusts the matching
    /// folder in both the flat `folders` array and any
    /// `MailSourceSection` containing it, then refreshes the dock
    /// badge. Counts are clamped to `>= 0` and a future folder-list
    /// refresh from the backend will correct any drift
    /// (The related feature request).
    /// Performs an action requested by a standalone (detached) message window
    /// through the main window's normal command handlers, so undo, optimistic UI,
    /// and folder refresh all apply. Commands act in the active command context;
    /// the message is assumed to belong to the currently active account.
    private func handleDetachedMessageCommand(_ request: DetachedMessageCommandRequest) {
        let header = request.header
        // Act on the message's own account, not whatever the main window currently
        // has selected, so mutations hit the right backend and replies compose from
        // the right address. Resolving the source through the active context keeps
        // the existing command handlers (undo, optimistic UI, refresh) intact. For a
        // single account this is a no-op; with multiple accounts it activates the
        // message's account in the main window.
        if let sourceID = request.sourceID {
            if navigation.selectedSourceID != sourceID {
                navigation.selectedSourceID = sourceID
            }
            navigation.composeSourceID = sourceID
        }
        switch request.command {
        case .reply:
            presentReply(to: header)
        case .replyAll:
            presentReplyAll(to: header)
        case .forward:
            presentForward(of: header)
        case .toggleFlag:
            Task { await toggleStar(for: header) }
        case .archive:
            Task { await archive(header: header) }
        case .delete:
            Task { await trash(header: header) }
        case .move:
            navigation.presentedSheet = .moveTo(
                messageIDs: [header.id],
                sourceID: request.sourceID,
                currentFolderID: header.folderID
            )
        case .setJunk:
            let isInSpam = folders.first { $0.id == header.folderID }?.role == .spam
            Task { await setJunk(!isInSpam, for: header) }
        }
    }

    private func openMessageInNewWindow(_ header: MessageHeader) {
        #if os(macOS)
        DetachedMessageWindow.open(
            header: header,
            backend: selectedBackend,
            sourceID: navigation.selectedSourceID,
            allFolders: folders,
            theme: theme
        )
        #endif
    }

    private func applyUnreadCountChange(folderID: Folder.ID, delta: Int) {
        let nextFolders = unreadCountReconciler.apply(folderID: folderID, delta: delta, to: folders)
        guard nextFolders != folders else { return }
        folders = nextFolders
        if let index = sourceSections.firstIndex(where: { $0.folders.contains { $0.id == folderID } }) {
            let section = sourceSections[index]
            let updatedSectionFolders = unreadCountReconciler.apply(
                folderID: folderID,
                delta: delta,
                to: section.folders
            )
            guard updatedSectionFolders != section.folders else { return }
            sourceSections[index] = MailSourceSection(
                id: section.id,
                account: section.account,
                mailbox: section.mailbox,
                folders: updatedSectionFolders,
                loadError: section.loadError
            )
        }
        updateUnreadBadge()
    }

    private func selectMailProfile(_ profileID: MailProfile.ID) {
        activeProfileID = MailProfileSelectionPolicy.selectedProfileID(profileID, profiles: profiles)
        applyActiveProfileSelection()
    }

    private func saveMailProfiles(_ profiles: [MailProfile]) {
        let normalizedProfiles = MailProfileSelectionPolicy.normalizedCustomProfiles(
            profiles,
            availableSourceIDs: enabledSourceSections.map(\.id)
        )
        customProfileStorage = MailProfileStorage.encode(normalizedProfiles)
        activeProfileID = normalizedActiveProfileID
        applyActiveProfileSelection()
    }

    private func applyActiveProfileSelection() {
        let visibleSections = visibleSourceSections
        navigation.reconcileReaderSources(Set(visibleSections.map(\.id)))
        if let selectedSourceID = navigation.selectedSourceID,
           let selected = visibleSections.first(where: { $0.id == selectedSourceID }) {
            applySelectedSourceSection(selected)
            return
        }
        if navigation.isSmartViewSelected {
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }
        if navigation.isAllAttachmentsSelected {
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }
        let inboxSections = visibleSections.filter { $0.folders.contains { $0.role == .inbox } }
        if inboxSections.count > 1 {
            navigation.selectUnifiedInbox()
            folders = []
            folderLoadError = nil
            mailboxes = visibleSections.map(\.mailbox)
            activeMailboxID = nil
            return
        }
        guard let fallback = preferredDefaultSection(in: inboxSections)
            ?? preferredDefaultSection(in: visibleSections)
            ?? inboxSections.first
            ?? visibleSections.first
        else {
            folders = []
            folderLoadError = nil
            mailboxes = []
            activeMailboxID = nil
            navigation.resetForMailboxSwitch()
            return
        }
        let selectedFolderID = FolderSelectionPolicy.selectedFolderID(
            afterLoading: visibleFolders(fallback.folders, sourceID: fallback.id),
            currentID: nil
        )
        navigation.resetForMailboxSwitch()
        navigation.selectedSourceID = fallback.id
        navigation.selectedFolderID = selectedFolderID
        navigation.selectedMessageID = nil
        navigation.currentFolderHeaders = []
        navigation.bulkSelection.removeAll()
        applySelectedSourceSection(fallback)
    }

    private func retryRootStatusAction() async {
        switch MailRootStatusRetryAction.next(
            mailboxSwitchRetryID: mailboxSwitchRetryID,
            shouldRetryMailboxLoad: shouldRetryMailboxLoad,
            shouldRetryFolderLoad: shouldRetryFolderLoad,
            isUnifiedInbox: navigation.isUnifiedInboxSelected
        ) {
        case .refreshSelectedFolder:
            await refreshSelectedFolder()
        case .refreshVisibleMail:
            await refreshVisibleMail()
        case .loadFolders:
            clearRootStatus()
            await loadFolders()
        case .loadMailboxes:
            let shouldRetryAllSourceSections = shouldRetrySourceSections
            clearRootStatus()
            if shouldRetryAllSourceSections {
                await loadSourceSections(supersedingActiveLoads: true)
            } else {
                await loadMailboxes()
            }
        case .switchMailbox(let mailboxSwitchRetryID):
            await switchMailbox(to: mailboxSwitchRetryID)
        }
    }

    private func clearRootStatus() {
        rootStatus = nil
        mailboxSwitchRetryID = nil
        shouldRetryMailboxLoad = false
        shouldRetrySourceSections = false
        shouldRetryFolderLoad = false
    }

    private func applyComposeCompletionFeedback(_ feedback: ComposeCompletionFeedback?) {
        switch feedback {
        case .topStatus(let status):
            clearEphemeralToast()
            rootStatus = status
        case .toast(let message, let tone):
            presentEphemeralToast(MailRootEphemeralToast(message: message, tone: tone))
        case nil:
            break
        }
    }

    private func presentEphemeralToast(_ toast: MailRootEphemeralToast) {
        ephemeralToastDismissTask?.cancel()
        ephemeralToast = toast
        let toastID = toast.id
        ephemeralToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, ephemeralToast?.id == toastID else { return }
            ephemeralToast = nil
        }
    }

    private func clearEphemeralToast() {
        ephemeralToastDismissTask?.cancel()
        ephemeralToastDismissTask = nil
        ephemeralToast = nil
    }

    /// Apply persisted avatar preferences to the shared resolver on
    /// launch. External sources default off per ADR-0006.
    private func bootstrapAvatarPreferences() async {
        await AvatarResolver.shared.updatePreferences(
            AvatarPreferencesBootstrap.preferences()
        )
    }

    /// Register the notification delegate, install the new-mail
    /// category, and wire the action closures to the primary backend.
    /// Re-runs on view recreation but the delegate identity is stable
    /// (held in `@State`).
    ///
    /// If the app delegate installed a `BrevNotificationDelegate` at
    /// launch (to reduce the early-notification delivery window), this
    /// method reuses that instance instead of replacing it.
    private func setupNotifications() async {
        // Prefer a delegate the app shell registered at launch; fall back to
        // the view-owned @State instance so the view is fully self-contained.
        // The canUseSystemNotificationCenterInCurrentProcess guard is required
        // before any call to UNUserNotificationCenter.current() — the SPM test
        // runner crashes otherwise (bundleProxyForCurrentProcess is nil).
        let activeDelegate: BrevNotificationDelegate
        if BrevLocalNotificationCenter.canUseSystemNotificationCenterInCurrentProcess,
           let existing = UNUserNotificationCenter.current().delegate as? BrevNotificationDelegate {
            activeDelegate = existing
        } else {
            activeDelegate = notificationDelegate
            if BrevLocalNotificationCenter.canUseSystemNotificationCenterInCurrentProcess {
                UNUserNotificationCenter.current().delegate = activeDelegate
            }
        }

        notificationCenter.setupNotificationCategories()
        await notificationCenter.currentAuthorizationStatus()
        await notificationCenter.cancelInactiveFollowUpReminders(
            settings: settingsStore.followUpSettings()
        )

        activeDelegate.onOpen = { route in
            Task { @MainActor in
                openNotificationRoute(route)
            }
        }
        activeDelegate.onMarkRead = { route in
            Task { @MainActor in
                // Fail closed: only act on the exact account the notification
                // targets. Falling back to the current account would mark a
                // DIFFERENT message read after the source account was signed out,
                // removed, or before it restored.
                guard let routeBackend = connectedBackend(forAccountID: route.accountID) else { return }
                try? await routeBackend.setRead(true, for: [route.messageID])
            }
        }
        activeDelegate.onArchive = { route in
            Task { @MainActor in
                // Fail closed — archiving the wrong account's message is
                // destructive (see onMarkRead).
                guard let routeBackend = connectedBackend(forAccountID: route.accountID) else { return }
                guard let archiveFolder = await Self.archiveFolder(for: routeBackend) else { return }
                try? await routeBackend.move(messageIDs: [route.messageID], to: archiveFolder)
            }
        }
        activeDelegate.onReply = { route, userText in
            await sendInlineNotificationReply(userText, route: route)
        }
    }

    private static func archiveFolder(for backend: any MailBackend) async -> Folder? {
        let folders: [Folder]
        do {
            folders = try await backend.folders()
        } catch {
            return nil
        }
        return folders.first { $0.role == .archive }
    }

    /// The connected backend for `accountID`, or nil when that account is not
    /// currently connected. Deliberately has NO fallback to the active backend:
    /// notification actions must never act on a different account than the one
    /// the notification targeted.
    private func connectedBackend(forAccountID accountID: String) -> (any MailBackend)? {
        backends.first { $0.account.id == accountID }
    }

    /// Persist and send the text entered directly in a new-mail notification.
    ///
    /// Header resolution is cache-only: the refresh that posted the
    /// notification has already warmed the provider's header cache, and a miss
    /// must fail closed instead of guessing the sender or threading metadata.
    private func sendInlineNotificationReply(
        _ userText: String,
        route: NotificationMailRoute
    ) async {
        guard let routeBackend = connectedBackend(forAccountID: route.accountID) else {
            await notificationCenter.postReplyFailureNotification(
                route: route,
                draftWasSaved: false
            )
            return
        }

        guard routeBackend.capabilities.contains(.smtpOAuth),
              routeBackend.extendedCapabilities.contains(.cachedMessageHeaders)
        else {
            await notificationCenter.postReplyFailureNotification(
                route: route,
                draftWasSaved: false
            )
            return
        }

        let sourceID: MailSourceID?
        if let routedSourceID = route.sourceID {
            guard routedSourceID.accountID == route.accountID else {
                await notificationCenter.postReplyFailureNotification(
                    route: route,
                    draftWasSaved: false
                )
                return
            }
            sourceID = routedSourceID
        } else {
            sourceID = nil
        }

        let header = await routeBackend
            .extensionService(CachedMessageHeaderProviding.self)?
            .cachedMessageHeader(
                messageID: route.messageID,
                folderID: route.folderID
            )
        let securityDefaults = composeSecurityDefaultsProvider?(routeBackend.account) ?? .disabled
        let securityMode = OutboundMessageSecurityMode(
            signing: securityDefaults.shouldSignByDefault,
            encrypting: securityDefaults.shouldEncryptByDefault
        )
        let signatureBody = signatureContextProvider?(routeBackend.account)
            .selectedSignature?.body

        guard let header,
              let draft = NotificationInlineReplyComposer.draft(
                  id: UUID().uuidString,
                  userText: userText,
                  header: header,
                  accountEmail: routeBackend.account.emailAddress,
                  signatureBody: signatureBody,
                  securityMode: securityMode
              )
        else {
            await notificationCenter.postReplyFailureNotification(
                route: route,
                draftWasSaved: false
            )
            return
        }

        let outcome = await NotificationInlineReplyPipeline.deliver(
            draft: draft,
            save: { draft in
                if let sourceID {
                    return try await routeBackend.save(draft: draft, sourceID: sourceID)
                }
                return try await routeBackend.save(draft: draft)
            },
            send: { draft in
                if let sourceID {
                    _ = try await routeBackend.send(draft: draft, sourceID: sourceID)
                } else {
                    _ = try await routeBackend.send(draft: draft)
                }
            }
        )
        if case .failed(let draftWasSaved) = outcome {
            await notificationCenter.postReplyFailureNotification(
                route: route,
                draftWasSaved: draftWasSaved
            )
        }
    }

    private func openNotificationRoute(_ route: NotificationMailRoute) {
        let matchingSection = visibleSourceSections.first { section in
            section.account.id == route.accountID
                && section.folders.contains { $0.id == route.folderID }
        }
        let routeFolders: [Folder]
        if let matchingSection {
            routeFolders = matchingSection.folders
        } else if selectedBackend.account.id == route.accountID {
            routeFolders = folders
        } else {
            routeFolders = []
        }

        let visibleHeaders = notificationRouteVisibleHeaders(
            route: route,
            matchingSection: matchingSection
        )
        let decision = NotificationRoutingPolicy.navigationDecision(
            for: route,
            folders: routeFolders,
            visibleHeaders: visibleHeaders
        )
        navigation.bulkSelection.removeAll()
        navigation.searchText = ""
        navigation.presentedSheet = nil
        switch decision {
        case .message(let folderID, let messageID):
            if let matchingSection {
                navigation.selectFolder(folderID, in: matchingSection.id)
            } else {
                navigation.selectFolder(folderID, in: nil)
                navigation.currentFolderHeaders = []
            }
            navigation.selectedMessageID = messageID
        case .folder(let folderID):
            if let matchingSection {
                navigation.selectFolder(folderID, in: matchingSection.id)
            } else {
                navigation.selectFolder(folderID, in: nil)
                navigation.selectedMessageID = nil
                navigation.currentFolderHeaders = []
            }
        case .unifiedInbox:
            navigation.selectUnifiedInbox()
        }
    }

    private func notificationRouteVisibleHeaders(
        route: NotificationMailRoute,
        matchingSection: MailSourceSection?
    ) -> [MessageHeader] {
        if let matchingSection {
            guard navigation.selectedSourceID == matchingSection.id,
                  navigation.selectedFolderID == route.folderID
            else { return [] }
            return navigation.currentFolderHeaders
        }

        guard navigation.selectedSourceID == nil,
              selectedBackend.account.id == route.accountID,
              navigation.selectedFolderID == route.folderID
        else { return [] }
        return navigation.currentFolderHeaders
    }

    private func toggleStar(for header: MessageHeader) async {
        guard canStartCommandMutation() else { return }
        let newValue = !header.isFlagged
        let originalValue = header.isFlagged
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        let capturedMessageIDs = [header.id]
        let capturedBackend = selectedBackend
        let capturedSourceID = navigation.selectedSourceID
        clearRootStatus()
        navigation.updateHeader(id: header.id) { $0.isFlagged = newValue }
        do {
            try await setFlagged(newValue, for: [header.id])
            let description = MailFlagUndo.description(.flagged, value: newValue)
            undoQueue.push(UndoableMutation(description: description) {
                if let sourceID = capturedSourceID {
                    try await capturedBackend.setFlagged(
                        originalValue,
                        for: capturedMessageIDs,
                        sourceID: sourceID
                    )
                } else {
                    try await capturedBackend.setFlagged(originalValue, for: capturedMessageIDs)
                }
            }, lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.updated(header))
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func toggleRead(for header: MessageHeader) async {
        guard canStartCommandMutation() else { return }
        let newValue = !header.isRead
        let originalValue = header.isRead
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        let capturedMessageIDs = [header.id]
        let capturedBackend = selectedBackend
        let capturedSourceID = navigation.selectedSourceID
        clearRootStatus()
        navigation.updateHeader(id: header.id) { $0.isRead = newValue }
        do {
            try await setRead(newValue, for: [header.id])
            let description = MailFlagUndo.description(.read, value: newValue)
            undoQueue.push(UndoableMutation(description: description) {
                if let sourceID = capturedSourceID {
                    try await capturedBackend.setRead(
                        originalValue,
                        for: capturedMessageIDs,
                        sourceID: sourceID
                    )
                } else {
                    try await capturedBackend.setRead(originalValue, for: capturedMessageIDs)
                }
            }, lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.updated(header))
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func archive(header: MessageHeader) async {
        guard canStartCommandMutation(),
              let archive = folder(role: .archive), header.folderID != archive.id else { return }
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        // Capture original folder for undo before mutating navigation state.
        let originalFolder = folders.first { $0.id == header.folderID }
            ?? Folder(id: header.folderID, name: header.folderID, role: .custom)
        clearRootStatus()
        navigation.removeHeaders(ids: [header.id])
        do {
            let receipt = try await moveWithUndo(messageIDs: [header.id], from: originalFolder, to: archive)
            undoQueue.registerMoves([receipt], description: String(localized: "Archived", bundle: .module), lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.removed(header))
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func move(header: MessageHeader, to destination: Folder) async {
        guard header.folderID != destination.id, canStartCommandMutation() else { return }
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        let originalFolder = folders.first { $0.id == header.folderID }
            ?? Folder(id: header.folderID, name: header.folderID, role: .custom)
        clearRootStatus()
        navigation.removeHeaders(ids: [header.id])
        do {
            let receipt = try await moveWithUndo(messageIDs: [header.id], from: originalFolder, to: destination)
            undoQueue.registerMoves(
                [receipt],
                description: String(localized: "Moved to \(destination.name)", bundle: .module),
                lease: undoLease
            )
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.removed(header))
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func setJunk(_ isJunk: Bool, for header: MessageHeader) async {
        guard canStartCommandMutation() else { return }
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        let capturedBackend = selectedBackend
        let capturedSourceID = navigation.selectedSourceID
        clearRootStatus()
        navigation.removeHeaders(ids: [header.id])
        do {
            let source: MailSourceID
            if let capturedSourceID {
                source = capturedSourceID
            } else {
                source = try await capturedBackend.sourceID(for: capturedBackend.currentMailbox())
            }
            let action = try await MailJunkUndo.perform(isJunk, header: header, folders: folders,
                                                        sourceID: source, backend: capturedBackend, lease: undoLease)
            undoQueue.registerBatch([action], description: MailJunkUndo.description(isJunk), lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.removed(header))
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func trash(header: MessageHeader) async {
        guard canStartCommandMutation() else { return }
        let request = startCommandMutationRequest(sourceFolderID: header.folderID)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        // Capture the original folder so we can move back on undo.
        // If the message is already in Trash, a permanent delete is implied
        // and we don't offer undo (the backend's `delete` is irreversible).
        let originalFolder = folders.first { $0.id == header.folderID }
            ?? Folder(id: header.folderID, name: header.folderID, role: .custom)
        let capturedBackend = selectedBackend
        let capturedSourceID = navigation.selectedSourceID
        clearRootStatus()
        navigation.removeHeaders(ids: [header.id])
        switch MessageDeletionOperation.operation(for: header) {
        case .delete(let messageIDs):
            do {
                let source: MailSourceID
                if let capturedSourceID {
                    source = capturedSourceID
                } else {
                    source = try await capturedBackend.sourceID(for: capturedBackend.currentMailbox())
                }
                let receipt = try await MailUndoableDelete.perform(
                    messageIDs: messageIDs, from: originalFolder, folders: folders, sourceID: source, backend: capturedBackend
                )
                undoQueue.registerMoves([receipt], description: String(localized: "Deleted", bundle: .module), lease: undoLease)
                guard canApplyCommandMutationResponse(request) else {
                    finishCommandMutation(request)
                    return
                }
                navigation.requestReloadIfVisibleFolderChanged(MessageCommandRefreshPolicy.removed(header))
                await loadFolders()
                finishCommandMutation(request)
            } catch {
                guard canApplyCommandMutationResponse(request) else {
                    finishCommandMutation(request)
                    return
                }
                handleCommandMutationFailure(error, rollback: rollback)
                finishCommandMutation(request)
            }
        }
    }

    private func refreshSelectedFolder() async {
        guard canStartRefresh(),
              let selectedFolder else { return }
        let request = startRefreshRequest(folderID: selectedFolder.id, mailboxID: activeMailboxID)
        clearRootStatus()
        do {
            try await refresh(folder: selectedFolder)
            guard canApplyRefreshResponse(request) else {
                finishRefresh(request)
                return
            }
            navigation.requestReload()
            await loadFolders()
            finishRefresh(request)
        } catch {
            guard canApplyRefreshResponse(request) else {
                finishRefresh(request)
                return
            }
            rootStatus = MailRefreshPresentation.refreshErrorStatus(for: error)
            finishRefresh(request)
        }
    }

    private func refreshVisibleMail() async {
        switch visibleRefreshTarget {
        case .selectedFolder:
            await refreshSelectedFolder()
        case .unifiedInbox:
            await refreshUnifiedInbox()
        case nil:
            return
        }
    }

    private func refreshUnifiedInbox() async {
        guard canStartRefresh() else { return }
        let request = startRefreshRequest(
            folderID: MailNavigationState.unifiedInboxFolderID,
            mailboxID: activeMailboxID
        )
        clearRootStatus()
        // Discover sources before selecting targets so an account omitted by
        // an earlier mailbox-load failure can participate on this very refresh.
        // Superseding prevents a stale event-driven metadata response from
        // overwriting the recovery result.
        await loadSourceSections(supersedingActiveLoads: true)
        guard canApplyRefreshResponse(request) else {
            finishRefresh(request)
            return
        }
        let failureMessage = await MailFetchScheduler.performVisibleInboxRefresh(
            backends: backends,
            sourceSections: enabledSourceSections
        )
        guard canApplyRefreshResponse(request) else {
            finishRefresh(request)
            return
        }
        navigation.requestReload()
        // Rebuild every source after refresh so a mailbox whose earlier folder
        // fetch failed can rejoin Unified Inbox as soon as connectivity returns.
        // This load intentionally supersedes an event-driven metadata request
        // emitted while another source was still refreshing.
        await loadSourceSections(supersedingActiveLoads: true)
        guard canApplyRefreshResponse(request) else {
            finishRefresh(request)
            return
        }
        if let failureMessage {
            rootStatus = MailRefreshPresentation.refreshErrorStatus(
                for: MailBackendError.backendSpecific(message: failureMessage)
            )
        }
        finishRefresh(request)
    }

    /// Runs the periodic automatic-fetch loop for the current `fetchIntervalRaw`.
    ///
    /// The task is restarted (via `.task(id: fetchIntervalRaw)`) whenever
    /// the user changes the fetch interval in settings. When the interval is
    /// manual-only the stream finishes immediately without refreshing.
    private func runPeriodicFetchScheduler() async {
        let interval = FetchInterval(rawValue: fetchIntervalRaw) ?? .manual
        for await _ in MailFetchScheduler.ticks(every: interval.intervalSeconds) {
            guard !Task.isCancelled else { break }
            await refreshVisibleMail()
        }
    }

    private func refreshOutboxCount() async {
        guard let manager = backend.extensionService(OutboxManaging.self) else { return }
        let mutations = await manager.pendingMutations()
        outboxPendingCount = mutations.count
    }

    private func switchMailbox(to id: Mailbox.ID) async {
        guard canStartMailboxSwitch(to: id) else { return }
        let request = startMailboxSwitchRequest(mailboxID: id)
        let rollback = MailboxSwitchRollback(activeMailboxID: activeMailboxID)
        clearRootStatus()
        activeCommandMutationRequest = nil
        activeMailboxLoadRequest = nil
        activeRefreshRequest = nil
        activeComposeCompletionRequest = nil
        activeMailboxID = id
        do {
            try await selectedBackend.switchMailbox(id: id)
            guard canApplyMailboxSwitchResponse(request) else {
                finishMailboxSwitch(request)
                return
            }
            applyMailboxSwitch(to: id)
            finishMailboxSwitch(request)
            await loadFolders()
        } catch {
            guard canApplyMailboxSwitchResponse(request) else {
                finishMailboxSwitch(request)
                return
            }
            activeMailboxID = rollback.restore()
            rootStatus = MailboxSwitchPresentation.switchErrorStatus(for: error)
            mailboxSwitchRetryID = id
            shouldRetryMailboxLoad = false
            finishMailboxSwitch(request)
        }
    }

    private func canStartMailboxSwitch(to id: Mailbox.ID) -> Bool {
        MailRootMailboxSwitchStartPolicy.canStartSwitch(
            requestedMailboxID: id,
            activeMailboxID: activeMailboxID,
            activeRequest: activeMailboxSwitchRequest,
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeCommandMutationRequest: activeCommandMutationRequest,
            activeComposeCompletionRequest: activeComposeCompletionRequest
        )
    }

    private func handleComposeCompletion(
        _ completion: ComposeCompletion,
        request: MailRootComposeCompletionRequest?,
        composePresentationID: Int,
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?
    ) async {
        guard let request = MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: request,
            activeRequest: activeComposeCompletionRequest,
            capturedComposePresentationID: composePresentationID
        ) else {
            return
        }
        guard canApplyComposeCompletionResponse(request) else {
            finishComposeCompletion(request)
            return
        }
        for event in ComposeCompletionRefreshPolicy.events(for: completion, folders: folders) {
            navigation.requestReloadIfVisibleFolderChanged(event)
        }
        updateComposeDraftRecovery(
            for: completion,
            accountID: accountID,
            sourceID: sourceID
        )
        applyComposeCompletionFeedback(ComposeCompletionPresentation.feedback(for: completion))
        finishComposeCompletion(request)
        // Refresh the folder list/counts in the background. Awaiting it here kept
        // the composer open and "sending" until a slow or blocked mailbox refresh
        // returned after a successful LIST/STATUS-like round trip, which looked
        // exactly like a stuck send window. The send already succeeded; the refresh must
        // not gate closing the composer.
        Task { await loadFolders() }
    }

    private func newMessageRecoverySnapshot(
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?
    ) -> ComposeDraftRecoverySnapshot? {
        guard navigation.composeReplyTo == nil,
              navigation.composeForwardOf == nil else {
            return nil
        }
        return ComposeDraftRecoveryStore.load(accountID: accountID, sourceID: sourceID)
    }

    private func updateComposeDraftRecovery(
        for completion: ComposeCompletion,
        accountID: BrevAccount.ID,
        sourceID: MailSourceID?
    ) {
        BrevMail.updateComposeDraftRecovery(
            for: completion,
            accountID: accountID,
            sourceID: sourceID
        )
    }

    /// Routes from an attachment search result to its message by selecting the
    /// owning source/folder and the message. The attachment's bytes are opened
    /// via the reader's existing download action, not a new network path.
    private func openAttachmentRoute(_ route: AttachmentSearchRoute) {
        navigation.selectFolder(route.folderID, in: route.sourceID)
        navigation.selectedMessageID = route.messageID
    }

    private func openMailContextMessage(_ item: SenderContextRecentItem) {
        if let sourceID = item.sourceID ?? navigation.selectedSourceID {
            navigation.selectFolder(item.folderID, in: sourceID)
        } else {
            navigation.selectFolder(item.folderID, in: nil)
            navigation.currentFolderHeaders = []
        }
        navigation.selectedMessageID = item.id
        navigation.bulkSelection.removeAll()
    }

    private func showAllMailFromSender(_ email: String) {
        navigation.showAllMailFromSender(email)
    }

    private func handleMessageListMutation(_ event: MailEvent) async {
        navigation.requestReloadIfVisibleFolderChanged(event)
        pendingBackendEventRefresh.record(
            event,
            requiresSourceSectionsRefresh: navigation.isUnifiedInboxSelected
                || navigation.isSmartViewSelected
                || navigation.selectedSourceID == nil
        )
        scheduleBackendEventRefreshIfNeeded()
    }

    private func handleDroppedMessages(
        messageIDs: [MessageHeader.ID],
        sourceID: MailSourceID? = nil,
        sourceFolder: Folder?,
        to destinationFolder: Folder
    ) async {
        let events = FolderDropRefreshPolicy.events(
            messageIDs: messageIDs,
            from: sourceFolder,
            to: destinationFolder
        )
        guard !events.isEmpty, let sourceFolder else { return }
        guard canStartCommandMutation() else { return }
        let ownerSourceID = sourceID ?? navigation.selectedSourceID
        let owner = ownerSourceID.map { backend(for: $0) } ?? selectedBackend
        let request = startCommandMutationRequest(sourceFolderID: sourceFolder.id)
        let undoLease = undoQueue.beginMutation(navigation: navigation)
        defer { undoQueue.endMutation(undoLease) }
        let rollback = MessageCommandMutationRollback(navigation: navigation)
        clearRootStatus()
        navigation.removeHeaders(ids: Set(messageIDs))
        do {
            let source: MailSourceID
            if let ownerSourceID {
                source = ownerSourceID
            } else {
                source = try await owner.sourceID(for: owner.currentMailbox())
            }
            let receipt = try await owner.moveWithUndo(
                messageIDs: messageIDs, from: sourceFolder, to: destinationFolder, sourceID: source
            )
            undoQueue.registerMoves([receipt], description: String(localized: "Moved", bundle: .module), lease: undoLease)
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            for event in events {
                navigation.requestReloadIfVisibleFolderChanged(event)
            }
            await loadFolders()
            finishCommandMutation(request)

        } catch {
            guard canApplyCommandMutationResponse(request) else {
                finishCommandMutation(request)
                return
            }
            handleCommandMutationFailure(error, rollback: rollback)
            finishCommandMutation(request)
        }
    }

    private func setRead(
        _ isRead: Bool,
        for messageIDs: [String],
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            try await backend(for: sourceID).setRead(isRead, for: messageIDs, sourceID: sourceID)
        } else {
            try await selectedBackend.setRead(isRead, for: messageIDs)
        }
    }

    private func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        if let sourceID = navigation.selectedSourceID {
            try await selectedBackend.setFlagged(isFlagged, for: messageIDs, sourceID: sourceID)
        } else {
            try await selectedBackend.setFlagged(isFlagged, for: messageIDs)
        }
    }

    private func moveWithUndo(messageIDs: [String], from sourceFolder: Folder,
                              to destination: Folder) async throws -> MailMoveUndo? {
        let owner = selectedBackend
        let source: MailSourceID
        if let selected = navigation.selectedSourceID {
            source = selected
        } else {
            source = try await owner.sourceID(for: owner.currentMailbox())
        }
        return try await owner.moveWithUndo(messageIDs: messageIDs, from: sourceFolder, to: destination, sourceID: source)
    }

    private func copy(
        messageIDs: [String],
        to folder: Folder,
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            try await backend(for: sourceID).copy(messageIDs: messageIDs, to: folder, sourceID: sourceID)
        } else {
            try await selectedBackend.copy(messageIDs: messageIDs, to: folder)
        }
    }

    private func unreadMessageIDs(
        in folder: Folder,
        sourceID: MailSourceID?
    ) async throws -> [String] {
        var pageToken: String?
        var unreadIDs: [String] = []

        repeat {
            let page = try await messages(in: folder, sourceID: sourceID, pageToken: pageToken)
            unreadIDs.append(contentsOf: page.headers.filter { !$0.isRead }.map(\.id))
            pageToken = page.nextPageToken
        } while pageToken != nil

        return unreadIDs
    }

    private func messages(
        in folder: Folder,
        sourceID: MailSourceID?,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        if let sourceID {
            return try await backend(for: sourceID).messages(in: folder, sourceID: sourceID, pageToken: pageToken)
        }
        return try await selectedBackend.messages(in: folder, pageToken: pageToken)
    }

    private func delete(messageIDs: [String]) async throws {
        if let sourceID = navigation.selectedSourceID {
            try await selectedBackend.delete(messageIDs: messageIDs, sourceID: sourceID)
        } else {
            try await selectedBackend.delete(messageIDs: messageIDs)
        }
    }

    private func resolveMailboxActionRequest(
        _ request: String
    ) async throws -> MailboxActionAgentPlanningResult {
        let sourceID = navigation.selectedSourceID
        return try await MailboxActionAgentRequestResolver().resolve(
            request: request,
            folders: mailboxActionFolders(for: sourceID),
            focusedFolder: selectedFolder,
            sourceID: sourceID,
            sourceScope: mailboxActionSourceScope(for: sourceID)
        ) { query, sourceID in
            if let sourceID {
                return try await backend(for: sourceID).search(query, sourceID: sourceID)
            }
            return try await selectedBackend.search(query)
        }
    }

    private func executeMailboxAction(
        plan: MailboxActionAgentPlan,
        confirmationPhrase: String? = nil
    ) async throws -> String {
        if let confirmationPhrase {
            let confirmation = MailboxActionAgentConfirmation(
                planID: plan.id,
                phrase: confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard plan.authorization(with: confirmation) == .authorized else {
                throw MailboxActionAgentExecutionError.confirmationRequired(
                    plan.confirmationChallenge.requiredPhrase
                )
            }
        }

        guard !plan.matchingMessageIDs.isEmpty else {
            return MailboxActionAgentCompletionPresentation.message(for: plan)
        }

        let sourceID = plan.sourceID
        let backend = backend(for: sourceID)
        switch plan.operation {
        case .delete:
            if let sourceID {
                try await backend.delete(messageIDs: plan.matchingMessageIDs, sourceID: sourceID)
            } else {
                try await backend.delete(messageIDs: plan.matchingMessageIDs)
            }
        case .move(let folder), .archive(let folder):
            if let sourceID {
                try await backend.move(messageIDs: plan.matchingMessageIDs, to: folder, sourceID: sourceID)
            } else {
                try await backend.move(messageIDs: plan.matchingMessageIDs, to: folder)
            }
        case .markRead:
            if let sourceID {
                try await backend.setRead(true, for: plan.matchingMessageIDs, sourceID: sourceID)
            } else {
                try await backend.setRead(true, for: plan.matchingMessageIDs)
            }
        case .markUnread:
            if let sourceID {
                try await backend.setRead(false, for: plan.matchingMessageIDs, sourceID: sourceID)
            } else {
                try await backend.setRead(false, for: plan.matchingMessageIDs)
            }
        case .flag:
            if let sourceID {
                try await backend.setFlagged(true, for: plan.matchingMessageIDs, sourceID: sourceID)
            } else {
                try await backend.setFlagged(true, for: plan.matchingMessageIDs)
            }
        case .unflag:
            if let sourceID {
                try await backend.setFlagged(false, for: plan.matchingMessageIDs, sourceID: sourceID)
            } else {
                try await backend.setFlagged(false, for: plan.matchingMessageIDs)
            }
        }

        return MailboxActionAgentCompletionPresentation.message(for: plan)
    }

    private enum MailboxActionAgentExecutionError: LocalizedError {
        case confirmationRequired(String)

        var errorDescription: String? {
            switch self {
            case .confirmationRequired(let phrase):
                return String(localized: "Type \(phrase) to confirm.", bundle: .module)
            }
        }
    }

    private func createFolder(
        name: String,
        parentID: Folder.ID?,
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws -> Folder {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            return try await backend(for: sourceID).createFolder(
                name: name,
                parentID: parentID,
                sourceID: sourceID
            )
        }
        return try await selectedBackend.createFolder(name: name, parentID: parentID)
    }

    private func renameFolder(
        id: Folder.ID,
        name: String,
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws -> Folder {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            return try await backend(for: sourceID).renameFolder(
                id: id,
                name: name,
                sourceID: sourceID
            )
        }
        return try await selectedBackend.renameFolder(id: id, name: name)
    }

    private func deleteFolder(
        id: Folder.ID,
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            try await backend(for: sourceID).deleteFolder(id: id, sourceID: sourceID)
        } else {
            try await selectedBackend.deleteFolder(id: id)
        }
    }

    private func flushFolder(
        id: Folder.ID,
        sourceID explicitSourceID: MailSourceID? = nil
    ) async throws {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            try await backend(for: sourceID).flushFolder(id: id, sourceID: sourceID)
        } else {
            try await selectedBackend.flushFolder(id: id)
        }
    }

    private func refresh(folder: Folder) async throws {
        try await refresh(folder: folder, sourceID: nil)
    }

    private func refresh(folder: Folder, sourceID explicitSourceID: MailSourceID?) async throws {
        if let sourceID = explicitSourceID ?? navigation.selectedSourceID {
            try await backend(for: sourceID).refresh(folder: folder, in: sourceID)
        } else {
            try await selectedBackend.refresh(folder: folder)
        }
    }

    private func startRefreshRequest(folderID: Folder.ID, mailboxID: Mailbox.ID?) -> MailRootRefreshRequest {
        nextRefreshRequestID += 1
        let request = MailRootRefreshRequest(
            id: nextRefreshRequestID,
            folderID: folderID,
            mailboxID: mailboxID
        )
        activeRefreshRequest = request
        return request
    }

    private func canStartRefresh() -> Bool {
        MailRootRefreshStartPolicy.canStartRefresh(
            activeRequest: activeRefreshRequest,
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeCommandMutationRequest: activeCommandMutationRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeComposeCompletionRequest: activeComposeCompletionRequest,
            hasPresentedSheet: navigation.presentedSheet != nil
        )
    }

    private func canApplyRefreshResponse(_ request: MailRootRefreshRequest) -> Bool {
        MailRootRefreshResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeRefreshRequest,
            currentSelectedFolderID: navigation.selectedFolderID,
            currentMailboxID: activeMailboxID
        )
    }

    private func finishRefresh(_ request: MailRootRefreshRequest) {
        guard activeRefreshRequest == request else { return }
        activeRefreshRequest = nil
    }

    private func startMailboxSwitchRequest(mailboxID: Mailbox.ID) -> MailRootMailboxSwitchRequest {
        invalidateSourceLoading()
        nextMailboxSwitchRequestID += 1
        let request = MailRootMailboxSwitchRequest(
            id: nextMailboxSwitchRequestID,
            mailboxID: mailboxID
        )
        activeMailboxSwitchRequest = request
        return request
    }

    private func canApplyMailboxSwitchResponse(_ request: MailRootMailboxSwitchRequest) -> Bool {
        MailRootMailboxSwitchResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeMailboxSwitchRequest,
            currentMailboxID: activeMailboxID
        )
    }

    private func finishMailboxSwitch(_ request: MailRootMailboxSwitchRequest) {
        guard activeMailboxSwitchRequest == request else { return }
        activeMailboxSwitchRequest = nil
    }

    private func applyMailboxSwitch(to mailboxID: Mailbox.ID) {
        activeCommandMutationRequest = nil
        activeMailboxLoadRequest = nil
        activeFolderLoadRequest = nil
        activeRefreshRequest = nil
        activeComposeCompletionRequest = nil
        activeMailboxID = mailboxID
        navigation.resetForMailboxSwitch()
        folders = []
    }

    private func recoverFromStaleRootWorkBlockIfNeeded(snapshot: MailRootWorkBlockSnapshot) async {
        guard MailRootWorkBlockRecoveryPolicy.shouldStartWatchdog(snapshot: snapshot) else { return }

        // Poll for progress rather than blindly recovering after a fixed delay.
        // A heartbeat (`bumpRootWorkProgress`) from backend events and operation
        // milestones resets the elapsed counter, so a slow-but-progressing
        // operation is not mistaken for a stuck one. Recovery fires only after a
        // full stale timeout with no progress at all.
        var lastObservedTick = rootWorkProgressTick
        var nanosecondsWithoutProgress: UInt64 = 0
        while !MailRootWorkBlockRecoveryPolicy.hasExceededStaleTimeout(
            nanosecondsWithoutProgress: nanosecondsWithoutProgress
        ) {
            do {
                try await Task.sleep(
                    nanoseconds: MailRootWorkBlockRecoveryPolicy.progressPollIntervalNanoseconds
                )
            } catch {
                return
            }
            // The outstanding work finished or changed shape — `.task(id:)`
            // restarts the watchdog for the new snapshot, so stop here.
            guard rootWorkBlockSnapshot == snapshot else { return }

            let tick = rootWorkProgressTick
            if tick != lastObservedTick {
                lastObservedTick = tick
                nanosecondsWithoutProgress = 0
            } else {
                nanosecondsWithoutProgress += MailRootWorkBlockRecoveryPolicy
                    .progressPollIntervalNanoseconds
            }
        }

        guard MailRootWorkBlockRecoveryPolicy.shouldRecoverStaleWork(
            snapshotAtStart: snapshot,
            currentSnapshot: rootWorkBlockSnapshot,
            hasPresentedSheet: navigation.presentedSheet != nil
        ) else { return }

        clearStaleRootWorkBlock()
        navigation.requestReload()
        rootStatus = MailRootStatus(
            message: String(
                localized: "Recovered from a stuck mail operation and reloaded the current mailbox.",
                bundle: .module
            ),
            tone: .warning
        )
    }

    /// Heartbeat for the stale-work watchdog: signals that outstanding root work
    /// is making progress so the watchdog doesn't recover a slow operation.
    private func bumpRootWorkProgress() {
        rootWorkProgressTick &+= 1
    }

    private func clearStaleRootWorkBlock() {
        activeFolderLoadRequest = nil
        activeMailboxLoadRequest = nil
        activeRefreshRequest = nil
        activeMailboxSwitchRequest = nil
        activeCommandMutationRequest = nil
        activeComposeCompletionRequest = nil
    }

    private func startComposeCompletionRequest(composePresentationID: Int) {
        nextComposeCompletionRequestID += 1
        activeComposeCompletionRequest = MailRootComposeCompletionRequest(
            id: nextComposeCompletionRequestID,
            composePresentationID: composePresentationID,
            mailboxID: activeMailboxID
        )
    }

    private func canApplyComposeCompletionResponse(
        _ request: MailRootComposeCompletionRequest
    ) -> Bool {
        MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeComposeCompletionRequest,
            currentComposePresentationID: navigation.composePresentationID,
            currentMailboxID: activeMailboxID
        )
    }

    private func finishComposeCompletion(_ request: MailRootComposeCompletionRequest) {
        guard activeComposeCompletionRequest == request else { return }
        activeComposeCompletionRequest = nil
    }

    private func startCommandMutationRequest(sourceFolderID: Folder.ID?) -> MailRootCommandMutationRequest {
        invalidateSourceLoading()
        nextCommandMutationRequestID += 1
        let request = MailRootCommandMutationRequest(
            id: nextCommandMutationRequestID,
            sourceFolderID: sourceFolderID,
            sourceID: navigation.selectedSourceID
        )
        activeCommandMutationRequest = request
        startCommandMutationWatchdog(for: request)
        return request
    }

    /// Arms the work-block watchdog for `request`. If the mutation hasn't called
    /// `finishCommandMutation` within the timeout, the request is still the active
    /// one — meaning the underlying operation wedged — so we clear it to unblock
    /// the UI and prompt a refresh (#192). A normal completion cancels this first.
    private func startCommandMutationWatchdog(for request: MailRootCommandMutationRequest) {
        commandMutationWatchdog?.cancel()
        commandMutationWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.commandMutationWatchdogTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            recoverFromStuckCommandMutationIfNeeded(request)
        }
    }

    /// Clears a wedged command mutation. Guarded on request identity so a slow op
    /// that finished normally (and started a newer mutation) is never disturbed;
    /// the still-running hung task, if it ever returns, is ignored by
    /// `canApplyCommandMutationResponse`, so there's no double-apply.
    private func recoverFromStuckCommandMutationIfNeeded(_ request: MailRootCommandMutationRequest) {
        guard activeCommandMutationRequest?.id == request.id else { return }
        activeCommandMutationRequest = nil
        commandMutationWatchdog = nil
        rootStatus = MessageCommandPresentation.mutationTimeoutStatus()
        navigation.requestReload()
    }

    /// Upper bound on how long the UI stays work-blocked for a single mutation.
    /// Generous enough that legitimately slow moves/deletes over a poor connection
    /// complete normally; short enough that a true hang recovers without relaunch.
    private static let commandMutationWatchdogTimeoutNanoseconds: UInt64 = 60_000_000_000 // 60s

    private var hasValidSelectedSourceBackend: Bool {
        navigation.selectedSourceID.map { backendAccountIDs.contains($0.accountID) } ?? true
    }

    private func canStartCommandMutation() -> Bool {
        guard hasValidSelectedSourceBackend, hasMailContext, !undoQueue.isUndoing else { return false }
        return MailRootCommandMutationStartPolicy.canStartMutation(
            activeRequest: activeCommandMutationRequest,
            activeFolderLoadRequest: activeFolderLoadRequest,
            activeMailboxLoadRequest: activeMailboxLoadRequest,
            activeRefreshRequest: activeRefreshRequest,
            activeMailboxSwitchRequest: activeMailboxSwitchRequest,
            activeComposeCompletionRequest: activeComposeCompletionRequest,
            hasPresentedSheet: navigation.presentedSheet != nil
        )
    }

    private func canApplyCommandMutationResponse(_ request: MailRootCommandMutationRequest) -> Bool {
        MailRootCommandMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeCommandMutationRequest,
            currentSelectedFolderID: navigation.selectedFolderID,
            currentSourceID: navigation.selectedSourceID
        )
    }

    private func finishCommandMutation(_ request: MailRootCommandMutationRequest) {
        guard activeCommandMutationRequest == request else { return }
        activeCommandMutationRequest = nil
        commandMutationWatchdog?.cancel()
        commandMutationWatchdog = nil
    }

    private func handleCommandMutationFailure(_ error: any Error, rollback: MessageCommandMutationRollback) {
        rollback.restore(navigation: navigation)
        rootStatus = MessageCommandPresentation.mutationErrorStatus(for: error)
        shouldRetryMailboxLoad = false
    }

    private func refreshFolderMetadataAfterChange() async {
        guard canStartFolderLoad() else { return }
        let request = startFolderLoadRequest()
        defer { finishFolderLoad(request) }
        do {
            let result: [Folder]
            let sourceID = visibleSelectedSourceID
            if let sourceID {
                result = try await selectedBackend.folders(in: sourceID)
            } else {
                result = try await selectedBackend.folders()
            }
            guard canApplyFolderLoadResponse(request) else { return }
            if sourceID == nil {
                navigation.selectedSourceID = nil
            }
            applyLoadedFolders(result)
            finishFolderLoad(request)
        } catch {
            guard canApplyFolderLoadResponse(request) else { return }
            rootStatus = FolderMetadataRefreshPresentation.refreshErrorStatus(for: error)
            mailboxSwitchRetryID = nil
            shouldRetryMailboxLoad = false
            shouldRetryFolderLoad = true
            finishFolderLoad(request)
        }
    }

    /// Batches IMAP's related header, arrival, and folder events so one server
    /// refresh produces at most one visible-list reload, metadata query, and
    /// Dock badge update per short burst.
    private func enqueueBackendEventRefresh(_ event: MailEvent) {
        pendingBackendEventRefresh.record(event)
        scheduleBackendEventRefreshIfNeeded()
    }

    private func scheduleBackendEventRefreshIfNeeded() {
        guard backendEventRefreshTask == nil else { return }
        backendEventRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await applyPendingBackendEventRefresh()
        }
    }

    private func applyPendingBackendEventRefresh() async {
        backendEventRefreshTask = nil
        let batch = pendingBackendEventRefresh
        pendingBackendEventRefresh = MailRootBackendEventRefreshBatch()
        guard !batch.isEmpty else { return }
        guard canStartFolderLoad() else {
            pendingBackendEventRefresh = batch
            scheduleBackendEventRefreshIfNeeded()
            return
        }
        if batch.affectsVisibleFolder(navigation.selectedFolderID) {
            navigation.requestReload()
        }
        if batch.requiresSourceSectionsRefresh {
            await loadSourceSections()
        } else {
            await refreshFolderMetadataAfterChange()
        }
        updateUnreadBadge()
    }

    private func refreshAfterSheetDismissalIfNeeded() async {
        guard shouldRefreshAfterSheetDismissal,
              navigation.presentedSheet == nil,
              activeComposeCompletionRequest == nil,
              canStartFolderLoad()
        else { return }
        shouldRefreshAfterSheetDismissal = false
        navigation.requestReload()
        await refreshFolderMetadataAfterChange()
    }

    private func subscribeToChanges() async {
        await withTaskGroup(of: Void.self) { group in
            for backend in backends {
                group.addTask {
                    for await event in backend.subscribeToChanges() {
                        await handleBackendEvent(event, from: backend)
                    }
                }
            }
        }
    }

    /// Surface a new-mail event to the local notification center. Gated
    /// on the user's `notificationsEnabled` preference and the cached
    /// authorization status — the notification center performs its own
    /// status check before scheduling, but we skip the work early when
    /// push is off.
    @MainActor
    private func postNewMailNotification(
        folderID: String,
        messageIDs: [String],
        backend: any MailBackend
    ) async {
        guard !messageIDs.isEmpty else { return }
        let settings = NotificationSettings.load()
        let decision = NewMailNotificationPolicy.decision(
            settings: settings,
            accountID: backend.account.id
        )
        guard decision.shouldDeliver else { return }
        guard let messageID = messageIDs.first else { return }
        let folderName = folderDisplayName(folderID: folderID, backend: backend)
        // Populate the preview from the locally cached header. The header
        // cache is warmed by the same refresh that produced this
        // `.messagesAdded` event, so this is a fast, network-free lookup;
        // on a miss we fall back to the generic "New mail" body the
        // content policy synthesizes from an empty subject. Read through the
        // capability-gated extension service (ADR-0028) rather than a
        // concrete backend type.
        let supportsCachedHeaders = backend.extendedCapabilities.contains(.cachedMessageHeaders)
        let preview: MessageHeader?
        if supportsCachedHeaders {
            preview = await backend
                .extensionService(CachedMessageHeaderProviding.self)?
                .cachedMessageHeader(messageID: messageID, folderID: folderID)
        } else {
            preview = nil
        }
        let allowsInlineReply = supportsCachedHeaders
            && backend.capabilities.contains(.smtpOAuth)
            && preview != nil
            && NotificationInlineReplyAvailabilityPolicy.allows(
                undoSendDelaySeconds: ComposeUndoSendPolicy.delaySeconds()
            )
        await notificationCenter.postNewMailNotification(
            from: preview?.from ?? Correspondent(name: nil, email: ""),
            subject: preview?.subject ?? "",
            snippet: preview?.snippet ?? "",
            receivedAt: preview?.date ?? Date(),
            messageID: messageID,
            accountID: backend.account.id,
            folderID: folderID,
            folderName: folderName,
            showPreviews: decision.showPreviews,
            playSound: decision.playSound,
            allowsInlineReply: allowsInlineReply
        )
    }

    private func folderDisplayName(
        folderID: String,
        backend: any MailBackend
    ) -> String? {
        MailRootFolderNamePolicy.resolve(
            folderID: folderID,
            backendAccountID: backend.account.id,
            selectedAccountID: selectedBackend.account.id,
            selectedAccountFolders: folders,
            sourceSections: sourceSections
        )
    }

    @MainActor
    private func handleBackendEvent(_ event: MailEvent, from backend: any MailBackend) async {
        // Any backend event is a sign the session is alive — feed the watchdog's
        // heartbeat so outstanding root work isn't mistaken for stuck.
        bumpRootWorkProgress()
        switch event {
        case .folderRefreshed, .messagesAdded, .messagesRemoved, .messagesUpdated:
            let effects = MailRootAccountEventPolicy.mailboxEventEffects(
                for: event,
                eventAccountID: backend.account.id,
                selectedAccountID: selectedBackend.account.id
            )
            if effects.refreshBackgroundAccountState {
                if case .messagesAdded(let folderID, let messageIDs) = event,
                   effects.postNewMailNotification {
                    await postNewMailNotification(
                        folderID: folderID,
                        messageIDs: messageIDs,
                        backend: backend
                    )
                }
                enqueueBackgroundAccountRefresh(for: backend.account.id)
                return
            }
            guard effects.refreshVisibleContent else { return }
            guard !MailRootWorkBlockPolicy.shouldDeferBackendEventRefresh(
                hasPresentedSheet: navigation.presentedSheet != nil,
                activeComposeCompletionRequest: activeComposeCompletionRequest
            ) else {
                shouldRefreshAfterSheetDismissal = true
                return
            }
            enqueueBackendEventRefresh(event)
            if case .messagesAdded(let folderID, let messageIDs) = event,
               effects.postNewMailNotification {
                await postNewMailNotification(
                    folderID: folderID,
                    messageIDs: messageIDs,
                    backend: backend
                )
            }
        case .mailboxChanged(let mailboxID):
            guard backend.account.id == selectedBackend.account.id,
                  MailRootMailboxChangedEventPolicy.shouldApplyEvent(
                      mailboxID: mailboxID,
                      currentMailboxID: activeMailboxID,
                      activeMailboxSwitchRequest: activeMailboxSwitchRequest
                  ) else {
                break
            }
            applyMailboxSwitch(to: mailboxID)
            activeMailboxSwitchRequest = nil
            await loadFolders()
        case .accountConnected, .accountDisconnected:
            guard MailRootAccountEventPolicy.action(
                for: event,
                currentAccountID: backend.account.id,
                hasSignOutHandler: onSignOut != nil
            ) == .signOut else {
                break
            }
            await onSignOut?()
        case .syncProgress(let completed, let total):
            // Only reflect progress for the account whose list is on screen,
            // so a background sync of another account doesn't show a bar over
            // the visible one.
            guard backend.account.id == selectedBackend.account.id else { return }
            if total > 0, completed < total {
                syncProgress = MailSyncProgress(completed: completed, total: total)
            } else {
                syncProgress = nil
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func brevMailFallbackToolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        #if os(macOS)
        if BrevMailToolbarRuntime.usesNativeToolbar {
            self
        } else {
            toolbar(content: content)
        }
        #else
        toolbar(content: content)
        #endif
    }
}

enum BrevMailToolbarRuntime {
    static var usesNativeToolbar: Bool {
        usesNativeToolbar(environment: ProcessInfo.processInfo.environment)
    }

    /// The native AppKit toolbar stays opt-in via `BREV_ENABLE_NATIVE_TOOLBAR=1`.
    ///
    /// It cannot be the default while this window also uses `.searchable`.
    /// SwiftUI's `AppKitWindowController` installs and KVO-observes the window's
    /// toolbar to host the search field; `BrevMailNativeToolbarBridge` assigns
    /// `window.toolbar` itself, so SwiftUI's later
    /// `removeObserver:forKeyPath:` throws on a toolbar it no longer owns and
    /// AppKit turns that into a launch crash. Measured at 2 crashes in 3 launches
    /// via the `open` path on macOS 26. Making this the default requires either
    /// moving search out of the toolbar or letting SwiftUI own the toolbar and
    /// contributing items to it, rather than replacing it.
    static func usesNativeToolbar(environment: [String: String]) -> Bool {
        environment["BREV_ENABLE_NATIVE_TOOLBAR"] == "1"
    }
}

private extension MailRootStatus.Tone {
    var inlineStatusTone: BrevInlineStatusTone {
        switch self {
        case .info:
            return .info
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }
}

extension MailNavigationState.Sheet: Identifiable {
    public var id: Self { self }
}

/// Determinate progress of the visible account's multi-folder background
/// refresh. `completed` of `total` folders have synced.
struct MailSyncProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
}

/// Short-lived bottom toast for benign mail-root confirmations.
struct MailRootEphemeralToast: Equatable, Sendable, Identifiable {
    let id: UUID
    let message: String
    let tone: MailRootStatus.Tone

    init(id: UUID = UUID(), message: String, tone: MailRootStatus.Tone) {
        self.id = id
        self.message = message
        self.tone = tone
    }
}
