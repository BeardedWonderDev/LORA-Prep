import SwiftUI
import AppKit
import LoRAPrepCore

struct ResultsView: View {
    @ObservedObject var model: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.title3)
                    .bold()
                Spacer()
                if let output = model.outputDirectory {
                    Button("Reveal Output Folder") {
                        model.revealOutput(in: output)
                    }
                    .disabled(model.isProcessing)
                }
            }

            if !model.progressMessage.isEmpty || model.isProcessing {
                ProgressView(value: model.isProcessing ? model.progressFraction : 1)
                    .progressViewStyle(.linear)
                Text(model.progressMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.results.isEmpty {
                placeholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(model.results) { pair in
                            ResultRowView(pair: pair) {
                                model.revealFile(pair.processed)
                            } revealOriginal: {
                                model.revealFile(pair.original)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !model.failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failures")
                        .font(.headline)
                    ForEach(Array(model.failures.enumerated()), id: \.offset) { entry in
                        Text("\(entry.offset + 1). \(entry.element.sourceURL.lastPathComponent): \(entry.element.underlying.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            if model.isProcessing {
                Text("Processing images…")
                    .foregroundStyle(.secondary)
            } else {
                Text("No processed images yet. Configure inputs and press “Process Images”.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ResultRowView: View {
    let pair: ResultPair
    let revealProcessed: () -> Void
    let revealOriginal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                thumbnailColumn(title: "Original", url: pair.original, action: revealOriginal)
                thumbnailColumn(title: "Processed", url: pair.processed, action: revealProcessed)
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func thumbnailColumn(title: String, url: URL, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ThumbnailImage(url: url)
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )
            Text(url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
            Button("Reveal in Finder") {
                action()
            }
        }
    }
}

private struct ThumbnailImage: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(Color.black.opacity(0.05))
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "questionmark.square.dashed")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let state = AppState()
    state.results = [
        ResultPair(original: URL(fileURLWithPath: "/tmp/input1.png"), processed: URL(fileURLWithPath: "/tmp/output1.png"))
    ]
    return ResultsView(model: state)
        .frame(width: 720)
        .padding()
}
