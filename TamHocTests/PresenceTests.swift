import XCTest
import CoreVideo
import ImageIO
import StudyCore
@testable import TamHoc

final class PresenceTests: XCTestCase {
    private func makeSolidBGRA(width: Int = 32, height: Int = 32, brightness: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * bytesPerRow + x * 4
                    ptr[idx] = brightness
                    ptr[idx + 1] = brightness
                    ptr[idx + 2] = brightness
                    ptr[idx + 3] = 255
                }
            }
        }
        return pb
    }

    func testROIMirrorAndAspectFillMapping() throws {
        // 1. Center ROI matches identically regardless of mirror
        let centerBounds = CGRect(x: 0, y: 0, width: 300, height: 600)
        let imageSize = CGSize(width: 300, height: 600)
        let centerRect = CGRect(x: 75, y: 150, width: 150, height: 300)

        let unmirroredCenter = try PreviewGeometry.visionROI(
            fromPreviewRect: centerRect,
            previewBounds: centerBounds,
            imageSize: imageSize,
            mirrored: false
        )
        let mirroredCenter = try PreviewGeometry.visionROI(
            fromPreviewRect: centerRect,
            previewBounds: centerBounds,
            imageSize: imageSize,
            mirrored: true
        )
        XCTAssertEqual(unmirroredCenter.roiX, 0.25, accuracy: 0.001)
        XCTAssertEqual(unmirroredCenter.roiY, 0.25, accuracy: 0.001)
        XCTAssertEqual(unmirroredCenter.roiWidth, 0.50, accuracy: 0.001)
        XCTAssertEqual(unmirroredCenter.roiHeight, 0.50, accuracy: 0.001)
        XCTAssertEqual(mirroredCenter.roiX, 0.25, accuracy: 0.001)

        // 2. Left preview box flips horizontally when mirrored (front camera)
        let topLeftRect = CGRect(x: 0, y: 0, width: 100, height: 200)
        let unmirroredLeft = try PreviewGeometry.visionROI(
            fromPreviewRect: topLeftRect,
            previewBounds: centerBounds,
            imageSize: imageSize,
            mirrored: false
        )
        let mirroredLeft = try PreviewGeometry.visionROI(
            fromPreviewRect: topLeftRect,
            previewBounds: centerBounds,
            imageSize: imageSize,
            mirrored: true
        )
        XCTAssertEqual(unmirroredLeft.roiX, 0.0, accuracy: 0.001)
        XCTAssertEqual(unmirroredLeft.roiY, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(mirroredLeft.roiX, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(mirroredLeft.roiY, 2.0 / 3.0, accuracy: 0.001)

        // 3. Aspect-fill vertical crop is accounted for (tall 1:2 image in 1:1 preview)
        let squareBounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        let fullSquare = try PreviewGeometry.visionROI(
            fromPreviewRect: squareBounds,
            previewBounds: squareBounds,
            imageSize: CGSize(width: 300, height: 600),
            mirrored: true
        )
        XCTAssertEqual(fullSquare.roiX, 0.0, accuracy: 0.001)
        XCTAssertEqual(fullSquare.roiWidth, 1.0, accuracy: 0.001)
        XCTAssertEqual(fullSquare.roiY, 0.25, accuracy: 0.001)
        XCTAssertEqual(fullSquare.roiHeight, 0.50, accuracy: 0.001)

        // 4. Completely out-of-bounds and NaN rects are rejected
        XCTAssertThrowsError(
            try PreviewGeometry.visionROI(
                fromPreviewRect: CGRect(x: -100, y: 0, width: 50, height: 100),
                previewBounds: centerBounds,
                imageSize: imageSize,
                mirrored: true
            )
        )
        XCTAssertThrowsError(
            try PreviewGeometry.visionROI(
                fromPreviewRect: CGRect(x: .nan, y: 0, width: 100, height: 100),
                previewBounds: centerBounds,
                imageSize: imageSize,
                mirrored: true
            )
        )
    }

    func testSingleInflightFrameDropsOverlappingFrames() throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let semaphore = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)

        struct BlockingDetector: PersonDetecting {
            let entered: DispatchSemaphore
            let release: DispatchSemaphore
            func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, calibration: Calibration) throws -> PresenceValue {
                entered.signal()
                _ = release.wait(timeout: .now() + 2.0)
                return .present
            }
        }

        let lock = NSLock()
        var emitted: [PresenceMonitorEvent] = []
        let coordinator = FrameAnalysisCoordinator(
            clock: clock,
            detector: BlockingDetector(entered: entered, release: semaphore)
        ) { event in
            lock.lock()
            emitted.append(event)
            lock.unlock()
        }

        let gen = UUID()
        coordinator.activate(generation: gen, calibration: .defaultCentered, thermalState: .nominal)
        let frame = try makeSolidBGRA(brightness: 180)

        let group = DispatchGroup()
        var firstAccepted = false
        group.enter()
        DispatchQueue.global().async {
            firstAccepted = coordinator.processFrame(frame)
            group.leave()
        }
        defer { semaphore.signal() }

        XCTAssertEqual(entered.wait(timeout: .now() + 2.0), .success)

        // While first frame is inflight, a later frame must be dropped without blocking or invoking detector
        clock.advance(by: 1.0)
        XCTAssertFalse(coordinator.processFrame(frame))

        semaphore.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 2.0), .success)
        XCTAssertTrue(firstAccepted)

        lock.lock()
        let count = emitted.count
        lock.unlock()
        XCTAssertEqual(count, 1)
    }

    func testSampleThrottleNormalAndSeriousThermal() throws {
        struct InstantDetector: PersonDetecting {
            func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, calibration: Calibration) throws -> PresenceValue {
                .present
            }
        }

        let clock = FakeClock(monotonicSeconds: 0)
        var emitted: [PresenceMonitorEvent] = []
        let coordinator = FrameAnalysisCoordinator(
            clock: clock,
            detector: InstantDetector()
        ) { event in
            emitted.append(event)
        }

        coordinator.activate(generation: UUID(), calibration: .defaultCentered, thermalState: .nominal)
        let frame = try makeSolidBGRA(brightness: 180)

        // t = 0.0 -> accepted
        XCTAssertTrue(coordinator.processFrame(frame))

        // t = 0.2 (< 0.5s) -> dropped
        clock.set(monotonicSeconds: 0.2)
        XCTAssertFalse(coordinator.processFrame(frame))

        // t = 0.5 (>= 0.5s) -> accepted
        clock.set(monotonicSeconds: 0.5)
        XCTAssertTrue(coordinator.processFrame(frame))

        // Thermal serious throttles to 1 Hz (1.0s interval)
        coordinator.updateThermalState(.serious)
        clock.set(monotonicSeconds: 1.1) // 0.6s since 0.5 -> allowed at 2Hz, dropped at 1Hz
        XCTAssertFalse(coordinator.processFrame(frame))

        clock.set(monotonicSeconds: 1.5) // 1.0s since 0.5 -> accepted
        XCTAssertTrue(coordinator.processFrame(frame))

        XCTAssertEqual(emitted.count, 3)
    }

    @MainActor
    func testPermissionDeniedDoesNotStartCapture() async {
        let deniedAuth = FakeCameraAuthorizer(status: .denied, frontCameraAvailable: true)
        let monitor = CameraPresenceMonitor(
            clock: FakeClock(),
            authorizer: deniedAuth,
            detector: VisionPersonDetector()
        )

        do {
            try await monitor.start(calibration: .defaultCentered, generation: UUID())
            XCTFail("Expected permissionDenied")
        } catch let error as PresenceMonitorError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(monitor.previewCaptureSession)
        XCTAssertEqual(deniedAuth.requestAccessCallCount, 0)

        let restrictedAuth = FakeCameraAuthorizer(status: .restricted, frontCameraAvailable: true)
        let restrictedMonitor = CameraPresenceMonitor(
            clock: FakeClock(),
            authorizer: restrictedAuth,
            detector: VisionPersonDetector()
        )
        do {
            try await restrictedMonitor.start(calibration: .defaultCentered, generation: UUID())
            XCTFail("Expected permissionRestricted")
        } catch let error as PresenceMonitorError {
            XCTAssertEqual(error, .permissionRestricted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(restrictedMonitor.previewCaptureSession)
    }

    func testStoppedGenerationNeverPublishesNewSamples() throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        struct SlowDetector: PersonDetecting {
            let entered: DispatchSemaphore
            let release: DispatchSemaphore
            func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, calibration: Calibration) throws -> PresenceValue {
                entered.signal()
                _ = release.wait(timeout: .now() + 2.0)
                return .present
            }
        }

        let lock = NSLock()
        var emitted: [PresenceMonitorEvent] = []
        let coordinator = FrameAnalysisCoordinator(
            clock: clock,
            detector: SlowDetector(entered: entered, release: release)
        ) { event in
            lock.lock()
            emitted.append(event)
            lock.unlock()
        }

        let oldGen = UUID()
        coordinator.activate(generation: oldGen, calibration: .defaultCentered, thermalState: .nominal)
        let frame = try makeSolidBGRA(brightness: 200)

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            _ = coordinator.processFrame(frame)
            group.leave()
        }
        defer { release.signal() }

        XCTAssertEqual(entered.wait(timeout: .now() + 2.0), .success)
        // Stop / deactivate while detector is still running for oldGen
        coordinator.deactivate()
        release.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 2.0), .success)

        lock.lock()
        let count = emitted.count
        lock.unlock()
        XCTAssertEqual(count, 0, "Stopped generation must never publish samples after stop")
    }

    func testLowLightAndDetectorFailureProduceUnknown() throws {
        let darkFrame = try makeSolidBGRA(brightness: 5) // ~0.02 < 0.08
        let detector = VisionPersonDetector()
        let lowLightResult = try detector.detect(
            pixelBuffer: darkFrame,
            orientation: .up,
            calibration: .defaultCentered
        )
        XCTAssertEqual(lowLightResult, .unknown(.lowLight))

        struct FailingDetector: PersonDetecting {
            enum Boom: Error { case fail }
            func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, calibration: Calibration) throws -> PresenceValue {
                throw Boom.fail
            }
        }

        let clock = FakeClock(monotonicSeconds: 1.0)
        var captured: [PresenceMonitorEvent] = []
        let coordinator = FrameAnalysisCoordinator(clock: clock, detector: FailingDetector()) { event in
            captured.append(event)
        }
        coordinator.activate(generation: UUID(), calibration: .defaultCentered, thermalState: .nominal)
        let brightFrame = try makeSolidBGRA(brightness: 180)
        XCTAssertTrue(coordinator.processFrame(brightFrame))
        XCTAssertEqual(captured.first?.sample.value, .unknown(.detectorFailure))
    }

    func testThermalCriticalEmitsThermalAndBlocksSubsequentFrames() throws {
        let clock = FakeClock(monotonicSeconds: 0)
        var emitted: [PresenceMonitorEvent] = []
        let coordinator = FrameAnalysisCoordinator(clock: clock, detector: VisionPersonDetector()) { event in
            emitted.append(event)
        }

        coordinator.activate(generation: UUID(), calibration: .defaultCentered, thermalState: .nominal)
        coordinator.updateThermalState(.critical)

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.sample.value, .unknown(.thermal))

        clock.advance(by: 2.0)
        let frame = try makeSolidBGRA(brightness: 180)
        XCTAssertFalse(coordinator.processFrame(frame))
    }

    func testPlanarVideoRangeLuminanceGate() throws {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            32,
            32,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let height = CVPixelBufferGetHeightOfPlane(pb, 0)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<bytesPerRow {
                    ptr[y * bytesPerRow + x] = 16 // video-range black
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        let result = try VisionPersonDetector().detect(
            pixelBuffer: pb,
            orientation: .up,
            calibration: .defaultCentered
        )
        XCTAssertEqual(result, .unknown(.lowLight))
    }
}
