import Foundation

public func segmentationModeIsAvailable(_ mode: LoRAPrepConfiguration.SegmentationMode) -> Bool {
    switch mode {
    case .automatic, .accurateVision:
        return true
    case .deepLabV3:
        return modelExists(named: "DeepLabV3")
    case .robustVideoMatting:
        return modelExists(named: "RobustVideoMatting")
    }
}

private func modelExists(named name: String) -> Bool {
    let fileManager = FileManager.default

    if let mainURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
       fileManager.fileExists(atPath: mainURL.path) {
        return true
    }

    if let frameworkURL = Bundle(for: BundleFinder.self).url(forResource: name, withExtension: "mlmodelc"),
       fileManager.fileExists(atPath: frameworkURL.path) {
        return true
    }

    return false
}

private final class BundleFinder {}
