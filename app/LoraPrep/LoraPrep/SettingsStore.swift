import Foundation
import Combine

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let removeBackground = "settings.defaultRemoveBackground"
        static let padWithTransparency = "settings.defaultPadWithTransparency"
        static let skipFaceDetection = "settings.defaultSkipFaceDetection"
        static let superResModelPath = "settings.superResModelPath"
    }

    private let defaults: UserDefaults

    @Published var defaultRemoveBackground: Bool {
        didSet { defaults.set(defaultRemoveBackground, forKey: Keys.removeBackground) }
    }

    @Published var defaultPadWithTransparency: Bool {
        didSet { defaults.set(defaultPadWithTransparency, forKey: Keys.padWithTransparency) }
    }

    @Published var defaultSkipFaceDetection: Bool {
        didSet { defaults.set(defaultSkipFaceDetection, forKey: Keys.skipFaceDetection) }
    }

    @Published var superResModelPath: String? {
        didSet {
            if let path = superResModelPath {
                defaults.set(path, forKey: Keys.superResModelPath)
            } else {
                defaults.removeObject(forKey: Keys.superResModelPath)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.padWithTransparency) == nil {
            defaults.set(true, forKey: Keys.padWithTransparency)
        }

        defaultRemoveBackground = defaults.bool(forKey: Keys.removeBackground)
        defaultPadWithTransparency = defaults.bool(forKey: Keys.padWithTransparency)
        defaultSkipFaceDetection = defaults.bool(forKey: Keys.skipFaceDetection)
        superResModelPath = defaults.string(forKey: Keys.superResModelPath)
    }
}
