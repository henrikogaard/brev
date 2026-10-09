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

/// Shared chrome for a settings detail pane: title at the top, scroll
/// region beneath, padded by the standard rhythm.
struct SectionScaffold<Content: View>: View {
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var interfaceDensityRaw = MailboxListDensity.platformDefault
        .rawValue
    private var interfaceDensity: MailboxListDensity { MailboxListDensity(rawValue: interfaceDensityRaw) ?? .comfortable }
    @Environment(\.brevTheme) private var theme
    @Environment(\.settingsSearchTarget) private var searchTarget
    @Environment(\.settingsScopeCaption) private var scopeCaption
    @Environment(\.settingsScopeAccessory) private var scopeAccessory
    let title: String
    let subtitle: String?
    /// Panes whose tab row already names them hide the repeated heading so the
    /// same word is not the pane title, the tab and the first group at once.
    let showsTitle: Bool
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsTitle: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsTitle = showsTitle
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        formBody
        #else
        scrollBody
        #endif
    }

    #if os(iOS)
    /// iPhone and iPad panes render as an inset-grouped `Form` like the iOS
    /// Settings app: explanatory copy sits in section footers, not in cards.
    private var formBody: some View {
        ScrollViewReader { proxy in
            Form {
                if hasPaneHeader {
                    Section {
                        if let scopeAccessory {
                            scopeAccessory
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                            if let subtitle {
                                Text(subtitle)
                            }
                            if let scopeCaption {
                                Text(scopeCaption)
                            }
                        }
                        .brevFont(.footnote)
                        .foregroundStyle(theme.textSecondary.color)
                    }
                    .listRowBackground(theme.bgPrimary.color)
                }
                content
            }
            .scrollContentBackground(.hidden)
            .background(theme.bgSecondary.color.ignoresSafeArea())
            .task(id: searchTarget) {
                guard let searchTarget else { return }
                await Task.yield()
                proxy.scrollTo(searchTarget, anchor: .top)
            }
        }
    }

    private var hasPaneHeader: Bool {
        subtitle != nil || scopeCaption != nil || scopeAccessory != nil
    }
    #endif

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Pane title, then groups. The gap below the title is wider
                // than the gap between groups so the pane reads as titled
                // content rather than as one more group in the stack.
                VStack(alignment: .leading, spacing: interfaceDensity.desktopSpacing(BrevSpacing.xl)) {
                    VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                        if showsTitle, !Self.navigationBarShowsTitle {
                            Text(title)
                                .brevFont(.headline)
                                .foregroundStyle(theme.textPrimary.color)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .brevFont(.subheadline)
                                .foregroundStyle(theme.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let scopeCaption {
                            Text(scopeCaption)
                                .brevFont(.footnote)
                                .foregroundStyle(theme.textSecondary.color)
                        }
                    }
                    if let scopeAccessory {
                        scopeAccessory
                    }
                    content
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, BrevSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .task(id: searchTarget) {
                guard let searchTarget else { return }
                await Task.yield()
                proxy.scrollTo(searchTarget, anchor: .top)
            }
        }
        .background(BrevWindowSurfaceBackground(role: .content).ignoresSafeArea())
    }

    /// iOS panes are pushed with the section name as the navigation title,
    /// so the in-pane heading would only repeat it.
    private static var navigationBarShowsTitle: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var horizontalPadding: CGFloat {
        SettingsLayout.paneHorizontalInset(interfaceDensity)
    }

    private var topPadding: CGFloat {
        #if os(iOS)
        BrevSpacing.xl
        #else
        interfaceDensity.desktopSpacing(BrevSpacing.xxl)
        #endif
    }
}

#if os(iOS)
extension View {
    /// Theme chrome for a `Form` pushed below a settings pane (account
    /// details, per-account switches): hidden system background over the
    /// grouped theme surface, matching `SectionScaffold`.
    func settingsFormChrome() -> some View {
        modifier(SettingsFormChrome())
    }
}

private struct SettingsFormChrome: ViewModifier {
    @Environment(\.brevTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.bgSecondary.color.ignoresSafeArea())
    }
}
#endif
