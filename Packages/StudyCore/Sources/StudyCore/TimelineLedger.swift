import Foundation

public struct TimelineLedger: Equatable, Sendable {
    public let plannedSeconds: Double
    public private(set) var segments: [TimelineSegment] = []

    public init(plannedSeconds: Double) {
        self.plannedSeconds = plannedSeconds
    }

    public mutating func append(startElapsed: Double, endElapsed: Double, bucket: TimeBucket) {
        guard startElapsed.isFinite, endElapsed.isFinite else { return }
        let clampedStart = max(0, min(plannedSeconds, startElapsed))
        let clampedEnd = max(0, min(plannedSeconds, endElapsed))
        guard clampedEnd > clampedStart else { return }

        if let lastIndex = segments.indices.last,
           segments[lastIndex].bucket == bucket,
           abs(segments[lastIndex].endElapsed - clampedStart) <= 1e-9 {
            segments[lastIndex].endElapsed = clampedEnd
        } else {
            segments.append(TimelineSegment(startElapsed: clampedStart, endElapsed: clampedEnd, bucket: bucket))
        }
    }

    public var totalElapsed: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    public var secondsByBucket: [TimeBucket: Double] {
        var totals: [TimeBucket: Double] = [:]
        for bucket in TimeBucket.allCases {
            totals[bucket] = 0
        }
        for segment in segments {
            totals[segment.bucket, default: 0] += segment.duration
        }
        return totals
    }
}
