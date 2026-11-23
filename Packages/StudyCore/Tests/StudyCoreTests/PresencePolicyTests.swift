import XCTest
@testable import StudyCore

final class PresencePolicyTests: XCTestCase {
    func testConstantsMatchSpecification() {
        XCTAssertEqual(PresencePolicy.sampleTTLSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(PresencePolicy.stabilityDurationSeconds, 5.0, accuracy: 0.0001)
        XCTAssertEqual(PresencePolicy.absenceWarningSeconds, 30.0, accuracy: 0.0001)
        XCTAssertEqual(PresencePolicy.longAbsenceSeconds, 60.0, accuracy: 0.0001)
    }

    func testWarmupTransitionsToStableAfterFiveSeconds() {
        var policy = PresencePolicy(mode: .cameraVerified, startMonotonic: 0)
        let seq = SampleSequenceGenerator()

        XCTAssertEqual(policy.effectivePresence(at: 0), .unknown(.warmingUp))

        _ = policy.accept(seq.sample(.present, at: 0), receivedAt: 0)
        XCTAssertEqual(policy.effectiveBucket(at: 0), .unknown)
        XCTAssertEqual(policy.effectivePresence(at: 0), .unknown(.warmingUp))

        _ = policy.accept(seq.sample(.present, at: 2), receivedAt: 2)
        _ = policy.accept(seq.sample(.present, at: 4), receivedAt: 4)
        XCTAssertEqual(policy.nextMilestone(after: 4, hasIncomingSampleAt: nil), 5.0)
        let events = policy.triggerMilestone(at: 5.0, canPromoteStability: true)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(policy.effectiveBucket(at: 5.0), .present)
        XCTAssertEqual(policy.effectivePresence(at: 5.0), .present)
    }
}
