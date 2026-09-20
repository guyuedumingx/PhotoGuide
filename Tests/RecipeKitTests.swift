import XCTest
import GuidanceCore
@testable import RecipeKit

final class RecipeKitTests: XCTestCase {
    func testBundledEnvironmentalPortraitRecipeLoadsWithoutFallback() {
        let recipe = RecipeLoader().loadEnvironmentalPortrait()

        XCTAssertEqual(recipe.source.id, "official.environment_portrait")
        XCTAssertEqual(recipe.goals.count, 8)
        XCTAssertEqual(recipe.actions.count, 16)
        XCTAssertTrue(recipe.validationIssues.isEmpty)
    }

    func testOrdinalMatchTargetsCompileToNeutralValue() {
        let recipe = RecipeLoader().loadEnvironmentalPortrait()
        let orientation = recipe.goals.first { $0.id.rawValue == "body_orientation" }

        XCTAssertEqual(orientation?.target, .ordinal(0))
    }

    func testCompiledRecipeCanReachReadyFromMatchingObservations() {
        let recipe = RecipeLoader().loadEnvironmentalPortrait()
        let session = GuidanceSession(goals: recipe.goals, actions: recipe.actions)

        for frame in 1...2 {
            for goal in recipe.goals {
                _ = session.ingest(Observation(
                    dimension: goal.dimension,
                    binding: goal.binding,
                    value: matchingValue(for: goal.target),
                    confidence: 0.95,
                    frameID: frame,
                    timestamp: .now
                ))
            }
        }

        XCTAssertEqual(session.tick(), .ready)
        XCTAssertEqual(session.readiness().conformance, .full)
    }

    private func matchingValue(for target: GoalTarget) -> DimensionValue {
        switch target {
        case .band(let band):
            .continuous((band.ideal.lowerBound + band.ideal.upperBound) / 2)
        case .ordinal(let value):
            .ordinal(value)
        case .boolean(let value):
            .boolean(value)
        case .categorical(let value):
            .categorical(value)
        }
    }
}
