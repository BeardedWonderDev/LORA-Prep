import SwiftUI
import AppKit
import Combine
import LoRAPrepCore
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    // MARK: - User-configurable inputs
    @Published var inputFolder: URL?
    @Published var loraName: String = ""
    @Published var size: Double = 1024
    @Published var removeBackground: Bool = false
    @Published var padWithTransparency: Bool = true
    @Published var skipFaceDetection: Bool = false
    @Published var superResModelURL: URL?

    // MARK: - Processing state
    @Published var isProcessing: Bool = false
    @Published var progressFraction: Double = 0
    @Published var progressMessage: String = ""
    @Published var outputDirectory: URL?
    @Published var results: [ResultPair] = []
    @Published var failures: [ProcessingFailure] = []
    @Published var errorAlert: IdentifiableError?

    // MARK: - Derived flags
    var normalizedLoRAName: String {
        normLoraName(loraName)
    }

    var isReadyToProcess: Bool {
        guard let _ = inputFolder else { return false }
        return !normalizedLoRAName.isEmpty && !isProcessing
    }

    // MARK: - Actions
    func chooseInputFolder() {
        guard let panel = configuredOpenPanel(canChooseFiles: false, allowedTypes: nil) else { return }
        panel.message = "Select the folder containing your training photos."
        if panel.runModal() == .OK {
            inputFolder = panel.urls.first
        }
    }

    func chooseSuperResModel() {
        let utTypes: [UTType] = [.init(filenameExtension: "mlmodel")!, .init(filenameExtension: "mlmodelc")!]
        guard let panel = configuredOpenPanel(canChooseFiles: true, allowedTypes: utTypes) else { return }
        panel.message = "Choose a Core ML super-resolution model (optional)."
        if panel.runModal() == .OK {
            superResModelURL = panel.urls.first
        }
    }

    func clearSuperResModel() {
        superResModelURL = nil
    }

    func startProcessing() {
        guard let inputFolder, !normalizedLoRAName.isEmpty else {
            errorAlert = IdentifiableError(message: "Provide both an input folder and LoRA name before processing.")
            return
        }
        isProcessing = true
        progressFraction = 0
        progressMessage = "Preparing…"
        results.removeAll()
        failures.removeAll()
        outputDirectory = nil

        let configuration = LoRAPrepConfiguration(
            inputFolder: inputFolder,
            loraName: normalizedLoRAName,
            size: CGFloat(size),
            removeBackground: removeBackground,
            superResModelURL: superResModelURL,
            padWithTransparency: padWithTransparency,
            skipFaceDetection: skipFaceDetection
        )

        Task.detached(priority: .userInitiated) { [configuration, weak self] in
            do {
                let pipeline = try LoRAPrepPipeline(configuration: configuration)
                let result = try pipeline.run { update in
                    Task { @MainActor [weak self] in
                        self?.handle(progress: update)
                    }
                }
                await MainActor.run {
                    guard let self else { return }
                    self.outputDirectory = result.outputDirectory
                    self.results = result.images.map { ResultPair(original: $0.originalURL, processed: $0.processedURL) }
                    self.failures = result.failures
                    self.isProcessing = false
                    self.progressFraction = 1
                    self.progressMessage = self.resultSummary(for: result)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isProcessing = false
                    self.progressMessage = ""
                    self.errorAlert = IdentifiableError(message: error.localizedDescription)
                }
            }
        }
    }

    func revealOutput(in finder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([finder])
    }

    func revealFile(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private helpers
    private func configuredOpenPanel(canChooseFiles: Bool, allowedTypes: [UTType]?) -> NSOpenPanel? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !canChooseFiles
        panel.canChooseFiles = canChooseFiles
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let allowedTypes {
            panel.allowedContentTypes = allowedTypes
        }
        return panel
    }

    private func handle(progress update: ProgressUpdate) {
        switch update.kind {
        case .started(let total, let output):
            progressFraction = 0
            progressMessage = "Preparing \(total) files…"
            outputDirectory = output
        case .processing(let index, let total, let input, _):
            progressFraction = Double(index - 1) / Double(total)
            progressMessage = "Processing \(index) of \(total): \(input.lastPathComponent)"
        case .faceDetection(let log):
            switch log {
            case .found:
                break
            case .none:
                break
            }
        case .fileWritten(let index, let total, let output):
            progressFraction = Double(index) / Double(total)
            progressMessage = "Saved \(output.lastPathComponent)"
        case .failed(let index, let total, let input, let error):
            progressFraction = Double(index) / Double(total)
            progressMessage = "Failed \(input.lastPathComponent): \(error.localizedDescription)"
        case .completed:
            progressFraction = 1
            // message is finalized in Task completion
        }
    }

    private func resultSummary(for result: LoRAPrepResult) -> String {
        let processedCount = result.images.count
        let failureCount = result.failures.count
        if failureCount == 0 {
            return "Processing complete: \(processedCount) images ready."
        } else {
            return "Processing complete: \(processedCount) succeeded, \(failureCount) failed."
        }
    }
}

struct ResultPair: Identifiable, Hashable {
    let id = UUID()
    let original: URL
    let processed: URL
}

struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}
