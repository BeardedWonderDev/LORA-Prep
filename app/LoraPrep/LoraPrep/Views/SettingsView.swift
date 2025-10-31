import SwiftUI
import LoRAPrepCore

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
                Toggle("Prefer padding over center crop by default", isOn: $settings.defaultPreferPaddingOverCrop)
                Toggle("Maximize subject fill after background removal by default", isOn: $settings.defaultMaximizeSubjectFill)
                Picker("Segmentation mode", selection: $settings.defaultSegmentationMode) {
                    ForEach(segmentationModes, id: \.self) { mode in
                        Text(label(for: mode)).tag(mode)
                    }
                }
                VStack(alignment: .leading) {
                    Slider(value: $settings.defaultMaskFeather, in: 0...10, step: 0.1) {
                        Text("Mask feather (px)")
                    }
                    Text("Mask feather: \(settings.defaultMaskFeather, specifier: "%.1f") px")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading) {
                    Slider(value: $settings.defaultMaskErosion, in: 0...5, step: 0.1) {
                        Text("Mask erosion (px)")
                    }
                    Text("Mask erosion: \(settings.defaultMaskErosion, specifier: "%.1f") px")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("Defaults apply on launch. Adjust per-run values under Advanced Options in the main window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }

    private var segmentationModes: [LoRAPrepConfiguration.SegmentationMode] {
        [.automatic, .accurateVision, .deepLabV3, .robustVideoMatting]
    }

    private func label(for mode: LoRAPrepConfiguration.SegmentationMode) -> String {
        switch mode {
        case .automatic:
            return "Automatic (Vision balanced)"
        case .accurateVision:
            return "Vision accurate"
        case .deepLabV3:
            return "DeepLabV3"
        case .robustVideoMatting:
            return "Robust Video Matting"
        }
    }
}

#Preview {
    let store = SettingsStore()
    return SettingsView()
        .environmentObject(AppState(settings: store))
        .environmentObject(store)
        .frame(width: 380)
}
