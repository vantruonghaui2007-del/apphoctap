import Foundation
import StudyCore

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentOnboardingVersion = 1

    public var defaultDurationSeconds: Double
    public var defaultPresenceMode: PresenceMode
    public var warningsEnabled: Bool
    public var onboardingVersionSeen: Int

    public init(
        defaultDurationSeconds: Double = SessionConfiguration.defaultDurationSeconds,
        defaultPresenceMode: PresenceMode = .cameraVerified,
        warningsEnabled: Bool = true,
        onboardingVersionSeen: Int = 0
    ) {
        self.defaultDurationSeconds = AppSettings.clampedDuration(defaultDurationSeconds)
        self.defaultPresenceMode = defaultPresenceMode
        self.warningsEnabled = warningsEnabled
        self.onboardingVersionSeen = onboardingVersionSeen
    }

    public static var `default`: AppSettings {
        AppSettings()
    }

    public func makeSessionConfiguration(
        durationSeconds: Double? = nil,
        presenceMode: PresenceMode? = nil
    ) throws -> SessionConfiguration {
        try SessionConfiguration.validated(
            plannedSeconds: durationSeconds ?? defaultDurationSeconds,
            presenceMode: presenceMode ?? defaultPresenceMode,
            warningsEnabled: warningsEnabled
        )
    }

    private static func clampedDuration(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return SessionConfiguration.defaultDurationSeconds }
        return min(SessionConfiguration.maximumDurationSeconds, max(SessionConfiguration.minimumDurationSeconds, seconds))
    }

    private enum CodingKeys: String, CodingKey {
        case defaultDurationSeconds
        case defaultPresenceMode
        case warningsEnabled
        case onboardingVersionSeen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try container.decode(Double.self, forKey: .defaultDurationSeconds)
        guard duration.isFinite,
              duration >= SessionConfiguration.minimumDurationSeconds,
              duration <= SessionConfiguration.maximumDurationSeconds else {
            throw DecodingError.dataCorruptedError(
                forKey: .defaultDurationSeconds,
                in: container,
                debugDescription: "Invalid defaultDurationSeconds"
            )
        }
        self.defaultDurationSeconds = duration
        self.defaultPresenceMode = try container.decode(PresenceMode.self, forKey: .defaultPresenceMode)
        self.warningsEnabled = try container.decode(Bool.self, forKey: .warningsEnabled)
        self.onboardingVersionSeen = try container.decode(Int.self, forKey: .onboardingVersionSeen)
    }
}
