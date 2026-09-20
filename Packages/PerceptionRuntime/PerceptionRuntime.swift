import CoreGraphics
import CoreVideo
import Foundation
import GuidanceCore
import ImageIO
@preconcurrency import Vision

public struct NormalizedPoint: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public init(x: Double, y: Double) {
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
  }
}

public struct NormalizedRect: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
    self.width = min(max(width, 0), 1 - self.x)
    self.height = min(max(height, 0), 1 - self.y)
  }

  public var midX: Double { x + width / 2 }
  public var midY: Double { y + height / 2 }
  public var area: Double { width * height }
  public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

  public func contains(_ point: NormalizedPoint) -> Bool {
    point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
  }
}

public struct PersonObservation: Equatable, Sendable {
  public let present: Bool
  public let visible: Bool
  public let scale: Double
  public let x: Double
  public let y: Double
  public let confidence: Double
  public let bounds: NormalizedRect?
  public let bodyOrientation: Int?

  public init(
    present: Bool, visible: Bool, scale: Double, x: Double, y: Double, confidence: Double,
    bounds: NormalizedRect? = nil, bodyOrientation: Int? = nil
  ) {
    self.present = present
    self.visible = visible
    self.scale = scale
    self.x = x
    self.y = y
    self.confidence = confidence
    self.bounds = bounds
    self.bodyOrientation = bodyOrientation
  }
}

public struct AnchorObservation: Equatable, Sendable {
  public let bounds: NormalizedRect
  public let confidence: Double
  public init(bounds: NormalizedRect, confidence: Double) {
    self.bounds = bounds
    self.confidence = min(max(confidence, 0), 1)
  }
}

public struct CompositionObservation: Equatable, Sendable {
  public let relativeScale: Int
  public let visualBalance: Int
  public let confidence: Double
  public init(relativeScale: Int, visualBalance: Int, confidence: Double) {
    self.relativeScale = relativeScale
    self.visualBalance = visualBalance
    self.confidence = min(max(confidence, 0), 1)
  }
}

public struct SceneObservation: Equatable, Sendable {
  public let person: PersonObservation
  public let anchor: AnchorObservation?
  public let composition: CompositionObservation?
  public let bindingVersion: Int
  public let conditions: SceneConditionProfile

  public init(
    person: PersonObservation, anchor: AnchorObservation?, composition: CompositionObservation?,
    bindingVersion: Int, conditions: SceneConditionProfile = SceneConditionProfile()
  ) {
    self.person = person
    self.anchor = anchor
    self.composition = composition
    self.bindingVersion = bindingVersion
    self.conditions = conditions
  }
}

public enum CompositionHeuristics {
  public static func evaluate(person: PersonObservation, anchor: AnchorObservation)
    -> CompositionObservation?
  {
    guard person.present, let personBounds = person.bounds, personBounds.area > 0.005,
      anchor.bounds.area > 0.001
    else { return nil }

    let areaRatio = anchor.bounds.area / personBounds.area
    let relativeScale: Int =
      switch areaRatio {
      case 0.45...2.20: 0
      case 0.22..<0.45: -1
      case ..<0.22: -2
      case 2.20...4.50: 1
      default: 2
      }

    let personWeight = max(0.08, sqrt(personBounds.area))
    let anchorWeight = max(0.06, sqrt(anchor.bounds.area))
    let visualCenter =
      (personBounds.midX * personWeight + anchor.bounds.midX * anchorWeight)
      / (personWeight + anchorWeight)
    let visualBalance: Int =
      switch visualCenter {
      case 0.44...0.56: 0
      case 0.34..<0.44: -1
      case ..<0.34: -2
      case 0.56...0.66: 1
      default: 2
      }

    return .init(
      relativeScale: relativeScale, visualBalance: visualBalance,
      confidence: min(person.confidence, anchor.confidence) * 0.88)
  }
}

/// On-device perception. The primary subject is sticky for short occlusions; when
/// it must be rebound, `bindingVersion` changes so delayed semantic results are invalidated.
public final class LocalPersonEvaluator: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.photoguide.perception.vision", qos: .userInitiated)
  private let minimumInterval: TimeInterval
  private let anchorInterval: TimeInterval
  private var lastEvaluation = Date.distantPast
  private var lastAnchorEvaluation = Date.distantPast
  private var trackedPersonBounds: NormalizedRect?
  private var lostTrackingFrames = 0
  private var bindingVersion = 0
  private var cachedAnchorPoint: NormalizedPoint?
  private var cachedAnchor: AnchorObservation?
  private var smoothedBounds: NormalizedRect?
  private var lastConditionBounds: NormalizedRect?
  private var lastConditionTime: Date?

  public init(maximumFramesPerSecond: Double = 8, anchorFramesPerSecond: Double = 2) {
    minimumInterval = 1 / max(1, maximumFramesPerSecond)
    anchorInterval = 1 / max(0.5, anchorFramesPerSecond)
  }

  public func evaluateScene(
    _ frame: CVPixelBuffer,
    orientation: CGImagePropertyOrientation = .up,
    anchorPoint: NormalizedPoint? = nil,
    frameID: Int? = nil
  ) async -> SceneObservation? {
    let box = PixelBufferBox(frame)
    return await withCheckedContinuation { continuation in
      queue.async {
        let now = Date()
        guard now.timeIntervalSince(self.lastEvaluation) >= self.minimumInterval else {
          continuation.resume(returning: nil)
          return
        }
        self.lastEvaluation = now
        continuation.resume(
          returning: self.performVision(
            box.value, orientation: orientation, anchorPoint: anchorPoint, now: now,
            frameID: frameID))
      }
    }
  }

  public func resetTracking() {
    queue.async {
      self.trackedPersonBounds = nil
      self.smoothedBounds = nil
      self.lostTrackingFrames = 0
      self.bindingVersion += 1
      self.cachedAnchor = nil
      self.lastConditionBounds = nil
      self.lastConditionTime = nil
    }
  }

  private func performVision(
    _ frame: CVPixelBuffer, orientation: CGImagePropertyOrientation, anchorPoint: NormalizedPoint?,
    now: Date, frameID: Int?
  ) -> SceneObservation {
    let human = VNDetectHumanRectanglesRequest()
    let pose = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(
      cvPixelBuffer: frame, orientation: orientation, options: [:])
    do { try handler.perform([human, pose]) } catch {
      let conditions = FrameConditionAnalyzer.analyze(
        frame: frame, person: nil, humanCount: 0, cameraMotion: 0, frameID: frameID)
      return .init(
        person: Self.missingPerson, anchor: cachedAnchor, composition: nil,
        bindingVersion: bindingVersion, conditions: conditions)
    }

    guard let selected = selectPrimaryPerson(from: human.results ?? []) else {
      let conditions = FrameConditionAnalyzer.analyze(
        frame: frame, person: nil, humanCount: human.results?.count ?? 0,
        cameraMotion: 0, frameID: frameID)
      return .init(
        person: Self.missingPerson, anchor: cachedAnchor, composition: nil,
        bindingVersion: bindingVersion, conditions: conditions)
    }

    let rawBounds = Self.topLeftRect(selected.boundingBox)
    let bounds = smooth(rawBounds)
    let margin = 0.012
    let visible =
      bounds.x >= margin && bounds.y >= margin && bounds.x + bounds.width <= 1 - margin
      && bounds.y + bounds.height <= 1 - margin
    let orientationValue = Self.bodyOrientation(pose.results?.first, personBounds: bounds)
    let person = PersonObservation(
      present: true,
      visible: visible,
      scale: bounds.area,
      x: bounds.midX,
      y: bounds.midY,
      confidence: Double(selected.confidence),
      bounds: bounds,
      bodyOrientation: orientationValue
    )
    let cameraMotion = conditionMotion(for: bounds, now: now)
    let conditions = FrameConditionAnalyzer.analyze(
      frame: frame,
      person: person,
      humanCount: human.results?.count ?? 1,
      cameraMotion: cameraMotion,
      frameID: frameID
    )

    guard let anchorPoint else {
      cachedAnchorPoint = nil
      cachedAnchor = nil
      return .init(
        person: person, anchor: nil, composition: nil, bindingVersion: bindingVersion,
        conditions: conditions)
    }

    let changed = cachedAnchorPoint != anchorPoint
    if changed || cachedAnchor == nil
      || now.timeIntervalSince(lastAnchorEvaluation) >= anchorInterval
    {
      cachedAnchorPoint = anchorPoint
      cachedAnchor = resolveAnchor(in: handler, around: anchorPoint, excluding: bounds)
      lastAnchorEvaluation = now
    }
    let composition = cachedAnchor.flatMap {
      CompositionHeuristics.evaluate(person: person, anchor: $0)
    }
    return .init(
      person: person, anchor: cachedAnchor, composition: composition,
      bindingVersion: bindingVersion,
      conditions: conditions
    )
  }

  private func conditionMotion(for bounds: NormalizedRect, now: Date) -> Double {
    defer {
      lastConditionBounds = bounds
      lastConditionTime = now
    }
    guard let previous = lastConditionBounds, let lastTime = lastConditionTime else { return 0 }
    let dt = max(1.0 / 60.0, now.timeIntervalSince(lastTime))
    let centerDelta = hypot(bounds.midX - previous.midX, bounds.midY - previous.midY)
    let scaleDelta = abs(bounds.area - previous.area)
    let velocity = (centerDelta + scaleDelta * 0.6) / dt
    return min(max(velocity / 2.2, 0), 1)
  }

  private func selectPrimaryPerson(from results: [VNHumanObservation]) -> VNHumanObservation? {
    guard !results.isEmpty else {
      lostTrackingFrames += 1
      if lostTrackingFrames >= 8 {
        trackedPersonBounds = nil
        smoothedBounds = nil
      }
      return nil
    }
    let candidates = results.map { ($0, Self.topLeftRect($0.boundingBox)) }
    if let trackedPersonBounds {
      if let nearest = candidates.min(by: {
        Self.centerDistance($0.1, trackedPersonBounds)
          < Self.centerDistance($1.1, trackedPersonBounds)
      }),
        Self.centerDistance(nearest.1, trackedPersonBounds) <= 0.25
      {
        self.trackedPersonBounds = nearest.1
        lostTrackingFrames = 0
        return nearest.0
      }
      lostTrackingFrames += 1
      if lostTrackingFrames < 8 { return nil }
    }

    let selected = candidates.max {
      Double($0.0.confidence) + $0.1.area * 0.8 < Double($1.0.confidence) + $1.1.area * 0.8
    }
    if selected != nil { bindingVersion += 1 }
    trackedPersonBounds = selected?.1
    smoothedBounds = selected?.1
    lostTrackingFrames = 0
    return selected?.0
  }

  private func smooth(_ rect: NormalizedRect) -> NormalizedRect {
    guard let previous = smoothedBounds else {
      smoothedBounds = rect
      return rect
    }
    let alpha = 0.38
    let result = NormalizedRect(
      x: previous.x * (1 - alpha) + rect.x * alpha,
      y: previous.y * (1 - alpha) + rect.y * alpha,
      width: previous.width * (1 - alpha) + rect.width * alpha,
      height: previous.height * (1 - alpha) + rect.height * alpha
    )
    smoothedBounds = result
    trackedPersonBounds = result
    return result
  }

  private func resolveAnchor(
    in handler: VNImageRequestHandler, around point: NormalizedPoint,
    excluding personBounds: NormalizedRect
  ) -> AnchorObservation? {
    let request = VNGenerateAttentionBasedSaliencyImageRequest()
    try? handler.perform([request])
    let boxes = (request.results?.first?.salientObjects ?? [])
      .map { (Self.topLeftRect($0.boundingBox), Double($0.confidence)) }
      .filter { !$0.0.contains(.init(x: personBounds.midX, y: personBounds.midY)) }
    let selected =
      boxes.first(where: { $0.0.contains(point) })
      ?? boxes.min(by: { Self.distance($0.0, point) < Self.distance($1.0, point) })
    if let selected, Self.distance(selected.0, point) < 0.26 {
      return .init(bounds: selected.0, confidence: max(0.58, selected.1))
    }
    // Manual anchor fallback is intentionally low-confidence: it keeps the
    // relation observable without claiming a semantic segmentation result.
    return .init(
      bounds: .init(x: point.x - 0.085, y: point.y - 0.085, width: 0.17, height: 0.17),
      confidence: 0.55)
  }

  private static let missingPerson = PersonObservation(
    present: false, visible: false, scale: 0, x: 0.5, y: 0.5, confidence: 0.94)
  private static func topLeftRect(_ rect: CGRect) -> NormalizedRect {
    .init(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
  }
  private static func distance(_ rect: NormalizedRect, _ point: NormalizedPoint) -> Double {
    hypot(rect.midX - point.x, rect.midY - point.y)
  }
  private static func centerDistance(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
    hypot(a.midX - b.midX, a.midY - b.midY)
  }

  private static func bodyOrientation(
    _ pose: VNHumanBodyPoseObservation?, personBounds: NormalizedRect
  ) -> Int? {
    guard let pose,
      let left = try? pose.recognizedPoint(.leftShoulder),
      let right = try? pose.recognizedPoint(.rightShoulder),
      left.confidence >= 0.30,
      right.confidence >= 0.30
    else { return nil }
    let shoulderWidth = abs(left.location.x - right.location.x)
    let ratio = shoulderWidth / max(personBounds.width, 0.01)
    return switch ratio {
    case 0.34...: 0
    case 0.21..<0.34: 1
    default: 2
    }
  }
}

public enum FrameConditionAnalyzer {
  /// Cheap BGRA sampler intended for runtime scheduling, not image-quality scoring.
  /// It estimates sensing difficulty only; no condition is treated as a user fault.
  public static func analyze(
    frame: CVPixelBuffer,
    person: PersonObservation?,
    humanCount: Int,
    cameraMotion: Double,
    frameID: Int? = nil
  ) -> SceneConditionProfile {
    var severities = [SceneCondition: Double]()

    if let stats = luminanceStats(frame) {
      let lowLight = max(
        max(0, (0.30 - stats.mean) / 0.30),
        max(0, (stats.darkFraction - 0.45) / 0.55)
      )
      severities[.lowLight] = clamp(lowLight)

      let backlitContrast = max(0, stats.outerMean - stats.centerMean)
      let backlit = clamp((backlitContrast - 0.10) / 0.32) * clamp((stats.outerMean - 0.45) / 0.45)
      severities[.backlit] = backlit

      let motion = clamp(cameraMotion)
      let lowDetail = clamp((0.055 - stats.edgeEnergy) / 0.055)
      severities[.motionBlur] = clamp(lowDetail * motion)
      severities[.cameraMotion] = motion
    } else {
      severities[.cameraMotion] = clamp(cameraMotion)
    }

    if let person {
      severities[.subjectSmall] = clamp((0.055 - person.scale) / 0.055)
      let poseUnavailablePenalty = person.bodyOrientation == nil ? 0.45 : 0
      let clippedPenalty = person.visible ? 0 : 0.65
      severities[.subjectOccluded] = max(poseUnavailablePenalty, clippedPenalty)
    }

    if humanCount > 1 {
      severities[.multiPersonCrowding] = clamp(Double(humanCount - 1) / 3.0)
    }

    return SceneConditionProfile(
      severities: severities,
      confidence: 0.78,
      frameID: frameID
    )
  }

  private struct LuminanceStats {
    let mean: Double
    let darkFraction: Double
    let centerMean: Double
    let outerMean: Double
    let edgeEnergy: Double
  }

  private static func luminanceStats(_ buffer: CVPixelBuffer) -> LuminanceStats? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard width > 2, height > 2 else { return nil }

    let xStep = max(1, width / 40)
    let yStep = max(1, height / 56)
    let ptr = base.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0
    var count = 0
    var dark = 0
    var centerSum = 0.0
    var centerCount = 0
    var outerSum = 0.0
    var outerCount = 0
    var edgeSum = 0.0
    var edgeCount = 0

    func luma(_ x: Int, _ y: Int) -> Double {
      let offset = y * bytesPerRow + x * 4
      let b = Double(ptr[offset]) / 255.0
      let g = Double(ptr[offset + 1]) / 255.0
      let r = Double(ptr[offset + 2]) / 255.0
      return 0.0722 * b + 0.7152 * g + 0.2126 * r
    }

    var y = 0
    while y < height {
      var x = 0
      while x < width {
        let value = luma(x, y)
        sum += value
        count += 1
        if value < 0.16 { dark += 1 }
        let nx = Double(x) / Double(max(1, width - 1))
        let ny = Double(y) / Double(max(1, height - 1))
        let inCenter = nx >= 0.25 && nx <= 0.75 && ny >= 0.20 && ny <= 0.80
        if inCenter {
          centerSum += value
          centerCount += 1
        } else {
          outerSum += value
          outerCount += 1
        }
        if x + xStep < width {
          edgeSum += abs(value - luma(x + xStep, y))
          edgeCount += 1
        }
        x += xStep
      }
      y += yStep
    }

    guard count > 0 else { return nil }
    return LuminanceStats(
      mean: sum / Double(count),
      darkFraction: Double(dark) / Double(count),
      centerMean: centerCount > 0 ? centerSum / Double(centerCount) : sum / Double(count),
      outerMean: outerCount > 0 ? outerSum / Double(outerCount) : sum / Double(count),
      edgeEnergy: edgeCount > 0 ? edgeSum / Double(edgeCount) : 0
    )
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

private final class PixelBufferBox: @unchecked Sendable {
  let value: CVPixelBuffer
  init(_ value: CVPixelBuffer) { self.value = value }
}

// MARK: - Semantic / DJev boundary

public struct SemanticSlot: Codable, Equatable, Sendable {
  public let goalID: GoalID
  public let dimension: DimensionID
  public let binding: Binding
  public let target: GoalTarget
  public let name: String
  public let description: String

  public init(
    goalID: GoalID,
    dimension: DimensionID,
    binding: Binding,
    target: GoalTarget,
    name: String,
    description: String
  ) {
    self.goalID = goalID
    self.dimension = dimension
    self.binding = binding
    self.target = target
    self.name = name
    self.description = description
  }
}

public struct SemanticEvaluationRequest: Sendable {
  public let frameID: Int
  public let sceneRevision: Int
  public let bindingVersion: Int
  public let slots: [SemanticSlot]
  public let imagePayload: Data

  public init(
    frameID: Int, sceneRevision: Int, bindingVersion: Int, slots: [SemanticSlot], imagePayload: Data
  ) {
    self.frameID = frameID
    self.sceneRevision = sceneRevision
    self.bindingVersion = bindingVersion
    self.slots = slots
    self.imagePayload = imagePayload
  }
}

public struct SemanticEvaluationResponse: Sendable {
  public let frameID: Int
  public let sceneRevision: Int
  public let bindingVersion: Int
  public let observations: [Observation]
}

public protocol SemanticEvaluating: Sendable {
  func evaluate(_ request: SemanticEvaluationRequest) async throws -> SemanticEvaluationResponse
}

public struct FreshSemanticResultGate: Sendable {
  public var maxFrameDelta = 6
  public init() {}
  public func accepts(
    _ response: SemanticEvaluationResponse, currentFrameID: Int, currentBindingVersion: Int,
    currentSceneRevision: Int
  ) -> Bool {
    response.frameID <= currentFrameID
      && currentFrameID - response.frameID <= maxFrameDelta
      && response.bindingVersion == currentBindingVersion
      && response.sceneRevision == currentSceneRevision
  }
}

/// Generic HTTP adapter for the future DJev service. The app can ship with this
/// unconfigured; local CV remains functional and no mock semantic result is emitted.
public struct HTTPDJevEvaluator: SemanticEvaluating {
  public struct Configuration: Sendable {
    public let endpoint: URL
    public let bearerToken: String?
    public init(endpoint: URL, bearerToken: String? = nil) {
      self.endpoint = endpoint
      self.bearerToken = bearerToken
    }
  }

  public let configuration: Configuration
  public init(configuration: Configuration) { self.configuration = configuration }

  public func evaluate(_ request: SemanticEvaluationRequest) async throws
    -> SemanticEvaluationResponse
  {
    var urlRequest = URLRequest(url: configuration.endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 2.5
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = configuration.bearerToken {
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let payload = WireRequest(
      frameID: request.frameID,
      sceneRevision: request.sceneRevision,
      bindingVersion: request.bindingVersion,
      slots: request.slots.map {
        .init(
          goalID: $0.goalID.rawValue,
          dimension: $0.dimension.rawValue,
          binding: WireBinding($0.binding),
          target: WireTarget($0.target),
          name: $0.name,
          description: $0.description
        )
      },
      imageBase64: request.imagePayload.base64EncodedString()
    )
    urlRequest.httpBody = try JSONEncoder().encode(payload)
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw DJevError.invalidResponse
    }
    let decoded = try JSONDecoder().decode(WireResponse.self, from: data)
    let observations = decoded.observations.compactMap { item -> Observation? in
      guard let binding = item.binding.coreBinding else { return nil }
      let value: DimensionValue =
        switch item.valueType {
        case "ordinal": .ordinal(item.ordinalValue ?? 0)
        case "boolean": .boolean(item.boolValue ?? false)
        case "continuous": .continuous(item.numberValue ?? 0)
        default: .categorical(item.stringValue ?? "")
        }
      return Observation(
        dimension: DimensionID(item.dimension),
        binding: binding,
        value: value,
        confidence: item.confidence,
        evaluator: EvaluatorID("djev.semantic"),
        distribution: item.distribution,
        frameID: decoded.frameID,
        bindingVersion: decoded.bindingVersion,
        sceneRevision: decoded.sceneRevision
      )
    }
    return .init(
      frameID: decoded.frameID, sceneRevision: decoded.sceneRevision,
      bindingVersion: decoded.bindingVersion, observations: observations)
  }
}

public enum DJevError: Error { case invalidResponse }

private struct WireRequest: Codable {
  let frameID: Int
  let sceneRevision: Int
  let bindingVersion: Int
  let slots: [WireSlot]
  let imageBase64: String
}
private struct WireSlot: Codable {
  let goalID: String
  let dimension: String
  let binding: WireBinding
  let target: WireTarget
  let name: String
  let description: String
}

private struct WireTarget: Codable {
  let type: String
  let idealLower: Double?
  let idealUpper: Double?
  let acceptableLower: Double?
  let acceptableUpper: Double?
  let ordinal: Int?
  let bool: Bool?
  let categorical: String?

  init(_ target: GoalTarget) {
    switch target {
    case .band(let band):
      type = "RANGE"
      idealLower = band.ideal.lowerBound
      idealUpper = band.ideal.upperBound
      acceptableLower = band.acceptable.lowerBound
      acceptableUpper = band.acceptable.upperBound
      ordinal = nil
      bool = nil
      categorical = nil
    case .ordinal(let value):
      type = "ORDINAL"
      idealLower = nil
      idealUpper = nil
      acceptableLower = nil
      acceptableUpper = nil
      ordinal = value
      bool = nil
      categorical = nil
    case .boolean(let value):
      type = "BOOLEAN"
      idealLower = nil
      idealUpper = nil
      acceptableLower = nil
      acceptableUpper = nil
      ordinal = nil
      bool = value
      categorical = nil
    case .categorical(let value):
      type = "CATEGORICAL"
      idealLower = nil
      idealUpper = nil
      acceptableLower = nil
      acceptableUpper = nil
      ordinal = nil
      bool = nil
      categorical = value
    }
  }
}
private struct WireBinding: Codable {
  let scope: String
  let id: String?
  init(_ binding: Binding) {
    switch binding {
    case .node(let id):
      scope = "NODE"
      self.id = id.rawValue
    case .relation(let id):
      scope = "RELATION"
      self.id = id.rawValue
    case .frame:
      scope = "FRAME"
      id = nil
    case .capture:
      scope = "CAPTURE"
      id = nil
    }
  }
  var coreBinding: Binding? {
    switch scope.uppercased() {
    case "NODE": id.map { .node(NodeID($0)) }
    case "RELATION": id.map { .relation(RelationID($0)) }
    case "FRAME": .frame
    case "CAPTURE": .capture
    default: nil
    }
  }
}
private struct WireResponse: Codable {
  let frameID: Int
  let sceneRevision: Int
  let bindingVersion: Int
  let observations: [WireObservation]
}
private struct WireObservation: Codable {
  let dimension: String
  let binding: WireBinding
  let valueType: String
  let ordinalValue: Int?
  let boolValue: Bool?
  let numberValue: Double?
  let stringValue: String?
  let confidence: Double
  let distribution: [String: Double]?
}

// MARK: - Frame encoding for optional semantic service

#if canImport(CoreImage)
  import CoreImage

  public enum SemanticFrameEncoder {
    public static func jpegData(
      from pixelBuffer: CVPixelBuffer,
      maxDimension: CGFloat = 896,
      quality: CGFloat = 0.72
    ) -> Data? {
      let image = CIImage(cvPixelBuffer: pixelBuffer)
      let extent = image.extent
      guard extent.width > 0, extent.height > 0 else { return nil }
      let scale = min(1, maxDimension / max(extent.width, extent.height))
      let transformed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      let context = CIContext(options: [.cacheIntermediates: false])
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      // Downscaling is the main payload-size control. Keep CIContext options
      // empty here for SDK compatibility; transport code may recompress later
      // if a stricter byte budget is needed.
      _ = quality
      return context.jpegRepresentation(
        of: transformed,
        colorSpace: colorSpace,
        options: [:]
      )
    }
  }
#endif
