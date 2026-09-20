import XCTest
@testable import PerceptionRuntime

final class PerceptionRuntimeTests: XCTestCase {
    func testBalancedPersonAndAnchorMatchLocalCompositionTargets() {
        let person = PersonObservation(
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
            bounds: NormalizedRect(x: 0.62, y: 0.34, width: 0.26, height: 0.40),
            confidence: 0.90
        )

        let result = CompositionHeuristics.evaluate(person: person, anchor: anchor)

        XCTAssertEqual(result?.relativeScale, 0)
        XCTAssertEqual(result?.visualBalance, 0)
        XCTAssertGreaterThan(result?.confidence ?? 0, 0.7)
    }

    func testTinyAnchorIsReportedAsUnderProminent() {
        let person = PersonObservation(
            present: true,
            visible: true,
            scale: 0.20,
            x: 0.35,
            y: 0.50,
            confidence: 0.95,
            bounds: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.68)
        )
        let anchor = AnchorObservation(
            bounds: NormalizedRect(x: 0.75, y: 0.40, width: 0.08, height: 0.10),
            confidence: 0.85
        )

        XCTAssertEqual(CompositionHeuristics.evaluate(person: person, anchor: anchor)?.relativeScale, -2)
    }

    func testMissingPersonProducesNoComposition() {
        let person = PersonObservation(
            present: false,
            visible: false,
            scale: 0,
            x: 0.5,
            y: 0.5,
            confidence: 0.9
        )
        let anchor = AnchorObservation(
            bounds: NormalizedRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2),
            confidence: 0.9
        )

        XCTAssertNil(CompositionHeuristics.evaluate(person: person, anchor: anchor))
    }

    func testNormalizedRectClampsToFrame() {
        let rect = NormalizedRect(x: -0.1, y: 0.9, width: 0.5, height: 0.5)

        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0.9, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.1, accuracy: 0.0001)
    }
}
