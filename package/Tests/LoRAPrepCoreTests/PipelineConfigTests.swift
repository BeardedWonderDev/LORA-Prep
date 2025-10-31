import XCTest
import LoRAPrepCore
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class PipelineConfigTests: XCTestCase {
    private let fm = FileManager.default

    func testPaddingWithEdgeColorProducesOpaquePNG() throws {
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let sourceImageURL = inputDir.appendingPathComponent("sample.png")
        try writeSolidImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1), size: CGSize(width: 200, height: 100), to: sourceImageURL)

        let config = LoRAPrepConfiguration(
            inputFolder: inputDir,
            loraName: "sample",
            size: 256,
            removeBackground: false,
            superResModelURL: nil,
            padWithTransparency: false,
            skipFaceDetection: true
        )

        let pipeline = try LoRAPrepPipeline(configuration: config)
        let result = try pipeline.run()

        XCTAssertEqual(result.images.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: result.outputDirectory.path))

        let processedURL = try XCTUnwrap(result.images.first?.processedURL)
        let alpha = try extractAlphaAtCorner(of: processedURL)
        XCTAssertEqual(alpha, 255, "Corner pixel should be opaque when padding with edge color")
    }

    func testPaddingTransparentHasZeroAlpha() throws {
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let sourceImageURL = inputDir.appendingPathComponent("sample.png")
        try writeSolidImage(color: CIColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1), size: CGSize(width: 100, height: 200), to: sourceImageURL)

        let config = LoRAPrepConfiguration(
            inputFolder: inputDir,
            loraName: "sample",
            size: 256,
            removeBackground: false,
            superResModelURL: nil,
            padWithTransparency: true,
            skipFaceDetection: true
        )

        let pipeline = try LoRAPrepPipeline(configuration: config)
        let result = try pipeline.run()

        XCTAssertEqual(result.images.count, 1)

        let processedURL = try XCTUnwrap(result.images.first?.processedURL)
        let alpha = try extractAlphaAtCorner(of: processedURL)
        XCTAssertEqual(alpha, 0, "Corner pixel should be transparent when padding transparently")
    }

    func testPreferPaddingOverCropAddsTransparentBorder() throws {
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let source = inputDir.appendingPathComponent("large.png")
        try writeSolidImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1),
                            size: CGSize(width: 800, height: 600),
                            to: source)

        let baseConfig = LoRAPrepConfiguration(
            inputFolder: inputDir,
            loraName: "sample",
            size: 256,
            removeBackground: false,
            superResModelURL: nil,
            padWithTransparency: true,
            skipFaceDetection: true
        )

        // Baseline: default behavior crops rather than pads, so the corner stays opaque.
        do {
            let pipeline = try LoRAPrepPipeline(configuration: baseConfig)
            let result = try pipeline.run()
            let processedURL = try XCTUnwrap(result.images.first?.processedURL)
            XCTAssertEqual(try extractAlphaAtCorner(of: processedURL), 255)
        }

        // Preferred padding: forces scale-long-side + padding, so the corner is transparent.
        do {
            let paddedConfig = LoRAPrepConfiguration(
                inputFolder: inputDir,
                loraName: "sample2",
                size: 256,
                removeBackground: false,
                superResModelURL: nil,
                padWithTransparency: true,
                skipFaceDetection: true,
                preferPaddingOverCrop: true
            )
            let pipeline = try LoRAPrepPipeline(configuration: paddedConfig)
            let result = try pipeline.run()
            let processedURL = try XCTUnwrap(result.images.first?.processedURL)
            XCTAssertEqual(try extractAlphaAtCorner(of: processedURL), 0)
        }
    }

    func testMaximizeSubjectFillExpandsOpaqueRegion() throws {
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let sourceImageURL = inputDir.appendingPathComponent("transparentSubject.png")
        try writeTransparentImage(size: CGSize(width: 512, height: 512),
                                  subjectRect: CGRect(x: 200, y: 160, width: 112, height: 160),
                                  color: CIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1),
                                  to: sourceImageURL)

        var baseConfig = LoRAPrepConfiguration(
            inputFolder: inputDir,
            loraName: "sample",
            size: 256,
            removeBackground: false,
            superResModelURL: nil,
            padWithTransparency: true,
            skipFaceDetection: true,
            preferPaddingOverCrop: true
        )

        // Without maximize flag
        var baselineWidth: CGFloat = 0
        do {
            let pipeline = try LoRAPrepPipeline(configuration: baseConfig)
            let result = try pipeline.run()
            let processedURL = try XCTUnwrap(result.images.first?.processedURL)
            let bbox = try XCTUnwrap(opaqueBoundingBox(of: processedURL))
            baselineWidth = bbox.width
            XCTAssertLessThan(bbox.width, 200, "Expected original transparent borders to remain without maximize flag")
        }

        // With maximize flag
        baseConfig.loraName = "sample-max"
        baseConfig.maximizeSubjectFill = true
        do {
            let pipeline = try LoRAPrepPipeline(configuration: baseConfig)
            let result = try pipeline.run()
            let processedURL = try XCTUnwrap(result.images.first?.processedURL)
            let bbox = try XCTUnwrap(opaqueBoundingBox(of: processedURL))
            XCTAssertGreaterThan(bbox.width, baselineWidth + 30, "Subject should expand when maximize flag is enabled")
        }
    }

    // MARK: - Helpers

    private func writeSolidImage(color: CIColor, size: CGSize, to url: URL) throws {
        let ciImage = CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
            XCTFail("Failed to create CGImage")
            return
        }
        try writePNG(to: url, image: cg)
    }

    private func writePNG(to url: URL, image: CGImage) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("Failed to create image destination")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            XCTFail("Failed to finalize image destination")
        }
    }

    private func extractAlphaAtCorner(of url: URL) throws -> UInt8 {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Failed to load image at \(url.path)")
        }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(ciImage,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel[3]
    }

    private func writeTransparentImage(size: CGSize, subjectRect: CGRect, color: CIColor, to url: URL) throws {
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let subject = CIImage(color: color).cropped(to: subjectRect)
        let composite = subject.composited(over: background)
        let context = CIContext()
        guard let cg = context.createCGImage(composite, from: composite.extent) else {
            XCTFail("Failed to create CGImage")
            return
        }
        try writePNG(to: url, image: cg)
    }

    private func opaqueBoundingBox(of url: URL) throws -> CGRect? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Failed to load image at \(url.path)")
        }
        guard let data = cgImage.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else {
            return nil
        }
        let bytesPerRow = cgImage.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            let row = pointer + y * bytesPerRow
            for x in 0..<width {
                let alpha = row[x * 4 + 3]
                if alpha > 16 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if maxX < minX || maxY < minY {
            return nil
        }
        let x = CGFloat(minX)
        let y = CGFloat(height - maxY - 1)
        let w = CGFloat(maxX - minX + 1)
        let h = CGFloat(maxY - minY + 1)
        // Normalize to image coordinates (0...size)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
