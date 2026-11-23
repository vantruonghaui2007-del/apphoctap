import Foundation
import Darwin
import StudyCore

public protocol SessionClock: Sendable {
    func now() -> TimePoint
}

public final class SystemSessionClock: SessionClock, @unchecked Sendable {
    private let timebaseNumer: UInt32
    private let timebaseDenom: UInt32
    private let isTimebaseValid: Bool

    public init() {
        var info = mach_timebase_info_data_t()
        let status = mach_timebase_info(&info)
        if status == KERN_SUCCESS && info.denom != 0 {
            self.timebaseNumer = info.numer
            self.timebaseDenom = info.denom
            self.isTimebaseValid = true
        } else {
            self.timebaseNumer = 0
            self.timebaseDenom = 1
            self.isTimebaseValid = false
        }
    }

    public func now() -> TimePoint {
        guard isTimebaseValid else {
            return TimePoint(monotonicSeconds: .nan, wallDate: Date())
        }
        let ticks = mach_continuous_time()
        let nanos = (Double(ticks) * Double(timebaseNumer)) / Double(timebaseDenom)
        return TimePoint(monotonicSeconds: nanos / 1_000_000_000.0, wallDate: Date())
    }
}
