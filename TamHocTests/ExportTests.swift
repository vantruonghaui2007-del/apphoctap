import XCTest
import StudyCore
@testable import TamHoc

@MainActor
final class ExportTests: XCTestCase {
    func testWarningOncePerAbsence() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let warning = SpyWarningPlayer()
        let coordinator = SessionCoordinator(
            clock: clock,
            lockMonitor: lock,
            presenceMonitor: presence,
            repository: repo,
            warningPlayer: warning,
            idleTimerController: FakeIdleTimerController(),
            backgroundTaskManager: FakeBackgroundTaskManager()
        )

        let cfg = try SessionConfiguration.validated(plannedSeconds: 300, presenceMode: .cameraVerified, warningsEnabled: true)
        try await coordinator.start(configuration: cfg, calibration: .defaultCentered)
        let gen = try XCTUnwrap(presence.lastStartedGeneration)
        try? await Task.sleep(nanoseconds: 20_000_000)

        var seq: UInt64 = 1
        func send(_ value: PresenceValue, at t: Double) async {
            clock.set(monotonicSeconds: t)
            presence.emit(PresenceSample(sequence: seq, capturedMonotonicSeconds: t, value: value), generation: gen)
            seq += 1
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        // Absent continuously 0..28s -> 0 warnings
        for t in stride(from: 0.0, through: 28.0, by: 2.0) {
            await send(.absent, at: t)
        }
        XCTAssertEqual(warning.playCount, 0)

        // Reaches 30s -> 1 warning
        await send(.absent, at: 30.0)
        XCTAssertEqual(warning.playCount, 1)

        // Remains absent through 60s -> does NOT repeat warning
        for t in stride(from: 32.0, through: 60.0, by: 2.0) {
            await send(.absent, at: t)
        }
        XCTAssertEqual(warning.playCount, 1)

        // Returns stably for 6s
        for t in stride(from: 62.0, through: 68.0, by: 2.0) {
            await send(.present, at: t)
        }
        XCTAssertEqual(coordinator.snapshot?.presence, .present)

        // Leaves again for 30s -> new warning fires once
        for t in stride(from: 70.0, through: 100.0, by: 2.0) {
            await send(.absent, at: t)
        }
        XCTAssertEqual(warning.playCount, 2)

        await coordinator.endEarly()
    }

    func testCSVQuotesNewlinesAndFormulaPrefixes() throws {
        // Formula injection neutralization on text cells
        XCTAssertEqual(SessionExporter.csvTextCell("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(SessionExporter.csvTextCell("+cmd"), "'+cmd")
        XCTAssertEqual(SessionExporter.csvTextCell("-danger"), "'-danger")
        XCTAssertEqual(SessionExporter.csvTextCell("@import"), "'@import")
        // Quotes and newlines properly escaped
        XCTAssertEqual(SessionExporter.csvTextCell("hello \"world\"\nline2"), "\"hello \"\"world\"\"\nline2\"")
        // Combined formula prefix + comma
        XCTAssertEqual(SessionExporter.csvTextCell("=1,2"), "\"'=1,2\"")
        // Numeric fields stay pure unquoted numbers
        XCTAssertEqual(SessionExporter.csvNumericCell(120.5), "120.50")

        // End-to-end record CSV check
        let cfg = try SessionConfiguration.validated(plannedSeconds: 180, presenceMode: .cameraVerified, warningsEnabled: true)
        let record = SessionRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            revision: 2,
            configuration: cfg,
            startedWallDate: Date(timeIntervalSince1970: 1_795_400_000),
            status: .completed,
            elapsedSeconds: 180,
            segments: [
                TimelineSegment(startElapsed: 0, endElapsed: 150, bucket: .present),
                TimelineSegment(startElapsed: 150, endElapsed: 180, bucket: .absent)
            ],
            events: []
        )

        let data = SessionExporter.csv(records: [record])
        let csvString = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csvString.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(lines[0]), SessionExporter.csvHeader)
        XCTAssertTrue(lines[1].contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(lines[1].contains(",180.00,180.00,150.00,30.00,0.00,0.00,0.00,1"))
    }

    func testExportContainsNoRawClockOrImage() throws {
        let cfg = try SessionConfiguration.validated(plannedSeconds: 120, presenceMode: .timerOnly, warningsEnabled: false)
        let record = SessionRecord(
            id: UUID(),
            revision: 1,
            configuration: cfg,
            startedWallDate: Date(timeIntervalSince1970: 1_795_400_000),
            status: .endedEarly(.userEnded),
            elapsedSeconds: 45,
            segments: [TimelineSegment(startElapsed: 0, endElapsed: 45, bucket: .unverified)],
            events: [SessionEvent(elapsedSeconds: 0, kind: .sessionStarted)]
        )

        let csvText = try XCTUnwrap(String(data: SessionExporter.csv(records: [record]), encoding: .utf8))
        let jsonData = try SessionExporter.json(records: [record])
        let jsonText = try XCTUnwrap(String(data: jsonData, encoding: .utf8))

        for forbidden in ["monotonic", "mach_continuous", "pixelBuffer", "image", "jpeg", "png"] {
            XCTAssertFalse(csvText.lowercased().contains(forbidden.lowercased()), "CSV leaked \(forbidden)")
            XCTAssertFalse(jsonText.lowercased().contains(forbidden.lowercased()), "JSON leaked \(forbidden)")
        }

        // Verify JSON parses cleanly as array of dictionaries
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(parsed?.first?["elapsedSeconds"] as? Double ?? -1, 45, accuracy: 0.01)
    }

    func testHistoryDeletionPersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TamHocHistoryTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repo = FileSessionRepository(directory: tempDir)
        let cfg = try SessionConfiguration.validated(plannedSeconds: 120, presenceMode: .timerOnly, warningsEnabled: true)
        let r1 = SessionRecord(
            id: UUID(),
            revision: 1,
            configuration: cfg,
            startedWallDate: Date(timeIntervalSince1970: 1_795_400_000),
            status: .completed,
            elapsedSeconds: 120,
            segments: [TimelineSegment(startElapsed: 0, endElapsed: 120, bucket: .unverified)],
            events: []
        )
        let r2 = SessionRecord(
            id: UUID(),
            revision: 1,
            configuration: cfg,
            startedWallDate: Date(timeIntervalSince1970: 1_795_401_000),
            status: .completed,
            elapsedSeconds: 120,
            segments: [TimelineSegment(startElapsed: 0, endElapsed: 120, bucket: .unverified)],
            events: []
        )

        try await repo.save(r1)
        try await repo.save(r2)

        let vm = HistoryViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.records.count, 2)

        await vm.delete(id: r1.id)
        XCTAssertEqual(vm.records.map(\.id), [r2.id])

        // Verify persisted across fresh repository instance
        let reloaded = try await FileSessionRepository(directory: tempDir).loadAll()
        XCTAssertEqual(reloaded.records.map(\.id), [r2.id])
    }
}
