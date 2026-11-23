import Foundation
import CoreVideo
import ImageIO
import Vision
import StudyCore

public protocol PersonDetecting: Sendable {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        calibration: Calibration
    ) throws -> PresenceValue
}

public enum VisionDetectorError: Error, Equatable {
    case emptyPixelBuffer
    case unsupportedPixelFormat
}

public struct VisionPersonDetector: PersonDetecting {
    public init() {}

    public func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        calibration: Calibration
    ) throws -> PresenceValue {
        guard let luminance = Self.normalizedMeanLuminance(of: pixelBuffer) else {
            throw VisionDetectorError.emptyPixelBuffer
        }
        if luminance < calibration.minLuminance {
            return .unknown(.lowLight)
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = true
        try handler.perform([humanRequest])

        if let humans = humanRequest.results {
            for observation in humans {
                if Double(observation.confidence) >= calibration.minConfidence,
                   calibration.containsCenter(of: observation.boundingBox) {
                    return .present
                }
            }
        }

        // Secondary fallback for leaning/writing postures when upper-body detector misses
        let faceRequest = VNDetectFaceRectanglesRequest()
        try handler.perform([faceRequest])

        if let faces = faceRequest.results {
            for observation in faces {
                if Double(observation.confidence) >= calibration.minConfidence,
                   calibration.containsCenter(of: observation.boundingBox) {
                    return .present
                }
            }
        }

        return .absent
    }

    public static func normalizedMeanLuminance(of pixelBuffer: CVPixelBuffer) -> Double? {
        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockResult == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if CVPixelBufferIsPlanar(pixelBuffer),
           CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
           let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard width > 0, height > 0, bytesPerRow >= width else { return nil }

            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            let stepX = max(1, width / 16)
            let stepY = max(1, height / 16)

            var sum = 0.0
            var count = 0
            let isVideoRange = (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)

            var y = 0
            while y < height {
                let rowOffset = y * bytesPerRow
                var x = 0
                while x < width {
                    let raw = Double(ptr[rowOffset + x])
                    let normalized: Double
                    if isVideoRange {
                        normalized = min(1.0, max(0.0, (raw - 16.0) / 219.0))
                    } else {
                        normalized = raw / 255.0
                    }
                    sum += normalized
                    count += 1
                    x += stepX
                }
                y += stepY
            }
            return count > 0 ? (sum / Double(count)) : nil
        }

        if pixelFormat == kCVPixelFormatType_32BGRA,
           let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }

            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            let stepX = max(1, width / 16)
            let stepY = max(1, height / 16)

            var sum = 0.0
            var count = 0

            var y = 0
            while y < height {
                let rowOffset = y * bytesPerRow
                var x = 0
                while x < width {
                    let pixelOffset = rowOffset + x * 4
                    let b = Double(ptr[pixelOffset]) / 255.0
                    let g = Double(ptr[pixelOffset + 1]) / 255.0
                    let r = Double(ptr[pixelOffset + 2]) / 255.0
                    sum += (0.2126 * r + 0.7152 * g + 0.0722 * b)
                    count += 1
                    x += stepX
                }
                y += stepY
            }
            return count > 0 ? (sum / Double(count)) : nil
        }

        return nil
    }
}
