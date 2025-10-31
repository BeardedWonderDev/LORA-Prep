import Foundation
import Vision
import CoreImage

protocol SegmentationEngine {
    func mask(for image: CIImage) throws -> CIImage?
}

enum SegmentationEngineError: Error {
    case modelUnavailable(String)
}

final class VisionSegmentationEngine: SegmentationEngine {
    private let quality: VNGeneratePersonSegmentationRequest.QualityLevel

    init(quality: VNGeneratePersonSegmentationRequest.QualityLevel) {
        self.quality = quality
    }

    func mask(for image: CIImage) throws -> CIImage? {
        #if os(macOS)
        if #available(macOS 12.0, *) {
            return try visionMask(for: image, quality: quality)
        } else {
            return nil
        }
        #else
        return try visionMask(for: image, quality: quality)
        #endif
    }
}

final class DeepLabSegmentationEngine: SegmentationEngine {
    init() throws {}

    func mask(for image: CIImage) throws -> CIImage? {
        throw SegmentationEngineError.modelUnavailable("DeepLabV3 Core ML model is not bundled.")
    }
}

final class RobustVideoMattingEngine: SegmentationEngine {
    init() throws {}

    func mask(for image: CIImage) throws -> CIImage? {
        throw SegmentationEngineError.modelUnavailable("Robust Video Matting Core ML model is not bundled.")
    }
}
