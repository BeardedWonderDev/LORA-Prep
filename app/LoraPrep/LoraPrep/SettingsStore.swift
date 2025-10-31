import Foundation
import Combine

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let removeBackground = "settings.defaultRemoveBackground"
        static let padWithTransparency = "settings.defaultPadWithTransparency"
        static let skipFaceDetection = "settings.defaultSkipFaceDetection"
        static let superResModelPath = "settings.superResModelPath"
        static let superResModelBookmark = "settings.superResModelBookmark"
        static let preferPaddingOverCrop = "settings.defaultPreferPaddingOverCrop"
        static let maximizeSubjectFill = "settings.defaultMaximizeSubjectFill"
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

    @Published var defaultPreferPaddingOverCrop: Bool {
        didSet { defaults.set(defaultPreferPaddingOverCrop, forKey: Keys.preferPaddingOverCrop) }
    }

    @Published var defaultMaximizeSubjectFill: Bool {
        didSet { defaults.set(defaultMaximizeSubjectFill, forKey: Keys.maximizeSubjectFill) }
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

    @Published var superResModelBookmark: Data? {
        didSet {
            if let bookmark = superResModelBookmark {
                defaults.set(bookmark, forKey: Keys.superResModelBookmark)
            } else {
                defaults.removeObject(forKey: Keys.superResModelBookmark)
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
        defaultPreferPaddingOverCrop = defaults.bool(forKey: Keys.preferPaddingOverCrop)
        defaultMaximizeSubjectFill = defaults.bool(forKey: Keys.maximizeSubjectFill)
        superResModelPath = defaults.string(forKey: Keys.superResModelPath)
        superResModelBookmark = defaults.data(forKey: Keys.superResModelBookmark)
    }

    func persistSuperResModelURL(_ url: URL) {
        superResModelPath = url.path
        do {
            superResModelBookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            superResModelBookmark = nil
        }
    }

    func clearSuperResModel() {
        superResModelBookmark = nil
        superResModelPath = nil
    }

    func loadSuperResModelURL() -> URL? {
        if let bookmark = superResModelBookmark {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
                if stale {
                    persistSuperResModelURL(url)
                }
                return url
            } catch {
                superResModelBookmark = nil
            }
        }

        if let path = superResModelPath {
            let cleanedPath: String
            if path.hasSuffix("/.") {
                cleanedPath = String(path.dropLast(2))
                superResModelPath = cleanedPath
            } else {
                cleanedPath = path
            }
            return URL(fileURLWithPath: cleanedPath)
        }

        return nil
    }
}
