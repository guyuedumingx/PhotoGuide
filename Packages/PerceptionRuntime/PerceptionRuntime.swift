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

public enum SubjectKind: String, Codable, Equatable, Sendable {
  case person
  case salientObject
  case scene
  case manualRegion
  case unknown
}

/// Geometry-first observation for the Recipe's primary visual subject.
///
/// This deliberately does not assume the subject is a person. Portrait recipes
/// may attach face/body metadata, while food, flowers, products, pets and other
/// objects can be driven by the same existence / visibility / scale / position
/// contract using saliency or user selection.
public struct SubjectObservation: Equatable, Sendable {
  public let kind: SubjectKind
  public let semanticHint: String?
  public let present: Bool
  public let visible: Bool
  public let scale: Double
  public let x: Double
  public let y: Double
  public let confidence: Double
  public let bounds: NormalizedRect?
  public let bodyOrientation: Int?

  public init(
    kind: SubjectKind = .person,
    semanticHint: String? = nil,
    present: Bool,
    visible: Bool,
    scale: Double,
    x: Double,
    y: Double,
    confidence: Double,
    bounds: NormalizedRect? = nil,
    bodyOrientation: Int? = nil
  ) {
    self.kind = kind
    self.semanticHint = semanticHint
    self.present = present
    self.visible = visible
    self.scale = min(max(scale, 0), 1)
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
    self.confidence = min(max(confidence, 0), 1)
    self.bounds = bounds
    self.bodyOrientation = bodyOrientation
  }
}

/// Backward-compatible name for portrait-specific call sites. New code should
/// prefer `SubjectObservation` and only use face/body fields when the Recipe
/// declares a human subject strategy.
public typealias PersonObservation = SubjectObservation

public struct FaceObservation: Equatable, Sendable {
  public let present: Bool
  public let visible: Bool
  public let confidence: Double
  public let bounds: NormalizedRect
  /// Vision-provided yaw/roll in radians when available.
  public let yaw: Double?
  public let roll: Double?

  public init(
    present: Bool = true,
    visible: Bool,
    confidence: Double,
    bounds: NormalizedRect,
    yaw: Double? = nil,
    roll: Double? = nil
  ) {
    self.present = present
    self.visible = visible
    self.confidence = min(max(confidence, 0), 1)
    self.bounds = bounds
    self.yaw = yaw
    self.roll = roll
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

/// Cheap frame-level measurements available for every Recipe, even when no
/// discrete subject is detectable. These are measurement signals, not aesthetic
/// scores, and therefore remain safe local fallbacks for landscape / food /
/// product / flower workflows.
public struct FrameVisualObservation: Equatable, Sendable {
  public let luminance: Double
  public let shadowFraction: Double
  public let highlightFraction: Double
  public let detailEnergy: Double
  public let saliencyX: Double?
  public let saliencyY: Double?
  public let confidence: Double

  public init(
    luminance: Double,
    shadowFraction: Double,
    highlightFraction: Double,
    detailEnergy: Double,
    saliencyX: Double? = nil,
    saliencyY: Double? = nil,
    confidence: Double = 0.82
  ) {
    self.luminance = min(max(luminance, 0), 1)
    self.shadowFraction = min(max(shadowFraction, 0), 1)
    self.highlightFraction = min(max(highlightFraction, 0), 1)
    self.detailEnergy = min(max(detailEnergy, 0), 1)
    self.saliencyX = saliencyX.map { min(max($0, 0), 1) }
    self.saliencyY = saliencyY.map { min(max($0, 0), 1) }
    self.confidence = min(max(confidence, 0), 1)
  }
}

public struct SceneObservation: Equatable, Sendable {
  public let subject: SubjectObservation
  public let face: FaceObservation?
  public let anchor: AnchorObservation?
  public let composition: CompositionObservation?
  public let frame: FrameVisualObservation?
  public let bindingVersion: Int
  public let conditions: SceneConditionProfile

  public var person: PersonObservation { subject }

  public init(
    subject: SubjectObservation,
    face: FaceObservation? = nil,
    anchor: AnchorObservation?,
    composition: CompositionObservation?,
    frame: FrameVisualObservation? = nil,
    bindingVersion: Int,
    conditions: SceneConditionProfile = SceneConditionProfile()
  ) {
    self.subject = subject
    self.face = face
    self.anchor = anchor
    self.composition = composition
    self.frame = frame
    self.bindingVersion = bindingVersion
    self.conditions = conditions
  }

  public init(
    person: PersonObservation,
    face: FaceObservation? = nil,
    anchor: AnchorObservation?,
    composition: CompositionObservation?,
    frame: FrameVisualObservation? = nil,
    bindingVersion: Int,
    conditions: SceneConditionProfile = SceneConditionProfile()
  ) {
    self.init(
      subject: person,
      face: face,
      anchor: anchor,
      composition: composition,
      frame: frame,
      bindingVersion: bindingVersion,
      conditions: conditions)
  }
}

public enum CompositionHeuristics {
  public static func evaluate(subject: SubjectObservation, anchor: AnchorObservation)
    -> CompositionObservation?
  {
    guard subject.present, let personBounds = subject.bounds, personBounds.area > 0.005,
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
      confidence: min(subject.confidence, anchor.confidence) * 0.88)
  }

  public static func evaluate(person: PersonObservation, anchor: AnchorObservation)
    -> CompositionObservation?
  {
    evaluate(subject: person, anchor: anchor)
  }
}

/// On-device perception. The primary subject is sticky for short occlusions; when
/// it must be rebound, `bindingVersion` changes so delayed semantic results are invalidated.
public final class LocalPersonEvaluator: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.photoguide.perception.vision", qos: .userInitiated)
  private let minimumInterval: TimeInterval
  private let anchorInterval: TimeInterval
  private let faceInterval: TimeInterval
  private let poseInterval: TimeInterval
  private var lastEvaluation = Date.distantPast
  private var lastAnchorEvaluation = Date.distantPast
  private var lastFaceEvaluation = Date.distantPast
  private var lastPoseEvaluation = Date.distantPast
  private var trackedPersonBounds: NormalizedRect?
  private var lostTrackingFrames = 0
  private var bindingVersion = 0
  private var cachedAnchorPoint: NormalizedPoint?
  private var cachedAnchor: AnchorObservation?
  private var cachedFace: FaceObservation?
  private var cachedBodyOrientation: Int?
  private var autoAnchorWasUsed = false
  private var smoothedBounds: NormalizedRect?
  private var lastConditionBounds: NormalizedRect?
  private var lastConditionTime: Date?

  public init(
    maximumFramesPerSecond: Double = 8,
    anchorFramesPerSecond: Double = 2,
    faceFramesPerSecond: Double = 4,
    poseFramesPerSecond: Double = 3
  ) {
    minimumInterval = 1 / max(1, maximumFramesPerSecond)
    anchorInterval = 1 / max(0.5, anchorFramesPerSecond)
    faceInterval = 1 / max(0.5, faceFramesPerSecond)
    poseInterval = 1 / max(0.5, poseFramesPerSecond)
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
      self.cachedAnchorPoint = nil
      self.cachedFace = nil
      self.cachedBodyOrientation = nil
      self.autoAnchorWasUsed = false
      self.lastConditionBounds = nil
      self.lastConditionTime = nil
    }
  }

  private func performVision(
    _ frame: CVPixelBuffer, orientation: CGImagePropertyOrientation, anchorPoint: NormalizedPoint?,
    now: Date, frameID: Int?
  ) -> SceneObservation {
    let human = VNDetectHumanRectanglesRequest()
    let shouldRefreshPose = now.timeIntervalSince(lastPoseEvaluation) >= poseInterval
    let shouldRefreshFace = now.timeIntervalSince(lastFaceEvaluation) >= faceInterval
    let pose = shouldRefreshPose ? VNDetectHumanBodyPoseRequest() : nil
    let face = shouldRefreshFace ? VNDetectFaceRectanglesRequest() : nil
    var requests: [VNRequest] = [human]
    if let pose { requests.append(pose) }
    if let face { requests.append(face) }
    let handler = VNImageRequestHandler(
      cvPixelBuffer: frame, orientation: orientation, options: [:])
    do { try handler.perform(requests) } catch {
      let conditions = FrameConditionAnalyzer.analyze(
        frame: frame, person: nil, humanCount: 0, cameraMotion: 0, frameID: frameID)
      return .init(
        person: Self.missingPerson, anchor: cachedAnchor, composition: nil,
        frame: FrameVisualAnalyzer.analyze(frame: frame),
        bindingVersion: bindingVersion, conditions: conditions)
    }

    let selected = selectPrimaryPerson(from: human.results ?? [])
    let rawHumanBounds = selected.map { Self.topLeftRect($0.boundingBox) }

    // Face detection is also a recovery path. Vision's human-rectangle request can fail
    // for tight head-and-shoulders framing even when a clear face is present. Treating
    // that as “no person” made close portraits oscillate back to the acquisition prompt.
    if let face {
      if let rawHumanBounds {
        cachedFace = Self.selectPrimaryFace(from: face.results ?? [], inside: rawHumanBounds)
      } else {
        cachedFace = Self.selectPrimaryFace(from: face.results ?? [])
      }
      lastFaceEvaluation = now
    }

    let freshFace: FaceObservation? = {
      guard let cachedFace else { return nil }
      let maximumAge = max(faceInterval * 1.8, 0.55)
      return now.timeIntervalSince(lastFaceEvaluation) <= maximumAge ? cachedFace : nil
    }()

    let usingFaceFallback = selected == nil && freshFace != nil
    let rawBounds: NormalizedRect
    let personConfidence: Double
    if let selected, let rawHumanBounds {
      rawBounds = rawHumanBounds
      personConfidence = Double(selected.confidence)
    } else if let freshFace {
      let hadTrackedSubject = trackedPersonBounds != nil
      rawBounds = Self.syntheticPersonBounds(from: freshFace.bounds)
      personConfidence = min(0.88, max(0.46, freshFace.confidence * 0.82))
      if !hadTrackedSubject { bindingVersion += 1 }
    } else {
      cachedBodyOrientation = nil
      let conditions = FrameConditionAnalyzer.analyze(
        frame: frame, person: nil, humanCount: human.results?.count ?? 0,
        cameraMotion: 0, frameID: frameID)
      return .init(
        person: Self.missingPerson, face: nil, anchor: cachedAnchor, composition: nil,
        frame: FrameVisualAnalyzer.analyze(frame: frame),
        bindingVersion: bindingVersion, conditions: conditions)
    }

    let bounds = smooth(rawBounds)

    if let pose, !usingFaceFallback {
      cachedBodyOrientation = Self.bodyOrientation(pose.results?.first, personBounds: bounds)
      lastPoseEvaluation = now
    } else if usingFaceFallback {
      // Never carry a stale body-pose estimate into a face-only crop.
      cachedBodyOrientation = nil
    }
    if face == nil, let cachedFace, !Self.face(cachedFace, belongsTo: bounds) {
      self.cachedFace = nil
    }

    let faceObservation = usingFaceFallback ? freshFace : cachedFace
    let visible = Self.subjectIsUsablyVisible(bounds, face: faceObservation)
    let orientationValue = cachedBodyOrientation ?? Self.faceOrientation(faceObservation)
    let person = PersonObservation(
      present: true,
      visible: visible,
      scale: bounds.area,
      x: bounds.midX,
      y: bounds.midY,
      confidence: personConfidence,
      bounds: bounds,
      bodyOrientation: orientationValue
    )
    let cameraMotion = conditionMotion(for: bounds, now: now)
    let inferredHumanCount = max(human.results?.count ?? 0, usingFaceFallback ? 1 : 0)
    let conditions = FrameConditionAnalyzer.analyze(
      frame: frame,
      person: person,
      humanCount: inferredHumanCount,
      cameraMotion: cameraMotion,
      frameID: frameID
    )

    if let anchorPoint {
      let changed = cachedAnchorPoint != anchorPoint || autoAnchorWasUsed
      if changed || cachedAnchor == nil
        || now.timeIntervalSince(lastAnchorEvaluation) >= anchorInterval
      {
        cachedAnchorPoint = anchorPoint
        cachedAnchor = resolveAnchor(in: handler, around: anchorPoint, excluding: bounds)
        autoAnchorWasUsed = false
        lastAnchorEvaluation = now
      }
    } else if cachedAnchor == nil || !autoAnchorWasUsed
      || now.timeIntervalSince(lastAnchorEvaluation) >= max(anchorInterval, 0.65)
    {
      cachedAnchorPoint = nil
      cachedAnchor = resolveAutomaticAnchor(in: handler, excluding: bounds)
      autoAnchorWasUsed = cachedAnchor != nil
      lastAnchorEvaluation = now
    }

    let composition = cachedAnchor.flatMap {
      CompositionHeuristics.evaluate(person: person, anchor: $0)
    }
    return .init(
      person: person, face: faceObservation, anchor: cachedAnchor, composition: composition,
      frame: FrameVisualAnalyzer.analyze(
        frame: frame,
        saliencyRegions: cachedAnchor.map { [$0.bounds] } ?? []),
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

  private func resolveAutomaticAnchor(
    in handler: VNImageRequestHandler,
    excluding personBounds: NormalizedRect
  ) -> AnchorObservation? {
    let request = VNGenerateAttentionBasedSaliencyImageRequest()
    try? handler.perform([request])
    let candidates = (request.results?.first?.salientObjects ?? [])
      .map { (Self.topLeftRect($0.boundingBox), Double($0.confidence)) }
      .filter { rect, _ in
        rect.area >= 0.006
          && Self.intersectionRatio(rect, personBounds) < 0.16
      }

    guard let selected = candidates.max(by: { lhs, rhs in
      let lhsScore = Self.anchorScore(lhs.0, confidence: lhs.1, personBounds: personBounds)
      let rhsScore = Self.anchorScore(rhs.0, confidence: rhs.1, personBounds: personBounds)
      return lhsScore < rhsScore
    }) else { return nil }

    return .init(bounds: selected.0, confidence: max(0.50, min(selected.1, 0.86)))
  }

  private static func selectPrimaryFace(
    from results: [VNFaceObservation],
    inside personBounds: NormalizedRect
  ) -> FaceObservation? {
    let candidates = results.compactMap { observation -> (VNFaceObservation, NormalizedRect)? in
      let rect = topLeftRect(observation.boundingBox)
      let center = NormalizedPoint(x: rect.midX, y: rect.midY)
      guard personBounds.contains(center) || intersectionRatio(rect, personBounds) > 0.55 else {
        return nil
      }
      return (observation, rect)
    }

    guard let selected = candidates.max(by: {
      Double($0.0.confidence) * 0.7 + $0.1.area
        < Double($1.0.confidence) * 0.7 + $1.1.area
    }) else { return nil }

    let rect = selected.1
    let margin = 0.008
    let visible =
      rect.x >= margin && rect.y >= margin
      && rect.x + rect.width <= 1 - margin
      && rect.y + rect.height <= 1 - margin

    return FaceObservation(
      visible: visible,
      confidence: Double(selected.0.confidence),
      bounds: rect,
      yaw: selected.0.yaw?.doubleValue,
      roll: selected.0.roll?.doubleValue
    )
  }

  private static func selectPrimaryFace(from results: [VNFaceObservation]) -> FaceObservation? {
    guard let selected = results.max(by: { lhs, rhs in
      let l = topLeftRect(lhs.boundingBox)
      let r = topLeftRect(rhs.boundingBox)
      return Double(lhs.confidence) * 0.70 + l.area < Double(rhs.confidence) * 0.70 + r.area
    }) else { return nil }

    let rect = topLeftRect(selected.boundingBox)
    let margin = 0.008
    let visible =
      rect.x >= margin && rect.y >= margin
      && rect.x + rect.width <= 1 - margin
      && rect.y + rect.height <= 1 - margin
    return FaceObservation(
      visible: visible,
      confidence: Double(selected.confidence),
      bounds: rect,
      yaw: selected.yaw?.doubleValue,
      roll: selected.roll?.doubleValue)
  }

  private static func syntheticPersonBounds(from face: NormalizedRect) -> NormalizedRect {
    // Head-and-shoulders proxy used only when Vision cannot produce a human rectangle.
    // Keep the face in the upper third and expand downwards to approximate portrait mass.
    let width = min(0.92, max(face.width * 2.15, 0.22))
    let height = min(0.96, max(face.height * 4.1, 0.34))
    let x = min(max(face.midX - width / 2, 0), 1 - width)
    let desiredY = face.y - face.height * 0.42
    let y = min(max(desiredY, 0), 1 - height)
    return NormalizedRect(x: x, y: y, width: width, height: height)
  }

  private static func anchorScore(
    _ rect: NormalizedRect,
    confidence: Double,
    personBounds: NormalizedRect
  ) -> Double {
    let separation = min(1, centerDistance(rect, personBounds) / 0.55)
    let usefulArea = min(rect.area / 0.16, 1)
    return confidence * 0.48 + separation * 0.34 + usefulArea * 0.18
  }

  private static func intersectionRatio(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
    let minX = max(a.x, b.x)
    let minY = max(a.y, b.y)
    let maxX = min(a.x + a.width, b.x + b.width)
    let maxY = min(a.y + a.height, b.y + b.height)
    guard maxX > minX, maxY > minY else { return 0 }
    let intersection = (maxX - minX) * (maxY - minY)
    return intersection / max(min(a.area, b.area), 0.0001)
  }

  private static func faceOrientation(_ face: FaceObservation?) -> Int? {
    guard let yaw = face?.yaw else { return nil }
    let magnitude = abs(yaw)
    if magnitude < 0.18 { return 0 }
    let sign = yaw >= 0 ? 1 : -1
    return magnitude < 0.48 ? sign : sign * 2
  }

  private static func subjectIsUsablyVisible(
    _ bounds: NormalizedRect, face: FaceObservation?
  ) -> Bool {
    // `visibility` is a guard for whether the subject is usable for guidance, not a
    // full-body requirement. Portraits commonly crop legs or the lower torso; treating
    // any edge contact as a HARD failure created the repeated “keep the whole person in
    // frame” loop seen on device. A clear face plus at most one cropped edge is usable.
    let margin = 0.008
    let clippedEdges = [
      bounds.x < margin,
      bounds.y < margin,
      bounds.x + bounds.width > 1 - margin,
      bounds.y + bounds.height > 1 - margin,
    ].filter { $0 }.count

    if let face, face.visible, face.confidence >= 0.35, clippedEdges <= 1 { return true }
    return clippedEdges == 0
  }

  private static func face(_ face: FaceObservation, belongsTo person: NormalizedRect) -> Bool {
    let center = NormalizedPoint(x: face.bounds.midX, y: face.bounds.midY)
    return person.contains(center) || intersectionRatio(face.bounds, person) > 0.45
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



public enum LocalSubjectAcquisitionStrategy: String, Codable, Sendable {
  /// Human rectangle + optional face/body pose assistance.
  case human
  /// Generic attention-saliency subject. Suitable for food, flowers, products,
  /// pets and other objects when no task-specific detector is installed.
  case saliency
  /// Frame-only scene analysis. No discrete primary subject is required.
  case scene
}

public struct LocalSceneEvaluationProfile: Equatable, Sendable {
  public let subjectStrategy: LocalSubjectAcquisitionStrategy
  public let semanticHint: String?
  public let faceAssist: Bool
  public let poseAssist: Bool
  public let automaticAnchor: Bool

  public init(
    subjectStrategy: LocalSubjectAcquisitionStrategy,
    semanticHint: String? = nil,
    faceAssist: Bool = false,
    poseAssist: Bool = false,
    automaticAnchor: Bool = false
  ) {
    self.subjectStrategy = subjectStrategy
    self.semanticHint = semanticHint
    self.faceAssist = faceAssist
    self.poseAssist = poseAssist
    self.automaticAnchor = automaticAnchor
  }

  public static let portrait = LocalSceneEvaluationProfile(
    subjectStrategy: .human, semanticHint: "person", faceAssist: true, poseAssist: true,
    automaticAnchor: false)
  public static let genericObject = LocalSceneEvaluationProfile(
    subjectStrategy: .saliency, semanticHint: nil, automaticAnchor: false)
  public static let scene = LocalSceneEvaluationProfile(
    subjectStrategy: .scene, semanticHint: "scene", automaticAnchor: false)
}

/// Recipe-driven on-device perception host.
///
/// `LocalPersonEvaluator` remains the optimized human specialization, while this
/// façade gives the product a single generic entry point. Non-human recipes use
/// Vision attention saliency and frame measurements rather than pretending a
/// human detector can generalize to arbitrary subjects.
public final class LocalSceneEvaluator: @unchecked Sendable {
  private let profile: LocalSceneEvaluationProfile
  private let portraitEvaluator: LocalPersonEvaluator?
  private let queue = DispatchQueue(label: "com.photoguide.perception.scene", qos: .userInitiated)
  private let minimumInterval: TimeInterval
  private var lastEvaluation = Date.distantPast
  private var trackedBounds: NormalizedRect?
  private var smoothedBounds: NormalizedRect?
  private var lostFrames = 0
  private var bindingVersion = 0
  private var cachedAnchor: AnchorObservation?
  private var cachedAnchorPoint: NormalizedPoint?

  public init(
    profile: LocalSceneEvaluationProfile,
    maximumFramesPerSecond: Double = 5.5
  ) {
    self.profile = profile
    self.minimumInterval = 1 / max(1, maximumFramesPerSecond)
    if profile.subjectStrategy == .human {
      portraitEvaluator = LocalPersonEvaluator(
        maximumFramesPerSecond: maximumFramesPerSecond,
        anchorFramesPerSecond: 1.25,
        faceFramesPerSecond: profile.faceAssist ? 3.5 : 0.5,
        poseFramesPerSecond: profile.poseAssist ? 2.5 : 0.5)
    } else {
      portraitEvaluator = nil
    }
  }

  public func evaluateScene(
    _ frame: CVPixelBuffer,
    orientation: CGImagePropertyOrientation = .up,
    subjectPoint: NormalizedPoint? = nil,
    anchorPoint: NormalizedPoint? = nil,
    frameID: Int? = nil
  ) async -> SceneObservation? {
    if let portraitEvaluator {
      guard let scene = await portraitEvaluator.evaluateScene(
        frame, orientation: orientation, anchorPoint: anchorPoint, frameID: frameID)
      else { return nil }
      let frameObservation = FrameVisualAnalyzer.analyze(frame: frame)
      return SceneObservation(
        subject: scene.subject,
        face: profile.faceAssist ? scene.face : nil,
        anchor: scene.anchor,
        composition: scene.composition,
        frame: frameObservation,
        bindingVersion: scene.bindingVersion,
        conditions: scene.conditions)
    }

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
          returning: self.performGenericVision(
            box.value,
            orientation: orientation,
            subjectPoint: subjectPoint,
            anchorPoint: anchorPoint,
            frameID: frameID))
      }
    }
  }

  public func resetTracking() {
    if let portraitEvaluator {
      portraitEvaluator.resetTracking()
      return
    }
    queue.async {
      self.trackedBounds = nil
      self.smoothedBounds = nil
      self.cachedAnchor = nil
      self.cachedAnchorPoint = nil
      self.lostFrames = 0
      self.bindingVersion += 1
    }
  }

  private func performGenericVision(
    _ frame: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    subjectPoint: NormalizedPoint?,
    anchorPoint: NormalizedPoint?,
    frameID: Int?
  ) -> SceneObservation {
    let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: orientation, options: [:])
    let attention = VNGenerateAttentionBasedSaliencyImageRequest()
    let objectness = VNGenerateObjectnessBasedSaliencyImageRequest()
    do { try handler.perform([attention, objectness]) } catch {
      let subject = missingSubject
      return SceneObservation(
        subject: subject,
        anchor: nil,
        composition: nil,
        frame: FrameVisualAnalyzer.analyze(frame: frame),
        bindingVersion: bindingVersion,
        conditions: FrameConditionAnalyzer.analyze(
          frame: frame, person: nil, humanCount: 0, cameraMotion: 0, frameID: frameID))
    }

    // Attention saliency is strong for visually dominant content while objectness
    // is better for bounded objects. Merging both is materially more robust than
    // assuming every non-human Recipe looks like a portrait detector target.
    let attentionCandidates = (attention.results?.first?.salientObjects ?? [])
      .map { (Self.topLeftRect($0.boundingBox), Double($0.confidence)) }
    let objectCandidates = (objectness.results?.first?.salientObjects ?? [])
      .map { (Self.topLeftRect($0.boundingBox), Double($0.confidence) * 0.94) }
    let candidates = Self.mergeSaliencyCandidates(attentionCandidates + objectCandidates)
      .filter { $0.0.area >= 0.004 }

    let frameObservation = FrameVisualAnalyzer.analyze(
      frame: frame, saliencyRegions: candidates.map(\.0))

    if profile.subjectStrategy == .scene {
      let strongestCandidate = candidates.first
      let subject = SubjectObservation(
        kind: .scene,
        semanticHint: profile.semanticHint,
        present: true,
        visible: true,
        scale: 1,
        x: frameObservation?.saliencyX ?? strongestCandidate?.0.midX ?? 0.5,
        y: frameObservation?.saliencyY ?? strongestCandidate?.0.midY ?? 0.5,
        confidence: frameObservation?.confidence ?? strongestCandidate?.1 ?? 0.35,
        bounds: nil)
      return SceneObservation(
        subject: subject,
        anchor: nil,
        composition: nil,
        frame: frameObservation,
        bindingVersion: bindingVersion,
        conditions: FrameConditionAnalyzer.analyze(
          frame: frame, person: nil, humanCount: 0, cameraMotion: 0, frameID: frameID))
    }

    let chosen: (NormalizedRect, Double)? =
      chooseSubject(from: candidates, preferredPoint: subjectPoint)
      ?? subjectPoint.map { point in
        // A user tap is an explicit subject declaration. If Vision saliency has
        // no usable proposal (low contrast flowers, grass, matte products), keep
        // the workflow alive with a conservative local ROI instead of pretending
        // there is no subject at all.
        let width = 0.28
        let height = 0.28
        return (
          NormalizedRect(
            x: point.x - width / 2, y: point.y - height / 2,
            width: width, height: height),
          0.56)
      }

    guard let chosen else {
      lostFrames += 1
      if lostFrames >= 6 {
        trackedBounds = nil
        smoothedBounds = nil
      }
      return SceneObservation(
        subject: missingSubject,
        anchor: nil,
        composition: nil,
        frame: frameObservation,
        bindingVersion: bindingVersion,
        conditions: FrameConditionAnalyzer.analyze(
          frame: frame, person: nil, humanCount: 0, cameraMotion: 0, frameID: frameID))
    }

    let hadTracked = trackedBounds != nil
    let bounds = smooth(chosen.0)
    if !hadTracked { bindingVersion += 1 }
    lostFrames = 0
    let subject = SubjectObservation(
      kind: subjectPoint == nil ? .salientObject : .manualRegion,
      semanticHint: profile.semanticHint,
      present: true,
      visible: Self.usablyVisible(bounds),
      scale: bounds.area,
      x: bounds.midX,
      y: bounds.midY,
      confidence: max(0.42, min(chosen.1, 0.88)),
      bounds: bounds)

    let anchor = resolveAnchor(
      from: candidates,
      subjectBounds: bounds,
      requestedPoint: anchorPoint)
    let composition = anchor.flatMap { CompositionHeuristics.evaluate(subject: subject, anchor: $0) }
    let conditions = FrameConditionAnalyzer.analyze(
      frame: frame, person: subject, humanCount: 0, cameraMotion: 0, frameID: frameID)
    return SceneObservation(
      subject: subject,
      anchor: anchor,
      composition: composition,
      frame: frameObservation,
      bindingVersion: bindingVersion,
      conditions: conditions)
  }

  private var missingSubject: SubjectObservation {
    SubjectObservation(
      kind: profile.subjectStrategy == .scene ? .scene : .unknown,
      semanticHint: profile.semanticHint,
      present: false,
      visible: false,
      scale: 0,
      x: 0.5,
      y: 0.5,
      confidence: 0.72)
  }

  private static func mergeSaliencyCandidates(
    _ candidates: [(NormalizedRect, Double)]
  ) -> [(NormalizedRect, Double)] {
    var merged: [(NormalizedRect, Double)] = []
    for candidate in candidates.sorted(by: { $0.1 > $1.1 }) {
      if let index = merged.firstIndex(where: { intersectionRatio($0.0, candidate.0) >= 0.62 }) {
        if candidate.1 > merged[index].1 { merged[index] = candidate }
      } else {
        merged.append(candidate)
      }
    }
    return Array(merged.prefix(8))
  }

  private func chooseSubject(
    from candidates: [(NormalizedRect, Double)],
    preferredPoint: NormalizedPoint?
  ) -> (NormalizedRect, Double)? {
    guard !candidates.isEmpty else { return nil }
    if let preferredPoint {
      let sorted = candidates.sorted {
        Self.distance($0.0, preferredPoint) < Self.distance($1.0, preferredPoint)
      }
      if let first = sorted.first, Self.distance(first.0, preferredPoint) <= 0.32 { return first }
    }
    if let trackedBounds,
      let nearest = candidates.min(by: {
        Self.centerDistance($0.0, trackedBounds) < Self.centerDistance($1.0, trackedBounds)
      }),
      Self.centerDistance(nearest.0, trackedBounds) <= 0.28
    {
      return nearest
    }
    return candidates.max(by: { lhs, rhs in
      Self.genericSubjectScore(lhs.0, confidence: lhs.1)
        < Self.genericSubjectScore(rhs.0, confidence: rhs.1)
    })
  }

  private func resolveAnchor(
    from candidates: [(NormalizedRect, Double)],
    subjectBounds: NormalizedRect,
    requestedPoint: NormalizedPoint?
  ) -> AnchorObservation? {
    guard profile.automaticAnchor || requestedPoint != nil else { return nil }
    if let requestedPoint {
      cachedAnchorPoint = requestedPoint
      if let selected = candidates.min(by: {
        Self.distance($0.0, requestedPoint) < Self.distance($1.0, requestedPoint)
      }), Self.distance(selected.0, requestedPoint) <= 0.30,
        Self.intersectionRatio(selected.0, subjectBounds) < 0.30
      {
        cachedAnchor = AnchorObservation(bounds: selected.0, confidence: max(0.52, selected.1))
      } else {
        cachedAnchor = AnchorObservation(
          bounds: NormalizedRect(
            x: requestedPoint.x - 0.08, y: requestedPoint.y - 0.08,
            width: 0.16, height: 0.16),
          confidence: 0.50)
      }
      return cachedAnchor
    }

    if let cachedAnchor, Self.intersectionRatio(cachedAnchor.bounds, subjectBounds) < 0.30 {
      return cachedAnchor
    }
    guard let selected = candidates
      .filter({ Self.intersectionRatio($0.0, subjectBounds) < 0.20 })
      .max(by: { lhs, rhs in
        Self.anchorScore(lhs.0, confidence: lhs.1, subjectBounds: subjectBounds)
          < Self.anchorScore(rhs.0, confidence: rhs.1, subjectBounds: subjectBounds)
      })
    else { return nil }
    cachedAnchor = AnchorObservation(bounds: selected.0, confidence: max(0.48, min(0.84, selected.1)))
    return cachedAnchor
  }

  private func smooth(_ rect: NormalizedRect) -> NormalizedRect {
    guard let previous = smoothedBounds else {
      smoothedBounds = rect
      trackedBounds = rect
      return rect
    }
    let alpha = 0.34
    let result = NormalizedRect(
      x: previous.x * (1 - alpha) + rect.x * alpha,
      y: previous.y * (1 - alpha) + rect.y * alpha,
      width: previous.width * (1 - alpha) + rect.width * alpha,
      height: previous.height * (1 - alpha) + rect.height * alpha)
    smoothedBounds = result
    trackedBounds = result
    return result
  }

  private static func genericSubjectScore(_ rect: NormalizedRect, confidence: Double) -> Double {
    let centerDistance = hypot(rect.midX - 0.5, rect.midY - 0.5)
    let area = min(rect.area / 0.24, 1)
    let centerPreference = max(0, 1 - centerDistance / 0.7)
    return confidence * 0.56 + area * 0.26 + centerPreference * 0.18
  }

  private static func anchorScore(
    _ rect: NormalizedRect,
    confidence: Double,
    subjectBounds: NormalizedRect
  ) -> Double {
    let separation = min(1, centerDistance(rect, subjectBounds) / 0.55)
    return confidence * 0.54 + separation * 0.32 + min(rect.area / 0.18, 1) * 0.14
  }

  private static func usablyVisible(_ rect: NormalizedRect) -> Bool {
    let inset = 0.006
    let clipped = [
      rect.x < inset,
      rect.y < inset,
      rect.x + rect.width > 1 - inset,
      rect.y + rect.height > 1 - inset,
    ].filter { $0 }.count
    return clipped <= 1 && rect.area >= 0.004
  }

  private static func topLeftRect(_ rect: CGRect) -> NormalizedRect {
    NormalizedRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func distance(_ rect: NormalizedRect, _ point: NormalizedPoint) -> Double {
    hypot(rect.midX - point.x, rect.midY - point.y)
  }

  private static func centerDistance(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
    hypot(a.midX - b.midX, a.midY - b.midY)
  }

  private static func intersectionRatio(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
    let minX = max(a.x, b.x)
    let minY = max(a.y, b.y)
    let maxX = min(a.x + a.width, b.x + b.width)
    let maxY = min(a.y + a.height, b.y + b.height)
    guard maxX > minX, maxY > minY else { return 0 }
    let intersection = (maxX - minX) * (maxY - minY)
    return intersection / max(min(a.area, b.area), 0.0001)
  }
}

public enum FrameVisualAnalyzer {
  /// Lightweight BGRA statistics that are safe to run for every Recipe.
  public static func analyze(
    frame: CVPixelBuffer,
    saliencyRegions: [NormalizedRect] = []
  ) -> FrameVisualObservation? {
    guard CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(frame, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
    let width = CVPixelBufferGetWidth(frame)
    let height = CVPixelBufferGetHeight(frame)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
    guard width > 2, height > 2 else { return nil }

    let ptr = base.assumingMemoryBound(to: UInt8.self)
    let xStep = max(1, width / 42)
    let yStep = max(1, height / 56)
    var sum = 0.0
    var dark = 0
    var highlight = 0
    var edge = 0.0
    var edgeCount = 0
    var count = 0

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
        if value <= 0.08 { dark += 1 }
        if value >= 0.94 { highlight += 1 }
        count += 1
        if x + xStep < width {
          edge += abs(value - luma(x + xStep, y))
          edgeCount += 1
        }
        x += xStep
      }
      y += yStep
    }
    guard count > 0 else { return nil }

    let totalWeight = saliencyRegions.reduce(0.0) { $0 + max($1.area, 0.002) }
    let saliencyX: Double? = totalWeight > 0
      ? saliencyRegions.reduce(0.0) { $0 + $1.midX * max($1.area, 0.002) } / totalWeight
      : nil
    let saliencyY: Double? = totalWeight > 0
      ? saliencyRegions.reduce(0.0) { $0 + $1.midY * max($1.area, 0.002) } / totalWeight
      : nil
    let rawEdge = edgeCount > 0 ? edge / Double(edgeCount) : 0
    return FrameVisualObservation(
      luminance: sum / Double(count),
      shadowFraction: Double(dark) / Double(count),
      highlightFraction: Double(highlight) / Double(count),
      detailEnergy: min(max(rawEdge / 0.16, 0), 1),
      saliencyX: saliencyX,
      saliencyY: saliencyY,
      confidence: 0.84)
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

// MARK: - Multimodal critic boundary

/// Tiny bounded buffer used to give a low-latency multimodal critic temporal
/// context without turning PhotoGuide into a video-understanding pipeline.
public struct SemanticSampleBuffer: Sendable {
  private var samples: [CriticImageSample] = []
  public var capacity: Int

  public init(capacity: Int = 5) {
    self.capacity = min(max(capacity, 1), 8)
  }

  public mutating func append(_ sample: CriticImageSample) {
    samples.removeAll { $0.frameID == sample.frameID }
    samples.append(sample)
    samples.sort { $0.timestamp < $1.timestamp }
    if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
  }

  public mutating func reset() { samples.removeAll(keepingCapacity: true) }

  public func selected(count: Int, minimumSpacing: TimeInterval) -> [CriticImageSample] {
    let wanted = min(max(count, 1), capacity)
    guard wanted > 1 else { return samples.suffix(1).map { $0 } }
    var result = [CriticImageSample]()
    for sample in samples.reversed() {
      if let newest = result.last, abs(newest.timestamp - sample.timestamp) < minimumSpacing { continue }
      result.append(sample)
      if result.count == wanted { break }
    }
    return Array(result.reversed())
  }
}

/// Generic HTTP edge adapter. The product core only knows `MultimodalCritic`;
/// transport-specific compatibility fields stay here at the edge.
public struct HTTPMultimodalCriticEvaluator: MultimodalCritic {
  public struct Configuration: Sendable {
    public let endpoint: URL
    public let bearerToken: String?
    public let timeout: TimeInterval

    public init(
      endpoint: URL,
      bearerToken: String? = nil,
      timeout: TimeInterval = 2.5
    ) {
      self.endpoint = endpoint
      self.bearerToken = bearerToken
      self.timeout = min(max(timeout, 0.5), 12)
    }
  }

  public let configuration: Configuration
  public init(configuration: Configuration) { self.configuration = configuration }

  public func critique(
    profile: CriticProfile,
    samples: [CriticImageSample],
    locale: String
  ) async throws -> SemanticCritique {
    guard !samples.isEmpty else { throw MultimodalCriticError.emptySampleSet }

    var urlRequest = URLRequest(url: configuration.endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = configuration.timeout
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = configuration.bearerToken {
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let latestFrameID = samples.last?.frameID ?? 0
    let payload = WireRequest(
      contractVersion: SemanticCriticContract.version,
      locale: locale,
      critic: profile,
      frames: samples.map {
        .init(
          frameID: $0.frameID,
          timestamp: $0.timestamp,
          imageBase64: $0.imagePayload.base64EncodedString())
      },
      imageBase64: samples.last?.imagePayload.base64EncodedString(),
      // Edge-only compatibility for early DJev servers. These fields are not
      // part of the product-core contract and carry no local-CV semantics.
      frameID: latestFrameID,
      sceneRevision: 0,
      bindingVersion: 0,
      recipeID: "photoguide",
      slots: []
    )
    urlRequest.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw MultimodalCriticError.invalidResponse
    }
    let decoded = try JSONDecoder().decode(WireResponse.self, from: data)
    guard let critique = decoded.critique else { throw MultimodalCriticError.missingCritique }
    return critique
  }
}

public enum MultimodalCriticError: Error {
  case emptySampleSet
  case invalidResponse
  case missingCritique
}

/// Compatibility aliases for early integrations. The runtime contract is model-agnostic.
public typealias HTTPDJevEvaluator = HTTPMultimodalCriticEvaluator
public typealias DJevError = MultimodalCriticError

private struct WireRequest: Codable {
  let contractVersion: Int
  let locale: String
  let critic: CriticProfile
  let frames: [WireFrame]
  /// Temporary backward-compatibility field for early DJev servers.
  let imageBase64: String?

  // Legacy edge fields: deliberately excluded from `MultimodalCritic`.
  let frameID: Int
  let sceneRevision: Int
  let bindingVersion: Int
  let recipeID: String
  let slots: [WireLegacySlot]
}

private struct WireFrame: Codable {
  let frameID: Int
  let timestamp: TimeInterval
  let imageBase64: String
}

private struct WireLegacySlot: Codable {}

private struct WireResponse: Codable {
  let critique: SemanticCritique?
}

// MARK: - Frame encoding for optional semantic service

#if canImport(CoreImage)
  @preconcurrency import CoreImage
  import UniformTypeIdentifiers

  public enum SemanticFrameEncoder {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func jpegData(
      from pixelBuffer: CVPixelBuffer,
      maxDimension: CGFloat = 720,
      quality: CGFloat = 0.68
    ) -> Data? {
      let image = CIImage(cvPixelBuffer: pixelBuffer)
      let extent = image.extent
      guard extent.width > 0, extent.height > 0 else { return nil }
      let scale = min(1, maxDimension / max(extent.width, extent.height))
      let transformed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      guard let cgImage = Self.context.createCGImage(transformed, from: transformed.extent) else {
        return nil
      }
      let data = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          data, UTType.jpeg.identifier as CFString, 1, nil)
      else { return nil }
      let options = [
        kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 0.95)
      ] as CFDictionary
      CGImageDestinationAddImage(destination, cgImage, options)
      guard CGImageDestinationFinalize(destination) else { return nil }
      return data as Data
    }
  }
#endif
