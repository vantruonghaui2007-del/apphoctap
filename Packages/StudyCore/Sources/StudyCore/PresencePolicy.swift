import Foundation

public struct PresencePolicy: Sendable {
    public static let sampleTTLSeconds: Double = 3.0
    public static let stabilityDurationSeconds: Double = 5.0
    public static let absenceWarningSeconds: Double = 30.0
    public static let longAbsenceSeconds: Double = 60.0

    public enum Outcome: Equatable, Sendable {
        case warnAbsence
        case longAbsence
        case presenceLost
        case presenceRecovered
        case cameraIssue(ObservationIssue)
    }

    private let mode: PresenceMode
    private let startMonotonic: Double

    private var lastAcceptedSample: PresenceSample?
    public private(set) var sampleExpiresAt: Double?

    private var currentSampleValue: PresenceValue
    private var presenceStreakStart: Double?
    private var presenceStabilityAt: Double?
    private var isPresenceStable: Bool = false
    private var hasLostPresence: Bool = false

    private var absenceStreakStart: Double?
    private var absenceWarningAt: Double?
    private var longAbsenceAt: Double?
    private var warningEmittedInCurrentAbsence: Bool = false
    private var longAbsenceEmittedInCurrentAbsence: Bool = false

    public init(mode: PresenceMode, startMonotonic: Double) {
        self.mode = mode
        self.startMonotonic = startMonotonic
        self.currentSampleValue = (mode == .timerOnly) ? .unknown(.cameraUnavailable) : .unknown(.warmingUp)
    }

    public func canAccept(_ sample: PresenceSample, receivedAt nowMonotonic: Double) -> Bool {
        guard mode == .cameraVerified else { return false }
        guard sample.capturedMonotonicSeconds.isFinite,
              sample.capturedMonotonicSeconds <= nowMonotonic,
              sample.capturedMonotonicSeconds >= startMonotonic else {
            return false
        }
        if let prev = lastAcceptedSample {
            if sample.sequence <= prev.sequence { return false }
            if sample.capturedMonotonicSeconds < prev.capturedMonotonicSeconds { return false }
        }
        let age = nowMonotonic - sample.capturedMonotonicSeconds
        if age >= Self.sampleTTLSeconds {
            return false
        }
        return true
    }

    public func effectiveBucket(at monotonic: Double) -> TimeBucket {
        if mode == .timerOnly {
            return .unverified
        }
        guard let expiresAt = sampleExpiresAt, monotonic < expiresAt else {
            return .unknown
        }
        switch currentSampleValue {
        case .present:
            return isPresenceStable ? .present : .unknown
        case .absent:
            return .absent
        case .unknown:
            return .unknown
        }
    }

    public func effectivePresence(at monotonic: Double) -> PresenceValue {
        if mode == .timerOnly {
            return .unknown(.cameraUnavailable)
        }
        guard let expiresAt = sampleExpiresAt, monotonic < expiresAt else {
            if case .unknown(let issue) = currentSampleValue, issue != .warmingUp {
                return .unknown(issue)
            }
            return lastAcceptedSample == nil ? .unknown(.warmingUp) : .unknown(.stale)
        }
        switch currentSampleValue {
        case .present:
            return isPresenceStable ? .present : .unknown(.warmingUp)
        case .absent:
            return .absent
        case .unknown(let issue):
            return .unknown(issue)
        }
    }

    public func nextMilestone(after monotonic: Double, hasIncomingSampleAt targetMonotonic: Double?) -> Double? {
        guard mode == .cameraVerified else { return nil }
        var candidates: [Double] = []

        if let expiresAt = sampleExpiresAt, expiresAt > monotonic {
            candidates.append(expiresAt)
        }
        if !isPresenceStable,
           case .present = currentSampleValue,
           let stabilityAt = presenceStabilityAt,
           stabilityAt > monotonic {
            candidates.append(stabilityAt)
        }
        if case .absent = currentSampleValue {
            if !warningEmittedInCurrentAbsence, let warnAt = absenceWarningAt, warnAt > monotonic {
                candidates.append(warnAt)
            }
            if !longAbsenceEmittedInCurrentAbsence, let longAt = longAbsenceAt, longAt > monotonic {
                candidates.append(longAt)
            }
        }

        let _ = targetMonotonic
        return candidates.min()
    }

    public mutating func triggerMilestone(
        at monotonic: Double,
        canPromoteStability: Bool,
        suppressExpiryIfIncomingAtTarget: Bool = false
    ) -> [Outcome] {
        guard mode == .cameraVerified else { return [] }
        var outcomes: [Outcome] = []
        let eps = 1e-9

        if case .absent = currentSampleValue {
            if !warningEmittedInCurrentAbsence,
               let warnAt = absenceWarningAt,
               monotonic + eps >= warnAt {
                warningEmittedInCurrentAbsence = true
                outcomes.append(.warnAbsence)
            }
            if !longAbsenceEmittedInCurrentAbsence,
               let longAt = longAbsenceAt,
               monotonic + eps >= longAt {
                longAbsenceEmittedInCurrentAbsence = true
                outcomes.append(.longAbsence)
            }
        }

        if !isPresenceStable,
           case .present = currentSampleValue,
           let stabilityAt = presenceStabilityAt,
           monotonic + eps >= stabilityAt,
           canPromoteStability {
            isPresenceStable = true
            if hasLostPresence {
                outcomes.append(.presenceRecovered)
            }
        }

        if let expiresAt = sampleExpiresAt,
           monotonic + eps >= expiresAt,
           !suppressExpiryIfIncomingAtTarget {
            expireSample(outcomes: &outcomes)
        }

        return outcomes
    }

    public mutating func accept(_ sample: PresenceSample, receivedAt nowMonotonic: Double) -> [Outcome] {
        guard canAccept(sample, receivedAt: nowMonotonic) else {
            return []
        }

        let previousValue = currentSampleValue
        let wasStable = isPresenceStable

        lastAcceptedSample = sample
        sampleExpiresAt = sample.capturedMonotonicSeconds + Self.sampleTTLSeconds
        currentSampleValue = sample.value

        var outcomes: [Outcome] = []

        switch sample.value {
        case .present:
            resetAbsence()
            if presenceStreakStart == nil {
                presenceStreakStart = nowMonotonic
                presenceStabilityAt = nowMonotonic + Self.stabilityDurationSeconds
                isPresenceStable = false
            }
            // Note: If stability threshold already passed because streak was preserved across exact boundary
            if !isPresenceStable,
               let stabilityAt = presenceStabilityAt,
               nowMonotonic + 1e-9 >= stabilityAt {
                isPresenceStable = true
                if hasLostPresence {
                    outcomes.append(.presenceRecovered)
                }
            }

        case .absent:
            if wasStable {
                hasLostPresence = true
                outcomes.append(.presenceLost)
            }
            resetPresence()
            if absenceStreakStart == nil {
                absenceStreakStart = nowMonotonic
                absenceWarningAt = nowMonotonic + Self.absenceWarningSeconds
                longAbsenceAt = nowMonotonic + Self.longAbsenceSeconds
                warningEmittedInCurrentAbsence = false
                longAbsenceEmittedInCurrentAbsence = false
            }

        case .unknown(let issue):
            if wasStable {
                hasLostPresence = true
                outcomes.append(.presenceLost)
            }
            resetPresence()
            resetAbsence()
            if issue != .warmingUp && previousValue != .unknown(issue) {
                outcomes.append(.cameraIssue(issue))
            }
        }

        return outcomes
    }

    public mutating func invalidateForInactivity() -> [Outcome] {
        var outcomes: [Outcome] = []
        if isPresenceStable {
            hasLostPresence = true
            outcomes.append(.presenceLost)
        }
        resetPresence()
        resetAbsence()
        sampleExpiresAt = nil
        if mode == .cameraVerified {
            currentSampleValue = .unknown(.warmingUp)
        }
        return outcomes
    }

    private mutating func expireSample(outcomes: inout [Outcome]) {
        let wasStable = isPresenceStable
        if wasStable {
            hasLostPresence = true
            outcomes.append(.presenceLost)
        }
        resetPresence()
        resetAbsence()
        sampleExpiresAt = nil
        if currentSampleValue != .unknown(.stale) {
            currentSampleValue = .unknown(.stale)
            outcomes.append(.cameraIssue(.stale))
        }
    }

    private mutating func resetPresence() {
        isPresenceStable = false
        presenceStreakStart = nil
        presenceStabilityAt = nil
    }

    private mutating func resetAbsence() {
        absenceStreakStart = nil
        absenceWarningAt = nil
        longAbsenceAt = nil
        warningEmittedInCurrentAbsence = false
        longAbsenceEmittedInCurrentAbsence = false
    }
}
