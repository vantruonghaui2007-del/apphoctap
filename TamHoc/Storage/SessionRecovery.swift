import Foundation
import StudyCore

public enum SessionRecovery {
    /// Marks a previously running session as interrupted at its last checkpointed elapsed time.
    /// Does not add unverified wall time or auto-resume a session.
    public static func interruptUnfinished(_ record: SessionRecord) -> SessionRecord {
        guard record.status == .running else {
            return record
        }
        var updated = record
        updated.status = .interrupted(.processRestart)
        updated.events.append(
            SessionEvent(
                elapsedSeconds: record.elapsedSeconds,
                kind: .sessionEnded,
                detail: .processRestart
            )
        )
        updated.revision += 1
        return updated
    }
}
