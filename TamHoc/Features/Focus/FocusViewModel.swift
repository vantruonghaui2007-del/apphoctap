import Foundation
import SwiftUI
import StudyCore

@MainActor
public final class FocusViewModel: ObservableObject {
    private let sessionViewModel: SessionViewModel

    public init(sessionViewModel: SessionViewModel) {
        self.sessionViewModel = sessionViewModel
    }

    public var snapshot: SessionSnapshot? {
        sessionViewModel.snapshot
    }

    public var mode: PresenceMode {
        sessionViewModel.activeConfiguration?.presenceMode ?? .timerOnly
    }

    public var plannedSeconds: Double {
        sessionViewModel.activeConfiguration?.plannedSeconds ?? 3000
    }

    public var remainingText: String {
        DurationFormatter.mmss(snapshot?.remainingSeconds ?? plannedSeconds)
    }

    public var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        let elapsed = snapshot?.elapsedSeconds ?? 0
        return min(1, max(0, elapsed / plannedSeconds))
    }

    public var isGuidedAccessEnabled: Bool {
        sessionViewModel.isGuidedAccessEnabled
    }

    public var presenceDisplay: (text: String, icon: String, tint: Color) {
        let value = snapshot?.presence ?? .unknown(.warmingUp)
        return PresenceDisplayFormatter.textAndIcon(for: value, mode: mode)
    }

    public func endEarly() async {
        await sessionViewModel.endEarly()
    }
}
