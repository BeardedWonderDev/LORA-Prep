import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Super-resolution Model") {
                Text(model.superResModelURL?.lastPathComponent ?? "No model selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Choose…") {
                        model.chooseSuperResModel()
                    }
                    Button("Clear") {
                        model.clearSuperResModel()
                    }
                    .disabled(model.superResModelURL == nil)
                    Spacer()
                }
            }

            Section("Run Defaults") {
                Toggle("Remove background by default", isOn: $settings.defaultRemoveBackground)
                Toggle("Pad with transparency by default", isOn: $settings.defaultPadWithTransparency)
                Toggle("Skip face detection by default", isOn: $settings.defaultSkipFaceDetection)
                Text("Defaults apply on launch. Adjust per-run values under Advanced Options in the main window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}

#Preview {
    let store = SettingsStore()
    return SettingsView()
        .environmentObject(AppState(settings: store))
        .environmentObject(store)
        .frame(width: 380)
}
