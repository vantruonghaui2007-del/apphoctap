import Foundation
import StudyCore

public struct RepositoryReadResult: Equatable, Sendable {
    public let records: [SessionRecord]
    public let quarantinedIDs: [UUID]
    public let unsupportedSchemaFiles: [String]

    public init(
        records: [SessionRecord],
        quarantinedIDs: [UUID],
        unsupportedSchemaFiles: [String] = []
    ) {
        self.records = records
        self.quarantinedIDs = quarantinedIDs
        self.unsupportedSchemaFiles = unsupportedSchemaFiles
    }
}

public protocol SessionRepository: Sendable {
    func loadAll() async throws -> RepositoryReadResult
    func save(_ record: SessionRecord) async throws
    func delete(id: UUID) async throws
}

public enum RepositoryError: Error, Equatable {
    case unsupportedSchema
    case revisionConflict
    case terminalImmutable
    case invalidRecord(String)
    case quarantineFailed(String)
}

enum RepositoryJSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }

            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            if let date = basic.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date string"
            )
        }
        return decoder
    }
}

private struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int
}

public actor FileSessionRepository: SessionRepository {
    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var knownRecords: [UUID: SessionRecord] = [:]
    private var knownEncodedData: [UUID: Data] = [:]

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = RepositoryJSONCoding.makeEncoder()
        self.decoder = RepositoryJSONCoding.makeDecoder()
    }

    public static func defaultSessionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("TamHoc", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
    }

    public func loadAll() async throws -> RepositoryReadResult {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var records: [SessionRecord] = []
        var quarantinedIDs: [UUID] = []
        var unsupportedFiles: [String] = []

        for fileURL in contents {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }

            let data = try Data(contentsOf: fileURL)

            if let probe = try? decoder.decode(SchemaVersionProbe.self, from: data),
               probe.schemaVersion != SessionRecord.currentSchemaVersion {
                // Keep future/unsupported schemas read-only and untouched.
                unsupportedFiles.append(fileURL.lastPathComponent)
                continue
            }

            do {
                let record = try decodeValidatedRecord(from: data)
                records.append(record)
                knownRecords[record.id] = record
                knownEncodedData[record.id] = data
            } catch {
                try quarantineFile(at: fileURL)
                let stem = fileURL.deletingPathExtension().lastPathComponent
                if let parsedID = UUID(uuidString: stem) {
                    quarantinedIDs.append(parsedID)
                }
            }
        }

        records.sort { $0.startedWallDate > $1.startedWallDate }
        return RepositoryReadResult(
            records: records,
            quarantinedIDs: quarantinedIDs,
            unsupportedSchemaFiles: unsupportedFiles
        )
    }

    public func save(_ record: SessionRecord) async throws {
        guard record.schemaVersion == SessionRecord.currentSchemaVersion else {
            throw RepositoryError.unsupportedSchema
        }
        try validateRecord(record)

        let fileURL = fileURL(for: record.id)

        // Ensure revision guard knows any existing record on disk even across repository instances
        if knownRecords[record.id] == nil, fileManager.fileExists(atPath: fileURL.path) {
            let existingData = try Data(contentsOf: fileURL)
            if let probe = try? decoder.decode(SchemaVersionProbe.self, from: existingData),
               probe.schemaVersion != SessionRecord.currentSchemaVersion {
                throw RepositoryError.unsupportedSchema
            }
            if let existingRecord = try? decodeValidatedRecord(from: existingData) {
                knownRecords[record.id] = existingRecord
                knownEncodedData[record.id] = existingData
            }
        }

        let newData = try encoder.encode(record)

        if let existing = knownRecords[record.id] {
            if record.revision < existing.revision {
                return
            }
            if record.revision == existing.revision {
                if record == existing || knownEncodedData[record.id] == newData {
                    return
                }
                throw RepositoryError.revisionConflict
            }
            if existing.status.isTerminal && !record.status.isTerminal {
                throw RepositoryError.terminalImmutable
            }
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try newData.write(to: fileURL, options: options)

        knownRecords[record.id] = record
        knownEncodedData[record.id] = newData
    }

    public func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        knownRecords.removeValue(forKey: id)
        knownEncodedData.removeValue(forKey: id)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func decodeValidatedRecord(from data: Data) throws -> SessionRecord {
        let record = try decoder.decode(SessionRecord.self, from: data)
        guard record.schemaVersion == SessionRecord.currentSchemaVersion else {
            throw RepositoryError.unsupportedSchema
        }
        try validateRecord(record)
        return record
    }

    private func validateRecord(_ record: SessionRecord) throws {
        guard record.elapsedSeconds.isFinite,
              record.elapsedSeconds >= 0,
              record.elapsedSeconds <= record.configuration.plannedSeconds + 0.01 else {
            throw RepositoryError.invalidRecord("Elapsed out of bounds")
        }
        for segment in record.segments {
            guard segment.startElapsed.isFinite,
                  segment.endElapsed.isFinite,
                  segment.startElapsed >= 0,
                  segment.endElapsed >= segment.startElapsed else {
                throw RepositoryError.invalidRecord("Invalid timeline segment")
            }
        }
    }

    private func quarantineFile(at sourceURL: URL) throws {
        let quarantineDir = directory.appendingPathComponent("Quarantine", isDirectory: true)
        do {
            try fileManager.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            var destination = quarantineDir.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destination.path) {
                let stem = sourceURL.deletingPathExtension().lastPathComponent
                destination = quarantineDir.appendingPathComponent("\(stem)-\(UUID().uuidString).json", isDirectory: false)
            }
            try fileManager.moveItem(at: sourceURL, to: destination)
        } catch {
            throw RepositoryError.quarantineFailed(error.localizedDescription)
        }
    }
}
