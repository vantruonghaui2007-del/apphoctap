import XCTest
import StudyCore
@testable import TamHoc

final class RepositoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TamHocRepoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeRecord(
        id: UUID = UUID(),
        revision: UInt64 = 1,
        status: SessionStatus = .completed,
        elapsed: Double = 120,
        startedAt: Date = Date(timeIntervalSince1970: 1_795_400_000.25)
    ) throws -> SessionRecord {
        let cfg = try SessionConfiguration.validated(
            plannedSeconds: 300,
            presenceMode: .cameraVerified,
            warningsEnabled: true
        )
        return SessionRecord(
            id: id,
            revision: revision,
            configuration: cfg,
            startedWallDate: startedAt,
            status: status,
            elapsedSeconds: elapsed,
            segments: [TimelineSegment(startElapsed: 0, endElapsed: elapsed, bucket: .present)],
            events: [SessionEvent(elapsedSeconds: 0, kind: .sessionStarted)]
        )
    }

    func testAtomicRoundTrip() async throws {
        let repo = FileSessionRepository(directory: tempDir)
        let record = try makeRecord()
        try await repo.save(record)

        // Reload via fresh repository instance
        let freshRepo = FileSessionRepository(directory: tempDir)
        let result = try await freshRepo.loadAll()

        XCTAssertTrue(result.quarantinedIDs.isEmpty)
        XCTAssertTrue(result.unsupportedSchemaFiles.isEmpty)
        XCTAssertEqual(result.records, [record])

        // Ensure raw monotonic wording or image bytes do not exist in stored JSON
        let fileURL = tempDir.appendingPathComponent("\(record.id.uuidString).json")
        let rawText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(rawText.contains("monotonicSeconds"))
    }

    func testCorruptRecordIsQuarantinedWithoutDeletingHistory() async throws {
        let repo = FileSessionRepository(directory: tempDir)
        let validRecord = try makeRecord()
        try await repo.save(validRecord)

        let corruptID = UUID()
        let corruptURL = tempDir.appendingPathComponent("\(corruptID.uuidString).json")
        try Data("{not valid json".utf8).write(to: corruptURL)

        let result = try await repo.loadAll()
        XCTAssertEqual(result.records, [validRecord])
        XCTAssertEqual(result.quarantinedIDs, [corruptID])

        // Corrupt file moved into Quarantine, NOT deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
        let quarantinedURL = tempDir
            .appendingPathComponent("Quarantine", isDirectory: true)
            .appendingPathComponent("\(corruptID.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedURL.path))
    }

    func testUnsupportedSchemaIsPreserved() async throws {
        let futureID = UUID()
        let futureURL = tempDir.appendingPathComponent("\(futureID.uuidString).json")
        let futureJSON = """
        {"schemaVersion":99,"id":"\(futureID.uuidString)","futureField":"keep-me"}
        """
        try Data(futureJSON.utf8).write(to: futureURL)

        let repo = FileSessionRepository(directory: tempDir)
        let result = try await repo.loadAll()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.quarantinedIDs.isEmpty)
        XCTAssertEqual(result.unsupportedSchemaFiles, ["\(futureID.uuidString).json"])
        // File must remain untouched on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: futureURL.path))
        XCTAssertEqual(try String(contentsOf: futureURL, encoding: .utf8), futureJSON)
    }

    func testRunningRecordBecomesInterruptedAtCheckpoint() async throws {
        let running = try makeRecord(revision: 4, status: .running, elapsed: 100)
        let repo = FileSessionRepository(directory: tempDir)
        try await repo.save(running)

        let loaded = try await repo.loadAll()
        let recovered = SessionRecovery.interruptUnfinished(try XCTUnwrap(loaded.records.first))

        XCTAssertEqual(recovered.status, .interrupted(.processRestart))
        XCTAssertEqual(recovered.elapsedSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(recovered.revision, 5)
        XCTAssertEqual(recovered.secondsByBucket[.present] ?? -1, 100, accuracy: 0.001)

        try await repo.save(recovered)
        let afterSave = try await FileSessionRepository(directory: tempDir).loadAll()
        XCTAssertEqual(afterSave.records.first?.status, .interrupted(.processRestart))
        XCTAssertEqual(afterSave.records.first?.elapsedSeconds ?? -1, 100, accuracy: 0.001)
    }

    func testOlderRevisionCannotOverwriteTerminal() async throws {
        let id = UUID()
        let repo = FileSessionRepository(directory: tempDir)

        let terminal = try makeRecord(id: id, revision: 5, status: .completed, elapsed: 300)
        try await repo.save(terminal)

        // Older revision is a no-op and preserves terminal record
        let older = try makeRecord(id: id, revision: 3, status: .running, elapsed: 90)
        try await repo.save(older)

        // Same revision with identical data is idempotent
        try await repo.save(terminal)

        // Same revision with different data throws revisionConflict and keeps old data
        let conflicting = try makeRecord(id: id, revision: 5, status: .endedEarly(.userEnded), elapsed: 150)
        do {
            try await repo.save(conflicting)
            XCTFail("Expected revisionConflict")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .revisionConflict)
        }

        let reloaded = try await FileSessionRepository(directory: tempDir).loadAll()
        XCTAssertEqual(reloaded.records, [terminal])
    }

    func testDiskWriteFailureIsReported() async throws {
        // Point repository directory to an existing regular file so directory/file write fails
        let fileNotDir = tempDir.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: fileNotDir)

        let repo = FileSessionRepository(directory: fileNotDir)
        let record = try makeRecord()

        do {
            try await repo.save(record)
            XCTFail("Expected write error when storage path is not a directory")
        } catch {
            // Expected error propagated cleanly
        }
    }

    func testSettingsAndCalibrationRoundTripDefaultsAndCorruptHandling() async throws {
        let settingsRepo = SettingsRepository(directory: tempDir)

        // Missing files return defaults / nil
        let initialSettings = try await settingsRepo.loadSettings()
        let initialCalibration = try await settingsRepo.loadCalibration()
        XCTAssertEqual(initialSettings, .default)
        XCTAssertNil(initialCalibration)

        // Round-trip
        let custom = AppSettings(
            defaultDurationSeconds: 1800,
            defaultPresenceMode: .timerOnly,
            warningsEnabled: false,
            onboardingVersionSeen: 1
        )
        try await settingsRepo.saveSettings(custom)
        let loadedSettings = try await settingsRepo.loadSettings()
        XCTAssertEqual(loadedSettings, custom)

        let cal = try Calibration(roiX: 0.2, roiY: 0.2, roiWidth: 0.6, roiHeight: 0.6)
        try await settingsRepo.saveCalibration(cal)
        let loadedCal = try await settingsRepo.loadCalibration()
        XCTAssertEqual(loadedCal, cal)

        // Corrupt settings file throws and keeps original corrupt file intact (no silent reset)
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let corruptPayload = Data("{broken".utf8)
        try corruptPayload.write(to: settingsURL)

        do {
            _ = try await settingsRepo.loadSettings()
            XCTFail("Expected decode error for corrupt settings")
        } catch {
            XCTAssertEqual(try Data(contentsOf: settingsURL), corruptPayload)
        }
    }
}
