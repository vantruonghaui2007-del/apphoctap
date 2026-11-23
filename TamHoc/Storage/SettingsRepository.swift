import Foundation

public actor SettingsRepository {
    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = RepositoryJSONCoding.makeEncoder()
        self.decoder = RepositoryJSONCoding.makeDecoder()
    }

    public static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TamHoc", isDirectory: true)
    }

    private var settingsURL: URL {
        directory.appendingPathComponent("settings.json", isDirectory: false)
    }

    private var calibrationURL: URL {
        directory.appendingPathComponent("calibration.json", isDirectory: false)
    }

    public func loadSettings() async throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: settingsURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func saveSettings(_ settings: AppSettings) async throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: settingsURL, options: options)
    }

    public func loadCalibration() async throws -> Calibration? {
        guard fileManager.fileExists(atPath: calibrationURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: calibrationURL)
        let decoded = try decoder.decode(Calibration.self, from: data)
        // Re-validate ROI bounds on decode
        return try Calibration(
            schemaVersion: decoded.schemaVersion,
            roiX: decoded.roiX,
            roiY: decoded.roiY,
            roiWidth: decoded.roiWidth,
            roiHeight: decoded.roiHeight,
            minConfidence: decoded.minConfidence,
            minLuminance: decoded.minLuminance,
            calibratedAt: decoded.calibratedAt
        )
    }

    public func saveCalibration(_ calibration: Calibration) async throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(calibration)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: calibrationURL, options: options)
    }
}
