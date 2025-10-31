import SwiftUI
import LoRAPrepCore

struct InputControlsView: View {
    @ObservedObject var model: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var advancedExpanded = false

    private let sizeRange = 512.0...2048.0
    private let featherRange = 0.0...10.0
    private let erosionRange = 0.0...5.0

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
                    if model.removeBackground {
                        segmentationControls
                    }
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

    private var segmentationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Segmentation mode", selection: $model.segmentationMode) {
                ForEach(availableSegmentationModes, id: \.self) { mode in
                    Text(label(for: mode)).tag(mode)
                }
            }
            .help("Choose which segmentation engine to use when removing backgrounds.")
            if !unavailableSegmentationModes.isEmpty {
                Text(unavailableDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mask feather")
                    Spacer()
                    Text("\(model.maskFeather, specifier: "%.1f") px")
                        .monospacedDigit()
                        .foregroundColor(model.maskFeather == settings.defaultMaskFeather ? .secondary : .orange)
                }
                Slider(value: $model.maskFeather, in: featherRange, step: 0.1)
                    .disabled(!model.removeBackground)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mask erosion")
                    Spacer()
                    Text("\(model.maskErosion, specifier: "%.1f") px")
                        .monospacedDigit()
                        .foregroundColor(model.maskErosion == settings.defaultMaskErosion ? .secondary : .orange)
                }
                Slider(value: $model.maskErosion, in: erosionRange, step: 0.1)
                    .disabled(!model.removeBackground)
            }
        }
        .onAppear { ensureValidSegmentationMode() }
        .onChange(of: model.segmentationMode, initial: false) { _, newValue in
            ensureValidSegmentationMode(for: newValue)
        }
    }

    private var availableSegmentationModes: [LoRAPrepConfiguration.SegmentationMode] {
        LoRAPrepConfiguration.SegmentationMode.allCases.filter { segmentationModeIsAvailable($0) }
    }

    private var unavailableSegmentationModes: [LoRAPrepConfiguration.SegmentationMode] {
        LoRAPrepConfiguration.SegmentationMode.allCases.filter { !segmentationModeIsAvailable($0) }
    }

    private var unavailableDescription: String {
        let names = unavailableSegmentationModes.map(label(for:)).joined(separator: ", ")
        return "Unavailable: \(names). Add the corresponding .mlmodelc to enable."
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

    private func ensureValidSegmentationMode() {
        guard !availableSegmentationModes.isEmpty else { return }
        if !segmentationModeIsAvailable(model.segmentationMode) {
            model.segmentationMode = availableSegmentationModes.first ?? .automatic
        }
    }

    private func ensureValidSegmentationMode(for selection: LoRAPrepConfiguration.SegmentationMode) {
        guard segmentationModeIsAvailable(selection) else {
            model.segmentationMode = availableSegmentationModes.first ?? .automatic
            return
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
