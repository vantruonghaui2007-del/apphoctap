import Foundation
import StudyCore

public enum SessionExporter {
    public enum CSVCell {
        case text(String)
        case number(Double)
        case integer(Int)
    }

    public static let csvHeader = [
        "id",
        "started_at_iso8601",
        "status",
        "end_reason",
        "presence_mode",
        "planned_seconds",
        "elapsed_seconds",
        "present_seconds",
        "absent_seconds",
        "unknown_seconds",
        "unverified_seconds",
        "ineligible_seconds",
        "schema_version"
    ].joined(separator: ",")

    public static func csv(records: [SessionRecord]) -> Data {
        var lines: [String] = [csvHeader]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for record in records {
            let buckets = record.secondsByBucket
            let (statusText, endReasonText) = exportStatusAndReason(record.status)
            let row = csvRow([
                .text(record.id.uuidString),
                .text(formatter.string(from: record.startedWallDate)),
                .text(statusText),
                .text(endReasonText),
                .text(record.configuration.presenceMode.rawValue),
                .number(record.configuration.plannedSeconds),
                .number(record.elapsedSeconds),
                .number(buckets[.present] ?? 0),
                .number(buckets[.absent] ?? 0),
                .number(buckets[.unknown] ?? 0),
                .number(buckets[.unverified] ?? 0),
                .number(buckets[.ineligible] ?? 0),
                .integer(record.schemaVersion)
            ])
            lines.append(row)
        }

        let content = lines.joined(separator: "\n") + "\n"
        return Data(content.utf8)
    }

    public static func csvRow(_ cells: [CSVCell]) -> String {
        cells.map { cell in
            switch cell {
            case .text(let s):
                return csvTextCell(s)
            case .number(let n):
                return csvNumericCell(n)
            case .integer(let i):
                return String(i)
            }
        }.joined(separator: ",")
    }

    /// Escapes quotes/newlines and neutralizes spreadsheet formula prefixes (`=`, `+`, `-`, `@`, tab, CR) on text fields.
    public static func csvTextCell(_ raw: String) -> String {
        var value = raw
        if let first = value.first,
           first == "=" || first == "+" || first == "-" || first == "@" || first == "\t" || first == "\r" {
            value = "'" + value
        }
        let needsQuotes = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        if needsQuotes {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    public static func csvNumericCell(_ value: Double) -> String {
        guard value.isFinite else { return "0.00" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public static func json(records: [SessionRecord]) throws -> Data {
        let summaries = records.map { ExportSummary(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(summaries)
    }

    private static func exportStatusAndReason(_ status: SessionStatus) -> (String, String) {
        switch status {
        case .running:
            return ("running", "")
        case .completed:
            return ("completed", "deadline")
        case .endedEarly(let reason):
            return ("endedEarly", reason.rawValue)
        case .interrupted(let reason):
            return ("interrupted", reason.rawValue)
        }
    }
}

private struct ExportSummary: Codable {
    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    let status: String
    let endReason: String
    let presenceMode: String
    let warningsEnabled: Bool
    let plannedSeconds: Double
    let elapsedSeconds: Double
    let secondsByBucket: [String: Double]
    let eventCount: Int

    init(from record: SessionRecord) {
        self.schemaVersion = record.schemaVersion
        self.id = record.id
        self.startedAt = record.startedWallDate
        switch record.status {
        case .running:
            self.status = "running"
            self.endReason = ""
        case .completed:
            self.status = "completed"
            self.endReason = "deadline"
        case .endedEarly(let reason):
            self.status = "endedEarly"
            self.endReason = reason.rawValue
        case .interrupted(let reason):
            self.status = "interrupted"
            self.endReason = reason.rawValue
        }
        self.presenceMode = record.configuration.presenceMode.rawValue
        self.warningsEnabled = record.configuration.warningsEnabled
        self.plannedSeconds = record.configuration.plannedSeconds
        self.elapsedSeconds = record.elapsedSeconds
        var buckets: [String: Double] = [:]
        for (bucket, seconds) in record.secondsByBucket {
            buckets[bucket.rawValue] = seconds
        }
        self.secondsByBucket = buckets
        self.eventCount = record.events.count
    }
}
