import Foundation
import AVFoundation
import CoreVideo
import ImageIO
import StudyCore

public struct PresenceMonitorEvent: Equatable, Sendable {
    public let generation: UUID
    public let sample: PresenceSample

    public init(generation: UUID, sample: PresenceSample) {
        self.generation = generation
        self.sample = sample
    }
}

@MainActor
public protocol PresenceMonitoring: AnyObject {
    var events: AsyncStream<PresenceMonitorEvent> { get }
    func start(calibration: Calibration, generation: UUID) async throws
    func stop(generation: UUID) async
    func stop() async
}

public extension PresenceMonitoring {
    func stop(generation: UUID) async {
        await stop()
    }
}

public enum PresenceMonitorError: Error, Equatable {
    case permissionDenied
    case permissionRestricted
    case cameraUnavailable
    case thermalCritical
}

public enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public protocol CameraAuthorizing: Sendable {
    func authorizationStatus() -> CameraAuthorizationState
    func requestAccess() async -> Bool
    func hasFrontCamera() -> Bool
}

public struct SystemCameraAuthorizer: CameraAuthorizing {
    public init() {}

    public func authorizationStatus() -> CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public func hasFrontCamera() -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }
}

/// Thread-safe gate enforcing single-inflight frame analysis, thermal-adaptive rate limiting,
/// and generation isolation between capture/analysis threads and MainActor.
final class FrameAnalysisCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: SessionClock
    private let detector: PersonDetecting
    private let emitHandler: @Sendable (PresenceMonitorEvent) -> Void

    private var activeGeneration: UUID?
    private var activeRunToken: UUID?
    private var pendingGeneration: UUID?
    private var pendingRunToken: UUID?
    private var calibration: Calibration?
    private var isInflight = false
    private var lastSampleMonotonic: Double?
    private var sequence: UInt64 = 0
    private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    init(
        clock: SessionClock,
        detector: PersonDetecting,
        emitHandler: @escaping @Sendable (PresenceMonitorEvent) -> Void
    ) {
        self.clock = clock
        self.detector = detector
        self.emitHandler = emitHandler
    }

    func prepareRun(generation: UUID, token: UUID) {
        lock.lock()
        self.pendingGeneration = generation
        self.pendingRunToken = token
        lock.unlock()
    }

    func activateIfPending(
        generation: UUID,
        token: UUID,
        calibration: Calibration,
        thermalState: ProcessInfo.ThermalState
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.pendingRunToken == token, self.pendingGeneration == generation else { return false }
        self.pendingRunToken = nil
        self.pendingGeneration = nil
        self.activeRunToken = token
        self.activeGeneration = generation
        self.calibration = calibration
        self.isInflight = false
        self.lastSampleMonotonic = nil
        self.thermalState = thermalState
        return true
    }

    func activate(generation: UUID, calibration: Calibration, thermalState: ProcessInfo.ThermalState) {
        lock.lock()
        self.pendingRunToken = nil
        self.pendingGeneration = nil
        self.activeRunToken = UUID()
        self.activeGeneration = generation
        self.calibration = calibration
        self.isInflight = false
        self.lastSampleMonotonic = nil
        // Keep sequence strictly monotonic across restarts so PresencePolicy never drops resumed frames
        self.thermalState = thermalState
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        self.pendingRunToken = nil
        self.pendingGeneration = nil
        self.activeRunToken = nil
        self.activeGeneration = nil
        self.calibration = nil
        self.isInflight = false
        lock.unlock()
    }

    func deactivateIfMatching(token: UUID) {
        lock.lock()
        if self.pendingRunToken == token {
            self.pendingRunToken = nil
            self.pendingGeneration = nil
        }
        if self.activeRunToken == token {
            self.activeRunToken = nil
            self.activeGeneration = nil
            self.calibration = nil
            self.isInflight = false
        }
        lock.unlock()
    }

    func deactivateIfMatching(generation: UUID) {
        lock.lock()
        if self.pendingGeneration == generation {
            self.pendingRunToken = nil
            self.pendingGeneration = nil
        }
        if self.activeGeneration == generation {
            self.activeRunToken = nil
            self.activeGeneration = nil
            self.calibration = nil
            self.isInflight = false
        }
        lock.unlock()
    }

    func updateThermalState(_ newState: ProcessInfo.ThermalState) {
        lock.lock()
        let gen = activeGeneration
        self.thermalState = newState
        var criticalEvent: PresenceMonitorEvent?
        if newState == .critical, let gen = gen {
            sequence += 1
            let now = clock.now().monotonicSeconds
            let sample = PresenceSample(sequence: sequence, capturedMonotonicSeconds: now, value: .unknown(.thermal))
            criticalEvent = PresenceMonitorEvent(generation: gen, sample: sample)
        }
        lock.unlock()

        if let event = criticalEvent {
            emitHandler(event)
        }
    }

    func emitIssue(_ issue: ObservationIssue, forToken expectedToken: UUID? = nil) {
        lock.lock()
        if let expectedToken = expectedToken, activeRunToken != expectedToken {
            lock.unlock()
            return
        }
        guard let gen = activeGeneration else {
            lock.unlock()
            return
        }
        sequence += 1
        let seq = sequence
        let now = clock.now().monotonicSeconds
        lock.unlock()

        let sample = PresenceSample(sequence: seq, capturedMonotonicSeconds: now, value: .unknown(issue))
        emitHandler(PresenceMonitorEvent(generation: gen, sample: sample))
    }

    static func sampleInterval(for thermal: ProcessInfo.ThermalState) -> Double? {
        switch thermal {
        case .nominal, .fair:
            return 0.5 // 2 Hz
        case .serious:
            return 1.0 // 1 Hz
        case .critical:
            return nil // stop verification
        @unknown default:
            return 1.0
        }
    }

    @discardableResult
    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) -> Bool {
        let captureTime = clock.now().monotonicSeconds
        guard captureTime.isFinite else { return false }

        lock.lock()
        guard let gen = activeGeneration, let runToken = activeRunToken, let cal = calibration else {
            lock.unlock()
            return false
        }
        guard let minInterval = Self.sampleInterval(for: thermalState) else {
            lock.unlock()
            return false
        }
        guard !isInflight else {
            lock.unlock()
            return false
        }
        if let last = lastSampleMonotonic, (captureTime - last) < minInterval - 1e-6 {
            lock.unlock()
            return false
        }
        isInflight = true
        lastSampleMonotonic = captureTime
        sequence += 1
        let seq = sequence
        lock.unlock()

        let detectedValue: PresenceValue
        do {
            detectedValue = try detector.detect(
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                calibration: cal
            )
        } catch {
            detectedValue = .unknown(.detectorFailure)
        }

        lock.lock()
        isInflight = false
        let stillActive = (activeGeneration == gen && activeRunToken == runToken)
        lock.unlock()

        guard stillActive else { return false }

        let sample = PresenceSample(
            sequence: seq,
            capturedMonotonicSeconds: captureTime,
            value: detectedValue
        )
        emitHandler(PresenceMonitorEvent(generation: gen, sample: sample))
        return true
    }
}

private final class CaptureSampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let coordinator: FrameAnalysisCoordinator

    init(coordinator: FrameAnalysisCoordinator) {
        self.coordinator = coordinator
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        coordinator.processFrame(pixelBuffer, orientation: .up)
    }
}

public protocol CaptureSessionDriving: AnyObject, Sendable {
    var rawCaptureSession: AVCaptureSession? { get }
    var notificationSender: AnyObject? { get }
    var isRunning: Bool { get }
    func configure(
        delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        analysisQueue: DispatchQueue
    ) throws
    func startRunning()
    func stopRunning()
}

public final class AVCaptureSessionDriver: CaptureSessionDriving, @unchecked Sendable {
    private let session = AVCaptureSession()

    public init() {}

    public var rawCaptureSession: AVCaptureSession? { session }
    public var notificationSender: AnyObject? { session }
    public var isRunning: Bool { session.isRunning }

    public func configure(
        delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        analysisQueue: DispatchQueue
    ) throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw PresenceMonitorError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        guard session.canAddInput(input) else {
            throw PresenceMonitorError.cameraUnavailable
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(delegate, queue: analysisQueue)

        guard session.canAddOutput(output) else {
            throw PresenceMonitorError.cameraUnavailable
        }
        session.addOutput(output)

        if output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        }

        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
    }

    public func startRunning() {
        session.startRunning()
    }

    public func stopRunning() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

private final class StartupErrorTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var inStartupPhase = true
    private var failed = false

    func recordStartupFailure() {
        lock.lock()
        if inStartupPhase {
            failed = true
        }
        lock.unlock()
    }

    func finishStartupPhase() {
        lock.lock()
        inStartupPhase = false
        lock.unlock()
    }

    var hasStartupError: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }
}

@MainActor
public final class CameraPresenceMonitor: PresenceMonitoring {
    private let clock: SessionClock
    private let authorizer: CameraAuthorizing
    private let detector: PersonDetecting
    private let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState
    private let sessionDriverFactory: @Sendable () -> CaptureSessionDriving
    private let notificationCenter: NotificationCenter
    private let broadcaster = StreamBroadcaster<PresenceMonitorEvent>()
    private let frameCoordinator: FrameAnalysisCoordinator

    private let captureQueue = DispatchQueue(label: "vn.tamhoc.camera.capture", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "vn.tamhoc.camera.analysis", qos: .userInitiated)

    private var captureDriver: CaptureSessionDriving?
    private var pendingSetupDriver: (generation: UUID, token: UUID, driver: CaptureSessionDriving)?
    private var sampleDelegate: CaptureSampleDelegate?
    private var observerBox: NotificationObserverBox?
    private var activeGeneration: UUID?
    private var desiredGeneration: UUID?
    private var desiredRunToken: UUID?

    /// Available only for CalibrationView live preview; never shown during FocusView.
    public var previewCaptureSession: AVCaptureSession? {
        captureDriver?.rawCaptureSession
    }

    public init(
        clock: SessionClock = SystemSessionClock(),
        authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
        detector: PersonDetecting = VisionPersonDetector(),
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        sessionDriverFactory: @escaping @Sendable () -> CaptureSessionDriving = { AVCaptureSessionDriver() },
        notificationCenter: NotificationCenter = .default
    ) {
        self.clock = clock
        self.authorizer = authorizer
        self.detector = detector
        self.thermalStateProvider = thermalStateProvider
        self.sessionDriverFactory = sessionDriverFactory
        self.notificationCenter = notificationCenter
        let broadcaster = self.broadcaster
        self.frameCoordinator = FrameAnalysisCoordinator(
            clock: clock,
            detector: detector
        ) { event in
            broadcaster.yield(event)
        }
    }

    public var events: AsyncStream<PresenceMonitorEvent> {
        broadcaster.makeStream()
    }

    public func start(calibration: Calibration, generation: UUID) async throws {
        let runToken = UUID()
        desiredRunToken = runToken
        desiredGeneration = generation

        // Check authorization and request only when camera mode is actively started
        switch authorizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let granted = await authorizer.requestAccess()
            guard desiredRunToken == runToken, !Task.isCancelled else {
                throw CancellationError()
            }
            guard granted else {
                if desiredRunToken == runToken {
                    desiredRunToken = nil
                    desiredGeneration = nil
                }
                throw PresenceMonitorError.permissionDenied
            }
        case .denied:
            if desiredRunToken == runToken {
                desiredRunToken = nil
                desiredGeneration = nil
            }
            throw PresenceMonitorError.permissionDenied
        case .restricted:
            if desiredRunToken == runToken {
                desiredRunToken = nil
                desiredGeneration = nil
            }
            throw PresenceMonitorError.permissionRestricted
        }

        guard authorizer.hasFrontCamera() else {
            if desiredRunToken == runToken {
                desiredRunToken = nil
                desiredGeneration = nil
            }
            throw PresenceMonitorError.cameraUnavailable
        }

        // Tear down any previous session cleanly while preserving our new desiredRunToken
        await teardownSessionOnQueue(preservingToken: runToken)
        guard desiredRunToken == runToken, !Task.isCancelled else {
            throw CancellationError()
        }

        let thermal = thermalStateProvider()
        if thermal == .critical {
            if desiredRunToken == runToken {
                desiredRunToken = nil
                desiredGeneration = nil
            }
            throw PresenceMonitorError.thermalCritical
        }

        let driver = sessionDriverFactory()
        let delegate = CaptureSampleDelegate(coordinator: frameCoordinator)
        let startupTracker = StartupErrorTracker()
        let sessionObserver = makeSessionObserver(
            for: driver,
            runToken: runToken,
            startupTracker: startupTracker
        )

        pendingSetupDriver = (generation: generation, token: runToken, driver: driver)
        frameCoordinator.prepareRun(generation: generation, token: runToken)

        let started = await configureAndStartDriver(
            driver: driver,
            delegate: delegate,
            generation: generation,
            runToken: runToken,
            calibration: calibration,
            thermal: thermal,
            startupTracker: startupTracker
        )

        if pendingSetupDriver?.token == runToken {
            pendingSetupDriver = nil
        }

        guard desiredRunToken == runToken, !Task.isCancelled else {
            sessionObserver.invalidate()
            frameCoordinator.deactivateIfMatching(token: runToken)
            await stopDriverOnQueue(driver)
            throw CancellationError()
        }

        guard started, driver.isRunning, !startupTracker.hasStartupError else {
            sessionObserver.invalidate()
            frameCoordinator.deactivateIfMatching(token: runToken)
            await stopDriverOnQueue(driver)
            if desiredRunToken == runToken {
                desiredRunToken = nil
                desiredGeneration = nil
            }
            throw PresenceMonitorError.cameraUnavailable
        }

        startupTracker.finishStartupPhase()
        self.captureDriver = driver
        self.sampleDelegate = delegate
        self.observerBox = sessionObserver
        self.activeGeneration = generation
    }

    public func stop(generation: UUID) async {
        frameCoordinator.deactivateIfMatching(generation: generation)
        if desiredGeneration == generation {
            desiredGeneration = nil
            desiredRunToken = nil
        }

        var driversToStop: [CaptureSessionDriving] = []
        if let pending = pendingSetupDriver, pending.generation == generation {
            pendingSetupDriver = nil
            driversToStop.append(pending.driver)
        }
        if activeGeneration == generation {
            activeGeneration = nil
            observerBox?.invalidate()
            observerBox = nil
            sampleDelegate = nil
            if let running = captureDriver {
                captureDriver = nil
                if !driversToStop.contains(where: { $0 === running }) {
                    driversToStop.append(running)
                }
            }
        }

        for driver in driversToStop {
            await stopDriverOnQueue(driver)
        }
    }

    public func stop() async {
        desiredRunToken = nil
        desiredGeneration = nil
        await teardownSessionOnQueue(preservingToken: nil)
    }

    private func teardownSessionOnQueue(preservingToken: UUID?) async {
        activeGeneration = nil
        if preservingToken == nil {
            frameCoordinator.deactivate()
        }
        observerBox?.invalidate()
        observerBox = nil

        let pending = pendingSetupDriver
        if pending != nil && pending?.token != preservingToken {
            pendingSetupDriver = nil
        }
        let running = captureDriver
        captureDriver = nil
        sampleDelegate = nil

        if let pendingDriver = pending?.driver, pending?.token != preservingToken {
            await stopDriverOnQueue(pendingDriver)
        }
        if let running = running, running !== pending?.driver {
            await stopDriverOnQueue(running)
        }
    }

    private func stopDriverOnQueue(_ driver: CaptureSessionDriving) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            captureQueue.async {
                driver.stopRunning()
                continuation.resume()
            }
        }
    }

    private func configureAndStartDriver(
        driver: CaptureSessionDriving,
        delegate: CaptureSampleDelegate,
        generation: UUID,
        runToken: UUID,
        calibration: Calibration,
        thermal: ProcessInfo.ThermalState,
        startupTracker: StartupErrorTracker
    ) async -> Bool {
        let analysisQueue = self.analysisQueue
        let frameCoordinator = self.frameCoordinator

        return await withCheckedContinuation { continuation in
            captureQueue.async {
                do {
                    try driver.configure(delegate: delegate, analysisQueue: analysisQueue)
                    guard frameCoordinator.activateIfPending(
                        generation: generation,
                        token: runToken,
                        calibration: calibration,
                        thermalState: thermal
                    ) else {
                        continuation.resume(returning: false)
                        return
                    }
                    driver.startRunning()
                    guard driver.isRunning, !startupTracker.hasStartupError else {
                        frameCoordinator.deactivateIfMatching(token: runToken)
                        driver.stopRunning()
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: true)
                } catch {
                    frameCoordinator.deactivateIfMatching(token: runToken)
                    driver.stopRunning()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func makeSessionObserver(
        for driver: CaptureSessionDriving,
        runToken: UUID,
        startupTracker: StartupErrorTracker
    ) -> NotificationObserverBox {
        let coordinator = self.frameCoordinator
        let thermalProvider = self.thermalStateProvider
        return NotificationObserverBox(
            center: notificationCenter,
            scopedRegistrations: [
                (AVCaptureSession.wasInterruptedNotification, driver.notificationSender, {
                    startupTracker.recordStartupFailure()
                    coordinator.emitIssue(.cameraUnavailable, forToken: runToken)
                }),
                (AVCaptureSession.runtimeErrorNotification, driver.notificationSender, {
                    startupTracker.recordStartupFailure()
                    coordinator.emitIssue(.cameraUnavailable, forToken: runToken)
                }),
                (ProcessInfo.thermalStateDidChangeNotification, nil, {
                    coordinator.updateThermalState(thermalProvider())
                })
            ]
        )
    }
}
