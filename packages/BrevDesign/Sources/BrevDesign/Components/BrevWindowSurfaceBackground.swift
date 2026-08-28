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

import BrevThemes
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

public struct BrevWindowSurfaceBackground: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @AppStorage(WindowAppearancePreferenceKey.mode) private var modeRaw = WindowTranslucencyMode.solid.rawValue
    @AppStorage(WindowAppearancePreferenceKey.scope) private var scopeRaw = WindowTranslucencyScope.mainWindow.rawValue
    @AppStorage(WindowAppearancePreferenceKey.surfaceOpacity) private var surfaceOpacity = WindowAppearancePreferences
        .defaultSurfaceOpacity
    @AppStorage(WindowAppearancePreferenceKey.sidebarOpacity) private var sidebarOpacity = WindowAppearancePreferences
        .defaultSidebarOpacity
    @AppStorage(WindowAppearancePreferenceKey.messageContentOpacityMode)
    private var messageContentOpacityModeRaw = MessageContentOpacityMode.followPane.rawValue
    @AppStorage(WindowAppearancePreferenceKey.messageContentOpacity)
    private var messageContentOpacity = WindowAppearancePreferences.defaultSurfaceOpacity

    private let role: WindowSurfaceRole

    public init(role: WindowSurfaceRole) {
        self.role = role
    }

    public var body: some View {
        ZStack {
            if usesMaterial {
                materialBackground
            }

            if let surfaceFillOpacity {
                solidBackground
                    .opacity(surfaceFillOpacity)
            }
        }
    }

    private var preferences: WindowAppearancePreferences {
        WindowAppearancePreferences(
            mode: WindowTranslucencyMode(rawValue: modeRaw) ?? .solid,
            scope: WindowTranslucencyScope(rawValue: scopeRaw) ?? .mainWindow,
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: persistedSidebarOpacity(sidebarOpacity),
            messageContentOpacityMode: MessageContentOpacityMode(rawValue: messageContentOpacityModeRaw) ?? .followPane,
            messageContentOpacity: persistedMessageContentOpacity(messageContentOpacity)
        )
    }

    private var usesMaterial: Bool {
        preferences.usesMaterial(for: role, reduceTransparency: reduceTransparency)
    }

    private var surfaceFillOpacity: Double? {
        preferences.surfaceFillOpacity(for: role, reduceTransparency: reduceTransparency)
    }

    @ViewBuilder
    private var solidBackground: some View {
        switch role {
        case .sidebar, .messageContent, .card:
            theme.bgSecondary.color
        case .mainWindow, .content, .settings, .utility:
            theme.bgPrimary.color
        }
    }

    @ViewBuilder
    private var materialBackground: some View {
        #if os(macOS)
        BrevVisualEffectBackground(
            material: preferences.effectiveMode(reduceTransparency: reduceTransparency)
                .visualEffectMaterial(for: role),
            blendingMode: .behindWindow
        )
        #else
        Rectangle()
            .fill(.regularMaterial)
        #endif
    }
}

public struct BrevWindowTranslucencyConfigurator: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @AppStorage(WindowAppearancePreferenceKey.mode) private var modeRaw = WindowTranslucencyMode.solid.rawValue
    @AppStorage(WindowAppearancePreferenceKey.scope) private var scopeRaw = WindowTranslucencyScope.mainWindow.rawValue
    @AppStorage(WindowAppearancePreferenceKey.surfaceOpacity) private var surfaceOpacity = WindowAppearancePreferences
        .defaultSurfaceOpacity
    @AppStorage(WindowAppearancePreferenceKey.sidebarOpacity) private var sidebarOpacity = WindowAppearancePreferences
        .defaultSidebarOpacity
    @AppStorage(WindowChromePreferenceKey.transparentMainTitlebar)
    private var transparentMainTitlebar = true
    private let windowRole: WindowSurfaceRole

    public init(windowRole: WindowSurfaceRole = .mainWindow) {
        self.windowRole = windowRole
    }

    public var body: some View {
        #if os(macOS)
        WindowConfiguratorView(
            preferences: preferences,
            windowRole: windowRole,
            reduceTransparency: reduceTransparency,
            transparentMainTitlebar: transparentMainTitlebar
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #else
        EmptyView()
        #endif
    }

    private var preferences: WindowAppearancePreferences {
        WindowAppearancePreferences(
            mode: WindowTranslucencyMode(rawValue: modeRaw) ?? .solid,
            scope: WindowTranslucencyScope(rawValue: scopeRaw) ?? .mainWindow,
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: persistedSidebarOpacity(sidebarOpacity)
        )
    }
}

public extension View {
    func brevWindowTranslucency(windowRole: WindowSurfaceRole = .mainWindow) -> some View {
        background(BrevWindowTranslucencyConfigurator(windowRole: windowRole))
    }

    func brevGlassSurface<SurfaceShape: Shape>(
        role: WindowSurfaceRole,
        in shape: SurfaceShape
    ) -> some View {
        modifier(BrevGlassSurfaceModifier(role: role, shape: shape))
    }
}

public struct BrevGlassSurfaceModifier<SurfaceShape: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @AppStorage(WindowAppearancePreferenceKey.mode) private var modeRaw = WindowTranslucencyMode.solid.rawValue
    @AppStorage(WindowAppearancePreferenceKey.scope) private var scopeRaw = WindowTranslucencyScope.mainWindow.rawValue
    @AppStorage(WindowAppearancePreferenceKey.surfaceOpacity) private var surfaceOpacity = WindowAppearancePreferences
        .defaultSurfaceOpacity
    @AppStorage(WindowAppearancePreferenceKey.sidebarOpacity) private var sidebarOpacity = WindowAppearancePreferences
        .defaultSidebarOpacity

    private let role: WindowSurfaceRole
    private let shape: SurfaceShape

    public init(role: WindowSurfaceRole, shape: SurfaceShape) {
        self.role = role
        self.shape = shape
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if shouldUseGlass {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                content.glassEffect(in: shape)
            } else {
                content
            }
            #else
            content
            #endif
        } else {
            content
        }
    }

    private var shouldUseGlass: Bool {
        let preferences = WindowAppearancePreferences(
            mode: WindowTranslucencyMode(rawValue: modeRaw) ?? .solid,
            scope: WindowTranslucencyScope(rawValue: scopeRaw) ?? .mainWindow,
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: persistedSidebarOpacity(sidebarOpacity)
        )
        return preferences.effectiveMode(reduceTransparency: reduceTransparency) == .glass
            && preferences.usesMaterial(for: role, reduceTransparency: reduceTransparency)
    }
}

private func persistedSidebarOpacity(_ appStorageValue: Double) -> Double? {
    guard UserDefaults.standard.object(forKey: WindowAppearancePreferenceKey.sidebarOpacity) != nil else {
        return nil
    }
    return appStorageValue
}

private func persistedMessageContentOpacity(_ appStorageValue: Double) -> Double? {
    guard UserDefaults.standard.object(forKey: WindowAppearancePreferenceKey.messageContentOpacity) != nil else {
        return nil
    }
    return appStorageValue
}

enum WindowChromePreferenceKey {
    static let transparentMainTitlebar = "window.transparentMainTitlebar"
}

enum WindowTransparentChromePolicy {
    static func usesTransparentChrome(
        preferences: WindowAppearancePreferences,
        for role: WindowSurfaceRole,
        reduceTransparency: Bool,
        transparentMainTitlebar: Bool
    ) -> Bool {
        let effectiveMode = preferences.effectiveMode(reduceTransparency: reduceTransparency)
        guard effectiveMode.usesTranslucency else { return false }

        if role == .mainWindow {
            return transparentMainTitlebar
        }

        if role == .settings {
            // Require both the title-bar preference and Settings being in scope
            // (Main window or All windows). Sidebar-only must not clear Settings.
            return transparentMainTitlebar
                && preferences.usesTransparentWindowChrome(
                    for: .settings,
                    reduceTransparency: reduceTransparency
                )
        }

        return preferences.usesTransparentWindowChrome(
            for: role,
            reduceTransparency: reduceTransparency
        )
    }
}

enum WindowTitlebarLayoutPolicy {
    static func usesUnifiedTitlebar(
        for role: WindowSurfaceRole,
        unifiedTitlebarEnabled: Bool
    ) -> Bool {
        guard role == .mainWindow || role == .settings else { return false }
        return unifiedTitlebarEnabled
    }
}

#if os(macOS)
public struct BrevVisualEffectBackground: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Clears opaque AppKit fills that `NavigationSplitView` inserts above column
/// materials, which otherwise hide behind-window vibrancy on macOS.
///
/// SwiftUI's `containerBackground(for: .navigationSplitView)` is unavailable
/// on macOS, so we walk to the enclosing `NSSplitView` and clear solid layer
/// fills on its column subviews while leaving `NSVisualEffectView` alone.
public struct BrevSplitViewColumnTransparencyFixer: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = SplitViewTransparencyProbe()
        view.clearOpaqueColumnFills()
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SplitViewTransparencyProbe)?.clearOpaqueColumnFills()
    }
}

struct SplitViewTransparencyPassState {
    /// Ceiling on settled passes the coordinator may arm on its own after one
    /// external trigger. Each re-arm requires the previous pass to have
    /// actually cleared a restored fill, so the chain reaches a fixpoint; the
    /// cap only guards against SwiftUI pathologically restoring chrome on
    /// every pass.
    static let maxSettledReArms = 5

    private(set) var isImmediatePassPending = false
    private var settledPassGeneration = 0
    private var consecutiveSettledReArms = 0

    mutating func requestImmediatePass() -> Bool {
        guard !isImmediatePassPending else { return false }
        isImmediatePassPending = true
        return true
    }

    mutating func completeImmediatePass() {
        isImmediatePassPending = false
    }

    mutating func requestSettledPass() -> Int {
        settledPassGeneration += 1
        return settledPassGeneration
    }

    func shouldRunSettledPass(_ generation: Int) -> Bool {
        generation == settledPassGeneration
    }

    mutating func noteExternalTrigger() {
        consecutiveSettledReArms = 0
    }

    mutating func requestSettledReArm() -> Bool {
        guard consecutiveSettledReArms < Self.maxSettledReArms else { return false }
        consecutiveSettledReArms += 1
        return true
    }
}

private final class SplitViewTransparencyProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearOpaqueColumnFills()
    }

    override func layout() {
        super.layout()
        clearOpaqueColumnFills()
    }

    func clearOpaqueColumnFills() {
        guard let splitView = Self.enclosingSplitView(from: self) else { return }
        SplitViewTransparencyPassCoordinator.shared.requestPass(for: splitView)
    }

    private static func enclosingSplitView(from view: NSView) -> NSSplitView? {
        var current: NSView? = view.superview
        while let candidate = current {
            if let splitView = candidate as? NSSplitView {
                return splitView
            }
            current = candidate.superview
        }
        return nil
    }
}

/// Coalesces transparency repair across every probe hosted by one split view.
/// Pane surfaces install probes independently, but only one recursive walk per
/// split view is useful during a layout turn.
final class SplitViewTransparencyPassCoordinator {
    /// Returns whether the pass cleared at least one restored opaque fill —
    /// the signal that SwiftUI rebuilt split-view chrome since the last pass
    /// and a verification pass is worth arming.
    typealias ApplyPass = (NSSplitView) -> Bool

    static let shared = SplitViewTransparencyPassCoordinator()

    private final class Entry {
        weak var splitView: NSSplitView?
        var passState = SplitViewTransparencyPassState()
        var settledPass: DispatchWorkItem?

        init(splitView: NSSplitView) {
            self.splitView = splitView
        }

        deinit {
            settledPass?.cancel()
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private let settledDelay: DispatchTimeInterval
    private let applyPass: ApplyPass

    init(
        settledDelay: DispatchTimeInterval = .milliseconds(200),
        applyPass: ApplyPass? = nil
    ) {
        self.settledDelay = settledDelay
        self.applyPass = applyPass ?? Self.clearOpaqueFills
    }

    func requestPass(for splitView: NSSplitView) {
        let identifier = ObjectIdentifier(splitView)
        if let existing = entries[identifier], existing.splitView !== splitView {
            entries.removeValue(forKey: identifier)
        }
        if entries[identifier] == nil, entries.count >= 8 {
            removeReleasedEntries()
        }
        let entry = entries[identifier] ?? {
            let entry = Entry(splitView: splitView)
            entries[identifier] = entry
            return entry
        }()

        entry.passState.noteExternalTrigger()

        if entry.passState.requestImmediatePass() {
            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self, let splitView,
                      let entry = self.entry(for: splitView, identifier: identifier) else { return }
                entry.passState.completeImmediatePass()
                _ = applyPass(splitView)
            }
        }

        // SwiftUI can restore split-view chrome after a layout burst. Keep one
        // final pass after resizing settles.
        scheduleSettledPass(for: splitView, identifier: identifier, entry: entry)
    }

    /// Arms the settled pass. When it runs and still finds restored opaque
    /// fills, it re-arms itself (budgeted per external trigger) so a chrome
    /// rebuild landing after the last layout burst cannot leave columns
    /// opaque — the failure mode behind readers/lists losing translucency.
    /// Generation validation is required because canceling an already
    /// submitted DispatchWorkItem is advisory.
    private func scheduleSettledPass(
        for splitView: NSSplitView,
        identifier: ObjectIdentifier,
        entry: Entry
    ) {
        entry.settledPass?.cancel()
        let generation = entry.passState.requestSettledPass()
        let settledPass = DispatchWorkItem { [weak self, weak splitView] in
            guard let self, let splitView,
                  let entry = self.entry(for: splitView, identifier: identifier),
                  entry.passState.shouldRunSettledPass(generation) else { return }
            entry.settledPass = nil
            let clearedRestoredFills = applyPass(splitView)
            if clearedRestoredFills, entry.passState.requestSettledReArm() {
                scheduleSettledPass(for: splitView, identifier: identifier, entry: entry)
            }
        }
        entry.settledPass = settledPass
        DispatchQueue.main.asyncAfter(
            deadline: .now() + settledDelay,
            execute: settledPass
        )
    }

    private func entry(
        for splitView: NSSplitView,
        identifier: ObjectIdentifier
    ) -> Entry? {
        guard let entry = entries[identifier], entry.splitView === splitView else { return nil }
        return entry
    }

    private func removeReleasedEntries() {
        entries = entries.filter { $0.value.splitView != nil }
    }

    /// Returns whether any visible fill was actually cleared. Already-clear
    /// layers don't count as work — the settled pass re-arms on this signal,
    /// and counting no-op writes would make every pass look like a restore.
    @discardableResult
    private static func clearOpaqueFills(in root: NSView) -> Bool {
        var clearedFill = false
        if !(root is NSVisualEffectView) {
            if let background = root.layer?.backgroundColor, background.alpha > 0 {
                root.wantsLayer = true
                root.layer?.backgroundColor = NSColor.clear.cgColor
                clearedFill = true
            }
            if let clipView = root as? NSClipView, clipView.drawsBackground {
                clipView.drawsBackground = false
                clipView.backgroundColor = .clear
                clearedFill = true
            }
            if let scrollView = root as? NSScrollView, scrollView.drawsBackground {
                scrollView.drawsBackground = false
                scrollView.backgroundColor = .clear
                clearedFill = true
            }
        }

        for child in root.subviews {
            if clearOpaqueFills(in: child) {
                clearedFill = true
            }
        }
        return clearedFill
    }
}

enum WindowTitlebarChromePolicy {
    static func apply(
        to window: NSWindow,
        for role: WindowSurfaceRole,
        usesUnifiedTitlebar: Bool
    ) {
        guard role == .mainWindow || role == .settings else { return }

        if usesUnifiedTitlebar {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
        } else {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarSeparatorStyle = .automatic
        }
    }
}

private struct WindowConfiguratorView: NSViewRepresentable {
    let preferences: WindowAppearancePreferences
    let windowRole: WindowSurfaceRole
    let reduceTransparency: Bool
    let transparentMainTitlebar: Bool

    func makeNSView(context: Context) -> WindowConfigurationProbe {
        WindowConfigurationProbe(
            preferences: preferences,
            windowRole: windowRole,
            reduceTransparency: reduceTransparency,
            transparentMainTitlebar: transparentMainTitlebar
        )
    }

    func updateNSView(_ view: WindowConfigurationProbe, context: Context) {
        view.preferences = preferences
        view.windowRole = windowRole
        view.reduceTransparency = reduceTransparency
        view.transparentMainTitlebar = transparentMainTitlebar
        view.applyConfiguration()
    }
}

private final class WindowConfigurationProbe: NSView {
    var preferences: WindowAppearancePreferences
    var windowRole: WindowSurfaceRole
    var reduceTransparency: Bool
    var transparentMainTitlebar: Bool

    init(
        preferences: WindowAppearancePreferences,
        windowRole: WindowSurfaceRole,
        reduceTransparency: Bool,
        transparentMainTitlebar: Bool
    ) {
        self.preferences = preferences
        self.windowRole = windowRole
        self.reduceTransparency = reduceTransparency
        self.transparentMainTitlebar = transparentMainTitlebar
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    func applyConfiguration() {
        guard let window else { return }
        BrevWindowChromeApplier.apply(
            preferences: preferences,
            to: window,
            for: windowRole,
            reduceTransparency: reduceTransparency,
            transparentMainTitlebar: transparentMainTitlebar
        )
        reapplyConfigurationAfterSwiftUISceneSettles(to: window)
    }

    private func reapplyConfigurationAfterSwiftUISceneSettles(to window: NSWindow) {
        let delays: [DispatchTimeInterval] = [
            .milliseconds(0),
            .milliseconds(50),
            .milliseconds(150),
            .milliseconds(350)
        ]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                BrevWindowChromeApplier.apply(
                    preferences: preferences,
                    to: window,
                    for: windowRole,
                    reduceTransparency: reduceTransparency,
                    transparentMainTitlebar: transparentMainTitlebar
                )
            }
        }
    }
}

public enum BrevWindowChromeApplier {
    public static func applyCurrentPreferences(
        to window: NSWindow,
        for role: WindowSurfaceRole
    ) {
        let transparentMainTitlebar = UserDefaults.standard.object(
            forKey: WindowChromePreferenceKey.transparentMainTitlebar
        ) as? Bool ?? true
        apply(
            preferences: WindowAppearancePreferences.load(),
            to: window,
            for: role,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            transparentMainTitlebar: transparentMainTitlebar
        )
    }

    static func apply(
        preferences: WindowAppearancePreferences,
        to window: NSWindow,
        for role: WindowSurfaceRole,
        reduceTransparency: Bool,
        transparentMainTitlebar: Bool
    ) {
        let usesTransparentChrome = WindowTransparentChromePolicy.usesTransparentChrome(
            preferences: preferences,
            for: role,
            reduceTransparency: reduceTransparency,
            transparentMainTitlebar: transparentMainTitlebar
        )
        let usesUnifiedTitlebar = WindowTitlebarLayoutPolicy.usesUnifiedTitlebar(
            for: role,
            unifiedTitlebarEnabled: transparentMainTitlebar
        )
        // Keep title-bar geometry independent from backdrop transmission.
        // Solid uses the same full-size layout as material modes, but its
        // SwiftUI surfaces and NSWindow backing remain fully opaque.
        WindowTitlebarChromePolicy.apply(
            to: window,
            for: role,
            usesUnifiedTitlebar: usesUnifiedTitlebar
        )

        let backgroundAlpha = usesTransparentChrome ? 0.0 : 1.0
        window.isOpaque = !usesTransparentChrome
        window.backgroundColor = .windowBackgroundColor.withAlphaComponent(CGFloat(backgroundAlpha))
        window.titlebarAppearsTransparent = usesUnifiedTitlebar || usesTransparentChrome
        WindowTrafficLightPolicy.apply(to: window, for: role)
        WindowTrafficLightPolicy.reapplyAfterSwiftUISceneSettles(to: window, for: role)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = usesTransparentChrome
            ? NSColor.clear.cgColor
            : nil
    }
}

enum WindowTrafficLightPolicy {
    private static let unconstrainedContentSize = NSSize(width: 100_000, height: 100_000)

    static func styleMaskInsertions(for role: WindowSurfaceRole) -> NSWindow.StyleMask {
        switch role {
        case .settings, .utility:
            return [.titled, .closable, .miniaturizable, .resizable]
        case .mainWindow, .sidebar, .content, .messageContent, .card:
            return []
        }
    }

    static func apply(to window: NSWindow, for role: WindowSurfaceRole) {
        let insertions = styleMaskInsertions(for: role)
        guard !insertions.isEmpty else { return }

        window.styleMask.insert(insertions)
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.maxSize = unconstrainedContentSize
        window.contentMaxSize = unconstrainedContentSize
        configureStandardControls(for: window)
    }

    static func reapplyAfterSwiftUISceneSettles(to window: NSWindow, for role: WindowSurfaceRole) {
        guard !styleMaskInsertions(for: role).isEmpty else { return }

        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            apply(to: window, for: role)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak window] in
            guard let window else { return }
            apply(to: window, for: role)
        }
    }

    private static func configureStandardControls(for window: NSWindow) {
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let control = window.standardWindowButton(button)
            control?.isHidden = false
            control?.isEnabled = true
        }
    }
}

enum WindowVisualEffectMaterialPolicy {
    static func material(
        for mode: WindowTranslucencyMode,
        role: WindowSurfaceRole
    ) -> NSVisualEffectView.Material {
        switch mode {
        case .solid:
            return .windowBackground
        case .subtle:
            return role == .sidebar ? .sidebar : .windowBackground
        case .frosted:
            return role == .sidebar || role == .mainWindow || role == .settings ? .sidebar : .hudWindow
        case .glass:
            // Keep sidebar on the native sidebar material so Glass mode still
            // reads as a translucent column rather than a dense HUD panel.
            return role == .sidebar || role == .mainWindow || role == .settings ? .sidebar : .hudWindow
        }
    }
}

private extension WindowTranslucencyMode {
    func visualEffectMaterial(for role: WindowSurfaceRole) -> NSVisualEffectView.Material {
        WindowVisualEffectMaterialPolicy.material(for: self, role: role)
    }
}
#endif
