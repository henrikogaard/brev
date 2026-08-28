import BrevPlugins
import SwiftUI

/// Example plugin that contributes one UI surface of each type to
/// demonstrate the BrevPlugin API.
@MainActor
public final class BrevExamplePlugin: BrevUIExtension {
    public let identifier = "com.brev.example-plugin"
    public let displayName = String(localized: "Example Plugin", bundle: .module)
    public let author = "Brev"

    public let contributions: [ContributionDefinition] = [
        ContributionDefinition(
            id: "compose-status",
            kind: .composeToolbar,
            displayName: String(localized: "Plugin Status", bundle: .module),
            sfSymbolName: "puzzlepiece.extension"
        ),
        ContributionDefinition(
            id: "menu-copy-link",
            kind: .messageContextMenu,
            displayName: String(localized: "Copy Message Link", bundle: .module),
            sfSymbolName: "link"
        ),
        ContributionDefinition(
            id: "settings-panel",
            kind: .settingsPanel,
            displayName: String(localized: "Example Plugin", bundle: .module),
            sfSymbolName: "puzzlepiece.extension"
        )
    ]

    public init() {}

    public func view(for contributionID: String) -> AnyView {
        switch contributionID {
        case "compose-status":
            AnyView(ComposeStatusView())
        case "menu-copy-link":
            AnyView(MessageMenuView())
        case "settings-panel":
            AnyView(ExampleSettingsView())
        default:
            AnyView(Text("Unknown contribution: \(contributionID)", bundle: .module))
        }
    }
}

// MARK: - Contribution views

private struct ComposeStatusView: View {
    var body: some View {
        Image(systemName: "puzzlepiece.extension")
            .foregroundStyle(.secondary)
            .help(String(localized: "Example plugin active", bundle: .module))
    }
}

private struct MessageMenuView: View {
    @State private var copied = false

    var body: some View {
        Button {
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        } label: {
            Label(
                copied
                    ? String(localized: "Copied!", bundle: .module)
                    : String(localized: "Copy Message Link", bundle: .module),
                systemImage: "link"
            )
        }
        .disabled(copied)
    }
}
