import Foundation
import SwiftUI
import UIKit
import StudyCore

@MainActor
public final class AppActivityMonitor {
    public private(set) var currentState: ActivityState
    private let broadcaster = StreamBroadcaster<ActivityState>()
    private var observerBox: NotificationObserverBox?

    public init(
        initialState: ActivityState? = nil,
        notificationCenter: NotificationCenter = .default,
        observeSystemNotifications: Bool = true
    ) {
        self.currentState = initialState ?? Self.readCurrentUIApplicationState()
        if observeSystemNotifications {
            self.observerBox = NotificationObserverBox(
                center: notificationCenter,
                registrations: [
                    (UIApplication.didBecomeActiveNotification, { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.report(.active)
                        }
                    }),
                    (UIApplication.willResignActiveNotification, { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.report(.inactive)
                        }
                    }),
                    (UIApplication.didEnterBackgroundNotification, { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.report(.background)
                        }
                    })
                ]
            )
        }
    }

    public var changes: AsyncStream<ActivityState> {
        broadcaster.makeStream()
    }

    public func report(_ newState: ActivityState) {
        guard newState != currentState else { return }
        currentState = newState
        broadcaster.yield(newState)
    }

    public func report(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            report(.active)
        case .inactive:
            report(.inactive)
        case .background:
            report(.background)
        @unknown default:
            report(.inactive)
        }
    }

    public static func readCurrentUIApplicationState() -> ActivityState {
        switch UIApplication.shared.applicationState {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}
