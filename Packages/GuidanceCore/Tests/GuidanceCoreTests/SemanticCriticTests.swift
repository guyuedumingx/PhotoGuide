import XCTest
@testable import GuidanceCore

final class SemanticCriticTests: XCTestCase {
  private let profile = CriticProfile(
    intent: "Make the photograph feel deliberate and polished.",
    dimensions: [
      .init(id: "composition", name: "Composition", rubric: "Judge framing", weight: 1, targetScore: 0.8),
      .init(id: "lighting", name: "Lighting", rubric: "Judge light", weight: 0.8, targetScore: 0.78),
      .init(id: "color", name: "Color", rubric: "Judge color", weight: 0.5, targetScore: 0.72),
    ])

  func testCritiqueValidationRejectsUnknownAndDuplicateDimensions() {
    let critique = SemanticCritique(assessments: [
      .init(dimensionID: "composition", score: 0.6, confidence: 0.9),
      .init(dimensionID: "composition", score: 0.7, confidence: 0.9),
      .init(dimensionID: "mystery", score: 0.2, confidence: 0.9),
      .init(dimensionID: "lighting", score: 0.8, confidence: 0.9),
    ])
    let result = SemanticCritiqueValidator().validate(critique, against: profile)
    XCTAssertEqual(result.critique.assessments.count, 2)
    XCTAssertTrue(result.issues.contains(.duplicateDimension("composition")))
    XCTAssertTrue(result.issues.contains(.unknownDimension("mystery")))
    XCTAssertTrue(result.issues.contains(.missingDimension("color")))
  }

  func testExplicitProfessionalAdviceWins() {
    let critique = SemanticCritique(
      assessments: [.init(dimensionID: "composition", score: 0.4, confidence: 0.9)],
      advice: [.init(dimensionID: "composition", kind: .composition, title: "Move closer", detail: "Trim empty space", confidence: 0.88)])
    let advice = SemanticCritiqueReducer().primaryAdvice(for: critique, profile: profile)
    XCTAssertEqual(advice?.title, "Move closer")
  }

  func testFallbackAdviceTargetsLargestWeightedDeficit() {
    let critique = SemanticCritique(assessments: [
      .init(dimensionID: "composition", score: 0.45, confidence: 0.95, rationale: "Too much dead space"),
      .init(dimensionID: "lighting", score: 0.60, confidence: 0.95, rationale: "Light is flat"),
      .init(dimensionID: "color", score: 0.30, confidence: 0.95, rationale: "Color conflict"),
    ])
    let advice = SemanticCritiqueReducer().primaryAdvice(for: critique, profile: profile)
    XCTAssertEqual(advice?.dimensionID, "composition")
  }

  func testCaptureReadyUsesQualityScoresNotSubjectType() {
    let critique = SemanticCritique(assessments: [
      .init(dimensionID: "composition", score: 0.88, confidence: 0.9),
      .init(dimensionID: "lighting", score: 0.84, confidence: 0.9),
      .init(dimensionID: "color", score: 0.77, confidence: 0.9),
    ])
    XCTAssertTrue(SemanticCritiqueReducer().isCaptureReady(critique, profile: profile))
  }
}

extension SemanticCriticTests {
  func testRequiredDimensionPreventsFalseReadyWhenMissing() {
    let gated = CriticProfile(
      intent: "Ship a usable photograph",
      dimensions: [
        .init(
          id: "composition", name: "Composition", rubric: "Judge framing", weight: 1,
          targetScore: 0.8, actionability: 1, requiredForReady: true,
          minimumConfidence: 0.55),
        .init(id: "color", name: "Color", rubric: "Judge color", weight: 0.4, targetScore: 0.7),
      ])
    let critique = SemanticCritique(
      assessments: [.init(dimensionID: "color", score: 0.95, confidence: 0.95)],
      captureReady: true)
    XCTAssertFalse(SemanticCritiqueReducer().isCaptureReady(critique, profile: gated))
  }

  func testPositiveModelReadyCannotBypassRequiredTarget() {
    let gated = CriticProfile(
      intent: "Ship a usable photograph",
      dimensions: [
        .init(
          id: "focus", name: "Focus", rubric: "Judge focus", weight: 1,
          targetScore: 0.82, actionability: 0.5, requiredForReady: true)
      ])
    let critique = SemanticCritique(
      assessments: [.init(dimensionID: "focus", score: 0.55, confidence: 0.95)],
      captureReady: true)
    XCTAssertFalse(SemanticCritiqueReducer().isCaptureReady(critique, profile: gated))
  }

  func testCriticSessionRejectsLowWeightedCoverage() {
    let profile = CriticProfile(
      intent: "Evaluate",
      dimensions: [
        .init(id: "primary", name: "Primary", rubric: "Primary", weight: 1, targetScore: 0.8),
        .init(id: "secondary", name: "Secondary", rubric: "Secondary", weight: 0.1, targetScore: 0.7),
      ])
    var session = SemanticCriticSession(profile: profile)
    let result = session.ingest(
      SemanticCritique(assessments: [
        .init(dimensionID: "secondary", score: 0.8, confidence: 0.9)
      ]))
    guard case .rejected(let issues) = result else {
      return XCTFail("Expected incomplete weighted critique to be rejected")
    }
    XCTAssertTrue(issues.contains(.lowCoverage) || issues.contains(.lowWeightedCoverage))
  }

  func testCriticSessionKeepsAdviceStableWithinHoldWindow() {
    let profile = CriticProfile(
      intent: "Evaluate",
      dimensions: [
        .init(id: "composition", name: "Composition", rubric: "Composition", weight: 1, targetScore: 0.8),
        .init(id: "light", name: "Light", rubric: "Light", weight: 1, targetScore: 0.8),
      ])
    let start = Date(timeIntervalSince1970: 100)
    var session = SemanticCriticSession(profile: profile, adviceHoldDuration: 2)
    _ = session.ingest(
      SemanticCritique(
        assessments: [
          .init(dimensionID: "composition", score: 0.4, confidence: 0.9),
          .init(dimensionID: "light", score: 0.7, confidence: 0.9),
        ],
        advice: [.init(dimensionID: "composition", kind: .composition, title: "Move closer", detail: "Trim space")]),
      at: start)
    _ = session.ingest(
      SemanticCritique(
        assessments: [
          .init(dimensionID: "composition", score: 0.65, confidence: 0.9),
          .init(dimensionID: "light", score: 0.3, confidence: 0.9),
        ],
        advice: [.init(dimensionID: "light", kind: .lighting, title: "Find softer light", detail: "Reduce contrast")]),
      at: start.addingTimeInterval(0.5))
    guard case .advise(let advice, _) = session.decision(at: start.addingTimeInterval(0.6)) else {
      return XCTFail("Expected stable advice")
    }
    XCTAssertEqual(advice.dimensionID, "composition")
  }

  func testCriticSessionExpiresWithoutFreshModelResult() {
    var session = SemanticCriticSession(profile: profile, freshnessWindow: 1)
    let start = Date(timeIntervalSince1970: 100)
    _ = session.ingest(
      SemanticCritique(assessments: [
        .init(dimensionID: "composition", score: 0.4, confidence: 0.9),
        .init(dimensionID: "lighting", score: 0.6, confidence: 0.9),
        .init(dimensionID: "color", score: 0.6, confidence: 0.9),
      ]), at: start)
    XCTAssertEqual(session.decision(at: start.addingTimeInterval(2)), .evaluating)
  }
}

extension SemanticCriticTests {
  func testDuplicateProfileDimensionIsReportedWithoutTrap() {
    let malformed = CriticProfile(
      intent: "Evaluate",
      dimensions: [
        .init(id: "composition", name: "A", rubric: "A"),
        .init(id: "composition", name: "B", rubric: "B"),
      ])
    let result = SemanticCritiqueValidator().validate(
      SemanticCritique(assessments: [
        .init(dimensionID: "composition", score: 0.7, confidence: 0.9)
      ]),
      against: malformed)
    XCTAssertTrue(result.issues.contains(.duplicateProfileDimension("composition")))
    XCTAssertEqual(result.critique.assessments.count, 1)
  }
}
