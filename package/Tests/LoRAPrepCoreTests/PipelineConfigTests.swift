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
}
