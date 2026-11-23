import Foundation
import CoreGraphics

public enum CalibrationError: Error, Equatable {
    case invalidROI
}

public struct Calibration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultMinConfidence = 0.6
    public static let defaultMinLuminance = 0.08

    public let schemaVersion: Int
    public let roiX: Double
    public let roiY: Double
    public let roiWidth: Double
    public let roiHeight: Double
    public let minConfidence: Double
    public let minLuminance: Double
    public let calibratedAt: Date

    public init(
        schemaVersion: Int = Calibration.currentSchemaVersion,
        roiX: Double,
        roiY: Double,
        roiWidth: Double,
        roiHeight: Double,
        minConfidence: Double = Calibration.defaultMinConfidence,
        minLuminance: Double = Calibration.defaultMinLuminance,
        calibratedAt: Date = Date()
    ) throws {
        let tolerance = 1e-9
        guard roiX.isFinite, roiY.isFinite, roiWidth.isFinite, roiHeight.isFinite,
              minConfidence.isFinite, minLuminance.isFinite,
              roiWidth > 0, roiHeight > 0,
              roiX >= -tolerance, roiY >= -tolerance,
              roiX + roiWidth <= 1.0 + tolerance,
              roiY + roiHeight <= 1.0 + tolerance,
              minConfidence > 0, minConfidence <= 1.0,
              minLuminance >= 0, minLuminance <= 1.0 else {
            throw CalibrationError.invalidROI
        }

        self.schemaVersion = schemaVersion
        self.roiX = min(1.0, max(0.0, roiX))
        self.roiY = min(1.0, max(0.0, roiY))
        self.roiWidth = min(1.0 - self.roiX, max(0.0, roiWidth))
        self.roiHeight = min(1.0 - self.roiY, max(0.0, roiHeight))
        guard self.roiWidth > 0, self.roiHeight > 0 else {
            throw CalibrationError.invalidROI
        }
        self.minConfidence = minConfidence
        self.minLuminance = minLuminance
        self.calibratedAt = calibratedAt
    }

    public var visionRect: CGRect {
        CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
    }

    public func containsCenter(of observationBox: CGRect) -> Bool {
        guard observationBox.width.isFinite, observationBox.height.isFinite,
              observationBox.origin.x.isFinite, observationBox.origin.y.isFinite else {
            return false
        }
        let cx = observationBox.midX
        let cy = observationBox.midY
        return cx >= roiX && cx <= (roiX + roiWidth) && cy >= roiY && cy <= (roiY + roiHeight)
    }

    public static var defaultCentered: Calibration {
        try! Calibration(roiX: 0.15, roiY: 0.15, roiWidth: 0.70, roiHeight: 0.75)
    }
}
