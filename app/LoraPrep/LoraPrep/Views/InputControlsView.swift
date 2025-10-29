import SwiftUI

struct InputControlsView: View {
    @ObservedObject var model: AppState

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

            HStack(spacing: 16) {
                Toggle("Remove background", isOn: $model.removeBackground)
                    .disabled(model.isProcessing)
                Toggle("Pad with transparency", isOn: $model.padWithTransparency)
                    .disabled(model.isProcessing)
                Toggle("Skip face detection", isOn: $model.skipFaceDetection)
                    .disabled(model.isProcessing)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Super-resolution Model")
                        .font(.headline)
                    if let modelURL = model.superResModelURL {
                        Text(modelURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Optional .mlmodel or .mlmodelc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Choose Model…") {
                    model.chooseSuperResModel()
                }
                .disabled(model.isProcessing)
                if model.superResModelURL != nil {
                    Button("Clear") {
                        model.clearSuperResModel()
                    }
                    .disabled(model.isProcessing)
                }
            }
        }
    }
}

#Preview {
    InputControlsView(model: AppState())
        .padding()
        .frame(width: 800)
}
