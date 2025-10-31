import Foundation
import AVFoundation
import CoreImage
import ImageIO

struct AuxiliaryAssets {
    let portraitMatte: AVPortraitEffectsMatte?
    let depthData: AVDepthData?

    static var empty: AuxiliaryAssets {
        AuxiliaryAssets(portraitMatte: nil, depthData: nil)
    }
}

func loadAuxiliaryAssets(for url: URL) -> AuxiliaryAssets {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return .empty
    }

    let index = 0
    let portraitKey: CFString = "PortraitEffectsMatte" as CFString
    let depthKey: CFString = "Depth" as CFString
    let disparityKey: CFString = "Disparity" as CFString

    let portraitInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, portraitKey) as? [AnyHashable: Any]

    let portraitMatte = portraitInfo.flatMap { try? AVPortraitEffectsMatte(fromDictionaryRepresentation: $0) }

    let depthInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, depthKey) as? [AnyHashable: Any]

    let disparityInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, disparityKey) as? [AnyHashable: Any]

    let depthData = depthInfo.flatMap { try? AVDepthData(fromDictionaryRepresentation: $0) }
        ?? disparityInfo.flatMap { try? AVDepthData(fromDictionaryRepresentation: $0) }

    return AuxiliaryAssets(portraitMatte: portraitMatte, depthData: depthData)
}

func ciImage(from matte: AVPortraitEffectsMatte?) -> CIImage? {
    guard let matte else { return nil }
    return CIImage(cvPixelBuffer: matte.mattingImage)
}

func ciImage(from depth: AVDepthData?) -> CIImage? {
    guard let depth else { return nil }
    let converted = depth.depthDataType == kCVPixelFormatType_DisparityFloat32
        ? depth
        : depth.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
    return CIImage(cvPixelBuffer: converted.depthDataMap)
}
