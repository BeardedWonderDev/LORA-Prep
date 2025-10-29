import Foundation
import AppKit
import LoRAPrepCore

struct Args {
    var input: URL
    var loraName: String
    var removeBackground: Bool = false
    var size: CGFloat = 1024
    var superResModel: URL?
    var padWithTransparency: Bool = true
    var skipFaceDetection: Bool = false

    static func parse() -> Args? {
        var input: URL?
        var name: String?
        var removeBG = false
        var size: CGFloat = 1024
        var superResModel: URL?
        var padTransparent = true
        var skipFaceDetection = false

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--input", "-i":
                if let p = it.next() { input = URL(fileURLWithPath: p) }
            case "--lora-name", "-n":
                if let s = it.next() { name = s }
            case "--":
                continue
            case "--remove-background", "-b":
                removeBG = true
            case "--size", "-s":
                if let v = it.next(), let f = Double(v) { size = CGFloat(f) }
            case "--superres-model":
                if let path = it.next() { superResModel = URL(fileURLWithPath: path) }
            case "--pad-transparent":
                padTransparent = true
            case "--pad-edge-color":
                padTransparent = false
            case "--skip-face-detection":
                skipFaceDetection = true
            case "--help", "-h":
                printUsage()
                return nil
            default:
                fputs("Unknown argument: \(a)\n", stderr)
                printUsage()
                return nil
            }
        }
        guard let input = input, let name = name else {
            print("Missing --input or --lora-name. Use --help.")
            return nil
        }
        var args = Args(input: input, loraName: name, removeBackground: removeBG, size: size)
        args.superResModel = superResModel
        args.padWithTransparency = padTransparent
        args.skipFaceDetection = skipFaceDetection
        return args
    }

    private static func printUsage() {
        print(
            """
            LoRAPrep
            Usage:
              LoRAPrep --input <folder> --lora-name <NAME> [options]
            Options:
              --remove-background, -b        Remove background using Vision segmentation (macOS 12+)
              --size <pixels>, -s            Target square output size (default 1024)
              --superres-model <path>        Optional CoreML super-resolution model (.mlmodel or .mlmodelc)
              --pad-transparent              Pad with transparent pixels (default)
              --pad-edge-color               Pad with average edge color (opaque)
              --skip-face-detection          Bypass Vision face detection and center crop/pad
              --help, -h                     Show this help message
            """
        )
    }
}

func runCLI() {
    let requestedHelp = CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h")
    guard let args = Args.parse() else { exit(requestedHelp ? 0 : 1) }

    let configuration = LoRAPrepConfiguration(
        inputFolder: args.input,
        loraName: args.loraName,
        size: args.size,
        removeBackground: args.removeBackground,
        superResModelURL: args.superResModel,
        padWithTransparency: args.padWithTransparency,
        skipFaceDetection: args.skipFaceDetection
    )

    do {
        let pipeline = try LoRAPrepPipeline(configuration: configuration)
        let result = try pipeline.run { update in
            switch update.kind {
            case .started(let total, let outputDirectory):
                print("[\(Date())] Output: \(outputDirectory.path) (\(total) files)")
            case .processing(let index, let total, let input, let output):
                print("[\(Date())] Processing (\(index)/\(total)): \(input.lastPathComponent) -> \(output.lastPathComponent)")
            case .faceDetection(let log):
                switch log {
                case .found(let rect, let size):
                    let desc = "FACE_FOUND box=(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.maxX)),\(Int(rect.maxY))) size=(\(Int(size.width))x\(Int(size.height)))"
                    print(desc)
                case .none(let size):
                    print("NO_FACE size=(\(Int(size.width))x\(Int(size.height)))")
                }
            case .fileWritten(_, _, let output):
                print("WROTE \(output.lastPathComponent)")
            case .failed(_, _, let input, let error):
                fputs("[ERROR] \(input.lastPathComponent): \(error.localizedDescription)\n", stderr)
            case .completed(let outputDirectory):
                print("Completed. Output at \(outputDirectory.path)")
            }
        }

        if !result.failures.isEmpty {
            fputs("Completed with \(result.failures.count) errors.\n", stderr)
        }

        NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
    } catch {
        fputs("Fatal: \(error.localizedDescription)\n", stderr)
        exit(2)
    }
}

runCLI()
