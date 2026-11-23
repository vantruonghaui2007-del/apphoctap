import Foundation
@testable import StudyCore

enum TestSupport {
    static let baseWallDate = Date(timeIntervalSince1970: 1_795_400_000)

    static func point(_ seconds: Double, wallOffset: Double? = nil) -> TimePoint {
        TimePoint(
            monotonicSeconds: seconds,
            wallDate: baseWallDate.addingTimeInterval(wallOffset ?? seconds)
        )
    }

    static func makeEngine(
        duration: Double = 120,
        presenceMode: PresenceMode = .cameraVerified,
        warningsEnabled: Bool = true,
        startSeconds: Double = 0
    ) -> SessionEngine {
        let config = try! SessionConfiguration.validated(
            plannedSeconds: duration,
            presenceMode: presenceMode,
            warningsEnabled: warningsEnabled
        )
        return SessionEngine(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            configuration: config,
            startedAt: point(startSeconds)
        )
    }
}

func makeEngine(
    duration: Double = 120,
    presenceMode: PresenceMode = .cameraVerified,
    warningsEnabled: Bool = true
) -> SessionEngine {
    TestSupport.makeEngine(duration: duration, presenceMode: presenceMode, warningsEnabled: warningsEnabled)
}

func point(_ seconds: Double, wallOffset: Double? = nil) -> TimePoint {
    TestSupport.point(seconds, wallOffset: wallOffset)
}

final class SampleSequenceGenerator {
    private var nextSequence: UInt64 = 1

    func sample(_ value: PresenceValue, at capturedSeconds: Double) -> PresenceSample {
        defer { nextSequence += 1 }
        return PresenceSample(
            sequence: nextSequence,
            capturedMonotonicSeconds: capturedSeconds,
            value: value
        )
    }
}
