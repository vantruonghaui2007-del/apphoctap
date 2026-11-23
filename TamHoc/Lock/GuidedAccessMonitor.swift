import Foundation
import UIKit

@MainActor
public protocol GuidedAccessMonitoring: AnyObject {
    var isEnabled: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

final class NotificationObserverBox: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter, registrations: [(Notification.Name, @Sendable () -> Void)]) {
        self.center = center
        for (name, handler) in registrations {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                handler()
            }
            tokens.append(token)
        }
    }

    func invalidate() {
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit {
        invalidate()
    }
}

final class StreamBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func makeStream() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func yield(_ value: Element) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        for continuation in active {
            continuation.yield(value)
        }
    }

    func finishAll() {
        lock.lock()
        let active = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in active {
            continuation.finish()
        }
    }

    deinit {
        finishAll()
    }
}

@MainActor
public final class GuidedAccessMonitor: GuidedAccessMonitoring {
    private let statusProvider: () -> Bool
    private let broadcaster = StreamBroadcaster<Bool>()
    private var observerBox: NotificationObserverBox?
    private var lastObservedValue: Bool

    public init(
        statusProvider: @escaping () -> Bool = { UIAccessibility.isGuidedAccessEnabled },
        notificationCenter: NotificationCenter = .default,
        notificationName: Notification.Name = UIAccessibility.guidedAccessStatusDidChangeNotification
    ) {
        self.statusProvider = statusProvider
        self.lastObservedValue = statusProvider()

        self.observerBox = NotificationObserverBox(
            center: notificationCenter,
            registrations: [
                (notificationName, { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.refreshFromSystem()
                    }
                })
            ]
        )
    }

    public var isEnabled: Bool {
        let current = statusProvider()
        lastObservedValue = current
        return current
    }

    public var changes: AsyncStream<Bool> {
        broadcaster.makeStream()
    }

    /// Reads current system Guided Access status directly; never blindly toggles cached state.
    public func refreshFromSystem() {
        let current = statusProvider()
        guard current != lastObservedValue else { return }
        lastObservedValue = current
        broadcaster.yield(current)
    }
}
