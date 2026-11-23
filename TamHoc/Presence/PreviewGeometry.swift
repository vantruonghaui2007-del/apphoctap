import Foundation
import CoreGraphics

public enum PreviewGeometryError: Error, Equatable {
    case invalidBounds
    case invalidRect
    case invalidImageSize
    case outOfBounds
}

public enum PreviewGeometry {
    /// Maps a rectangle in portrait `.resizeAspectFill` UIKit preview coordinates (top-left origin)
    /// into normalized Vision coordinates (bottom-left origin, [0, 1]).
    public static func visionROI(
        fromPreviewRect previewRect: CGRect,
        previewBounds: CGRect,
        imageSize: CGSize,
        mirrored: Bool
    ) throws -> Calibration {
        guard previewBounds.origin.x.isFinite,
              previewBounds.origin.y.isFinite,
              previewBounds.size.width.isFinite,
              previewBounds.size.height.isFinite,
              previewBounds.size.width > 0,
              previewBounds.size.height > 0 else {
            throw PreviewGeometryError.invalidBounds
        }

        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0 else {
            throw PreviewGeometryError.invalidImageSize
        }

        guard previewRect.origin.x.isFinite,
              previewRect.origin.y.isFinite,
              previewRect.size.width.isFinite,
              previewRect.size.height.isFinite,
              previewRect.size.width > 0,
              previewRect.size.height > 0 else {
            throw PreviewGeometryError.invalidRect
        }

        let clipped = previewRect.intersection(previewBounds)
        guard !clipped.isNull,
              clipped.size.width > 0,
              clipped.size.height > 0 else {
            throw PreviewGeometryError.outOfBounds
        }

        // Aspect-fill layout of oriented image inside previewBounds
        let scale = max(previewBounds.width / imageSize.width, previewBounds.height / imageSize.height)
        let displayedWidth = imageSize.width * scale
        let displayedHeight = imageSize.height * scale
        let offsetX = (previewBounds.width - displayedWidth) / 2.0
        let offsetY = (previewBounds.height - displayedHeight) / 2.0

        let relMinX = clipped.minX - previewBounds.minX
        let relMaxX = clipped.maxX - previewBounds.minX
        let relMinY = clipped.minY - previewBounds.minY
        let relMaxY = clipped.maxY - previewBounds.minY

        let nx0 = clampUnit((relMinX - offsetX) / displayedWidth)
        let nx1 = clampUnit((relMaxX - offsetX) / displayedWidth)
        let nyTop = clampUnit((relMinY - offsetY) / displayedHeight)
        let nyBottom = clampUnit((relMaxY - offsetY) / displayedHeight)

        let visionX0 = mirrored ? (1.0 - nx1) : nx0
        let visionX1 = mirrored ? (1.0 - nx0) : nx1
        let visionY0 = 1.0 - nyBottom
        let visionY1 = 1.0 - nyTop

        let width = visionX1 - visionX0
        let height = visionY1 - visionY0
        guard width > 0, height > 0 else {
            throw PreviewGeometryError.outOfBounds
        }

        return try Calibration(
            roiX: visionX0,
            roiY: visionY0,
            roiWidth: width,
            roiHeight: height
        )
    }

    /// Inverse projection for rendering a stored Vision Calibration box over a portrait aspect-fill preview.
    public static func previewRect(
        from calibration: Calibration,
        previewBounds: CGRect,
        imageSize: CGSize,
        mirrored: Bool
    ) -> CGRect {
        guard previewBounds.width > 0, previewBounds.height > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let scale = max(previewBounds.width / imageSize.width, previewBounds.height / imageSize.height)
        let displayedWidth = imageSize.width * scale
        let displayedHeight = imageSize.height * scale
        let offsetX = (previewBounds.width - displayedWidth) / 2.0
        let offsetY = (previewBounds.height - displayedHeight) / 2.0

        let vx0 = calibration.roiX
        let vx1 = calibration.roiX + calibration.roiWidth
        let vy0 = calibration.roiY
        let vy1 = calibration.roiY + calibration.roiHeight

        let nx0 = mirrored ? (1.0 - vx1) : vx0
        let nx1 = mirrored ? (1.0 - vx0) : vx1
        let nyTop = 1.0 - vy1
        let nyBottom = 1.0 - vy0

        let minX = previewBounds.minX + offsetX + nx0 * displayedWidth
        let maxX = previewBounds.minX + offsetX + nx1 * displayedWidth
        let minY = previewBounds.minY + offsetY + nyTop * displayedHeight
        let maxY = previewBounds.minY + offsetY + nyBottom * displayedHeight

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private static func clampUnit(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
