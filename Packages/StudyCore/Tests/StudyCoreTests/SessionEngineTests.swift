import XCTest
@testable import StudyCore

final class SessionEngineTests: XCTestCase {
    func testDurationBounds() throws {
        XCTAssertThrowsError(try SessionConfiguration.validated(plannedSeconds: 119, presenceMode: .cameraVerified, warningsEnabled: true)) { error in
            XCTAssertEqual(error as? EngineError, .invalidDuration)
        }
        XCTAssertThrowsError(try SessionConfiguration.validated(plannedSeconds: 10_801, presenceMode: .timerOnly, warningsEnabled: false)) { error in
            XCTAssertEqual(error as? EngineError, .invalidDuration)
        }
        XCTAssertThrowsError(try SessionConfiguration.validated(plannedSeconds: .nan, presenceMode: .timerOnly, warningsEnabled: true)) { error in
            XCTAssertEqual(error as? EngineError, .invalidDuration)
        }
        XCTAssertThrowsError(try SessionConfiguration.validated(plannedSeconds: .infinity, presenceMode: .timerOnly, warningsEnabled: true)) { error in
            XCTAssertEqual(error as? EngineError, .invalidDuration)
        }
        XCTAssertThrowsError(try SessionConfiguration.validated(plannedSeconds: -50, presenceMode: .timerOnly, warningsEnabled: true)) { error in
            XCTAssertEqual(error as? EngineError, .invalidDuration)
        }

        let minCfg = try SessionConfiguration.validated(plannedSeconds: 120, presenceMode: .cameraVerified, warningsEnabled: true)
        let defaultCfg = try SessionConfiguration.validated(plannedSeconds: 3_000, presenceMode: .cameraVerified, warningsEnabled: true)
        let maxCfg = try SessionConfiguration.validated(plannedSeconds: 10_800, presenceMode: .timerOnly, warningsEnabled: false)
        XCTAssertEqual(minCfg.plannedSeconds, 120)
        XCTAssertEqual(defaultCfg.plannedSeconds, 3_000)
        XCTAssertEqual(maxCfg.plannedSeconds, 10_800)
    }

    func testDelayedTickUsesClockAndClampsAtDeadline() throws {
        var engine = makeEngine(duration: 120, presenceMode: .timerOnly)
        let result = try engine.handle(.tick, at: point(200))

        XCTAssertEqual(result.snapshot.elapsedSeconds, 120, accuracy: 0.01)
        XCTAssertEqual(result.snapshot.remainingSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(result.snapshot.status, .completed)
        XCTAssertEqual(result.effects.filter { $0 == .finish(.deadline) }.count, 1)

        // Repeated terminal handling produces no second finish and does not increment revision.
        let revisionAfterComplete = engine.record.revision
        let repeatResult = try engine.handle(.finish(.userEnded), at: point(210))
        XCTAssertTrue(repeatResult.effects.isEmpty)
        XCTAssertEqual(repeatResult.snapshot.status, .completed)
        XCTAssertEqual(engine.record.revision, revisionAfterComplete)
    }

    func testStablePresenceRequiresFiveSeconds() throws {
        var engine = makeEngine(duration: 120, presenceMode: .cameraVerified)
        let gen = SampleSequenceGenerator()

        for t in stride(from: 0.0, through: 4.0, by: 1.0) {
            let update = try engine.handle(.sample(gen.sample(.present, at: t)), at: point(t))
            XCTAssertEqual(update.snapshot.secondsByBucket[.present] ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual(update.snapshot.presence, .unknown(.warmingUp))
        }

        let atFive = try engine.handle(.sample(gen.sample(.present, at: 5.0)), at: point(5.0))
        XCTAssertEqual(atFive.snapshot.secondsByBucket[.present] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(atFive.snapshot.secondsByBucket[.unknown] ?? -1, 5.0, accuracy: 0.001)
        XCTAssertEqual(atFive.snapshot.presence, .present)

        let atSix = try engine.handle(.tick, at: point(6.0))
        XCTAssertEqual(atSix.snapshot.secondsByBucket[.unknown] ?? -1, 5.0, accuracy: 0.001)
        XCTAssertEqual(atSix.snapshot.secondsByBucket[.present] ?? -1, 1.0, accuracy: 0.001)
    }

    func testStaleSampleCannotAccruePresence() throws {
        var engine = makeEngine(duration: 120, presenceMode: .cameraVerified)
        let gen = SampleSequenceGenerator()

        // Reach stable presence through t10
        for t in stride(from: 0.0, through: 10.0, by: 2.0) {
            _ = try engine.handle(.sample(gen.sample(.present, at: t)), at: point(t))
        }

        // No further samples after t10; tick at t20 -> only [5, 13] may be present (8s total).
        let atTwenty = try engine.handle(.tick, at: point(20.0))
        XCTAssertEqual(atTwenty.snapshot.secondsByBucket[.present] ?? -1, 8.0, accuracy: 0.01)
        XCTAssertEqual(atTwenty.snapshot.secondsByBucket[.unknown] ?? -1, 12.0, accuracy: 0.01)
        XCTAssertEqual(atTwenty.snapshot.presence, .unknown(.stale))
    }

    func testAbsenceThresholdsOnce() throws {
        var engine = makeEngine(duration: 300, presenceMode: .cameraVerified, warningsEnabled: true)
        let gen = SampleSequenceGenerator()

        // Feed continuous absent samples every 2 seconds up to 29.9s
        var t = 0.0
        while t <= 28.0 {
            let update = try engine.handle(.sample(gen.sample(.absent, at: t)), at: point(t))
            XCTAssertFalse(update.effects.contains(.warnAbsence))
            XCTAssertFalse(update.effects.contains(.longAbsence))
            t += 2.0
        }

        let at299 = try engine.handle(.tick, at: point(29.9))
        XCTAssertFalse(at299.effects.contains(.warnAbsence))

        // At 30.0s -> 1 warning
        let at30 = try engine.handle(.sample(gen.sample(.absent, at: 30.0)), at: point(30.0))
        XCTAssertEqual(at30.effects.filter { $0 == .warnAbsence }.count, 1)
        XCTAssertFalse(at30.effects.contains(.longAbsence))

        // Continue absent through 58s -> no repeat warning
        for step in stride(from: 32.0, through: 58.0, by: 2.0) {
            let u = try engine.handle(.sample(gen.sample(.absent, at: step)), at: point(step))
            XCTAssertFalse(u.effects.contains(.warnAbsence))
            XCTAssertFalse(u.effects.contains(.longAbsence))
        }

        // At 60.0s -> 1 longAbsence
        let at60 = try engine.handle(.sample(gen.sample(.absent, at: 60.0)), at: point(60.0))
        XCTAssertEqual(at60.effects.filter { $0 == .longAbsence }.count, 1)
        XCTAssertFalse(at60.effects.contains(.warnAbsence))

        // Ticking further while absent does not repeat either
        let at70 = try engine.handle(.sample(gen.sample(.absent, at: 69.0)), at: point(70.0))
        XCTAssertFalse(at70.effects.contains(.warnAbsence))
        XCTAssertFalse(at70.effects.contains(.longAbsence))

        // Return stably for 5+ seconds
        for step in stride(from: 72.0, through: 78.0, by: 2.0) {
            _ = try engine.handle(.sample(gen.sample(.present, at: step)), at: point(step))
        }
        let recovered = try engine.handle(.tick, at: point(78.0))
        XCTAssertEqual(recovered.snapshot.presence, .present)

        // New absence episode triggers new warning at +30s
        for step in stride(from: 80.0, through: 108.0, by: 2.0) {
            let u = try engine.handle(.sample(gen.sample(.absent, at: step)), at: point(step))
            XCTAssertFalse(u.effects.contains(.warnAbsence))
        }
        let secondWarning = try engine.handle(.sample(gen.sample(.absent, at: 110.0)), at: point(110.0))
        XCTAssertEqual(secondWarning.effects.filter { $0 == .warnAbsence }.count, 1)
    }

    func testWarningsDisabledSuppressesWarnAbsenceEffect() throws {
        var engine = makeEngine(duration: 180, presenceMode: .cameraVerified, warningsEnabled: false)
        let gen = SampleSequenceGenerator()
        var warnCount = 0
        var longCount = 0
        for t in stride(from: 0.0, through: 62.0, by: 2.0) {
            let u = try engine.handle(.sample(gen.sample(.absent, at: t)), at: point(t))
            warnCount += u.effects.filter { $0 == .warnAbsence }.count
            longCount += u.effects.filter { $0 == .longAbsence }.count
        }
        XCTAssertEqual(warnCount, 0)
        XCTAssertEqual(longCount, 1)
    }

    func testCameraGapBreaksAbsenceChain() throws {
        var engine = makeEngine(duration: 300, presenceMode: .cameraVerified, warningsEnabled: true)
        let gen = SampleSequenceGenerator()

        // Absent for 20s (last sample at t17, expires at t20)
        for t in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 17.0] {
            let u = try engine.handle(.sample(gen.sample(.absent, at: t)), at: point(t))
            XCTAssertFalse(u.effects.contains(.warnAbsence))
        }

        // Gap of 20s (t20..t40) -> becomes stale at t20 and breaks absence chain
        let afterGap = try engine.handle(.sample(gen.sample(.absent, at: 40.0)), at: point(40.0))
        XCTAssertFalse(afterGap.effects.contains(.warnAbsence))

        // Absent another 20s (t40..t60): must NOT combine into 40s continuous absence!
        for t in stride(from: 42.0, through: 60.0, by: 2.0) {
            let u = try engine.handle(.sample(gen.sample(.absent, at: t)), at: point(t))
            XCTAssertFalse(u.effects.contains(.warnAbsence))
            XCTAssertFalse(u.effects.contains(.longAbsence))
        }
    }

    func testInactiveIsIneligibleAndLockReleaseEndsEarly() throws {
        var engine = makeEngine(duration: 120, presenceMode: .cameraVerified)
        let gen = SampleSequenceGenerator()

        for t in stride(from: 0.0, through: 6.0, by: 2.0) {
            _ = try engine.handle(.sample(gen.sample(.present, at: t)), at: point(t))
        }

        _ = try engine.handle(.activityChanged(.inactive), at: point(10.0))
        let bgUpdate = try engine.handle(.activityChanged(.background), at: point(20.0))
        XCTAssertEqual(bgUpdate.snapshot.secondsByBucket[.ineligible] ?? -1, 10.0, accuracy: 0.01)

        // Sample arriving while inactive does not accrue presence
        let lateSample = try engine.handle(.sample(gen.sample(.present, at: 25.0)), at: point(25.0))
        XCTAssertEqual(lateSample.snapshot.secondsByBucket[.ineligible] ?? -1, 15.0, accuracy: 0.01)

        // Lock released ends session early immediately
        let lockLoss = try engine.handle(.lockChanged(false), at: point(30.0))
        XCTAssertEqual(lockLoss.snapshot.status, .endedEarly(.lockReleased))
        XCTAssertEqual(lockLoss.snapshot.secondsByBucket[.ineligible] ?? -1, 20.0, accuracy: 0.01)
        XCTAssertTrue(lockLoss.effects.contains(.finish(.lockReleased)))
        XCTAssertTrue(engine.record.events.contains(where: { $0.kind == .lockReleased }))
    }

    func testTimerOnlyNeverClaimsCameraVerified() throws {
        var engine = makeEngine(duration: 120, presenceMode: .timerOnly)
        let gen = SampleSequenceGenerator()

        // Even if a stray sample arrives, timerOnly stays unverified
        _ = try engine.handle(.sample(gen.sample(.present, at: 2.0)), at: point(2.0))
        let update = try engine.handle(.tick, at: point(30.0))

        XCTAssertEqual(update.snapshot.secondsByBucket[.present] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(update.snapshot.secondsByBucket[.unverified] ?? -1, 30, accuracy: 0.001)
    }

    func testWallClockJumpDoesNotChangeDuration() throws {
        var engine = makeEngine(duration: 120, presenceMode: .timerOnly)
        // Wall clock jumps backward by 10 hours while monotonic advances 30 seconds
        let update = try engine.handle(.tick, at: point(30.0, wallOffset: -36_000))
        XCTAssertEqual(update.snapshot.elapsedSeconds, 30.0, accuracy: 0.01)
        XCTAssertEqual(update.snapshot.remainingSeconds, 90.0, accuracy: 0.01)
        XCTAssertEqual(update.snapshot.status, .running)

        // Non-monotonic monotonic clock throws
        XCTAssertThrowsError(try engine.handle(.tick, at: point(29.0))) { error in
            XCTAssertEqual(error as? EngineError, .nonMonotonicTime)
        }
    }

    func testReorderedAndDuplicateSamplesIgnored() throws {
        var engine = makeEngine(duration: 120, presenceMode: .cameraVerified)

        let s1 = PresenceSample(sequence: 10, capturedMonotonicSeconds: 4.0, value: .present)
        _ = try engine.handle(.sample(s1), at: point(4.0))
        let revAfterFirst = engine.record.revision

        // Duplicate sequence
        let dup = PresenceSample(sequence: 10, capturedMonotonicSeconds: 4.0, value: .absent)
        _ = try engine.handle(.sample(dup), at: point(4.0))
        XCTAssertEqual(engine.record.revision, revAfterFirst)

        // Lower sequence even with newer timestamp
        let lowerSeq = PresenceSample(sequence: 9, capturedMonotonicSeconds: 4.5, value: .absent)
        _ = try engine.handle(.sample(lowerSeq), at: point(4.5))
        XCTAssertNotEqual(engine.snapshot.presence, .absent)

        // Stale sample (> 3s old) on a fresh engine with no prior samples
        var freshEngine = makeEngine(duration: 120, presenceMode: .cameraVerified)
        let staleOnly = PresenceSample(sequence: 1, capturedMonotonicSeconds: 0.5, value: .present)
        _ = try freshEngine.handle(.sample(staleOnly), at: point(5.0))
        XCTAssertEqual(freshEngine.snapshot.secondsByBucket[.present] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(freshEngine.snapshot.presence, .unknown(.warmingUp))

        // Stale sample (> 3s old)
        let stale = PresenceSample(sequence: 11, capturedMonotonicSeconds: 0.5, value: .absent)
        _ = try engine.handle(.sample(stale), at: point(5.0))
        XCTAssertEqual(engine.record.events.filter { $0.kind == .presenceLost }.count, 0)

        // Invalid NaN sample throws
        let nanSample = PresenceSample(sequence: 12, capturedMonotonicSeconds: .nan, value: .present)
        XCTAssertThrowsError(try engine.handle(.sample(nanSample), at: point(5.5))) { error in
            XCTAssertEqual(error as? EngineError, .invalidSample)
        }
    }

    func testAllBucketsPartitionElapsed() throws {
        var engine = makeEngine(duration: 200, presenceMode: .cameraVerified)
        let gen = SampleSequenceGenerator()

        for t in stride(from: 0.0, through: 10.0, by: 1.0) {
            _ = try engine.handle(.sample(gen.sample(.present, at: t)), at: point(t))
        }
        _ = try engine.handle(.sample(gen.sample(.absent, at: 15.0)), at: point(15.0))
        _ = try engine.handle(.activityChanged(.inactive), at: point(25.0))
        _ = try engine.handle(.activityChanged(.active), at: point(40.0))
        let final = try engine.handle(.tick, at: point(200.0))

        let sum = final.snapshot.secondsByBucket.values.reduce(0, +)
        XCTAssertEqual(sum, final.snapshot.elapsedSeconds, accuracy: 0.01)
        XCTAssertEqual(final.snapshot.elapsedSeconds, 200.0, accuracy: 0.01)
        for value in final.snapshot.secondsByBucket.values {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 200.0 + 0.01)
        }
    }

    func testTenThousandEventDeterministicInvariants() throws {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }

        var rng = SplitMix64(state: 0x5EED_2026_1124)
        var engine = makeEngine(duration: 10_800, presenceMode: .cameraVerified)
        var now = 0.0
        var seq: UInt64 = 1
        var finishCount = 0

        for _ in 0..<10_000 {
            let dt = Double(rng.next() % 150) / 100.0 // 0.00 ... 1.49s
            now += dt
            let wallDelta = Double(Int64(bitPattern: rng.next() % 1_000) - 500)
            let tp = point(now, wallOffset: wallDelta)
            let choice = rng.next() % 10

            let input: SessionInput
            switch choice {
            case 0...4:
                let lag = Double(rng.next() % 40) / 10.0 // 0..3.9s lag (some stale!)
                let captured = max(0, now - lag)
                let valChoice = rng.next() % 4
                let val: PresenceValue = valChoice == 0 ? .absent : (valChoice == 1 ? .unknown(.lowLight) : .present)
                seq += 1
                input = .sample(PresenceSample(sequence: seq, capturedMonotonicSeconds: captured, value: val))
            case 5...7:
                input = .tick
            case 8:
                let act: ActivityState = (rng.next() % 2 == 0) ? .active : .inactive
                input = .activityChanged(act)
            default:
                input = .tick
            }

            let update = try engine.handle(input, at: tp)
            for eff in update.effects {
                if case .finish = eff { finishCount += 1 }
            }
            let sum = update.snapshot.secondsByBucket.values.reduce(0, +)
            XCTAssertEqual(sum, update.snapshot.elapsedSeconds, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(update.snapshot.elapsedSeconds, 0)
            XCTAssertLessThanOrEqual(update.snapshot.elapsedSeconds, 10_800 + 0.01)
            for v in update.snapshot.secondsByBucket.values {
                XCTAssertGreaterThanOrEqual(v, 0)
            }
        }

        XCTAssertLessThanOrEqual(finishCount, 1)
    }
}
