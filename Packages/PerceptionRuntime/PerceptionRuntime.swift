@preconcurrency import Vision
import CoreGraphics
import CoreVideo
import Foundation
import GuidanceCore
import ImageIO

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
    /// Zero means a broadly front-facing shoulder line. Larger values mean the
    /// pose is increasingly oblique or could not be measured confidently.
    public let bodyOrientation: Int?

    public init(
        present: Bool,
        visible: Bool,
        scale: Double,
        x: Double,
        y: Double,
        confidence: Double,
        bounds: NormalizedRect? = nil,
        bodyOrientation: Int? = nil
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

    public init(person: PersonObservation, anchor: AnchorObservation?, composition: CompositionObservation?) {
        self.person = person
        self.anchor = anchor
        self.composition = composition
    }
}

/// Deterministic and testable local replacement for the semantic dimensions.
/// It is deliberately conservative: uncertainty becomes a low-confidence
/// observation instead of pretending that the frame matches the recipe.
public enum CompositionHeuristics {
    public static func evaluate(
        person: PersonObservation,
        anchor: AnchorObservation
    ) -> CompositionObservation? {
        guard person.present,
              let personBounds = person.bounds,
              personBounds.area > 0.005,
              anchor.bounds.area > 0.001 else { return nil }

        let areaRatio = anchor.bounds.area / personBounds.area
        let relativeScale: Int
        switch areaRatio {
        case 0.45...2.20: relativeScale = 0
        case 0.22..<0.45: relativeScale = -1
        case ..<0.22: relativeScale = -2
        case 2.20...4.50: relativeScale = 1
        default: relativeScale = 2
        }

        let personWeight = max(0.08, sqrt(personBounds.area))
        let anchorWeight = max(0.06, sqrt(anchor.bounds.area))
        let visualCenter = (
            personBounds.midX * personWeight + anchor.bounds.midX * anchorWeight
        ) / (personWeight + anchorWeight)
        let visualBalance: Int
        switch visualCenter {
        case 0.44...0.56: visualBalance = 0
        case 0.34..<0.44: visualBalance = -1
        case ..<0.34: visualBalance = -2
        case 0.56...0.66: visualBalance = 1
        default: visualBalance = 2
        }

        return CompositionObservation(
            relativeScale: relativeScale,
            visualBalance: visualBalance,
            confidence: min(person.confidence, anchor.confidence) * 0.90
        )
    }
}

public final class LocalPersonEvaluator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.photoguide.perception.vision", qos: .userInitiated)
    private var lastEvaluation = Date.distantPast
    private let minimumInterval: TimeInterval
    private var trackedPersonBounds: NormalizedRect?
    private var lostTrackingFrames = 0
    private var cachedAnchorPoint: NormalizedPoint?
    private var cachedAnchor: AnchorObservation?
    private var lastAnchorEvaluation = Date.distantPast

    public init(maximumFramesPerSecond: Double = 8) {
        minimumInterval = 1 / max(1, maximumFramesPerSecond)
    }

    public func evaluate(_ frame: CVPixelBuffer) async -> PersonObservation? {
        (await evaluateScene(frame))?.person
    }

    public func evaluateScene(
        _ frame: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        anchorPoint: NormalizedPoint? = nil
    ) async -> SceneObservation? {
        let frameBox = PixelBufferBox(frame)
        return await withCheckedContinuation { continuation in
            queue.async {
                let now = Date()
                guard now.timeIntervalSince(self.lastEvaluation) >= self.minimumInterval else {
                    continuation.resume(returning: nil)
                    return
                }
                self.lastEvaluation = now
                continuation.resume(returning: self.performVision(
                    frameBox.value,
                    orientation: orientation,
                    anchorPoint: anchorPoint
                ))
            }
        }
    }

    private func performVision(
        _ frame: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        anchorPoint: NormalizedPoint?
    ) -> SceneObservation {
        let humanRequest = VNDetectHumanRectanglesRequest()
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: orientation, options: [:])

        do {
            try handler.perform([humanRequest, poseRequest])
        } catch {
            return SceneObservation(person: Self.missingPerson, anchor: nil, composition: nil)
        }

        guard let result = selectPrimaryPerson(from: humanRequest.results ?? []) else {
            return SceneObservation(person: Self.missingPerson, anchor: nil, composition: nil)
        }

        let bounds = Self.topLeftRect(result.boundingBox)
        let edgeMargin = 0.015
        let visible = bounds.x >= edgeMargin
            && bounds.y >= edgeMargin
            && bounds.x + bounds.width <= 1 - edgeMargin
            && bounds.y + bounds.height <= 1 - edgeMargin
        let bodyOrientation = Self.bodyOrientation(
            poseRequest.results?.first,
            personBounds: bounds
        )
        let person = PersonObservation(
            present: true,
            visible: visible,
            scale: bounds.area,
            x: bounds.midX,
            y: bounds.midY,
            confidence: Double(result.confidence),
            bounds: bounds,
            bodyOrientation: bodyOrientation
        )

        guard let anchorPoint else {
            cachedAnchorPoint = nil
            cachedAnchor = nil
            return SceneObservation(person: person, anchor: nil, composition: nil)
        }

        let anchor: AnchorObservation?
        let anchorChanged = cachedAnchorPoint != anchorPoint
        if anchorChanged || Date().timeIntervalSince(lastAnchorEvaluation) >= 0.5 || cachedAnchor == nil {
            cachedAnchorPoint = anchorPoint
            cachedAnchor = resolveAnchor(in: handler, around: anchorPoint, excluding: bounds)
            lastAnchorEvaluation = .now
        }
        anchor = cachedAnchor
        return SceneObservation(
            person: person,
            anchor: anchor,
            composition: anchor.flatMap { CompositionHeuristics.evaluate(person: person, anchor: $0) }
        )
    }

    private func selectPrimaryPerson(
        from results: [VNHumanObservation]
    ) -> VNHumanObservation? {
        guard !results.isEmpty else {
            lostTrackingFrames += 1
            if lostTrackingFrames >= 6 { trackedPersonBounds = nil }
            return nil
        }

        let candidates = results.map { ($0, Self.topLeftRect($0.boundingBox)) }
        if let trackedPersonBounds {
            let nearest = candidates.min {
                Self.centerDistance($0.1, trackedPersonBounds) < Self.centerDistance($1.1, trackedPersonBounds)
            }
            if let nearest, Self.centerDistance(nearest.1, trackedPersonBounds) <= 0.28 {
                self.trackedPersonBounds = nearest.1
                lostTrackingFrames = 0
                return nearest.0
            }

            // Do not silently attach the primary role to a different person
            // during a crossing or a short tracking loss.
            lostTrackingFrames += 1
            if lostTrackingFrames < 6 { return nil }
        }

        let selected = candidates.max {
            let left = Double($0.0.confidence) + $0.1.area
            let right = Double($1.0.confidence) + $1.1.area
            return left < right
        }
        trackedPersonBounds = selected?.1
        lostTrackingFrames = 0
        return selected?.0
    }

    private func resolveAnchor(
        in handler: VNImageRequestHandler,
        around point: NormalizedPoint,
        excluding personBounds: NormalizedRect
    ) -> AnchorObservation? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([request])
        let candidates = request.results?.first?.salientObjects ?? []
        let boxes = candidates
            .map { (Self.topLeftRect($0.boundingBox), Double($0.confidence)) }
            .filter { !$0.0.contains(NormalizedPoint(x: personBounds.midX, y: personBounds.midY)) }
        let selected = boxes.first(where: { $0.0.contains(point) })
            ?? boxes.min(by: { Self.distance(from: $0.0, to: point) < Self.distance(from: $1.0, to: point) })

        if let selected, Self.distance(from: selected.0, to: point) < 0.28 {
            return AnchorObservation(bounds: selected.0, confidence: max(0.62, selected.1))
        }

        // A manual tap is still useful when Vision finds no saliency object. Use
        // a conservative region and lower confidence so the controller asks the
        // user to hold/recheck rather than over-correcting.
        let fallback = NormalizedRect(
            x: point.x - 0.09,
            y: point.y - 0.09,
            width: 0.18,
            height: 0.18
        )
        return AnchorObservation(bounds: fallback, confidence: 0.62)
    }

    private static let missingPerson = PersonObservation(
        present: false,
        visible: false,
        scale: 0,
        x: 0.5,
        y: 0.5,
        confidence: 0.92
    )

    private static func topLeftRect(_ rect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: rect.minX,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func distance(from rect: NormalizedRect, to point: NormalizedPoint) -> Double {
        hypot(rect.midX - point.x, rect.midY - point.y)
    }

    private static func centerDistance(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }

    private static func bodyOrientation(
        _ pose: VNHumanBodyPoseObservation?,
        personBounds: NormalizedRect
    ) -> Int? {
        guard let pose,
              let left = try? pose.recognizedPoint(.leftShoulder),
              let right = try? pose.recognizedPoint(.rightShoulder),
              left.confidence >= 0.25,
              right.confidence >= 0.25 else { return nil }
        let shoulderWidth = abs(left.location.x - right.location.x)
        let ratio = shoulderWidth / max(personBounds.width, 0.01)
        switch ratio {
        case 0.32...: return 0
        case 0.20..<0.32: return 1
        default: return 2
        }
    }
}

private final class PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
}

// MARK: - Future DJev boundary

public struct SemanticSlot: Hashable, Sendable {
    public let dimension: DimensionID
    public let binding: Binding
    public init(dimension: DimensionID, binding: Binding) { self.dimension = dimension; self.binding = binding }
}

public struct SemanticEvaluationRequest: Sendable {
    public let frameID: Int
    public let sceneRevision: Int
    public let bindingVersion: Int
    public let slots: [SemanticSlot]
    public let imagePayload: Data?
    public init(frameID: Int, sceneRevision: Int, bindingVersion: Int, slots: [SemanticSlot], imagePayload: Data? = nil) {
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
    public init(frameID: Int, sceneRevision: Int, bindingVersion: Int, observations: [Observation]) {
        self.frameID = frameID
        self.sceneRevision = sceneRevision
        self.bindingVersion = bindingVersion
        self.observations = observations
    }
}

public protocol SemanticEvaluating: Sendable {
    func evaluate(_ request: SemanticEvaluationRequest) async throws -> SemanticEvaluationResponse
}

public struct FreshSemanticResultGate: Sendable {
    public var maxFrameDelta: Int
    public init(maxFrameDelta: Int = 5) { self.maxFrameDelta = maxFrameDelta }
    public func accepts(_ response: SemanticEvaluationResponse, currentFrameID: Int, currentBindingVersion: Int, currentSceneRevision: Int) -> Bool {
        response.frameID <= currentFrameID
            && currentFrameID - response.frameID <= maxFrameDelta
            && response.bindingVersion == currentBindingVersion
            && response.sceneRevision == currentSceneRevision
    }
}
