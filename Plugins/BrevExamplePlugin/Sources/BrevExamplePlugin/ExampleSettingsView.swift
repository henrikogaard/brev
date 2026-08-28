import SwiftUI

/// A simple settings panel view contributed by the example plugin.
struct ExampleSettingsView: View {
    @AppStorage("brev.examplePlugin.enabled") private var isEnabled = true
    @State private var showAbout = false

    var body: some View {
        Form {
            Toggle(
                String(localized: "Enable example plugin features", bundle: .module),
                isOn: $isEnabled
            )

            Button(String(localized: "About this plugin", bundle: .module)) {
                showAbout = true
            }
            .sheet(isPresented: $showAbout) {
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Brev Example Plugin", bundle: .module)
                        .font(.headline)
                    Text(
                        "Demonstrates the BrevPlugins API with all four contribution types.",
                        bundle: .module
                    )
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    Button(String(localized: "Close", bundle: .module)) { showAbout = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(width: 300, height: 250)
            }
        }
        .padding()
    }
}
