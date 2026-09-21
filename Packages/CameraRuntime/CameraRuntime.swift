@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Photos
import QuartzCore
import UIKit

public struct CameraExposureTelemetry: Equatable, Sendable {
  public let iso: Float
  public let exposureDurationSeconds: Double
  public let exposureBias: Float

  public init(iso: Float, exposureDurationSeconds: Double, exposureBias: Float) {
    self.iso = iso
    self.exposureDurationSeconds = exposureDurationSeconds
    self.exposureBias = exposureBias
  }
}

public struct CameraFrame: @unchecked Sendable {
  public let id: Int
  public let pixelBuffer: CVPixelBuffer
  public let timestamp: CMTime
  public let capturedAt: Date
  public let position: CameraPosition
  public let zoomFactor: Double
  public let exposure: CameraExposureTelemetry?

  public init(
    id: Int,
    pixelBuffer: CVPixelBuffer,
    timestamp: CMTime,
    capturedAt: Date = .now,
    position: CameraPosition,
    zoomFactor: Double,
    exposure: CameraExposureTelemetry? = nil
  ) {
    self.id = id
    self.pixelBuffer = pixelBuffer
    self.timestamp = timestamp
    self.capturedAt = capturedAt
    self.position = position
    self.zoomFactor = zoomFactor
    self.exposure = exposure
  }
}

public enum CameraAuthorizationStatus: Equatable, Sendable {
  case notDetermined, authorized, denied, restricted, unavailable
}

public enum CameraPosition: Equatable, Sendable { case front, back }
public enum CameraFlashMode: Equatable, Sendable { case off, on, auto }
public enum PhotoSaveResult: Equatable, Sendable { case saved }
public enum CameraAvailability: Equatable, Sendable {
  case unknown
  case unavailable(String)
  case denied, ready
}

public struct CameraZoomOption: Equatable, Sendable, Hashable {
  /// Value shown to the user (for example 0.5×, 1×, 2×).
  public let displayFactor: Double
  /// AVFoundation `videoZoomFactor` value used by the active capture device.
  public let deviceFactor: Double

  public init(displayFactor: Double, deviceFactor: Double) {
    self.displayFactor = displayFactor
    self.deviceFactor = deviceFactor
  }
}

public struct CameraCapabilities: Equatable, Sendable {
  public let zoomOptions: [CameraZoomOption]
  public let hasFlash: Bool
  public let supportsTapFocus: Bool
  public let exposureBiasRange: ClosedRange<Float>?

  public init(
    zoomOptions: [CameraZoomOption] = [.init(displayFactor: 1, deviceFactor: 1)],
    hasFlash: Bool = false,
    supportsTapFocus: Bool = false,
    exposureBiasRange: ClosedRange<Float>? = nil
  ) {
    self.zoomOptions = zoomOptions
    self.hasFlash = hasFlash
    self.supportsTapFocus = supportsTapFocus
    self.exposureBiasRange = exposureBiasRange
  }

  public var displayZoomFactors: [Double] { zoomOptions.map(\.displayFactor) }

  public var coreCapabilityIDs: Set<String> {
    var result = Set<String>()
    if zoomOptions.contains(where: { abs($0.displayFactor - 2) < 0.16 }) {
      result.insert("zoom.2x")
    }
    if zoomOptions.count > 1 {
      result.insert("zoom.in")
      result.insert("zoom.out")
    }
    return result
  }
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
  case zoomUnavailable
  case exposureBiasUnavailable
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
    case .invalidFocusPoint: "The focus point must be normalized to 0...1."
    case .focusUnavailable: "This camera does not support point focus."
    case .zoomUnavailable: "The requested zoom factor is unavailable."
    case .exposureBiasUnavailable: "Exposure compensation is unavailable on this camera."
    case .photoLibraryDenied: "Photo Library access was denied."
    case .photoLibraryRestricted: "Photo Library access is restricted."
    case .photoDataUnavailable: "The captured image could not be encoded."
    case .photoLibrarySaveFailed(let reason): reason
    }
  }
}

public final class CameraService: NSObject, @unchecked Sendable {
  public let session = AVCaptureSession()
  public let photoOutput = AVCapturePhotoOutput()

  private let sessionQueue = DispatchQueue(
    label: "com.photoguide.camera.session", qos: .userInitiated)
  private let stateLock = NSLock()
  private let frameLock = NSLock()
  private let videoOutput = AVCaptureVideoDataOutput()

  private var stateAvailability: CameraAvailability = .unknown
  private var stateAuthorization: CameraAuthorizationStatus = .notDetermined
  private var statePosition: CameraPosition = .back
  private var stateFlashMode: CameraFlashMode = .off
  private var stateCapabilities = CameraCapabilities()
  private var stateZoomFactor: Double = 1
  private var stateExposureBias: Float = 0
  private var frameContinuation: AsyncStream<CameraFrame>.Continuation?
  private var frameID = 0
  private var configured = false
  private var cameraInput: AVCaptureDeviceInput?
  private var photoContinuation: CheckedContinuation<UIImage, Error>?

  public var availability: CameraAvailability { stateLock.withLock { stateAvailability } }
  public var authorizationStatus: CameraAuthorizationStatus {
    stateLock.withLock { stateAuthorization }
  }
  public var currentPosition: CameraPosition { stateLock.withLock { statePosition } }
  public var flashMode: CameraFlashMode { stateLock.withLock { stateFlashMode } }
  public var capabilities: CameraCapabilities { stateLock.withLock { stateCapabilities } }
  public var zoomFactor: Double { stateLock.withLock { stateZoomFactor } }
  public var exposureBias: Float { stateLock.withLock { stateExposureBias } }

  public override init() {
    super.init()
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    refreshAuthorizationStatus()
  }

  public func requestAccessAndPrepare() async -> CameraAvailability {
    let authorization = await requestCameraAccessIfNeeded()
    guard authorization == .authorized else {
      let availability: CameraAvailability =
        authorization == .denied ? .denied : .unavailable("Camera is not available.")
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

  public func startAndPrepare() async throws {
    let availability = await requestAccessAndPrepare()
    guard availability == .ready else { throw authorizationOrAvailabilityError() }
    try await startCapture()
  }

  public func startCapture() async throws {
    guard authorizationStatus == .authorized else { throw authorizationOrAvailabilityError() }
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

  public func start() {
    sessionQueue.async {
      guard self.authorizationStatus == .authorized, self.configured, !self.session.isRunning else {
        return
      }
      self.session.startRunning()
    }
  }

  public func stop() {
    sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
  }

  public func frames() -> AsyncStream<CameraFrame> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      frameLock.withLock { frameContinuation = continuation }
      continuation.onTermination = { @Sendable _ in
        self.frameLock.withLock { self.frameContinuation = nil }
      }
    }
  }

  public func switchCamera(to position: CameraPosition) async throws {
    guard authorizationStatus == .authorized else { throw authorizationOrAvailabilityError() }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      sessionQueue.async {
        do {
          try self.switchCameraOnQueue(to: position)
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  /// Sets the zoom using a display factor that matches camera UI conventions.
  /// AVFoundation virtual cameras can use a different internal videoZoomFactor;
  /// `displayVideoZoomFactorMultiplier` provides the mapping.
  public func setZoomFactor(_ requestedDisplayFactor: Double, animated: Bool = true) async throws {
    guard requestedDisplayFactor.isFinite else { throw CameraRuntimeError.zoomUnavailable }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      sessionQueue.async {
        guard let device = self.cameraInput?.device else {
          continuation.resume(throwing: self.unavailableError())
          return
        }
        let multiplier = max(Double(device.displayVideoZoomFactorMultiplier), 0.000_001)
        let requestedDeviceFactor = requestedDisplayFactor / multiplier
        let target = min(
          max(CGFloat(requestedDeviceFactor), device.minAvailableVideoZoomFactor),
          device.maxAvailableVideoZoomFactor)
        let targetDisplay = Double(target) * multiplier
        guard abs(targetDisplay - requestedDisplayFactor) < 0.16 else {
          continuation.resume(throwing: CameraRuntimeError.zoomUnavailable)
          return
        }
        do {
          try device.lockForConfiguration()
          if animated {
            device.ramp(toVideoZoomFactor: target, withRate: 6)
          } else {
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = target
          }
          device.unlockForConfiguration()
          self.setState(zoomFactor: targetDisplay)
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  public func setExposureBias(_ requestedBias: Float) async throws {
    guard requestedBias.isFinite else { throw CameraRuntimeError.exposureBiasUnavailable }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      sessionQueue.async {
        guard let device = self.cameraInput?.device else {
          continuation.resume(throwing: self.unavailableError())
          return
        }
        let minimum = device.minExposureTargetBias
        let maximum = device.maxExposureTargetBias
        guard maximum - minimum > 0.01 else {
          continuation.resume(throwing: CameraRuntimeError.exposureBiasUnavailable)
          return
        }
        let target = min(max(requestedBias, minimum), maximum)
        do {
          try device.lockForConfiguration()
          device.setExposureTargetBias(target, completionHandler: nil)
          device.unlockForConfiguration()
          self.setState(exposureBias: target)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func setFlashMode(_ mode: CameraFlashMode) async throws {
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
        self.setState(flashMode: mode)
        continuation.resume()
      }
    }
  }

  public func focus(atDevicePoint point: CGPoint) async throws {
    guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y)
    else { throw CameraRuntimeError.invalidFocusPoint }
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
          }
          if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            if device.isExposureModeSupported(.continuousAutoExposure) {
              device.exposureMode = .continuousAutoExposure
            }
          }
          device.unlockForConfiguration()
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
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
        settings.photoQualityPrioritization = .quality
        let requested = self.flashMode.avMode
        if self.photoOutput.supportedFlashModes.contains(requested) {
          settings.flashMode = requested
        }
        self.photoContinuation = continuation
        self.photoOutput.capturePhoto(with: settings, delegate: self)
      }
    }
  }

  public func savePhotoToLibrary(_ image: UIImage) async -> Result<
    PhotoSaveResult, CameraRuntimeError
  > {
    guard let data = image.jpegData(compressionQuality: 0.96) else {
      return .failure(.photoDataUnavailable)
    }
    let authorization = await requestPhotoLibraryAccessIfNeeded()
    switch authorization {
    case .authorized, .limited: break
    case .denied: return .failure(.photoLibraryDenied)
    case .restricted: return .failure(.photoLibraryRestricted)
    default:
      return .failure(.photoLibrarySaveFailed("Photo Library authorization did not complete."))
    }
    return await withCheckedContinuation { continuation in
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
      }) { success, error in
        continuation.resume(
          returning: success
            ? .success(.saved)
            : .failure(
              .photoLibrarySaveFailed(error?.localizedDescription ?? "Unable to save photo.")))
      }
    }
  }

  private func configureIfNeeded() {
    guard !configured else { return }
    guard let device = Self.bestDevice(for: .back) else {
      setState(availability: .unavailable("No camera is available."), authorization: .unavailable)
      return
    }
    session.beginConfiguration()
    session.sessionPreset = .photo
    defer { session.commitConfiguration() }
    do {
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input), session.canAddOutput(videoOutput),
        session.canAddOutput(photoOutput)
      else { throw CameraRuntimeError.unavailable("Camera input/output is unavailable.") }
      session.addInput(input)
      session.addOutput(videoOutput)
      session.addOutput(photoOutput)
      photoOutput.maxPhotoQualityPrioritization = .quality
      cameraInput = input
      configured = true
      configureConnectionsOnQueue(for: .back)
      refreshCapabilities(device)
      setComfortableDefaultZoomOnQueue(device)
      refreshCapabilities(device)
      setState(availability: .ready, position: .back)
    } catch { setState(availability: .unavailable(error.localizedDescription)) }
  }

  private func switchCameraOnQueue(to position: CameraPosition) throws {
    guard configured, let oldInput = cameraInput else { throw unavailableError() }
    guard position != currentPosition else { return }
    guard let device = Self.bestDevice(for: position) else {
      throw CameraRuntimeError.unavailable("Requested camera is unavailable.")
    }
    let newInput = try AVCaptureDeviceInput(device: device)
    session.beginConfiguration()
    session.removeInput(oldInput)
    guard session.canAddInput(newInput) else {
      if session.canAddInput(oldInput) { session.addInput(oldInput) }
      session.commitConfiguration()
      throw CameraRuntimeError.unavailable("Requested camera input is unavailable.")
    }
    session.addInput(newInput)
    configureConnectionsOnQueue(for: position)
    session.commitConfiguration()
    cameraInput = newInput
    refreshCapabilities(device)
    setComfortableDefaultZoomOnQueue(device)
    refreshCapabilities(device)
    setState(position: position, flashMode: .off)
  }

  private func configureConnectionsOnQueue(for position: CameraPosition) {
    for output in [videoOutput, photoOutput] {
      guard let connection = output.connection(with: .video) else { continue }
      if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
      if connection.isVideoMirroringSupported { connection.isVideoMirrored = position == .front }
    }
  }

  private func refreshCapabilities(_ device: AVCaptureDevice) {
    let multiplier = max(Double(device.displayVideoZoomFactorMultiplier), 0.000_001)
    let minDevice = Double(device.minAvailableVideoZoomFactor)
    let maxDevice = Double(device.maxAvailableVideoZoomFactor)
    let minDisplay = minDevice * multiplier
    let maxDisplay = maxDevice * multiplier

    var displayCandidates = [0.5, 1.0, 2.0, 3.0, 5.0].filter {
      $0 >= minDisplay - 0.06 && $0 <= maxDisplay + 0.06
    }
    displayCandidates += device.virtualDeviceSwitchOverVideoZoomFactors.map {
      Double(truncating: $0) * multiplier
    }
    let currentDisplay = Double(device.videoZoomFactor) * multiplier
    displayCandidates.append(currentDisplay)
    if 1 >= minDisplay - 0.06, 1 <= maxDisplay + 0.06 { displayCandidates.append(1) }

    let sorted = displayCandidates.sorted()
    var unique = [Double]()
    for value in sorted where value > 0 {
      if unique.last.map({ abs($0 - value) > 0.10 }) ?? true { unique.append(value) }
    }
    if unique.isEmpty { unique = [currentDisplay] }

    let options = unique.map { display in
      CameraZoomOption(
        displayFactor: display,
        deviceFactor: min(max(display / multiplier, minDevice), maxDevice))
    }
    let biasRange: ClosedRange<Float>? =
      device.maxExposureTargetBias - device.minExposureTargetBias > 0.01
      ? device.minExposureTargetBias...device.maxExposureTargetBias
      : nil
    setState(
      capabilities: CameraCapabilities(
        zoomOptions: options, hasFlash: device.hasFlash,
        supportsTapFocus: device.isFocusPointOfInterestSupported,
        exposureBiasRange: biasRange),
      zoomFactor: currentDisplay,
      exposureBias: device.exposureTargetBias)
  }

  private func setComfortableDefaultZoomOnQueue(_ device: AVCaptureDevice) {
    let multiplier = max(Double(device.displayVideoZoomFactorMultiplier), 0.000_001)
    let desiredDisplay = 1.0
    let desiredDevice = desiredDisplay / multiplier
    guard desiredDevice >= Double(device.minAvailableVideoZoomFactor) - 0.01,
      desiredDevice <= Double(device.maxAvailableVideoZoomFactor) + 0.01
    else {
      setState(zoomFactor: Double(device.videoZoomFactor) * multiplier)
      return
    }
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = CGFloat(desiredDevice)
      device.unlockForConfiguration()
      setState(zoomFactor: desiredDisplay)
    } catch {
      setState(zoomFactor: Double(device.videoZoomFactor) * multiplier)
    }
  }

  private func refreshAuthorizationStatus() {
    let raw = AVCaptureDevice.authorizationStatus(for: .video)
    let hasCamera = Self.bestDevice(for: .back) != nil || Self.bestDevice(for: .front) != nil
    let status: CameraAuthorizationStatus =
      switch raw {
      case .notDetermined: hasCamera ? .notDetermined : .unavailable
      case .authorized: hasCamera ? .authorized : .unavailable
      case .denied: .denied
      case .restricted: .restricted
      @unknown default: .unavailable
      }
    setState(authorization: status)
  }

  private func requestCameraAccessIfNeeded() async -> CameraAuthorizationStatus {
    refreshAuthorizationStatus()
    let current = authorizationStatus
    guard current == .notDetermined else { return current }
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    refreshAuthorizationStatus()
    return granted ? .authorized : .denied
  }

  private func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
    let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard current == .notDetermined else { return current }
    return await withCheckedContinuation { continuation in
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
    }
  }

  private func unavailableError() -> CameraRuntimeError {
    if case .unavailable(let reason) = availability { return .unavailable(reason) }
    return .unavailable("Camera session is not running.")
  }

  private func authorizationOrAvailabilityError() -> CameraRuntimeError {
    switch authorizationStatus {
    case .denied: .authorizationDenied
    case .restricted: .authorizationRestricted
    default: unavailableError()
    }
  }

  private static func bestDevice(for position: CameraPosition) -> AVCaptureDevice? {
    let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
    let types: [AVCaptureDevice.DeviceType] =
      position == .back
      ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
      : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: types, mediaType: .video, position: avPosition
    ).devices.first
  }

  private func setState(
    availability: CameraAvailability? = nil,
    authorization: CameraAuthorizationStatus? = nil,
    position: CameraPosition? = nil,
    flashMode: CameraFlashMode? = nil,
    capabilities: CameraCapabilities? = nil,
    zoomFactor: Double? = nil,
    exposureBias: Float? = nil
  ) {
    stateLock.withLock {
      if let availability { stateAvailability = availability }
      if let authorization { stateAuthorization = authorization }
      if let position { statePosition = position }
      if let flashMode { stateFlashMode = flashMode }
      if let capabilities { stateCapabilities = capabilities }
      if let zoomFactor { stateZoomFactor = zoomFactor }
      if let exposureBias { stateExposureBias = exposureBias }
    }
  }
}

extension CameraFlashMode {
  fileprivate var avMode: AVCaptureDevice.FlashMode {
    switch self {
    case .off: .off
    case .on: .on
    case .auto: .auto
    }
  }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let buffer = sampleBuffer.imageBuffer else { return }
    frameID += 1
    let position = currentPosition
    let device = cameraInput?.device
    let zoom: Double
    if let device {
      let multiplier = max(Double(device.displayVideoZoomFactorMultiplier), 0.000_001)
      zoom = Double(device.videoZoomFactor) * multiplier
      setState(zoomFactor: zoom)
    } else {
      zoom = zoomFactor
    }
    let exposure = device.map { device in
      CameraExposureTelemetry(
        iso: device.iso,
        exposureDurationSeconds: CMTimeGetSeconds(device.exposureDuration),
        exposureBias: device.exposureTargetBias)
    }
    if let exposure { setState(exposureBias: exposure.exposureBias) }
    frameLock.withLock {
      _ = frameContinuation?.yield(
        CameraFrame(
          id: frameID, pixelBuffer: buffer, timestamp: sampleBuffer.presentationTimeStamp,
          position: position, zoomFactor: zoom, exposure: exposure))
    }
  }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
  public func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
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

public struct CameraTapPoint: Equatable, Sendable {
  public let imageNormalized: CGPoint
  public let deviceFocus: CGPoint
}

public enum CameraGuideCue: Equatable, Sendable {
  case none
  case left
  case right
  case up
  case down
}

public enum CameraZoomGesturePhase: Equatable, Sendable {
  case began
  case changed
  case ended
  case cancelled
}

public struct CameraZoomGesture: Equatable, Sendable {
  public let scale: Double
  public let phase: CameraZoomGesturePhase

  public init(scale: Double, phase: CameraZoomGesturePhase) {
    self.scale = scale
    self.phase = phase
  }
}

@MainActor
public final class CameraPreviewView: UIView {
  public let previewLayer: AVCaptureVideoPreviewLayer
  private let subjectLayer = CAShapeLayer()
  private let faceLayer = CAShapeLayer()
  private let anchorLayer = CAShapeLayer()
  private let markerLayer = CAShapeLayer()
  private let cueLayer = CAShapeLayer()
  private let focusLayer = CAShapeLayer()

  public var onTap: ((CameraTapPoint) -> Void)?
  public var onZoomGesture: ((CameraZoomGesture) -> Void)?
  private var lastPinchEmissionTime: CFTimeInterval = 0
  private var lastGuideCue: CameraGuideCue = .none
  private var lastSelectedImagePoint: CGPoint?
  private var lastSubjectVisible = false
  private var lastFaceVisible = false
  private var lastAnchorVisible = false

  public init(session: AVCaptureSession) {
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    super.init(frame: .zero)
    previewLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(previewLayer)
    [subjectLayer, faceLayer, anchorLayer, markerLayer, cueLayer, focusLayer].forEach { layer.addSublayer($0) }
    let accent = UIColor(red: 0.66, green: 0.95, blue: 0.86, alpha: 1)
    subjectLayer.fillColor = UIColor.clear.cgColor
    subjectLayer.strokeColor = accent.withAlphaComponent(0.74).cgColor
    subjectLayer.lineWidth = 1.2
    subjectLayer.lineCap = .round
    subjectLayer.lineJoin = .round
    faceLayer.fillColor = UIColor.clear.cgColor
    faceLayer.strokeColor = UIColor(red: 0.67, green: 0.78, blue: 0.96, alpha: 0.92).cgColor
    faceLayer.lineWidth = 1.35
    faceLayer.lineCap = .round
    faceLayer.lineJoin = .round
    anchorLayer.fillColor = UIColor.clear.cgColor
    anchorLayer.strokeColor = accent.withAlphaComponent(0.82).cgColor
    anchorLayer.lineWidth = 1.2
    anchorLayer.lineDashPattern = [7, 6]
    markerLayer.fillColor = UIColor.clear.cgColor
    markerLayer.strokeColor = accent.withAlphaComponent(0.92).cgColor
    markerLayer.lineWidth = 1.2
    cueLayer.fillColor = UIColor.clear.cgColor
    cueLayer.strokeColor = accent.withAlphaComponent(0.88).cgColor
    cueLayer.lineWidth = 1.8
    cueLayer.lineCap = .round
    cueLayer.lineJoin = .round
    focusLayer.fillColor = UIColor.clear.cgColor
    focusLayer.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
    focusLayer.lineWidth = 1.2
    focusLayer.opacity = 0
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    addGestureRecognizer(tap)
    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    addGestureRecognizer(pinch)
    backgroundColor = .black
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  public override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer.frame = bounds
  }

  public func updateOverlays(
    subject: CGRect?,
    face: CGRect? = nil,
    anchor: CGRect?,
    selectedImagePoint: CGPoint?,
    cue: CameraGuideCue = .none
  ) {
    let subjectLayerRect = subject.map { layerRect(forNormalizedImageRect: $0) }
    let faceLayerRect = face.map { layerRect(forNormalizedImageRect: $0) }
    let anchorLayerRect = anchor.map { layerRect(forNormalizedImageRect: $0) }
    let subjectAcquired = !lastSubjectVisible && subjectLayerRect != nil
    let faceAcquired = !lastFaceVisible && faceLayerRect != nil
    let anchorAcquired = !lastAnchorVisible && anchorLayerRect != nil
    let cueChanged = cue != lastGuideCue
    let markerChanged = !samePoint(selectedImagePoint, lastSelectedImagePoint)

    // Tracking overlays can update several times per second. Disable implicit Core Animation
    // interpolation so the visual guides stay attached to the live subject instead of lagging.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    subjectLayer.path = subjectLayerRect.map { cornerGuidePath(in: $0).cgPath }
    faceLayer.path = faceLayerRect.map { faceGuidePath(in: $0).cgPath }
    faceLayer.opacity = faceLayerRect == nil ? 0 : 1
    anchorLayer.path = anchorLayerRect.map {
      UIBezierPath(roundedRect: $0, cornerRadius: 14).cgPath
    }
    if let point = selectedImagePoint {
      let rect = layerRect(
        forNormalizedImageRect: CGRect(
          x: point.x - 0.002, y: point.y - 0.002, width: 0.004, height: 0.004))
      markerLayer.path =
        UIBezierPath(ovalIn: CGRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12))
        .cgPath
      markerLayer.opacity = 1
    } else {
      markerLayer.path = nil
      markerLayer.opacity = 0
    }
    cueLayer.path = subjectLayerRect.flatMap { guideCuePath(cue, around: $0)?.cgPath }
    cueLayer.opacity = cue == .none ? 0 : 1
    CATransaction.commit()

    if markerChanged, selectedImagePoint != nil { animateMarkerSelection() }
    if cueChanged { animateCueChange(to: cue) }
    if subjectAcquired { animateAcquisition(subjectLayer, key: "subjectAcquired") }
    if faceAcquired { animateAcquisition(faceLayer, key: "faceAcquired") }
    if anchorAcquired { animateAcquisition(anchorLayer, key: "anchorAcquired") }

    lastGuideCue = cue
    lastSelectedImagePoint = selectedImagePoint
    lastSubjectVisible = subjectLayerRect != nil
    lastFaceVisible = faceLayerRect != nil
    lastAnchorVisible = anchorLayerRect != nil
  }

  private func samePoint(_ lhs: CGPoint?, _ rhs: CGPoint?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (let a?, let b?): abs(a.x - b.x) < 0.0005 && abs(a.y - b.y) < 0.0005
    default: false
    }
  }

  private func animateAcquisition(_ target: CAShapeLayer, key: String) {
    target.removeAnimation(forKey: key)
    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0.15
    opacity.toValue = 1.0
    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 1.04
    scale.toValue = 1.0
    let group = CAAnimationGroup()
    group.animations = [opacity, scale]
    group.duration = 0.34
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    target.add(group, forKey: key)
  }

  private func animateMarkerSelection() {
    markerLayer.removeAnimation(forKey: "markerSelection")
    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 0.72
    scale.toValue = 1.0
    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0.25
    opacity.toValue = 1.0
    let group = CAAnimationGroup()
    group.animations = [scale, opacity]
    group.duration = 0.32
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    markerLayer.add(group, forKey: "markerSelection")
  }

  private func animateCueChange(to cue: CameraGuideCue) {
    cueLayer.removeAnimation(forKey: "cueArrival")
    guard cue != .none else { return }

    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0
    opacity.toValue = 1

    let translation = CABasicAnimation(keyPath: "transform")
    let offset: (CGFloat, CGFloat)
    switch cue {
    case .left: offset = (5, 0)
    case .right: offset = (-5, 0)
    case .up: offset = (0, 5)
    case .down: offset = (0, -5)
    case .none: return
    }
    translation.fromValue = NSValue(
      caTransform3D: CATransform3DMakeTranslation(offset.0, offset.1, 0))
    translation.toValue = NSValue(caTransform3D: CATransform3DIdentity)

    let group = CAAnimationGroup()
    group.animations = [opacity, translation]
    group.duration = 0.28
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    cueLayer.add(group, forKey: "cueArrival")
  }

  private func guideCuePath(_ cue: CameraGuideCue, around rect: CGRect) -> UIBezierPath? {
    guard cue != .none else { return nil }
    let path = UIBezierPath()
    let length: CGFloat = 38
    let head: CGFloat = 9
    let margin: CGFloat = 18
    let start: CGPoint
    let end: CGPoint

    switch cue {
    case .left:
      start = CGPoint(x: rect.minX - margin + length, y: rect.midY)
      end = CGPoint(x: rect.minX - margin, y: rect.midY)
    case .right:
      start = CGPoint(x: rect.maxX + margin - length, y: rect.midY)
      end = CGPoint(x: rect.maxX + margin, y: rect.midY)
    case .up:
      start = CGPoint(x: rect.midX, y: rect.minY - margin + length)
      end = CGPoint(x: rect.midX, y: rect.minY - margin)
    case .down:
      start = CGPoint(x: rect.midX, y: rect.maxY + margin - length)
      end = CGPoint(x: rect.midX, y: rect.maxY + margin)
    case .none:
      return nil
    }

    path.move(to: start)
    path.addLine(to: end)
    let angle = atan2(end.y - start.y, end.x - start.x)
    for offset in [CGFloat.pi * 0.80, -CGFloat.pi * 0.80] {
      path.move(to: end)
      path.addLine(
        to: CGPoint(
          x: end.x + cos(angle + offset) * head,
          y: end.y + sin(angle + offset) * head))
    }
    return path
  }

  private func faceGuidePath(in rect: CGRect) -> UIBezierPath {
    let inset = rect.insetBy(dx: -5, dy: -5)
    let radius = max(10, min(inset.width, inset.height) * 0.24)
    let path = UIBezierPath(roundedRect: inset, cornerRadius: radius)
    let cross: CGFloat = 4.5
    path.move(to: CGPoint(x: inset.midX - cross, y: inset.midY))
    path.addLine(to: CGPoint(x: inset.midX + cross, y: inset.midY))
    path.move(to: CGPoint(x: inset.midX, y: inset.midY - cross))
    path.addLine(to: CGPoint(x: inset.midX, y: inset.midY + cross))
    return path
  }

  private func cornerGuidePath(in rect: CGRect) -> UIBezierPath {
    let insetRect = rect.insetBy(dx: -4, dy: -4)
    let length = min(max(min(insetRect.width, insetRect.height) * 0.12, 12), 24)
    let radius: CGFloat = 10
    let path = UIBezierPath()

    path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY + length))
    path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: insetRect.minX + radius, y: insetRect.minY),
      controlPoint: CGPoint(x: insetRect.minX, y: insetRect.minY))
    path.addLine(to: CGPoint(x: insetRect.minX + length, y: insetRect.minY))

    path.move(to: CGPoint(x: insetRect.maxX - length, y: insetRect.minY))
    path.addLine(to: CGPoint(x: insetRect.maxX - radius, y: insetRect.minY))
    path.addQuadCurve(
      to: CGPoint(x: insetRect.maxX, y: insetRect.minY + radius),
      controlPoint: CGPoint(x: insetRect.maxX, y: insetRect.minY))
    path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + length))

    path.move(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - length))
    path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: insetRect.maxX - radius, y: insetRect.maxY),
      controlPoint: CGPoint(x: insetRect.maxX, y: insetRect.maxY))
    path.addLine(to: CGPoint(x: insetRect.maxX - length, y: insetRect.maxY))

    path.move(to: CGPoint(x: insetRect.minX + length, y: insetRect.maxY))
    path.addLine(to: CGPoint(x: insetRect.minX + radius, y: insetRect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: insetRect.minX, y: insetRect.maxY - radius),
      controlPoint: CGPoint(x: insetRect.minX, y: insetRect.maxY))
    path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - length))

    return path
  }

  private func layerRect(forNormalizedImageRect rect: CGRect) -> CGRect {
    previewLayer.layerRectConverted(fromMetadataOutputRect: rect)
  }

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    let p = recognizer.location(in: self)
    showFocusReticle(at: p)
    let focus = previewLayer.captureDevicePointConverted(fromLayerPoint: p)
    let tiny = CGRect(x: p.x - 0.5, y: p.y - 0.5, width: 1, height: 1)
    let metadata = previewLayer.metadataOutputRectConverted(fromLayerRect: tiny)
    let imagePoint = CGPoint(x: metadata.midX, y: metadata.midY)
    onTap?(CameraTapPoint(imageNormalized: imagePoint, deviceFocus: focus))
  }

  @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
    let phase: CameraZoomGesturePhase
    switch recognizer.state {
    case .began:
      phase = .began
    case .changed:
      phase = .changed
    case .ended:
      phase = .ended
    case .cancelled, .failed:
      phase = .cancelled
    default:
      return
    }

    if phase == .changed {
      let now = CACurrentMediaTime()
      guard now - lastPinchEmissionTime >= 1.0 / 30.0 else { return }
      lastPinchEmissionTime = now
    }
    onZoomGesture?(CameraZoomGesture(scale: Double(recognizer.scale), phase: phase))
  }

  private func showFocusReticle(at point: CGPoint) {
    let size: CGFloat = 54
    let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
    let tick: CGFloat = 6
    path.move(to: CGPoint(x: rect.midX, y: rect.minY - tick / 2))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + tick))
    path.move(to: CGPoint(x: rect.midX, y: rect.maxY - tick))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + tick / 2))
    path.move(to: CGPoint(x: rect.minX - tick / 2, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.minX + tick, y: rect.midY))
    path.move(to: CGPoint(x: rect.maxX - tick, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX + tick / 2, y: rect.midY))
    focusLayer.path = path.cgPath
    focusLayer.removeAllAnimations()
    focusLayer.opacity = 1

    let arrivalScale = CABasicAnimation(keyPath: "transform.scale")
    arrivalScale.fromValue = 1.12
    arrivalScale.toValue = 1.0
    let arrivalOpacity = CABasicAnimation(keyPath: "opacity")
    arrivalOpacity.fromValue = 0.15
    arrivalOpacity.toValue = 1.0
    let arrival = CAAnimationGroup()
    arrival.animations = [arrivalScale, arrivalOpacity]
    arrival.duration = 0.20
    arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
    focusLayer.add(arrival, forKey: "focusArrival")

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.beginTime = CACurrentMediaTime() + 0.62
    fade.duration = 0.34
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    focusLayer.add(fade, forKey: "focusFade")
  }
}

extension NSLock {
  @inline(__always) fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
