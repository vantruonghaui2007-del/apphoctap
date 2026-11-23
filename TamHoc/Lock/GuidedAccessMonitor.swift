import Foundation
import UIKit

@MainActor
public protocol GuidedAccessMonitoring: AnyObject {
    var isEnabled: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

private final class NotificationObserverBox: @unchecked Sendable {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @Sendable () -> Void
    ) {
        self.center = center
        self.token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            handler()
        }
    }

    func invalidate() {
        if let token = token {
            center.removeObserver(token)
            self.token = nil
        }
    }

    deinit {
        invalidate()
    }
}

@MainActor
public final class GuidedAccessMonitor: GuidedAccessMonitoring {
    private let statusProvider: () -> Bool
    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var observerBox: NotificationObserverBox?
    private var lastObservedValue: Bool

    public init(
        statusProvider: @escaping () -> Bool = { UIAccessibility.isGuidedAccessEnabled },
        notificationCenter: NotificationCenter = .default,
        notificationName: Notification.Name = UIAccessibility.guidedAccessStatusDidChangeNotification
    ) {
        self.statusProvider = statusProvider
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.lastObservedValue = statusProvider()

        self.observerBox = NotificationObserverBox(
            center: notificationCenter,
            name: notificationName
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFromSystem()
            }
        }
    }

    public var isEnabled: Bool {
        let current = statusProvider()
        lastObservedValue = current
        return current
    }

    public var changes: AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    public func refreshFromSystem() {
        let current = statusProvider()
        guard current != lastObservedValue else { return }
        lastObservedValue = current
        for continuation in continuations.values {
            continuation.yield(current)
        }
    }
}
