@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Photos
import UIKit

public struct CameraFrame: @unchecked Sendable {
    public let id: Int
    public let pixelBuffer: CVPixelBuffer
    public let timestamp: CMTime
    public let capturedAt: Date

    public init(id: Int, pixelBuffer: CVPixelBuffer, timestamp: CMTime, capturedAt: Date = .now) {
        self.id = id
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.capturedAt = capturedAt
    }
}

public enum CameraAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable

    fileprivate var message: String {
        switch self {
        case .notDetermined: "Camera permission has not been requested."
        case .authorized: "Camera is authorized."
        case .denied: "Camera access was denied."
        case .restricted: "Camera access is restricted on this device."
        case .unavailable: "No camera is available on this device or simulator."
        }
    }
}

public enum CameraPosition: Equatable, Sendable {
    case front
    case back

    fileprivate var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: .front
        case .back: .back
        }
    }
}

public enum CameraFlashMode: Equatable, Sendable {
    case off
    case on
    case auto

    fileprivate var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .on: .on
        case .auto: .auto
        }
    }
}

public enum PhotoSaveResult: Equatable, Sendable {
    case saved
}

public enum CameraAvailability: Equatable, Sendable {
    case unknown
    case unavailable(String)
    case denied
    case ready
}

public enum CameraRuntimeError: LocalizedError, Equatable, Sendable {
    case authorizationDenied
    case authorizationRestricted
    case unavailable(String)
    case photoCaptureInProgress
    case photoCaptureFailed
    case flashUnavailable
    case invalidFocusPoint
    case focusUnavailable
    case photoLibraryDenied
    case photoLibraryRestricted
    case photoDataUnavailable
    case photoLibrarySaveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied: "Camera access was denied."
        case .authorizationRestricted: "Camera access is restricted on this device."
        case .unavailable(let reason): reason
        case .photoCaptureInProgress: "A photo capture is already in progress."
        case .photoCaptureFailed: "The photo could not be captured."
        case .flashUnavailable: "The selected flash mode is unavailable on this camera."
        case .invalidFocusPoint: "The focus point must be normalized to the 0...1 range."
        case .focusUnavailable: "This camera does not support focus at that point."
        case .photoLibraryDenied: "Photo Library access was denied."
        case .photoLibraryRestricted: "Photo Library access is restricted on this device."
        case .photoDataUnavailable: "The captured image could not be encoded."
        case .photoLibrarySaveFailed(let reason): reason
        }
    }
}

/// AVFoundation-backed camera runtime. Capture session/device configuration
/// is queue-confined to `sessionQueue` to avoid races with frame callbacks.
public final class CameraService: NSObject, @unchecked Sendable {
    public let session = AVCaptureSession()
    public let photoOutput = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(label: "com.photoguide.camera.session", qos: .userInitiated)
    private let stateLock = NSLock()
    private let frameLock = NSLock()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var stateAvailability: CameraAvailability = .unknown
    private var stateAuthorization: CameraAuthorizationStatus = .notDetermined
    private var statePosition: CameraPosition = .back
    private var stateFlashMode: CameraFlashMode = .off
    private var frameContinuation: AsyncStream<CameraFrame>.Continuation?
    private var frameID = 0
    private var configured = false
    private var cameraInput: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<UIImage, Error>?

    /// Compatibility state used by the existing GuidanceUI.
    public var availability: CameraAvailability {
        stateLock.withLock { stateAvailability }
    }

    /// Distinguishes permission state from a simulator/no-device fallback.
    public var authorizationStatus: CameraAuthorizationStatus {
        stateLock.withLock { stateAuthorization }
    }

    public var currentPosition: CameraPosition {
        stateLock.withLock { statePosition }
    }

    public var flashMode: CameraFlashMode {
        stateLock.withLock { stateFlashMode }
    }

    public override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        refreshAuthorizationStatus()
    }

    /// Compatibility API: request permission and prepare without throwing.
    /// Use `startAndPrepare()` when UI needs typed failures.
    public func requestAccessAndPrepare() async -> CameraAvailability {
        let authorization = await requestCameraAccessIfNeeded()
        guard authorization == .authorized else {
            let availability: CameraAvailability = authorization == .denied
                ? .denied
                : .unavailable(authorization.message)
            setState(availability: availability, authorization: authorization)
            return availability
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.configureIfNeeded()
                continuation.resume(returning: self.availability)
            }
        }
    }

    /// Requests permission, prepares the session, and starts capture while
    /// returning authorization/configuration failures to the caller.
    public func startAndPrepare() async throws {
        let availability = await requestAccessAndPrepare()
        guard availability == .ready else {
            switch authorizationStatus {
            case .denied: throw CameraRuntimeError.authorizationDenied
            case .restricted: throw CameraRuntimeError.authorizationRestricted
            default:
                if case .unavailable(let reason) = availability {
                    throw CameraRuntimeError.unavailable(reason)
                }
                throw CameraRuntimeError.unavailable("Camera is not ready.")
            }
        }
        try await startCapture()
    }

    /// Async throwing start API; it never starts an unauthorized session.
    public func startCapture() async throws {
        guard authorizationStatus == .authorized else {
            throw authorizationError()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                guard self.configured else {
                    continuation.resume(throwing: self.unavailableError())
                    return
                }
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume()
            }
        }
    }

    /// Compatibility start API used by GuidanceUI. It is intentionally
    /// non-blocking; callers needing failures should use startAndPrepare().
    public func start() {
        sessionQueue.async {
            guard self.authorizationStatus == .authorized, self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    public func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    public func frames() -> AsyncStream<CameraFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.frameLock.withLock { self.frameContinuation = continuation }
            continuation.onTermination = { @Sendable _ in
                self.frameLock.withLock { self.frameContinuation = nil }
            }
        }
    }

    public func switchCamera(to position: CameraPosition) async throws {
        guard authorizationStatus == .authorized else { throw authorizationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.switchCameraOnQueue(to: position)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func setFlashMode(_ mode: CameraFlashMode) async throws {
        guard authorizationStatus == .authorized else { throw authorizationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                guard let device = self.cameraInput?.device, device.hasFlash else {
                    if mode == .off {
                        self.setState(flashMode: .off)
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CameraRuntimeError.flashUnavailable)
                    }
                    return
                }
                guard self.photoOutput.supportedFlashModes.contains(mode.avMode) else {
                    continuation.resume(throwing: CameraRuntimeError.flashUnavailable)
                    return
                }
                self.setState(flashMode: mode)
                continuation.resume()
            }
        }
    }

    public func focus(at point: CGPoint) async throws {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
            throw CameraRuntimeError.invalidFocusPoint
        }
        guard authorizationStatus == .authorized else { throw authorizationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                guard let device = self.cameraInput?.device, device.isFocusPointOfInterestSupported else {
                    continuation.resume(throwing: CameraRuntimeError.focusUnavailable)
                    return
                }
                do {
                    try device.lockForConfiguration()
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CameraRuntimeError.unavailable("Unable to configure focus: \(error.localizedDescription)"))
                }
            }
        }
    }

    @MainActor
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    public func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.configured, self.session.isRunning else {
                    continuation.resume(throwing: self.unavailableError())
                    return
                }
                guard self.photoContinuation == nil else {
                    continuation.resume(throwing: CameraRuntimeError.photoCaptureInProgress)
                    return
                }
                let settings = AVCapturePhotoSettings()
                let requestedFlash = self.flashMode.avMode
                if self.photoOutput.supportedFlashModes.contains(requestedFlash) {
                    settings.flashMode = requestedFlash
                } else if requestedFlash != .off {
                    continuation.resume(throwing: CameraRuntimeError.flashUnavailable)
                    return
                }
                self.photoContinuation = continuation
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    public func savePhotoToLibrary(_ image: UIImage) async -> Result<PhotoSaveResult, CameraRuntimeError> {
        guard image.jpegData(compressionQuality: 0.95) != nil else { return .failure(.photoDataUnavailable) }
        let authorization = await requestPhotoLibraryAccessIfNeeded()
        switch authorization {
        case .authorized, .limited: break
        case .denied: return .failure(.photoLibraryDenied)
        case .restricted: return .failure(.photoLibraryRestricted)
        case .notDetermined: return .failure(.photoLibrarySaveFailed("Photo Library authorization did not complete."))
        @unknown default: return .failure(.photoLibrarySaveFailed("Unknown Photo Library authorization state."))
        }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return .failure(.photoDataUnavailable) }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: .success(.saved))
                } else {
                    continuation.resume(returning: .failure(.photoLibrarySaveFailed(error?.localizedDescription ?? "Unable to save the photo to the Photo Library.")))
                }
            })
        }
    }

    public func captureAndSavePhoto() async throws -> PhotoSaveResult {
        let image = try await capturePhoto()
        let result = await savePhotoToLibrary(image)
        switch result {
        case .success(let saved): return saved
        case .failure(let error): throw error
        }
    }

    private func refreshAuthorizationStatus() {
        let raw = AVCaptureDevice.authorizationStatus(for: .video)
        let hasCamera = Self.hasCameraDevice
        let status: CameraAuthorizationStatus
        switch raw {
        case .notDetermined: status = hasCamera ? .notDetermined : .unavailable
        case .authorized: status = hasCamera ? .authorized : .unavailable
        case .denied: status = .denied
        case .restricted: status = .restricted
        @unknown default: status = .unavailable
        }
        setState(authorization: status)
    }

    private func requestCameraAccessIfNeeded() async -> CameraAuthorizationStatus {
        refreshAuthorizationStatus()
        let current = authorizationStatus
        if current == .unavailable || current == .denied || current == .restricted || current == .authorized { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        refreshAuthorizationStatus()
        if granted, authorizationStatus == .notDetermined { setState(authorization: .authorized) }
        return granted ? .authorized : .denied
    }

    private func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in continuation.resume(returning: status) }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        guard authorizationStatus == .authorized else {
            setState(availability: .unavailable("Camera permission is not available."))
            return
        }
        guard let device = Self.defaultDevice(for: .back) else {
            setState(availability: .unavailable("No camera is available on this device or simulator."), authorization: .unavailable)
            return
        }
        session.beginConfiguration()
        var addedInput: AVCaptureDeviceInput?
        var addedVideo = false
        defer { session.commitConfiguration() }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraRuntimeError.unavailable("Camera input is unavailable.") }
            session.addInput(input)
            addedInput = input
            guard session.canAddOutput(videoOutput) else { throw CameraRuntimeError.unavailable("Video output is unavailable.") }
            session.addOutput(videoOutput)
            addedVideo = true
            guard session.canAddOutput(photoOutput) else { throw CameraRuntimeError.unavailable("Photo output is unavailable.") }
            session.addOutput(photoOutput)
            session.sessionPreset = .high
            configureConnectionsOnQueue(for: .back)
            cameraInput = input
            configured = true
            setState(availability: .ready, position: .back)
        } catch {
            if addedVideo { session.removeOutput(videoOutput) }
            if let addedInput { session.removeInput(addedInput) }
            cameraInput = nil
            configured = false
            setState(availability: .unavailable(error.localizedDescription))
        }
    }

    private func switchCameraOnQueue(to position: CameraPosition) throws {
        guard configured, let oldInput = cameraInput else { throw unavailableError() }
        guard position != currentPosition else { return }
        guard let device = Self.defaultDevice(for: position) else {
            throw CameraRuntimeError.unavailable("The requested camera is not available on this device or simulator.")
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.removeInput(oldInput)
        guard session.canAddInput(newInput) else {
            if session.canAddInput(oldInput) { session.addInput(oldInput) }
            session.commitConfiguration()
            throw CameraRuntimeError.unavailable("The requested camera input is unavailable.")
        }
        session.addInput(newInput)
        configureConnectionsOnQueue(for: position)
        session.commitConfiguration()
        cameraInput = newInput
        setState(position: position)
    }

    /// Keep both the preview frames and still photos in portrait orientation.
    /// Front-camera mirroring is explicit so the frame stream matches the
    /// familiar selfie preview while the rear camera remains unmirrored.
    private func configureConnectionsOnQueue(for position: CameraPosition) {
        for output in [videoOutput, photoOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = position == .front
            }
        }
    }

    private func unavailableError() -> CameraRuntimeError {
        if case .unavailable(let reason) = availability { return .unavailable(reason) }
        return .unavailable("Camera session is not running.")
    }

    private func authorizationError() -> CameraRuntimeError {
        switch authorizationStatus {
        case .denied: return .authorizationDenied
        case .restricted: return .authorizationRestricted
        case .unavailable: return .unavailable("No camera is available on this device or simulator.")
        case .notDetermined: return .unavailable("Camera permission has not been requested.")
        case .authorized: return .unavailable("Camera is not ready.")
        }
    }

    private static var hasCameraDevice: Bool { defaultDevice(for: .back) != nil || defaultDevice(for: .front) != nil }

    private static func defaultDevice(for position: CameraPosition) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition)
    }

    private func setState(
        availability: CameraAvailability? = nil,
        authorization: CameraAuthorizationStatus? = nil,
        position: CameraPosition? = nil,
        flashMode: CameraFlashMode? = nil
    ) {
        stateLock.withLock {
            if let availability { stateAvailability = availability }
            if let authorization { stateAuthorization = authorization }
            if let position { statePosition = position }
            if let flashMode { stateFlashMode = flashMode }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer else { return }
        frameID += 1
        _ = frameLock.withLock { frameContinuation?.yield(CameraFrame(id: frameID, pixelBuffer: buffer, timestamp: sampleBuffer.presentationTimeStamp)) }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async {
            guard let continuation = self.photoContinuation else { return }
            self.photoContinuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
                continuation.resume(returning: image)
            } else {
                continuation.resume(throwing: CameraRuntimeError.photoCaptureFailed)
            }
        }
    }
}

@MainActor
public final class CameraPreviewView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    public init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

private extension NSLock {
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
