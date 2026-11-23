import XCTest
import StudyCore
@testable import TamHoc

final class RetentionPolicyTests: XCTestCase {
    func testRetentionKeepsSummaryAfter30Days() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldDate = now.addingTimeInterval(-31 * 86_400)
        let recentDate = now.addingTimeInterval(-10 * 86_400)
        let futureDate = now.addingTimeInterval(5 * 86_400)

        let cfg = try SessionConfiguration.validated(
            plannedSeconds: 300,
            presenceMode: .cameraVerified,
            warningsEnabled: true
        )
        let sampleEvents = [
            SessionEvent(elapsedSeconds: 0, kind: .sessionStarted),
            SessionEvent(elapsedSeconds: 30, kind: .absenceWarning),
            SessionEvent(elapsedSeconds: 300, kind: .sessionEnded, detail: .deadline)
        ]
        let sampleSegments = [
            TimelineSegment(startElapsed: 0, endElapsed: 250, bucket: .present),
            TimelineSegment(startElapsed: 250, endElapsed: 300, bucket: .absent)
        ]

        // 1. Old terminal record (>30 days) -> prunes detailed events, keeps totals & segments
        let oldRecord = SessionRecord(
            id: UUID(),
            revision: 3,
            configuration: cfg,
            startedWallDate: oldDate,
            status: .completed,
            elapsedSeconds: 300,
            segments: sampleSegments,
            events: sampleEvents
        )
        let prunedOld = RetentionPolicy.pruneDetailedEvents(in: oldRecord, now: now)
        XCTAssertTrue(prunedOld.events.isEmpty)
        XCTAssertEqual(prunedOld.revision, 4)
        XCTAssertEqual(prunedOld.segments, sampleSegments)
        XCTAssertEqual(prunedOld.elapsedSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(prunedOld.secondsByBucket[.present] ?? -1, 250, accuracy: 0.001)
        XCTAssertEqual(prunedOld.secondsByBucket[.absent] ?? -1, 50, accuracy: 0.001)

        // 2. Recent record (<30 days) -> keeps events untouched
        let recentRecord = SessionRecord(
            id: UUID(),
            revision: 3,
            configuration: cfg,
            startedWallDate: recentDate,
            status: .completed,
            elapsedSeconds: 300,
            segments: sampleSegments,
            events: sampleEvents
        )
        let checkedRecent = RetentionPolicy.pruneDetailedEvents(in: recentRecord, now: now)
        XCTAssertEqual(checkedRecent, recentRecord)

        // 3. Backward wall-clock jump (record date appears in future relative to now) -> never prunes!
        let futureRecord = SessionRecord(
            id: UUID(),
            revision: 3,
            configuration: cfg,
            startedWallDate: futureDate,
            status: .completed,
            elapsedSeconds: 300,
            segments: sampleSegments,
            events: sampleEvents
        )
        let checkedFuture = RetentionPolicy.pruneDetailedEvents(in: futureRecord, now: now)
        XCTAssertEqual(checkedFuture, futureRecord)
    }
}
