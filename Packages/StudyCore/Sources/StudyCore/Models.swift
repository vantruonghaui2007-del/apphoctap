import Foundation

public enum StudyCoreInfo {
    public static let minimumSupportedIOSVersion = "15.7"
    public static let defaultPlannedMinutes = 50
    public static let minPlannedMinutes = 2
    public static let maxPlannedMinutes = 180
}

public struct TimePoint: Equatable, Sendable {
    public let monotonicSeconds: Double
    public let wallDate: Date

    public init(monotonicSeconds: Double, wallDate: Date) {
        self.monotonicSeconds = monotonicSeconds
        self.wallDate = wallDate
    }
}

public enum PresenceMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case cameraVerified
    case timerOnly
}

public struct SessionConfiguration: Codable, Equatable, Sendable {
    public static let minimumDurationSeconds: Double = 120
    public static let maximumDurationSeconds: Double = 10_800
    public static let defaultDurationSeconds: Double = 3_000

    public let plannedSeconds: Double
    public let presenceMode: PresenceMode
    public let warningsEnabled: Bool

    private init(plannedSeconds: Double, presenceMode: PresenceMode, warningsEnabled: Bool) {
        self.plannedSeconds = plannedSeconds
        self.presenceMode = presenceMode
        self.warningsEnabled = warningsEnabled
    }

    public static func validated(
        plannedSeconds: Double,
        presenceMode: PresenceMode,
        warningsEnabled: Bool
    ) throws -> SessionConfiguration {
        guard plannedSeconds.isFinite,
              plannedSeconds >= minimumDurationSeconds,
              plannedSeconds <= maximumDurationSeconds else {
            throw EngineError.invalidDuration
        }
        return SessionConfiguration(
            plannedSeconds: plannedSeconds,
            presenceMode: presenceMode,
            warningsEnabled: warningsEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case plannedSeconds
        case presenceMode
        case warningsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let plannedSeconds = try container.decode(Double.self, forKey: .plannedSeconds)
        let presenceMode = try container.decode(PresenceMode.self, forKey: .presenceMode)
        let warningsEnabled = try container.decode(Bool.self, forKey: .warningsEnabled)
        guard plannedSeconds.isFinite,
              plannedSeconds >= Self.minimumDurationSeconds,
              plannedSeconds <= Self.maximumDurationSeconds else {
            throw DecodingError.dataCorruptedError(
                forKey: .plannedSeconds,
                in: container,
                debugDescription: "Session duration out of supported bounds [120, 10800]"
            )
        }
        self.init(plannedSeconds: plannedSeconds, presenceMode: presenceMode, warningsEnabled: warningsEnabled)
    }
}

public enum ObservationIssue: String, Codable, Equatable, Hashable, Sendable {
    case warmingUp
    case stale
    case lowLight
    case cameraUnavailable
    case thermal
    case detectorFailure
}

public enum PresenceValue: Equatable, Hashable, Sendable, Codable {
    case present
    case absent
    case unknown(ObservationIssue)

    private enum CodingKeys: String, CodingKey {
        case kind
        case issue
    }

    private enum Kind: String, Codable {
        case present
        case absent
        case unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .present:
            self = .present
        case .absent:
            self = .absent
        case .unknown:
            let issue = try container.decode(ObservationIssue.self, forKey: .issue)
            self = .unknown(issue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .present:
            try container.encode(Kind.present, forKey: .kind)
        case .absent:
            try container.encode(Kind.absent, forKey: .kind)
        case .unknown(let issue):
            try container.encode(Kind.unknown, forKey: .kind)
            try container.encode(issue, forKey: .issue)
        }
    }
}

public struct PresenceSample: Equatable, Sendable {
    public let sequence: UInt64
    public let capturedMonotonicSeconds: Double
    public let value: PresenceValue

    public init(sequence: UInt64, capturedMonotonicSeconds: Double, value: PresenceValue) {
        self.sequence = sequence
        self.capturedMonotonicSeconds = capturedMonotonicSeconds
        self.value = value
    }
}

public enum ActivityState: String, Codable, Equatable, Sendable {
    case active
    case inactive
    case background
}

public enum EndReason: String, Codable, Equatable, Hashable, Sendable {
    case deadline
    case userEnded
    case lockReleased
    case processRestart
    case storageFailure
    case thermalLimit
    case clockFailure
}

public enum SessionStatus: Codable, Equatable, Sendable {
    case running
    case completed
    case endedEarly(EndReason)
    case interrupted(EndReason)

    public var isTerminal: Bool {
        self != .running
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
    }

    private enum Kind: String, Codable {
        case running
        case completed
        case endedEarly
        case interrupted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .endedEarly:
            let reason = try container.decode(EndReason.self, forKey: .reason)
            self = .endedEarly(reason)
        case .interrupted:
            let reason = try container.decode(EndReason.self, forKey: .reason)
            self = .interrupted(reason)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .running:
            try container.encode(Kind.running, forKey: .kind)
        case .completed:
            try container.encode(Kind.completed, forKey: .kind)
        case .endedEarly(let reason):
            try container.encode(Kind.endedEarly, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .interrupted(let reason):
            try container.encode(Kind.interrupted, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public enum TimeBucket: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case present
    case absent
    case unknown
    case unverified
    case ineligible
}

public struct TimelineSegment: Codable, Equatable, Sendable {
    public let startElapsed: Double
    public var endElapsed: Double
    public let bucket: TimeBucket

    public init(startElapsed: Double, endElapsed: Double, bucket: TimeBucket) {
        self.startElapsed = startElapsed
        self.endElapsed = endElapsed
        self.bucket = bucket
    }

    public var duration: Double {
        max(0, endElapsed - startElapsed)
    }
}

public enum SessionEventKind: String, Codable, Equatable, Hashable, Sendable {
    case sessionStarted
    case absenceWarning
    case longAbsence
    case presenceLost
    case presenceRecovered
    case activityChanged
    case cameraUnavailable
    case lockReleased
    case sessionEnded
    case storageFailure
}

/// Strict whitelist metadata for events; never stores free-text, app names, or camera frames.
public enum SessionEventDetail: String, Codable, Equatable, Hashable, Sendable {
    case active
    case inactive
    case background
    case warmingUp
    case stale
    case lowLight
    case cameraUnavailable
    case thermal
    case detectorFailure
    case deadline
    case userEnded
    case lockReleased
    case processRestart
    case storageFailure
    case thermalLimit
    case clockFailure

    init(activity: ActivityState) {
        switch activity {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        }
    }

    init(issue: ObservationIssue) {
        switch issue {
        case .warmingUp: self = .warmingUp
        case .stale: self = .stale
        case .lowLight: self = .lowLight
        case .cameraUnavailable: self = .cameraUnavailable
        case .thermal: self = .thermal
        case .detectorFailure: self = .detectorFailure
        }
    }

    init(endReason: EndReason) {
        switch endReason {
        case .deadline: self = .deadline
        case .userEnded: self = .userEnded
        case .lockReleased: self = .lockReleased
        case .processRestart: self = .processRestart
        case .storageFailure: self = .storageFailure
        case .thermalLimit: self = .thermalLimit
        case .clockFailure: self = .clockFailure
        }
    }
}

public struct SessionEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let elapsedSeconds: Double
    public let kind: SessionEventKind
    public let detail: SessionEventDetail?

    public init(
        id: UUID = UUID(),
        elapsedSeconds: Double,
        kind: SessionEventKind,
        detail: SessionEventDetail? = nil
    ) {
        self.id = id
        self.elapsedSeconds = elapsedSeconds
        self.kind = kind
        self.detail = detail
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public var revision: UInt64
    public let configuration: SessionConfiguration
    public let startedWallDate: Date
    public var status: SessionStatus
    public var elapsedSeconds: Double
    public var segments: [TimelineSegment]
    public var events: [SessionEvent]

    public init(
        schemaVersion: Int = SessionRecord.currentSchemaVersion,
        id: UUID,
        revision: UInt64 = 0,
        configuration: SessionConfiguration,
        startedWallDate: Date,
        status: SessionStatus,
        elapsedSeconds: Double,
        segments: [TimelineSegment],
        events: [SessionEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.configuration = configuration
        self.startedWallDate = startedWallDate
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.segments = segments
        self.events = events
    }

    public var secondsByBucket: [TimeBucket: Double] {
        var totals: [TimeBucket: Double] = [:]
        for bucket in TimeBucket.allCases {
            totals[bucket] = 0
        }
        for segment in segments {
            totals[segment.bucket, default: 0] += segment.duration
        }
        return totals
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public let status: SessionStatus
    public let remainingSeconds: Double
    public let elapsedSeconds: Double
    public let secondsByBucket: [TimeBucket: Double]
    public let presence: PresenceValue

    public init(
        status: SessionStatus,
        remainingSeconds: Double,
        elapsedSeconds: Double,
        secondsByBucket: [TimeBucket: Double],
        presence: PresenceValue
    ) {
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.elapsedSeconds = elapsedSeconds
        self.secondsByBucket = secondsByBucket
        self.presence = presence
    }
}

public enum SessionInput: Equatable, Sendable {
    case tick
    case sample(PresenceSample)
    case activityChanged(ActivityState)
    case lockChanged(Bool)
    case finish(EndReason)
}

public enum SessionEffect: Equatable, Sendable {
    case warnAbsence
    case longAbsence
    case checkpoint
    case finish(EndReason)
}

public struct SessionUpdate: Equatable, Sendable {
    public let snapshot: SessionSnapshot
    public let effects: [SessionEffect]

    public init(snapshot: SessionSnapshot, effects: [SessionEffect]) {
        self.snapshot = snapshot
        self.effects = effects
    }
}

public enum EngineError: Error, Equatable, Sendable {
    case invalidDuration
    case nonMonotonicTime
    case invalidSample
}
