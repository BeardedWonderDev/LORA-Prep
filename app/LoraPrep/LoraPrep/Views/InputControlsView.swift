import SwiftUI

struct InputControlsView: View {
    @ObservedObject var model: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var advancedExpanded = false

    private let sizeRange = 512.0...2048.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input Folder")
                        .font(.headline)
                    if let folder = model.inputFolder {
                        Text(folder.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("No folder selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Choose Folder…") {
                    model.chooseInputFolder()
                }
                .disabled(model.isProcessing)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LoRA Name")
                        .font(.headline)
                    TextField("Display name used in filenames", text: $model.loraName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .disabled(model.isProcessing)
                    Text("Normalized: \(model.normalizedLoRAName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Size")
                        .font(.headline)
                    HStack {
                        Slider(value: $model.size, in: sizeRange, step: 64)
                            .disabled(model.isProcessing)
                        Stepper(value: $model.size, in: sizeRange, step: 64) {
                            Text("\(Int(model.size)) px")
                                .monospacedDigit()
                        }
                        .disabled(model.isProcessing)
                    }
                }
            }

            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    advancedToggle(title: "Remove background",
                                   binding: $model.removeBackground,
                                   defaultValue: settings.defaultRemoveBackground,
                                   help: "Use Vision person segmentation to cut out the background before saving.")
                    advancedToggle(title: "Pad with transparency",
                                   binding: $model.padWithTransparency,
                                   defaultValue: settings.defaultPadWithTransparency,
                                   help: "Fill padded regions with transparent pixels; disable to use edge color padding.")
                    advancedToggle(title: "Skip face detection",
                                   binding: $model.skipFaceDetection,
                                   defaultValue: settings.defaultSkipFaceDetection,
                                   help: "Bypass Vision face detection and use simple center crop/pad instead.")
                    advancedToggle(title: "Prefer padding over center crop",
                                   binding: $model.preferPaddingOverCrop,
                                   defaultValue: settings.defaultPreferPaddingOverCrop,
                                   help: "Scale longer edges to fit and add padding instead of center-cropping when images are larger than the target size.")
                    advancedToggle(title: "Maximize subject fill after background removal",
                                   binding: $model.maximizeSubjectFill,
                                   defaultValue: settings.defaultMaximizeSubjectFill,
                                   help: "After removing the background, crop and scale the remaining subject so it fills the frame without trimming.")
                    Divider()
                    HStack {
                        Button("Reset to defaults") {
                            model.resetAdvancedOptionsToDefaults()
                        }
                        .disabled(model.isProcessing)
                        Text("Defaults can be changed under Settings (⌘,).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Options")
            }
            .disabled(model.isProcessing)
            .tint(.accentColor)

            Text("Configure super-resolution models from Settings (⌘,).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func advancedToggle(title: String,
                                binding: Binding<Bool>,
                                defaultValue: Bool,
                                help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: binding)
                .help(help)
            let matchesDefault = binding.wrappedValue == defaultValue
            let status = matchesDefault ? "Matches default" : "Default: \(defaultValue ? "On" : "Off")"
            Text(status)
                .font(.caption2)
                .foregroundColor(matchesDefault ? .secondary : .orange)
        }
    }
}

#Preview {
    let store = SettingsStore()
    InputControlsView(model: AppState(settings: store))
        .environmentObject(store)
        .padding()
        .frame(width: 800)
}
