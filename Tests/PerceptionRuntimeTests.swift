import XCTest

@testable import PerceptionRuntime

final class PerceptionRuntimeTests: XCTestCase {
  func testBalancedGenericSubjectAndAnchorMatchTargets() {
    let person = SubjectObservation(kind: .salientObject, semanticHint: "food",
      present: true,
      visible: true,
      scale: 0.16,
      x: 0.30,
      y: 0.50,
      confidence: 0.95,
      bounds: NormalizedRect(x: 0.18, y: 0.20, width: 0.24, height: 0.66),
      bodyOrientation: 0
    )
    let anchor = AnchorObservation(
      bounds: NormalizedRect(x: 0.62, y: 0.34, width: 0.26, height: 0.40), confidence: 0.90)
    let result = CompositionHeuristics.evaluate(subject: person, anchor: anchor)
    XCTAssertEqual(result?.relativeScale, 0)
    XCTAssertEqual(result?.visualBalance, 0)
    XCTAssertGreaterThan(result?.confidence ?? 0, 0.7)
  }

  func testTinyAnchorIsUnderProminent() {
    let person = PersonObservation(
      present: true, visible: true, scale: 0.20, x: 0.35, y: 0.50, confidence: 0.95,
      bounds: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.68))
    let anchor = AnchorObservation(
      bounds: NormalizedRect(x: 0.75, y: 0.40, width: 0.08, height: 0.10), confidence: 0.85)
    XCTAssertEqual(
      CompositionHeuristics.evaluate(person: person, anchor: anchor)?.relativeScale, -2)
  }

  func testMissingPersonProducesNoComposition() {
    let person = PersonObservation(
      present: false, visible: false, scale: 0, x: 0.5, y: 0.5, confidence: 0.9)
    let anchor = AnchorObservation(
      bounds: NormalizedRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2), confidence: 0.9)
    XCTAssertNil(CompositionHeuristics.evaluate(person: person, anchor: anchor))
  }

  func testNormalizedRectClampsToFrame() {
    let rect = NormalizedRect(x: -0.1, y: 0.9, width: 0.5, height: 0.5)
    XCTAssertEqual(rect.x, 0)
    XCTAssertEqual(rect.y, 0.9, accuracy: 0.0001)
    XCTAssertEqual(rect.width, 0.5, accuracy: 0.0001)
    XCTAssertEqual(rect.height, 0.1, accuracy: 0.0001)
  }

  func testGenericSubjectContractSupportsNonHumanRecipes() {
    let flower = SubjectObservation(
      kind: .salientObject,
      semanticHint: "flower",
      present: true,
      visible: true,
      scale: 0.18,
      x: 0.62,
      y: 0.44,
      confidence: 0.82,
      bounds: NormalizedRect(x: 0.49, y: 0.28, width: 0.26, height: 0.32))
    XCTAssertTrue(flower.present)
    XCTAssertEqual(flower.kind, .salientObject)
    XCTAssertEqual(flower.semanticHint, "flower")
    XCTAssertEqual(flower.x, 0.62, accuracy: 0.001)
  }

  func testFrameVisualObservationClampsMetrics() {
    let frame = FrameVisualObservation(
      luminance: 1.4,
      shadowFraction: -0.2,
      highlightFraction: 1.3,
      detailEnergy: 0.55,
      saliencyX: 1.2,
      saliencyY: -0.1,
      confidence: 1.4)
    XCTAssertEqual(frame.luminance, 1)
    XCTAssertEqual(frame.shadowFraction, 0)
    XCTAssertEqual(frame.highlightFraction, 1)
    XCTAssertEqual(frame.saliencyX, 1)
    XCTAssertEqual(frame.saliencyY, 0)
    XCTAssertEqual(frame.confidence, 1)
  }

  func testLocalPerceptionProfilesCoverHumanObjectAndSceneModes() {
    XCTAssertEqual(LocalSceneEvaluationProfile.portrait.subjectStrategy, .human)
    XCTAssertEqual(LocalSceneEvaluationProfile.genericObject.subjectStrategy, .saliency)
    XCTAssertEqual(LocalSceneEvaluationProfile.scene.subjectStrategy, .scene)
  }

  func testSemanticSampleBufferIsIndependentFromLocalBindingState() {
    var buffer = SemanticSampleBuffer(capacity: 3)
    buffer.append(.init(frameID: 100, timestamp: 1.0, imagePayload: Data([1])))
    buffer.append(.init(frameID: 101, timestamp: 1.3, imagePayload: Data([2])))
    buffer.append(.init(frameID: 102, timestamp: 1.6, imagePayload: Data([3])))

    let samples = buffer.selected(count: 3, minimumSpacing: 0.2)
    XCTAssertEqual(samples.map(\.frameID), [100, 101, 102])
  }

}
