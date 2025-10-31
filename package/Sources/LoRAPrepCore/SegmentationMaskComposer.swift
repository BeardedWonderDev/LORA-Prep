import CoreImage
import CoreImage.CIFilterBuiltins

struct MaskCompositionOptions {
    let featherRadius: CGFloat
    let erosionRadius: CGFloat
}

extension MaskCompositionOptions {
    static let zero = MaskCompositionOptions(featherRadius: 0, erosionRadius: 0)
}

func compositeMask(visionMask: CIImage?,
                   auxiliary: AuxiliaryAssets,
                   targetExtent: CGRect,
                   feather: CGFloat,
                   erosion: CGFloat) -> CIImage? {
    var masks: [CIImage] = []
    if let visionMask {
        masks.append(visionMask)
    }
    if let portrait = ciImage(from: auxiliary.portraitMatte) {
        masks.append(portrait)
    }
    if let depth = ciImage(from: auxiliary.depthData) {
        // Convert disparity to alpha-ish map: closer objects -> opaque
        let normalized = depth
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.5])
        masks.append(normalized)
    }

    guard !masks.isEmpty else { return visionMask }
    let combined = masks.dropFirst().reduce(masks[0]) { current, next in
        current.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: next])
    }

    let scaled: CIImage
    if combined.extent != targetExtent {
        let sx = targetExtent.width / combined.extent.width
        let sy = targetExtent.height / combined.extent.height
        scaled = combined
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: targetExtent)
    } else {
        scaled = combined
    }

    let morphologyAdjusted: CIImage
    if erosion > 0 {
        morphologyAdjusted = scaled.applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": erosion])
    } else {
        morphologyAdjusted = scaled
    }

    if feather > 0 {
        return morphologyAdjusted
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: targetExtent)
    } else {
        return morphologyAdjusted
    }
}
