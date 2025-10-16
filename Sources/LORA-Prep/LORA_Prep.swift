import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

// MARK: - CLI args

struct Args {
    var input: URL
    var loraName: String
    var removeBackground: Bool = false
    var size: CGFloat = 1024

    static func parse() -> Args? {
        var input: URL?
        var name: String?
        var removeBG = false
        var size: CGFloat = 1024

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--input", "-i":
                if let p = it.next() { input = URL(fileURLWithPath: p) }
            case "--lora-name", "-n":
                if let s = it.next() { name = s }
            case "--remove-background", "-b":
                removeBG = true
            case "--size", "-s":
                if let v = it.next(), let f = Double(v) { size = CGFloat(f) }
            case "--help", "-h":
                print("""
                LoRAPrep
                Usage:
                  LoRAPrep --input <folder> --lora-name <NAME> [--remove-background] [--size 1024]
                """)
                return nil
            default:
                print("Unknown arg: \(a)")
            }
        }
        guard let input = input, let name = name else {
            print("Missing --input or --lora-name. Use --help.")
            return nil
        }
        return Args(input: input, loraName: name, removeBackground: removeBG, size: size)
    }
}

// MARK: - Utilities

let ctx = CIContext(options: [.useSoftwareRenderer: false])

func nowStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: Date())
}

func normLoraName(_ s: String) -> String {
    var t = s.uppercased()
    t = t.replacingOccurrences(of: "[^A-Z0-9 _-]", with: "", options: .regularExpression)
    t = t.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    return t.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

func loadCIImage(_ url: URL) throws -> (CIImage, CGImagePropertyOrientation) {
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

func writePNG(_ url: URL, _ cg: CGImage) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Write", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create destination"])
    }
    // No metadata supplied -> EXIF stripped
    CGImageDestinationAddImage(dest, cg, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "Write", code: 2, userInfo: [NSLocalizedDescriptionKey: "Finalize failed"])
    }
}

/// Renders the average color of a CIImage region (used by both whole-image and edge-average)
private func regionAverageColor(_ image: CIImage, rect: CGRect) -> CIColor {
    let filter = CIFilter.areaAverage()
    filter.inputImage = image.cropped(to: rect)
    filter.extent = rect
    guard let out = filter.outputImage else { return CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1) }
    var bitmap = [UInt8](repeating: 0, count: 4)
    ctx.render(out, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    return CIColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1.0)
}

/// Whole-image average (kept for completeness)
func averageColor(_ image: CIImage) -> CIColor {
    return regionAverageColor(image, rect: image.extent)
}

/// Edge-average color: averages a thin band along all four edges (default 4% of min dimension)
func edgeAverageColor(_ image: CIImage, borderFrac: CGFloat = 0.04) -> CIColor {
    let e = image.extent
    let bw = max(1.0, min(e.width, e.height) * borderFrac)
    let top = CGRect(x: e.minX, y: e.maxY - bw, width: e.width, height: bw)
    let bottom = CGRect(x: e.minX, y: e.minY, width: e.width, height: bw)
    let left = CGRect(x: e.minX, y: e.minY, width: bw, height: e.height)
    let right = CGRect(x: e.maxX - bw, y: e.minY, width: bw, height: e.height)

    // Average the four bands by sampling each then averaging their RGBA components
    let cTop = regionAverageColor(image, rect: top)
    let cBottom = regionAverageColor(image, rect: bottom)
    let cLeft = regionAverageColor(image, rect: left)
    let cRight = regionAverageColor(image, rect: right)

    func comp(_ f: (CIColor) -> CGFloat) -> CGFloat {
        let vals = [f(cTop), f(cBottom), f(cLeft), f(cRight)]
        return vals.reduce(0, +) / CGFloat(vals.count)
    }
    return CIColor(red: comp { $0.red }, green: comp { $0.green }, blue: comp { $0.blue }, alpha: 1)
}

// MARK: - Vision helpers

struct FaceBox {
    let rect: CGRect // in image coordinates
}

struct FaceCandidate {
    let rect: CGRect
    let support: Int
}

/// Filters Vision face boxes similar to the Python pipeline (size sanity + edge guard)
func filterFaceCandidates(_ candidates: [FaceCandidate], in extent: CGRect) -> [FaceCandidate] {
    let imgW = extent.width, imgH = extent.height
    let imgArea = imgW * imgH
    let minFrac: CGFloat = 0.06   // 6%
    let maxFrac: CGFloat = 0.60   // 60%
    let edgeGuard: CGFloat = 0.04 // 4%

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

// MARK: - Detection helpers

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
    if abs(degrees) < 0.0001 {
        return (ci, .identity)
    }
    let radians = degrees * (.pi / 180)
    let center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
    let translateToOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
    let rotation = translateToOrigin.rotated(by: radians).translatedBy(x: center.x, y: center.y)
    let rotated = ci.transformed(by: rotation)
    let align = CGAffineTransform(translationX: -rotated.extent.origin.x, y: -rotated.extent.origin.y)
    let output = rotated.transformed(by: align)
    return (output, rotation.concatenating(align))
}

private func visionFaceRects(in image: CIImage) throws -> [CGRect] {
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    let req = VNDetectFaceRectanglesRequest()
    try handler.perform([req])
    guard let obs: [VNFaceObservation] = req.results, !obs.isEmpty else { return [] }
    let w = image.extent.width, h = image.extent.height
    return obs.map { bb in
        let b = bb.boundingBox
        return CGRect(x: b.minX * w, y: b.minY * h, width: b.width * w, height: b.height * h)
    }
}

private struct RectCluster {
    private(set) var count: Int
    private var sumMinX: CGFloat
    private var sumMinY: CGFloat
    private var sumMaxX: CGFloat
    private var sumMaxY: CGFloat
    private(set) var representative: CGRect

    init(_ rect: CGRect) {
        count = 1
        sumMinX = rect.minX
        sumMinY = rect.minY
        sumMaxX = rect.maxX
        sumMaxY = rect.maxY
        representative = rect
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

func detectLargestFace(in ci: CIImage) throws -> FaceBox? {
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
func personMask(for ci: CIImage) throws -> CIImage? {
    let req = VNGeneratePersonSegmentationRequest()
    req.qualityLevel = .accurate
    req.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let handler = VNImageRequestHandler(ciImage: ci, options: [:])
    try handler.perform([req])
    guard let obs = req.results?.first as? VNPixelBufferObservation else { return nil }
    let mask = CIImage(cvPixelBuffer: obs.pixelBuffer)
    // Vision masks come normalized to the input request extent size; CIImage above keeps its own size.
    // We’ll scale it to match the original image extent.
    let scaleX = ci.extent.width / mask.extent.width
    let scaleY = ci.extent.height / mask.extent.height
    return mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
}

// MARK: - Geom ops

func clampSquareAround(face: CGRect, in img: CGRect, marginK: CGFloat) -> CGRect {
    // Proposed side with margin
    var side = max(face.width, face.height) * marginK
    // Python parity: clamp side between half of min(imgW,imgH) and 110% of max(imgW,imgH)
    let minSide = min(img.width, img.height) / 2.0
    let maxSide = max(img.width, img.height) * 1.10
    side = max(minSide, min(side, maxSide))

    let cx = face.midX, cy = face.midY
    var x1 = cx - side/2, y1 = cy - side/2
    var x2 = cx + side/2, y2 = cy + side/2

    // clamp to image bounds by shifting the square
    if x1 < img.minX { let d = img.minX - x1; x1 += d; x2 += d }
    if y1 < img.minY { let d = img.minY - y1; y1 += d; y2 += d }
    if x2 > img.maxX { let d = x2 - img.maxX; x1 -= d; x2 -= d }
    if y2 > img.maxY { let d = y2 - img.maxY; y1 -= d; y2 -= d }

    // Ensure we still have a square fully inside image (shrink if necessary)
    let finalSide = min(x2 - x1, y2 - y1)
    let nx1 = max(img.minX, min(cx - finalSide/2, img.maxX - finalSide))
    let ny1 = max(img.minY, min(cy - finalSide/2, img.maxY - finalSide))
    return CGRect(x: nx1, y: ny1, width: finalSide, height: finalSide)
}

func scaleLongSide(_ ci: CIImage, to target: CGFloat) -> CIImage {
    let w = ci.extent.width, h = ci.extent.height
    let longSide = max(w, h)
    if longSide <= target + 0.0001 { return ci }
    let s = target / longSide
    return ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
}

func centerCropOrPadToSquare(_ ci: CIImage, size: CGFloat, padColor: CIColor) -> CIImage {
    let w = ci.extent.width, h = ci.extent.height
    if w >= size && h >= size {
        // center-crop
        let x = (w - size)/2, y = (h - size)/2
        return ci.cropped(to: CGRect(x: x, y: y, width: size, height: size))
    } else {
        // pad
        let bg = CIImage(color: padColor).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let ox = (size - w)/2, oy = (size - h)/2
        return ci.transformed(by: CGAffineTransform(translationX: ox, y: oy)).composited(over: bg)
    }
}

// MARK: - Pipeline

struct Pipeline {
    let args: Args

    func run() throws {
        let fm = FileManager.default
        let lora = normLoraName(args.loraName)
        let out = args.input.appendingPathComponent("processed-\(lora)-\(nowStamp())", isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)

        // gather top-level images
        let exts: Set<String> = ["jpg","jpeg","png","heic","tif","tiff","webp"]
        let items = try fm.contentsOfDirectory(at: args.input, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        if items.isEmpty {
            throw NSError(domain: "CLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No images in \(args.input.path)"])
        }

        print("[\(Date())] Output: \(out.path)")

        var idx = 0
        for url in items {
            idx += 1
            let newName = String(format: "%02d_%@.png", idx, lora)
            let dst = out.appendingPathComponent(newName)
            print("[\(Date())] Processing: \(url.lastPathComponent) -> \(newName)")

            do {
                try processOne(inputURL: url, outputURL: dst)
            } catch {
                fputs("[ERROR] \(url.lastPathComponent): \(error)\n", stderr)
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }

    func processOne(inputURL: URL, outputURL: URL) throws {
        var (ci, _) = try loadCIImage(inputURL)
        // Ensure we work in a standard bounds origin
        ci = ci.transformed(by: .identity)
        ci = scaleLongSide(ci, to: args.size)
        let basePadColor = edgeAverageColor(ci)

        // 1) FACE PATH
        var faceRect: CGRect? = nil
        if let box = try? detectLargestFace(in: ci) {
            faceRect = box.rect
        }

        let final: CIImage
        if let fr = faceRect {
            print("FACE_FOUND box=(\(Int(fr.minX)),\(Int(fr.minY)),\(Int(fr.maxX)),\(Int(fr.maxY))) size=(\(Int(ci.extent.width))x\(Int(ci.extent.height)))")
            // Face-aware square around face with margin + pad background if needed
            let square = clampSquareAround(face: fr, in: ci.extent, marginK: 1.9)
            let padColor = basePadColor
            // Crop if square fully inside; else pad canvas to square then crop
            var stage: CIImage
            if ci.extent.contains(square) {
                stage = ci.cropped(to: square)
            } else {
                // Make a square canvas and paste the crop area (pad)
                let side = max(square.width, square.height)
                let bg = CIImage(color: padColor).cropped(to: CGRect(origin: .zero, size: CGSize(width: side, height: side)))
                let translated = ci.cropped(to: ci.extent.intersection(square))
                    .transformed(by: CGAffineTransform(translationX: max(0, -square.minX), y: max(0, -square.minY)))
                stage = translated.composited(over: bg)
            }
            // Resize to output size
            let scale = args.size / max(stage.extent.width, stage.extent.height)
            let stageResized = stage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            // Optional: background removal (Vision segmentation) → transparent background
            if args.removeBackground, #available(macOS 12.0, *), let mask = try? personMask(for: stageResized) {
                let transparent = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                    .cropped(to: CGRect(x: 0, y: 0, width: args.size, height: args.size))
                final = stageResized.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: transparent,
                    kCIInputMaskImageKey: mask
                ])
            } else {
                final = stageResized
            }
        } else {
            print("NO_FACE size=(\(Int(ci.extent.width))x\(Int(ci.extent.height)))")
            // 2) NO-FACE PATH: long side already scaled; center-crop or pad to 1024
            final = centerCropOrPadToSquare(ci, size: args.size, padColor: basePadColor)
        }

        // Render and write PNG (no metadata)
        let rect = CGRect(x: final.extent.origin.x, y: final.extent.origin.y, width: args.size, height: args.size)
        guard let cg = ctx.createCGImage(final.cropped(to: rect), from: rect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            throw NSError(domain: "Render", code: 1, userInfo: [NSLocalizedDescriptionKey: "Render failed"])
        }
        try writePNG(outputURL, cg)
    }
}

// MARK: - Main

guard let args = Args.parse() else { exit(1) }
do {
    try Pipeline(args: args).run()
} catch {
    fputs("Fatal: \(error)\n", stderr)
    exit(2)
}
