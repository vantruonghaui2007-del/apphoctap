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
    func stop() async
}

public enum PresenceMonitorError: Error, Equatable {
    case permissionDenied
    case permissionRestricted
    case cameraUnavailable
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

    func activate(generation: UUID, calibration: Calibration, thermalState: ProcessInfo.ThermalState) {
        lock.lock()
        self.activeGeneration = generation
        self.calibration = calibration
        self.isInflight = false
        self.lastSampleMonotonic = nil
        self.sequence = 0
        self.thermalState = thermalState
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        self.activeGeneration = nil
        self.calibration = nil
        self.isInflight = false
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

    func emitIssue(_ issue: ObservationIssue) {
        lock.lock()
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
        guard let gen = activeGeneration, let cal = calibration else {
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
        let stillActive = (activeGeneration == gen)
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

@MainActor
public final class CameraPresenceMonitor: PresenceMonitoring {
    private let clock: SessionClock
    private let authorizer: CameraAuthorizing
    private let detector: PersonDetecting
    private let broadcaster = StreamBroadcaster<PresenceMonitorEvent>()
    private let frameCoordinator: FrameAnalysisCoordinator

    private let captureQueue = DispatchQueue(label: "vn.tamhoc.camera.capture", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "vn.tamhoc.camera.analysis", qos: .userInitiated)

    private var captureSession: AVCaptureSession?
    private var sampleDelegate: CaptureSampleDelegate?
    private var observerBox: NotificationObserverBox?
    private var activeGeneration: UUID?

    /// Available only for CalibrationView live preview; never shown during FocusView.
    public var previewCaptureSession: AVCaptureSession? {
        captureSession
    }

    public init(
        clock: SessionClock = SystemSessionClock(),
        authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
        detector: PersonDetecting = VisionPersonDetector()
    ) {
        self.clock = clock
        self.authorizer = authorizer
        self.detector = detector
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
        // Check authorization and request only when camera mode is actively started
        switch authorizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let granted = await authorizer.requestAccess()
            guard granted else {
                throw PresenceMonitorError.permissionDenied
            }
        case .denied:
            throw PresenceMonitorError.permissionDenied
        case .restricted:
            throw PresenceMonitorError.permissionRestricted
        }

        guard authorizer.hasFrontCamera() else {
            throw PresenceMonitorError.cameraUnavailable
        }

        // Tear down any previous session cleanly before starting new generation
        await stop()

        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .critical {
            activeGeneration = generation
            frameCoordinator.activate(generation: generation, calibration: calibration, thermalState: thermal)
            frameCoordinator.emitIssue(.thermal)
            return
        }

        let session = AVCaptureSession()
        let delegate = CaptureSampleDelegate(coordinator: frameCoordinator)

        let configured = await configureAndStartSession(
            session: session,
            delegate: delegate,
            generation: generation,
            calibration: calibration,
            thermal: thermal
        )
        guard configured else {
            throw PresenceMonitorError.cameraUnavailable
        }

        if Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                captureQueue.async {
                    if session.isRunning {
                        session.stopRunning()
                    }
                    continuation.resume()
                }
            }
            frameCoordinator.deactivate()
            throw CancellationError()
        }

        self.captureSession = session
        self.sampleDelegate = delegate
        self.activeGeneration = generation
        installObservers(for: session)
    }

    public func stop() async {
        activeGeneration = nil
        frameCoordinator.deactivate()
        observerBox?.invalidate()
        observerBox = nil

        guard let session = captureSession else {
            sampleDelegate = nil
            return
        }
        captureSession = nil
        sampleDelegate = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            captureQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureAndStartSession(
        session: AVCaptureSession,
        delegate: CaptureSampleDelegate,
        generation: UUID,
        calibration: Calibration,
        thermal: ProcessInfo.ThermalState
    ) async -> Bool {
        let analysisQueue = self.analysisQueue
        let frameCoordinator = self.frameCoordinator

        return await withCheckedContinuation { continuation in
            captureQueue.async {
                guard let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .front
                ) else {
                    continuation.resume(returning: false)
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    if session.canSetSessionPreset(.vga640x480) {
                        session.sessionPreset = .vga640x480
                    } else if session.canSetSessionPreset(.medium) {
                        session.sessionPreset = .medium
                    }

                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                    session.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(delegate, queue: analysisQueue)

                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
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

                    session.commitConfiguration()
                    frameCoordinator.activate(
                        generation: generation,
                        calibration: calibration,
                        thermalState: thermal
                    )
                    session.startRunning()
                    continuation.resume(returning: true)
                } catch {
                    if session.isRunning {
                        session.stopRunning()
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func installObservers(for session: AVCaptureSession) {
        let coordinator = self.frameCoordinator
        self.observerBox = NotificationObserverBox(
            center: .default,
            registrations: [
                (AVCaptureSession.wasInterruptedNotification, {
                    coordinator.emitIssue(.cameraUnavailable)
                }),
                (AVCaptureSession.runtimeErrorNotification, {
                    coordinator.emitIssue(.cameraUnavailable)
                }),
                (ProcessInfo.thermalStateDidChangeNotification, {
                    coordinator.updateThermalState(ProcessInfo.processInfo.thermalState)
                })
            ]
        )
    }
}
