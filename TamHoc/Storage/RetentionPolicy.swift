import Foundation
import StudyCore

public enum RetentionPolicy {
    public static let detailedEventRetentionDays: Int = 30
    private static let retentionSeconds: TimeInterval = TimeInterval(detailedEventRetentionDays) * 86_400

    /// Prunes detailed event logs older than 30 days based strictly on the record's wall date.
    /// Summary totals, segments, status, and configuration remain intact.
    /// Backward wall-clock jumps (`now < record.startedWallDate`) will never delete events.
    public static func pruneDetailedEvents(in record: SessionRecord, now: Date) -> SessionRecord {
        guard record.status.isTerminal else { return record }
        guard !record.events.isEmpty else { return record }
        guard record.startedWallDate.timeIntervalSince1970 > 0 else { return record }
        guard record.startedWallDate <= now else { return record }

        let age = now.timeIntervalSince(record.startedWallDate)
        guard age > retentionSeconds else { return record }

        var pruned = record
        pruned.events = []
        pruned.revision += 1
        return pruned
    }

    public static func pruneRepository(_ repository: SessionRepository, now: Date = Date()) async throws {
        let loaded = try await repository.loadAll()
        for record in loaded.records {
            let pruned = pruneDetailedEvents(in: record, now: now)
            if pruned.revision != record.revision {
                try await repository.save(pruned)
            }
        }
    }
}
