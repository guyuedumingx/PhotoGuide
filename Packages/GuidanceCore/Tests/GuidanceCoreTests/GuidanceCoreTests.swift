import XCTest
@testable import GuidanceCore

final class GuidanceCoreTests: XCTestCase {
    private let goalID = GoalID("g")
    private let dimensionID = DimensionID("x")
    private let binding = Binding([])

    private func goal(
        id: GoalID? = nil,
        target: GoalTarget = .boolean(true),
        dependencies: Set<GoalID> = [],
        constraint: ConstraintClass = .core
    ) -> GoalDefinition {
        GoalDefinition(
            id: id ?? goalID,
            dimension: dimensionID,
            binding: binding,
            target: target,
            constraint: constraint,
            dependencies: dependencies
        )
    }

    private func observation(
        _ value: DimensionValue,
        confidence: Double = 1,
        frame: Int = 1,
        bindingVersion: Int = 0,
        scene: Int = 0,
        distribution: [String: Double]? = nil
    ) -> Observation {
        Observation(
            dimension: dimensionID,
            binding: binding,
            value: value,
            confidence: confidence,
            distribution: distribution,
            frameID: frame,
            timestamp: .now,
            bindingVersion: bindingVersion,
            sceneRevision: scene
        )
    }

    private func action(
        _ id: String = "a",
        affects: Set<GoalID>? = nil,
        damages: Set<GoalID> = [],
        gain: Double = 1,
        burden: Double = 0,
        family: String = "move",
        safe: Bool = true
    ) -> ActionDefinition {
        ActionDefinition(
            id: ActionID(id),
            affects: affects ?? [goalID],
            damages: damages,
            expectedGain: gain,
            burden: burden,
            family: family,
            safe: safe
        )
    }

    private func makeActive(_ engine: GoalEngine) {
        engine.enterFrames = 1
        engine.exitFrames = 1
        _ = engine.ingest(observation(.boolean(false)))
    }

    func test_regression_reactivates_goal() {
        let engine = GoalEngine([goal()])
        engine.enterFrames = 1
        engine.exitFrames = 2

        _ = engine.ingest(observation(.boolean(true)))
        _ = engine.ingest(observation(.boolean(false), frame: 2))
        XCTAssertEqual(engine.states[goalID]?.state, .satisfied)

        _ = engine.ingest(observation(.boolean(false), frame: 3))
        XCTAssertEqual(engine.states[goalID]?.state, .drifted)
    }

    func test_cancel_stops_transaction_without_rollback() {
        let planner = ActionPlanner()
        var transaction: ActionInstance? = ActionInstance(action())
        planner.openTemporaryViolationWindow()

        planner.apply(.cancel, transaction: &transaction)

        XCTAssertNil(transaction)
        XCTAssertEqual(planner.lastTerminatedAction?.state, .cancelled)
        XCTAssertEqual(planner.lastOutcome, .cancelled(ActionID("a")))
        XCTAssertTrue(planner.needsReobserve)
        XCTAssertFalse(planner.temporaryViolationWindowOpen)
    }

    func test_blocked_action_is_not_reproposed() {
        let planner = ActionPlanner()
        var transaction: ActionInstance? = ActionInstance(action())

        planner.apply(.impossible(ActionID("a")), transaction: &transaction)

        XCTAssertTrue(planner.rank([action(), action("same-family")]).isEmpty)
        XCTAssertEqual(planner.lastOutcome, .constrained("move"))
    }

    func test_declined_action_prefers_alternative() {
        let planner = ActionPlanner()
        var transaction: ActionInstance? = ActionInstance(action())

        planner.apply(.anotherWay, transaction: &transaction)

        XCTAssertEqual(planner.rank([action(), action("b")]).first?.id, ActionID("b"))
        XCTAssertEqual(transaction?.state, .declined)
    }

    func test_locked_goal_is_not_damaged() {
        let planner = ActionPlanner()
        planner.lockedGoals = [goalID]

        XCTAssertTrue(planner.rank([action(damages: [goalID])]).isEmpty)
        XCTAssertEqual(planner.rank([action("safe", damages: [])]).count, 1)
    }

    func test_skipped_goal_reduces_conformance_not_readiness() {
        let session = GuidanceSession(goals: [goal()], actions: [])
        var transaction: ActionInstance?

        session.handle(.skip(goalID), transaction: &transaction)
        let decision = session.tick()

        XCTAssertEqual(decision, .ready)
        XCTAssertEqual(session.readiness().state, .ready)
        XCTAssertEqual(session.readiness().conformance, .partial)
    }

    func test_unstable_observation_produces_wait() {
        let session = GuidanceSession(goals: [goal()], actions: [action()])
        _ = session.ingest(observation(.boolean(true), confidence: 0.1))

        XCTAssertEqual(session.tick(), .unknown)
        XCTAssertEqual(session.engine.states[goalID]?.state, .unknown)
    }

    func test_stale_semantic_result_is_rejected() {
        XCTAssertFalse(
            FreshnessEvaluator().accepts(
                result: observation(.boolean(true)),
                currentFrame: 20,
                currentBindingVersion: 0,
                currentSceneRevision: 0
            )
        )
    }

    func test_variant_does_not_flap() {
        var selector = VariantSelector(currentID: "portrait", switchMargin: 0.05, requiredConfirmations: 2)

        XCTAssertEqual(
            selector.select(from: [.init(id: "portrait", score: 0.80), .init(id: "wide", score: 0.82)]),
            "portrait"
        )
        XCTAssertEqual(
            selector.select(from: [.init(id: "portrait", score: 0.70), .init(id: "wide", score: 0.90)]),
            "portrait"
        )
        XCTAssertEqual(
            selector.select(from: [.init(id: "portrait", score: 0.69), .init(id: "wide", score: 0.91)]),
            "wide"
        )
    }

    func test_opposite_execution_triggers_recovery() {
        let planner = ActionPlanner()
        planner.memory.oppositeEffects = 2
        let engine = GoalEngine([goal()])
        makeActive(engine)

        XCTAssertEqual(
            GuidanceScheduler().decide(engine: engine, planner: planner, actions: [action()]),
            .wait
        )
    }

    func test_no_feasible_action_terminates_cleanly() {
        let session = GuidanceSession(goals: [goal()], actions: [])
        session.engine.enterFrames = 1
        session.engine.exitFrames = 1
        _ = session.ingest(observation(.boolean(false)))

        XCTAssertEqual(session.tick(), .unreachable)
    }

    func test_user_satisfied_stops_soft_optimization() {
        let session = GuidanceSession(goals: [goal()], actions: [action()])
        var transaction: ActionInstance?

        session.handle(.satisfied, transaction: &transaction)

        XCTAssertEqual(session.tick(), .readyByUser)
        XCTAssertEqual(session.readiness().state, .readyByUser)
    }

    func test_binding_identity_does_not_silently_swap() {
        var store = BindingStore()

        XCTAssertTrue(store.bind(role: "subject", node: NodeID("one")))
        XCTAssertFalse(store.bind(role: "subject", node: NodeID("two")))
        XCTAssertEqual(store.bindings["subject"], NodeID("one"))
    }

    func test_soft_gain_not_worth_burden() {
        let planner = ActionPlanner()
        let engine = GoalEngine([goal()])
        makeActive(engine)
        let expensive = action("tiny", gain: 0.01, burden: 1)

        XCTAssertEqual(
            GuidanceScheduler().decide(engine: engine, planner: planner, actions: [expensive]),
            .ready
        )
    }

    func test_goal_hysteresis_requires_enter_frames() {
        let engine = GoalEngine([goal()])

        _ = engine.ingest(observation(.boolean(true)))
        XCTAssertEqual(engine.states[goalID]?.state, .unresolved)

        _ = engine.ingest(observation(.boolean(true), frame: 2))
        XCTAssertEqual(engine.states[goalID]?.state, .satisfied)
    }

    func test_dirty_propagates_transitively() {
        let a = GoalID("a")
        let b = GoalID("b")
        let c = GoalID("c")
        let definitions = [
            goal(id: a),
            goal(id: b, dependencies: [a]),
            goal(id: c, dependencies: [b]),
        ]
        let engine = GoalEngine(definitions)
        for id in [b, c] {
            engine.clearDirty(id)
        }

        engine.propagateDirty(from: a)

        XCTAssertTrue(engine.states[b]?.dirty == true)
        XCTAssertTrue(engine.states[c]?.dirty == true)
    }

    func test_done_requests_verification() {
        let planner = ActionPlanner()
        var transaction: ActionInstance? = ActionInstance(action())

        planner.apply(.done, transaction: &transaction)

        XCTAssertEqual(transaction?.state, .verifyRequested)
        XCTAssertEqual(planner.lastOutcome, .verifyRequested)
        XCTAssertTrue(planner.needsReobserve)
        XCTAssertFalse(planner.temporaryViolationWindowOpen)
    }

    func test_done_waits_for_a_new_observation_before_replanning() {
        let session = GuidanceSession(goals: [goal()], actions: [action()])
        session.engine.enterFrames = 1
        session.engine.exitFrames = 1
        _ = session.ingest(observation(.boolean(false), frame: 10))
        var transaction: ActionInstance? = ActionInstance(action())

        session.handle(.done, transaction: &transaction)
        XCTAssertEqual(session.tick(), .wait)

        _ = session.ingest(observation(.boolean(true), frame: 11))
        XCTAssertEqual(session.tick(), .ready)
    }

    func test_user_satisfied_does_not_hide_failed_hard_guard() {
        let hardGoal = goal(constraint: .hard)
        let session = GuidanceSession(goals: [hardGoal], actions: [action()])
        session.engine.enterFrames = 1
        session.engine.exitFrames = 1
        _ = session.ingest(observation(.boolean(false)))
        var transaction: ActionInstance?

        session.handle(.satisfied, transaction: &transaction)

        XCTAssertEqual(session.tick(), .propose(action()))
    }

    func test_known_active_goal_can_progress_while_noncritical_goal_is_unknown() {
        let activeID = GoalID("active")
        let unknownID = GoalID("unknown")
        let activeGoal = goal(id: activeID)
        let unknownGoal = GoalDefinition(
            id: unknownID,
            dimension: DimensionID("semantic"),
            binding: binding,
            target: .ordinal(0),
            constraint: .core
        )
        let candidate = action("fix-active", affects: [activeID])
        let session = GuidanceSession(goals: [activeGoal, unknownGoal], actions: [candidate])
        session.engine.enterFrames = 1
        session.engine.exitFrames = 1
        _ = session.ingest(observation(.boolean(false)))

        XCTAssertEqual(session.tick(), .propose(candidate))
    }

    func test_lock_event_updates_policy() {
        let engine = GoalEngine([goal()])
        let planner = ActionPlanner()
        var transaction: ActionInstance?

        planner.apply(.lock(goalID), transaction: &transaction, engine: engine)

        XCTAssertEqual(engine.states[goalID]?.policy, .locked)
        XCTAssertEqual(planner.lastOutcome, .goalLocked(goalID))
    }

    func test_freshness_rejects_binding_change() {
        XCTAssertFalse(
            FreshnessEvaluator().accepts(
                result: observation(.boolean(true), bindingVersion: 1),
                currentFrame: 1,
                currentBindingVersion: 2,
                currentSceneRevision: 0
            )
        )
    }

    func test_freshness_rejects_scene_change() {
        XCTAssertFalse(
            FreshnessEvaluator().accepts(
                result: observation(.boolean(true), scene: 1),
                currentFrame: 1,
                currentBindingVersion: 0,
                currentSceneRevision: 4
            )
        )
    }

    func test_freshness_accepts_current_result() {
        XCTAssertTrue(
            FreshnessEvaluator().accepts(
                result: observation(.boolean(true), frame: 10, bindingVersion: 2, scene: 3),
                currentFrame: 12,
                currentBindingVersion: 2,
                currentSceneRevision: 3
            )
        )
    }

    func test_ordinal_distribution_uses_expected_utility() {
        let result = Scoring.evaluate(
            observation(.ordinal(2), distribution: ["0": 0.75, "2": 0.25]),
            target: .ordinal(0)
        )

        XCTAssertGreaterThan(result.score, 0.8)
        XCTAssertLessThan(result.score, 1)
    }

    func test_validator_missing_dimension() {
        let issues = RecipeValidator().validate(goals: [goal()], dimensions: [], actions: [])
        XCTAssertTrue(issues.contains { $0.rule == .missingDimensionReference })
    }

    func test_validator_missing_dependency() {
        let issues = RecipeValidator().validate(
            goals: [goal(dependencies: [GoalID("missing")])],
            dimensions: [dimensionID],
            actions: []
        )
        XCTAssertTrue(issues.contains { $0.rule == .missingDependencyReference })
    }

    func test_validator_cycle() {
        let a = GoalID("a")
        let b = GoalID("b")
        let definitions = [goal(id: a, dependencies: [b]), goal(id: b, dependencies: [a])]
        let issues = RecipeValidator().validate(
            goals: definitions,
            dimensions: [dimensionID],
            actions: []
        )

        XCTAssertTrue(issues.contains { $0.rule == .hardDependencyCycle })
    }

    func test_validator_unsafe_required_action() {
        let issues = RecipeValidator().validate(
            goals: [goal(constraint: .hard)],
            dimensions: [dimensionID],
            actions: [action(safe: false)]
        )

        XCTAssertTrue(issues.contains { $0.rule == .unsafeOnlyRequiredActions })
        XCTAssertTrue(issues.contains { $0.rule == .impossibleReadiness })
    }

    func test_validator_invalid_cancellation() {
        let issues = RecipeValidator().validate(
            goals: [goal()],
            dimensions: [dimensionID],
            actions: [action()],
            cancellationAllowed: false
        )
        XCTAssertTrue(issues.contains { $0.rule == .invalidCancellationRestriction })
    }

    func test_validator_missing_action_coverage() {
        let issues = RecipeValidator().validate(
            goals: [goal()],
            dimensions: [dimensionID],
            actions: []
        )
        XCTAssertTrue(issues.contains { $0.rule == .missingActionCoverage })
    }

    func test_validator_detects_contradictory_hard_goals() {
        let first = goal(id: GoalID("a"), target: .boolean(true), constraint: .hard)
        let second = goal(id: GoalID("b"), target: .boolean(false), constraint: .hard)
        let issues = RecipeValidator().validate(
            goals: [first, second],
            dimensions: [dimensionID],
            actions: [
                action("first", affects: [first.id]),
                action("second", affects: [second.id]),
            ]
        )

        XCTAssertTrue(issues.contains { $0.rule == .contradictoryGoals })
    }

    func test_validator_marks_hard_goal_without_action_impossible() {
        let issues = RecipeValidator().validate(
            goals: [goal(constraint: .hard)],
            dimensions: [dimensionID],
            actions: []
        )
        XCTAssertTrue(issues.contains { $0.rule == .impossibleReadiness })
    }

    func test_scoring_target_band() {
        let target = TargetBand(ideal: 0...1, acceptable: -1...2)
        XCTAssertEqual(Scoring.band(0.5, target), 1)
        XCTAssertEqual(Scoring.band(-1, target), 0)
        XCTAssertEqual(Scoring.band(2, target), 0)
    }

    func test_observation_roundTripsThroughCodable() throws {
        let original = observation(
            .ordinal(1),
            frame: 42,
            bindingVersion: 3,
            scene: 7,
            distribution: ["0": 0.2, "1": 0.8]
        )
        let decoded = try JSONDecoder().decode(
            Observation.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
