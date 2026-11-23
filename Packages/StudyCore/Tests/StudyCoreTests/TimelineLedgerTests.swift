import XCTest
@testable import StudyCore

final class TimelineLedgerTests: XCTestCase {
    func testMergesAdjacentSameBucketSegments() {
        var ledger = TimelineLedger(plannedSeconds: 120)
        ledger.append(startElapsed: 0, endElapsed: 5, bucket: .unknown)
        ledger.append(startElapsed: 5, endElapsed: 10, bucket: .unknown)
        ledger.append(startElapsed: 10, endElapsed: 20, bucket: .present)
        ledger.append(startElapsed: 20, endElapsed: 25, bucket: .present)

        XCTAssertEqual(ledger.segments.count, 2)
        XCTAssertEqual(ledger.segments[0], TimelineSegment(startElapsed: 0, endElapsed: 10, bucket: .unknown))
        XCTAssertEqual(ledger.segments[1], TimelineSegment(startElapsed: 10, endElapsed: 25, bucket: .present))
        XCTAssertEqual(ledger.secondsByBucket[.unknown] ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(ledger.secondsByBucket[.present] ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(ledger.totalElapsed, 25, accuracy: 0.001)
    }

    func testIgnoresZeroOrReversedIntervalsAndClampsToPlannedSeconds() {
        var ledger = TimelineLedger(plannedSeconds: 100)
        ledger.append(startElapsed: 10, endElapsed: 10, bucket: .present)
        ledger.append(startElapsed: 15, endElapsed: 10, bucket: .present)
        ledger.append(startElapsed: 0, endElapsed: 150, bucket: .unverified)

        XCTAssertEqual(ledger.segments.count, 1)
        XCTAssertEqual(ledger.totalElapsed, 100, accuracy: 0.001)
        XCTAssertEqual(ledger.secondsByBucket[.unverified] ?? -1, 100, accuracy: 0.001)
    }
}
