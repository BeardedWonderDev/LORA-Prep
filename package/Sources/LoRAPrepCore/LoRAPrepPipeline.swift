import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

private let ctx = CIContext(options: [.useSoftwareRenderer: false])

// MARK: - Public API

public struct LoRAPrepConfiguration {
    public var inputFolder: URL
    public var loraName: String
    public var size: CGFloat
    public var removeBackground: Bool
    public var superResModelURL: URL?
    public var padWithTransparency: Bool
    public var skipFaceDetection: Bool
    public var fileExtensions: Set<String>

    public init(
        inputFolder: URL,
        loraName: String,
        size: CGFloat = 1024,
        removeBackground: Bool = false,
        superResModelURL: URL? = nil,
        padWithTransparency: Bool = true,
        skipFaceDetection: Bool = false,
        fileExtensions: Set<String> = ["jpg","jpeg","png","heic","tif","tiff","webp"]
    ) {
        self.inputFolder = inputFolder
        self.loraName = loraName
        self.size = size
        self.removeBackground = removeBackground
        self.superResModelURL = superResModelURL
        self.padWithTransparency = padWithTransparency
        self.skipFaceDetection = skipFaceDetection
        self.fileExtensions = fileExtensions
    }
}

public struct ProcessedImagePair: Hashable {
    public let originalURL: URL
    public let processedURL: URL

    public init(originalURL: URL, processedURL: URL) {
        self.originalURL = originalURL
        self.processedURL = processedURL
    }
}

public struct ProcessingFailure: Error {
    public let sourceURL: URL
    public let underlying: Error
}

public enum ProgressKind {
    case started(total: Int, outputDirectory: URL)
    case processing(index: Int, total: Int, input: URL, output: URL)
    case faceDetection(FaceDetectionLog)
    case fileWritten(index: Int, total: Int, output: URL)
    case failed(index: Int, total: Int, input: URL, error: Error)
    case completed(outputDirectory: URL)
}

public struct ProgressUpdate {
    public let kind: ProgressKind

    public init(kind: ProgressKind) {
        self.kind = kind
    }
}

public enum FaceDetectionLog {
    case found(rect: CGRect, imageSize: CGSize)
    case none(imageSize: CGSize)
}

public struct LoRAPrepResult {
    public let outputDirectory: URL
    public let images: [ProcessedImagePair]
    public let failures: [ProcessingFailure]
}

public final class LoRAPrepPipeline {
    private let configuration: LoRAPrepConfiguration
    private let superResEngine: SuperResolutionEngine?
    private let fileManager: FileManager

    public init(configuration: LoRAPrepConfiguration, fileManager: FileManager = .default) throws {
        self.configuration = configuration
        self.fileManager = fileManager
        if let modelURL = configuration.superResModelURL {
            self.superResEngine = try SuperResolutionEngine(modelURL: modelURL)
        } else {
            self.superResEngine = nil
        }
    }

    public func run(progress: ((ProgressUpdate) -> Void)? = nil) throws -> LoRAPrepResult {
        let normName = normLoraName(configuration.loraName)
        guard fileManager.fileExists(atPath: configuration.inputFolder.path) else {
            throw NSError(domain: "LoRAPrep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Input folder does not exist: \(configuration.inputFolder.path)"])
        }

        let outputDirectory = configuration.inputFolder.appendingPathComponent("processed-\(normName)-\(nowStamp())", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let items = try fileManager.contentsOfDirectory(at: configuration.inputFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { configuration.fileExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        if items.isEmpty {
            throw NSError(domain: "LoRAPrep", code: 2, userInfo: [NSLocalizedDescriptionKey: "No images in \(configuration.inputFolder.path)"])
        }

        progress?(ProgressUpdate(kind: .started(total: items.count, outputDirectory: outputDirectory)))

        var pairs: [ProcessedImagePair] = []
        var failures: [ProcessingFailure] = []
        var index = 0

        for url in items {
            index += 1
            let newName = String(format: "%02d_%@.png", index, normName)
            let dst = outputDirectory.appendingPathComponent(newName)
            progress?(ProgressUpdate(kind: .processing(index: index, total: items.count, input: url, output: dst)))
            do {
                try processOne(inputURL: url, outputURL: dst, progress: progress)
                pairs.append(ProcessedImagePair(originalURL: url, processedURL: dst))
                progress?(ProgressUpdate(kind: .fileWritten(index: index, total: items.count, output: dst)))
            } catch {
                failures.append(ProcessingFailure(sourceURL: url, underlying: error))
                progress?(ProgressUpdate(kind: .failed(index: index, total: items.count, input: url, error: error)))
            }
        }

        progress?(ProgressUpdate(kind: .completed(outputDirectory: outputDirectory)))
        return LoRAPrepResult(outputDirectory: outputDirectory, images: pairs, failures: failures)
    }

    private func processOne(inputURL: URL, outputURL: URL, progress: ((ProgressUpdate) -> Void)?) throws {
        var (ci, _) = try loadCIImage(inputURL)
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))

        let detectedFace: FaceBox?
        if configuration.skipFaceDetection {
            detectedFace = nil
        } else {
            detectedFace = try detectLargestFace(in: ci)
        }

        if let fr = detectedFace?.rect {
            progress?(ProgressUpdate(kind: .faceDetection(.found(rect: fr, imageSize: ci.extent.size))))
        } else {
            progress?(ProgressUpdate(kind: .faceDetection(.none(imageSize: ci.extent.size))))
        }

        var working = ci
        if let fr = detectedFace?.rect {
            working = centerImageOnFace(working, faceRect: fr, padColor: paddingColor(for: working))
        }

        if let engine = superResEngine {
            working = engine.upscaleUntilShortSideMeetsTarget(working, target: configuration.size)
        }

        if min(working.extent.width, working.extent.height) + 0.5 >= configuration.size {
            working = scaleShortSide(working, to: configuration.size)
            let ext = working.extent.standardized
            if ext.width >= configuration.size - 0.5 && ext.height >= configuration.size - 0.5 {
                working = centerCropSquare(working, size: configuration.size)
            } else {
                working = padToSquare(working, size: configuration.size, padColor: paddingColor(for: working))
            }
        } else {
            working = scaleLongSide(working, to: configuration.size)
            working = padToSquare(working, size: configuration.size, padColor: paddingColor(for: working))
        }

        let final: CIImage
        if configuration.removeBackground, #available(macOS 12.0, *), let mask = try? personMask(for: working) {
            let transparent = backgroundImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0), size: CGSize(width: configuration.size, height: configuration.size))
            final = working.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: mask
            ])
        } else {
            final = working
        }

        let rect = CGRect(x: final.extent.origin.x, y: final.extent.origin.y, width: configuration.size, height: configuration.size)
        guard let cg = ctx.createCGImage(final.cropped(to: rect), from: rect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            throw NSError(domain: "LoRAPrep", code: 3, userInfo: [NSLocalizedDescriptionKey: "Render failed for \(inputURL.lastPathComponent)"])
        }
        try writePNG(outputURL, cg)
    }

    private func paddingColor(for image: CIImage) -> CIColor {
        if configuration.padWithTransparency {
            return CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        return averageEdgeColor(of: image) ?? CIColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
}

// MARK: - Utilities

public func normLoraName(_ s: String) -> String {
    var t = s.uppercased()
    t = t.replacingOccurrences(of: "[^A-Z0-9 _-]", with: "", options: .regularExpression)
    t = t.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    return t.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

private func nowStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: Date())
}

private func loadCIImage(_ url: URL) throws -> (CIImage, CGImagePropertyOrientation) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw NSError(domain: "Load", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open \(url.path)"])
    }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let orientationRaw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up

    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "Load", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode \(url.lastPathComponent)"])
    }
    let ci = CIImage(cgImage: cg).oriented(forExifOrientation: Int32(orientation.rawValue))
    return (ci, orientation)
}

private func writePNG(_ url: URL, _ cg: CGImage) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Write", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create destination"])
    }
    CGImageDestinationAddImage(dest, cg, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "Write", code: 2, userInfo: [NSLocalizedDescriptionKey: "Finalize failed"])
    }
}

private struct FaceBox {
    let rect: CGRect
}

private struct FaceCandidate {
    let rect: CGRect
    let support: Int
}

private func filterFaceCandidates(_ candidates: [FaceCandidate], in extent: CGRect) -> [FaceCandidate] {
    let imgW = extent.width, imgH = extent.height
    let imgArea = imgW * imgH
    let minFrac: CGFloat = 0.06
    let maxFrac: CGFloat = 0.60
    let edgeGuard: CGFloat = 0.04

    return candidates.compactMap { cand in
        let r = cand.rect
        let area = r.width * r.height
        let frac = area / imgArea
        guard frac >= minFrac && frac <= maxFrac else { return nil }
        let cx = (r.midX - extent.minX) / imgW
        let cy = (r.midY - extent.minY) / imgH
        guard cx > edgeGuard && cx < (1 - edgeGuard) && cy > edgeGuard && cy < (1 - edgeGuard) else { return nil }
        return cand
    }
}

private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let inter = a.intersection(b)
    if inter.isNull || inter.width <= 0 || inter.height <= 0 {
        return 0
    }
    let interArea = inter.width * inter.height
    let unionArea = (a.width * a.height) + (b.width * b.height) - interArea
    if unionArea <= 0 { return 0 }
    return interArea / unionArea
}

private func transformRect(_ rect: CGRect, by transform: CGAffineTransform) -> CGRect {
    let p1 = rect.origin.applying(transform)
    let p2 = CGPoint(x: rect.maxX, y: rect.minY).applying(transform)
    let p3 = CGPoint(x: rect.minX, y: rect.maxY).applying(transform)
    let p4 = CGPoint(x: rect.maxX, y: rect.maxY).applying(transform)
    let xs = [p1.x, p2.x, p3.x, p4.x]
    let ys = [p1.y, p2.y, p3.y, p4.y]
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return rect.standardized
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

private func rotatedImage(_ ci: CIImage, degrees: CGFloat) -> (CIImage, CGAffineTransform) {
    if degrees == 0 { return (ci, .identity) }
    let radians = degrees * .pi / 180.0
    let rotation = CGAffineTransform(rotationAngle: radians)
    let rotated = ci.transformed(by: rotation)
    let extent = rotated.extent
    let translate = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    return (rotated.transformed(by: translate), rotation.concatenating(translate))
}

private func clusterRects(_ rects: [CGRect], iouThreshold: CGFloat) -> [RectCluster] {
    var clusters: [RectCluster] = []
    for rect in rects {
        var matched = false
        for idx in clusters.indices {
            if intersectionOverUnion(clusters[idx].representative, rect) >= iouThreshold {
                clusters[idx].add(rect)
                matched = true
                break
            }
        }
        if !matched {
            clusters.append(RectCluster(rect))
        }
    }
    return clusters
}

private struct RectCluster {
    private(set) var representative: CGRect
    private(set) var count: Int = 0
    private var sumMinX: CGFloat = 0
    private var sumMinY: CGFloat = 0
    private var sumMaxX: CGFloat = 0
    private var sumMaxY: CGFloat = 0

    init(_ rect: CGRect) {
        self.representative = rect
        self.count = 1
        self.sumMinX = rect.minX
        self.sumMinY = rect.minY
        self.sumMaxX = rect.maxX
        self.sumMaxY = rect.maxY
    }

    mutating func add(_ rect: CGRect) {
        count += 1
        sumMinX += rect.minX
        sumMinY += rect.minY
        sumMaxX += rect.maxX
        sumMaxY += rect.maxY
        representative = averageRect
    }

    var averageRect: CGRect {
        let c = CGFloat(count)
        let minX = sumMinX / c
        let minY = sumMinY / c
        let maxX = sumMaxX / c
        let maxY = sumMaxY / c
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}

private func detectFaceCandidates(in ci: CIImage, angles: [CGFloat]) throws -> [FaceCandidate] {
    var detections: [CGRect] = []
    for angle in angles {
        let (imageForDetection, forwardTransform) = rotatedImage(ci, degrees: angle)
        let rects = try visionFaceRects(in: imageForDetection)
        if rects.isEmpty { continue }
        let inverse = forwardTransform.inverted()
        for rect in rects {
            var mapped = transformRect(rect, by: inverse)
            mapped = mapped.intersection(ci.extent)
            if mapped.isNull || mapped.width <= 2 || mapped.height <= 2 {
                continue
            }
            detections.append(mapped)
        }
    }
    if detections.isEmpty { return [] }
    let clusters = clusterRects(detections, iouThreshold: 0.35)
    return clusters.map { cluster in
        let rect = cluster.averageRect.intersection(ci.extent)
        return FaceCandidate(rect: rect, support: cluster.count)
    }
}

private func visionFaceRects(in ci: CIImage) throws -> [CGRect] {
    #if targetEnvironment(macCatalyst)
    return []
    #else
    let handler = VNImageRequestHandler(ciImage: ci, options: [:])
    let request = VNDetectFaceRectanglesRequest()
    try handler.perform([request])
    guard let results = request.results else { return [] }
    let extent = ci.extent
    return results.map { obs in
        let boundingBox = obs.boundingBox
        let w = boundingBox.width * extent.width
        let h = boundingBox.height * extent.height
        let x = boundingBox.minX * extent.width
        let y = boundingBox.minY * extent.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
    #endif
}

private final class SuperResolutionEngine {
    private let request: VNCoreMLRequest

    init(modelURL: URL) throws {
        let compiled: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiled = modelURL
        } else {
            compiled = try MLModel.compileModel(at: modelURL)
        }
        let model = try MLModel(contentsOf: compiled)
        let vnModel = try VNCoreMLModel(for: model)
        request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit
        request.usesCPUOnly = false
    }

    private func upscaleOnce(_ ci: CIImage) throws -> CIImage {
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            throw NSError(domain: "SuperRes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage for super-resolution"])
        }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first as? VNPixelBufferObservation else {
            throw NSError(domain: "SuperRes", code: 2, userInfo: [NSLocalizedDescriptionKey: "Super-resolution model returned no pixel buffer"])
        }
        let output = CIImage(cvPixelBuffer: obs.pixelBuffer)
        return output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
    }

    func upscaleUntilShortSideMeetsTarget(_ ci: CIImage, target: CGFloat) -> CIImage {
        var current = ci
        var iterations = 0
        while min(current.extent.width, current.extent.height) + 0.5 < target && iterations < 4 {
            guard let actual = try? upscaleOnce(current) else { break }
            let gainW = actual.extent.width / current.extent.width
            let gainH = actual.extent.height / current.extent.height
            if gainW <= 1.01 && gainH <= 1.01 {
                break
            }
            current = actual.transformed(by: CGAffineTransform(translationX: -actual.extent.minX, y: -actual.extent.minY))
            iterations += 1
        }
        return current
    }
}

private func detectLargestFace(in ci: CIImage) throws -> FaceBox? {
    let angles: [CGFloat] = [-15, 0, 15]
    let candidates = try detectFaceCandidates(in: ci, angles: angles)

    if candidates.isEmpty {
        let baseline = try visionFaceRects(in: ci)
        guard let largest = baseline.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        return FaceBox(rect: largest)
    }

    let prioritized = candidates.filter { $0.support >= 2 }
    var filtered = filterFaceCandidates(prioritized, in: ci.extent)
    if filtered.isEmpty {
        filtered = filterFaceCandidates(candidates, in: ci.extent)
    }

    if let best = filtered.max(by: { ($0.rect.width * $0.rect.height) < ($1.rect.width * $1.rect.height) }) {
        return FaceBox(rect: best.rect)
    }

    let fallbackSource = prioritized.isEmpty ? candidates : prioritized
    if let best = fallbackSource.max(by: { lhs, rhs in
        if lhs.support == rhs.support {
            return (lhs.rect.width * lhs.rect.height) < (rhs.rect.width * rhs.rect.height)
        }
        return lhs.support < rhs.support
    }) {
        return FaceBox(rect: best.rect)
    }
    return nil
}

@available(macOS 12.0, *)
private func personMask(for ci: CIImage) throws -> CIImage? {
    let req = VNGeneratePersonSegmentationRequest()
    req.qualityLevel = .accurate
    req.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let handler = VNImageRequestHandler(ciImage: ci, options: [:])
    try handler.perform([req])
    guard let obs = req.results?.first as? VNPixelBufferObservation else { return nil }
    let mask = CIImage(cvPixelBuffer: obs.pixelBuffer)
    let scaleX = ci.extent.width / mask.extent.width
    let scaleY = ci.extent.height / mask.extent.height
    return mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
}

private func scaleLongSide(_ ci: CIImage, to target: CGFloat) -> CIImage {
    let w = ci.extent.width, h = ci.extent.height
    let longSide = max(w, h)
    if longSide <= target + 0.0001 { return ci }
    let s = target / longSide
    return ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
}

private func scaleShortSide(_ ci: CIImage, to target: CGFloat) -> CIImage {
    let w = ci.extent.width, h = ci.extent.height
    let shortSide = min(w, h)
    if abs(shortSide - target) < 0.001 { return ci }
    let scale = target / shortSide
    return ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
}

private func padToSquare(_ ci: CIImage, size: CGFloat, padColor: CIColor) -> CIImage {
    let extent = ci.extent.standardized
    let w = extent.width
    let h = extent.height
    guard size >= w - 0.001 && size >= h - 0.001 else { return ci }
    let ox = (size - w) / 2 - extent.minX
    let oy = (size - h) / 2 - extent.minY
    let background = backgroundImage(color: padColor, size: CGSize(width: size, height: size))
    let translated = ci.transformed(by: CGAffineTransform(translationX: ox, y: oy))
    return translated.composited(over: background).cropped(to: background.extent)
}

private func backgroundImage(color: CIColor, size: CGSize) -> CIImage {
    CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size.width, height: size.height))
}

private func centerImageOnFace(_ ci: CIImage, faceRect: CGRect, padColor: CIColor) -> CIImage {
    let extent = ci.extent.standardized
    let face = faceRect.standardized

    let left = face.midX - extent.minX
    let right = extent.maxX - face.midX
    let bottom = face.midY - extent.minY
    let top = extent.maxY - face.midY

    let padLeft = max(0, right - left)
    let padRight = max(0, left - right)
    let padBottom = max(0, top - bottom)
    let padTop = max(0, bottom - top)

    let newWidth = extent.width + padLeft + padRight
    let newHeight = extent.height + padTop + padBottom

    let translated = ci.transformed(by: CGAffineTransform(translationX: padLeft - extent.minX,
                                                          y: padBottom - extent.minY))
    let background = backgroundImage(color: padColor, size: CGSize(width: newWidth, height: newHeight))
    return translated.composited(over: background).cropped(to: background.extent)
}

private func centerCropSquare(_ ci: CIImage, size: CGFloat) -> CIImage {
    let extent = ci.extent.standardized
    let x = extent.midX - size / 2.0
    let y = extent.midY - size / 2.0
    let cropRect = CGRect(x: x, y: y, width: size, height: size)
    let intersection = cropRect.intersection(extent)
    let cropped = ci.cropped(to: intersection)
    return cropped.transformed(by: CGAffineTransform(translationX: -intersection.minX, y: -intersection.minY))
}

private func averageEdgeColor(of image: CIImage, borderFraction: CGFloat = 0.04) -> CIColor? {
    let extent = image.extent.standardized
    guard extent.width > 0, extent.height > 0 else { return nil }
    let border = max(1.0, min(extent.width, extent.height) * borderFraction)
    var colors: [CIColor] = []
    let regions: [CGRect] = [
        CGRect(x: extent.minX, y: extent.maxY - border, width: extent.width, height: border),
        CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: border),
        CGRect(x: extent.minX, y: extent.minY, width: border, height: extent.height),
        CGRect(x: extent.maxX - border, y: extent.minY, width: border, height: extent.height)
    ]
    for region in regions {
        if region.width <= 0 || region.height <= 0 { continue }
        if let color = averageColor(of: image.cropped(to: region)) {
            colors.append(color)
        }
    }
    guard !colors.isEmpty else { return nil }
    let sum = colors.reduce(into: (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))) { partial, color in
        partial.r += color.red
        partial.g += color.green
        partial.b += color.blue
        partial.a += color.alpha
    }
    let count = CGFloat(colors.count)
    return CIColor(red: sum.r / count, green: sum.g / count, blue: sum.b / count, alpha: sum.a / count)
}

private func averageColor(of image: CIImage) -> CIColor? {
    guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    let extent = image.extent
    filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
    guard let output = filter.outputImage else { return nil }
    var bitmap = [UInt8](repeating: 0, count: 4)
    ctx.render(output,
               toBitmap: &bitmap,
               rowBytes: 4,
               bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBA8,
               colorSpace: CGColorSpaceCreateDeviceRGB())
    let r = CGFloat(bitmap[0]) / 255
    let g = CGFloat(bitmap[1]) / 255
    let b = CGFloat(bitmap[2]) / 255
    let a = CGFloat(bitmap[3]) / 255
    return CIColor(red: r, green: g, blue: b, alpha: a)
}
