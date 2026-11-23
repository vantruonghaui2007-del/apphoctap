import Foundation

public struct SessionEngine: Sendable {
    public private(set) var record: SessionRecord

    private let startedAt: TimePoint
    private let deadlineMonotonic: Double
    private var lastMonotonic: Double
    private var activity: ActivityState = .active
    private var isLocked: Bool = true
    private var ledger: TimelineLedger
    private var policy: PresencePolicy
    private var lastCheckpointElapsed: Double = 0

    public init(id: UUID = UUID(), configuration: SessionConfiguration, startedAt: TimePoint) {
        self.startedAt = startedAt
        self.deadlineMonotonic = startedAt.monotonicSeconds + configuration.plannedSeconds
        self.lastMonotonic = startedAt.monotonicSeconds
        self.ledger = TimelineLedger(plannedSeconds: configuration.plannedSeconds)
        self.policy = PresencePolicy(mode: configuration.presenceMode, startMonotonic: startedAt.monotonicSeconds)
        self.record = SessionRecord(
            schemaVersion: SessionRecord.currentSchemaVersion,
            id: id,
            revision: 0,
            configuration: configuration,
            startedWallDate: startedAt.wallDate,
            status: .running,
            elapsedSeconds: 0,
            segments: [],
            events: [
                SessionEvent(elapsedSeconds: 0, kind: .sessionStarted)
            ]
        )
    }

    public var snapshot: SessionSnapshot {
        snapshot(at: lastMonotonic)
    }

    public mutating func handle(_ input: SessionInput, at time: TimePoint) throws -> SessionUpdate {
        guard startedAt.monotonicSeconds.isFinite,
              time.monotonicSeconds.isFinite,
              time.monotonicSeconds >= lastMonotonic else {
            throw EngineError.nonMonotonicTime
        }

        if record.status.isTerminal {
            return SessionUpdate(snapshot: snapshot(at: lastMonotonic), effects: [])
        }

        var incomingSample: PresenceSample?
        var incomingSampleWillApply = false

        if case .sample(let sample) = input {
            guard sample.capturedMonotonicSeconds.isFinite,
                  sample.capturedMonotonicSeconds <= time.monotonicSeconds else {
                throw EngineError.invalidSample
            }
            incomingSample = sample
            if record.configuration.presenceMode == .cameraVerified,
               activity == .active,
               isLocked {
                incomingSampleWillApply = policy.canAccept(sample, receivedAt: time.monotonicSeconds)
            }
        }

        let previousStatus = record.status
        let previousElapsed = record.elapsedSeconds
        let previousSegments = record.segments
        let previousEvents = record.events

        var effects: [SessionEffect] = []
        var needsCheckpoint = false

        let targetMonotonic = min(time.monotonicSeconds, deadlineMonotonic)

        while lastMonotonic < targetMonotonic && record.status == .running {
            let nextMilestone: Double?
            if record.configuration.presenceMode == .cameraVerified && activity == .active && isLocked {
                nextMilestone = policy.nextMilestone(
                    after: lastMonotonic,
                    hasIncomingSampleAt: incomingSampleWillApply ? time.monotonicSeconds : nil
                )
            } else {
                nextMilestone = nil
            }

            let stepEnd = min(targetMonotonic, nextMilestone ?? targetMonotonic)
            let intervalBucket: TimeBucket
            if activity != .active || !isLocked {
                intervalBucket = .ineligible
            } else if record.configuration.presenceMode == .timerOnly {
                intervalBucket = .unverified
            } else {
                intervalBucket = policy.effectiveBucket(at: lastMonotonic)
            }

            let startElapsed = lastMonotonic - startedAt.monotonicSeconds
            let endElapsed = stepEnd - startedAt.monotonicSeconds
            ledger.append(startElapsed: startElapsed, endElapsed: endElapsed, bucket: intervalBucket)

            lastMonotonic = stepEnd
            record.elapsedSeconds = ledger.totalElapsed

            if let milestone = nextMilestone, abs(stepEnd - milestone) <= 1e-9 {
                let isTargetBoundary = abs(stepEnd - time.monotonicSeconds) <= 1e-9
                let incomingIsPresent = incomingSampleWillApply && incomingSample?.value == .present
                let hasRemainingFreshness = (policy.sampleExpiresAt ?? -Double.infinity) > stepEnd + 1e-9
                let canPromoteStability = hasRemainingFreshness || (isTargetBoundary && incomingIsPresent)
                let suppressExpiry = isTargetBoundary && incomingSampleWillApply

                let outcomes = policy.triggerMilestone(
                    at: stepEnd,
                    canPromoteStability: canPromoteStability,
                    suppressExpiryIfIncomingAtTarget: suppressExpiry
                )
                applyPolicyOutcomes(
                    outcomes,
                    elapsed: record.elapsedSeconds,
                    effects: &effects,
                    needsCheckpoint: &needsCheckpoint
                )
            }
        }

        // Complete at deadline before applying non-terminal or late inputs
        if lastMonotonic + 1e-9 >= deadlineMonotonic && record.status == .running {
            lastMonotonic = deadlineMonotonic
            record.elapsedSeconds = record.configuration.plannedSeconds
            record.status = .completed
            record.events.append(
                SessionEvent(
                    elapsedSeconds: record.elapsedSeconds,
                    kind: .sessionEnded,
                    detail: .deadline
                )
            )
            effects.append(.finish(.deadline))
        }

        if record.status == .running {
            switch input {
            case .tick:
                break

            case .sample(let sample):
                if incomingSampleWillApply {
                    let outcomes = policy.accept(sample, receivedAt: time.monotonicSeconds)
                    applyPolicyOutcomes(
                        outcomes,
                        elapsed: record.elapsedSeconds,
                        effects: &effects,
                        needsCheckpoint: &needsCheckpoint
                    )
                }

            case .activityChanged(let newState):
                if newState != activity {
                    activity = newState
                    if newState != .active {
                        let outcomes = policy.invalidateForInactivity()
                        applyPolicyOutcomes(
                            outcomes,
                            elapsed: record.elapsedSeconds,
                            effects: &effects,
                            needsCheckpoint: &needsCheckpoint
                        )
                    }
                    record.events.append(
                        SessionEvent(
                            elapsedSeconds: record.elapsedSeconds,
                            kind: .activityChanged,
                            detail: SessionEventDetail(activity: newState)
                        )
                    )
                    needsCheckpoint = true
                }

            case .lockChanged(let locked):
                if locked != isLocked {
                    isLocked = locked
                    if !locked {
                        record.status = .endedEarly(.lockReleased)
                        record.events.append(
                            SessionEvent(
                                elapsedSeconds: record.elapsedSeconds,
                                kind: .lockReleased,
                                detail: .lockReleased
                            )
                        )
                        record.events.append(
                            SessionEvent(
                                elapsedSeconds: record.elapsedSeconds,
                                kind: .sessionEnded,
                                detail: .lockReleased
                            )
                        )
                        effects.append(.finish(.lockReleased))
                    }
                }

            case .finish(let reason):
                if reason == .deadline && lastMonotonic + 1e-9 >= deadlineMonotonic {
                    record.status = .completed
                } else if reason == .processRestart {
                    record.status = .interrupted(.processRestart)
                } else {
                    record.status = .endedEarly(reason)
                }
                if reason == .storageFailure {
                    record.events.append(
                        SessionEvent(
                            elapsedSeconds: record.elapsedSeconds,
                            kind: .storageFailure,
                            detail: .storageFailure
                        )
                    )
                }
                if reason == .lockReleased {
                    record.events.append(
                        SessionEvent(
                            elapsedSeconds: record.elapsedSeconds,
                            kind: .lockReleased,
                            detail: .lockReleased
                        )
                    )
                }
                record.events.append(
                    SessionEvent(
                        elapsedSeconds: record.elapsedSeconds,
                        kind: .sessionEnded,
                        detail: SessionEventDetail(endReason: reason)
                    )
                )
                effects.append(.finish(reason))
            }
        }

        if record.status == .running {
            if needsCheckpoint || (record.elapsedSeconds - lastCheckpointElapsed >= 5.0) {
                if !effects.contains(.checkpoint) {
                    effects.append(.checkpoint)
                }
                lastCheckpointElapsed = record.elapsedSeconds
            }
        }

        record.segments = ledger.segments

        if record.status != previousStatus
            || abs(record.elapsedSeconds - previousElapsed) > 1e-12
            || record.segments != previousSegments
            || record.events != previousEvents {
            record.revision += 1
        }

        return SessionUpdate(snapshot: snapshot(at: lastMonotonic), effects: effects)
    }

    private mutating func applyPolicyOutcomes(
        _ outcomes: [PresencePolicy.Outcome],
        elapsed: Double,
        effects: inout [SessionEffect],
        needsCheckpoint: inout Bool
    ) {
        for outcome in outcomes {
            switch outcome {
            case .warnAbsence:
                if record.configuration.warningsEnabled {
                    record.events.append(SessionEvent(elapsedSeconds: elapsed, kind: .absenceWarning))
                    effects.append(.warnAbsence)
                    needsCheckpoint = true
                }
            case .longAbsence:
                record.events.append(SessionEvent(elapsedSeconds: elapsed, kind: .longAbsence))
                effects.append(.longAbsence)
                needsCheckpoint = true
            case .presenceLost:
                record.events.append(SessionEvent(elapsedSeconds: elapsed, kind: .presenceLost))
                needsCheckpoint = true
            case .presenceRecovered:
                record.events.append(SessionEvent(elapsedSeconds: elapsed, kind: .presenceRecovered))
                needsCheckpoint = true
            case .cameraIssue(let issue):
                record.events.append(
                    SessionEvent(
                        elapsedSeconds: elapsed,
                        kind: .cameraUnavailable,
                        detail: SessionEventDetail(issue: issue)
                    )
                )
                needsCheckpoint = true
            }
        }
    }

    private func snapshot(at monotonic: Double) -> SessionSnapshot {
        let remaining = max(0, record.configuration.plannedSeconds - record.elapsedSeconds)
        let presence: PresenceValue
        if record.configuration.presenceMode == .timerOnly {
            presence = .unknown(.cameraUnavailable)
        } else if activity != .active || !isLocked {
            presence = .unknown(.cameraUnavailable)
        } else {
            presence = policy.effectivePresence(at: monotonic)
        }
        return SessionSnapshot(
            status: record.status,
            remainingSeconds: remaining,
            elapsedSeconds: record.elapsedSeconds,
            secondsByBucket: ledger.secondsByBucket,
            presence: presence
        )
    }
}
