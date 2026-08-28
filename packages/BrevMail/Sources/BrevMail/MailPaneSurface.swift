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

enum MailPaneNavigationTitleStyle: Equatable, Sendable {
    case automatic
    case inline
}

struct MailPaneSurfacePolicy: Equatable, Sendable {
    let role: WindowSurfaceRole
    let fillsPane: Bool
    let ignoresTitlebarSafeArea: Bool
    let navigationTitleStyle: MailPaneNavigationTitleStyle
    let navigationBarBackgroundRole: WindowSurfaceRole?

    static let sidebar = MailPaneSurfacePolicy(
        role: .sidebar,
        fillsPane: true,
        ignoresTitlebarSafeArea: true,
        navigationTitleStyle: .inline,
        navigationBarBackgroundRole: .sidebar
    )
    static let content = MailPaneSurfacePolicy(
        role: .content,
        fillsPane: true,
        ignoresTitlebarSafeArea: true,
        // The list and reader panes carry no navigation title, so `.automatic`
        // only reserved an empty iOS large-title strip above the toolbar.
        // Inline keeps the top compact (the toolbar sits directly under the
        // status bar).
        navigationTitleStyle: .inline,
        navigationBarBackgroundRole: .content
    )

    var ignoredSafeAreaEdges: Edge.Set {
        ignoresTitlebarSafeArea ? .all : [.horizontal, .bottom]
    }
}

enum MailPanePlatform: Equatable, Sendable {
    case iPad
    case iPhone
    case macOS
}

struct MailPaneColumnWidth: Equatable, Sendable {
    let minimum: CGFloat
    let ideal: CGFloat
    let maximum: CGFloat
}

enum MailPaneColumnWidthPolicy {
    static func messageList(platform: MailPanePlatform) -> MailPaneColumnWidth? {
        switch platform {
        case .iPad:
            MailPaneColumnWidth(minimum: 320, ideal: 380, maximum: 460)
        case .iPhone:
            nil
        case .macOS:
            // Deliberately unconstrained. A `maximum` here does not survive a
            // divider drag — AppKit hands the space over anyway — so what keeps
            // the list from swallowing the reader is `readerMinimumWidth`, on
            // the other side of the divider.
            nil
        }
    }

    /// Bounds for the folder sidebar column.
    ///
    /// These have to reach the split view rather than the hosted content. A
    /// content-side `.frame(minWidth:idealWidth:)` leaves AppKit resolving the
    /// column width against the hosting view on every step of a divider drag,
    /// so the sidebar's own layout lags the divider and the half-resized
    /// content is drawn stretched against the trailing edge.
    static func folderSidebar(platform: MailPanePlatform) -> MailPaneColumnWidth? {
        switch platform {
        case .macOS, .iPad:
            MailPaneColumnWidth(minimum: 200, ideal: 240, maximum: 420)
        case .iPhone:
            nil
        }
    }

    /// Narrowest the macOS reader may become.
    ///
    /// The reader's action cluster shares one trailing toolbar section with the
    /// message list's controls, so a reader narrower than that cluster pushes
    /// its own icons back over the list. Measured against the cluster with
    /// search collapsed — Get Mail, New Message, the five message actions,
    /// search, and the AI Sidebar toggle. Sits far enough under the 960pt
    /// default window width that the window still resizes down.
    static func readerMinimumWidth(platform: MailPanePlatform) -> CGFloat? {
        switch platform {
        case .macOS:
            420
        case .iPad, .iPhone:
            nil
        }
    }

    /// Width budget for the macOS Mail Context inspector column.
    /// Width the AI Sidebar opens at before the user has resized it.
    static let mailContextDefaultWidth: CGFloat = 320

    static func mailContext(platform: MailPanePlatform) -> MailPaneColumnWidth? {
        switch platform {
        case .macOS:
            MailPaneColumnWidth(minimum: 280, ideal: mailContextDefaultWidth, maximum: 420)
        case .iPad, .iPhone:
            nil
        }
    }
}

struct MessageReaderLayout: Equatable, Sendable {
    let maximumContentWidth: CGFloat?
    let usesCardSurface: Bool
    let outerHorizontalPadding: CGFloat
    let outerVerticalPadding: CGFloat
    let contentPadding: CGFloat
}

enum MessageReaderLayoutPolicy {
    static func layout(
        platform: MailPanePlatform,
        density: MailboxListDensity
    ) -> MessageReaderLayout {
        switch platform {
        case .macOS:
            boundedLayout(maximumContentWidth: 760, density: density, usesCardSurface: false)
        case .iPad:
            boundedLayout(maximumContentWidth: 760, density: density)
        case .iPhone:
            MessageReaderLayout(
                maximumContentWidth: nil,
                usesCardSurface: false,
                outerHorizontalPadding: 0,
                outerVerticalPadding: 0,
                contentPadding: BrevSpacing.lg
            )
        }
    }

    private static func boundedLayout(
        maximumContentWidth: CGFloat,
        density: MailboxListDensity,
        usesCardSurface: Bool = true
    ) -> MessageReaderLayout {
        let outerPadding = max(BrevSpacing.md, density.metadataSpacing * 2)
        let contentPadding: CGFloat = switch density {
        case .compact: BrevSpacing.lg
        case .comfortable: BrevSpacing.xl
        case .spacious: BrevSpacing.xxl
        }
        return MessageReaderLayout(
            maximumContentWidth: maximumContentWidth,
            usesCardSurface: usesCardSurface,
            outerHorizontalPadding: outerPadding,
            outerVerticalPadding: outerPadding,
            contentPadding: contentPadding
        )
    }
}

extension View {
    func brevMailPaneSurface(_ policy: MailPaneSurfacePolicy) -> some View {
        modifier(MailPaneSurfaceModifier(policy: policy))
    }

    func brevMailPaneColumnWidth(_ width: MailPaneColumnWidth?) -> some View {
        modifier(MailPaneColumnWidthModifier(width: width))
    }
}

private struct MailPaneSurfaceModifier: ViewModifier {
    @Environment(\.brevTheme) private var theme

    let policy: MailPaneSurfacePolicy

    func body(content: Content) -> some View {
        pane(content: content)
            .mailPaneNavigationTitleStyle(policy.navigationTitleStyle)
            .mailPaneNavigationBarBackground(policy.navigationBarBackgroundRole, theme: theme)
        #if os(macOS)
            .background(BrevSplitViewColumnTransparencyFixer())
        #endif
    }

    private func pane(content: Content) -> some View {
        ZStack {
            if policy.fillsPane {
                BrevWindowSurfaceBackground(role: policy.role)
                    .ignoresSafeArea(edges: policy.ignoredSafeAreaEdges)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func mailPaneNavigationTitleStyle(_ style: MailPaneNavigationTitleStyle) -> some View {
        #if os(iOS)
        switch style {
        case .automatic:
            self
        case .inline:
            navigationBarTitleDisplayMode(.inline)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func mailPaneNavigationBarBackground(_ role: WindowSurfaceRole?, theme: BrevTheme) -> some View {
        #if os(iOS)
        if let role {
            toolbarBackground(mailPaneNavigationBarColor(for: role, theme: theme), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    private func mailPaneNavigationBarColor(for role: WindowSurfaceRole, theme: BrevTheme) -> Color {
        switch role {
        case .sidebar, .messageContent, .card:
            theme.bgSecondary.color
        case .mainWindow, .content, .settings, .utility:
            theme.bgPrimary.color
        }
    }
}

private struct MailPaneColumnWidthModifier: ViewModifier {
    let width: MailPaneColumnWidth?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let width {
            content.navigationSplitViewColumnWidth(
                min: width.minimum,
                ideal: width.ideal,
                max: width.maximum
            )
        } else {
            content
        }
    }
}
