import XCTest

@testable import GuidanceCore

final class GuidanceCoreTests: XCTestCase {
  let g = GoalID("g")
  let d = DimensionID("std.node.exists")
  let n = NodeID("primary")

  func goal(
    id: GoalID? = nil,
    dimension: DimensionID? = nil,
    target: GoalTarget = .boolean(true),
    constraint: ConstraintClass = .core,
    stability: StabilityPolicy = .init(),
    skippable: Bool? = nil
  ) -> GoalDefinition {
    GoalDefinition(
      id: id ?? g,
      dimension: dimension ?? d,
      binding: .node(n),
      target: target,
      constraint: constraint,
      stability: stability,
      skippable: skippable
    )
  }

  func obs(
    _ value: DimensionValue, dimension: DimensionID? = nil, confidence: Double = 1, frame: Int = 1
  ) -> Observation {
    Observation(
      dimension: dimension ?? d, binding: .node(n), value: value, confidence: confidence,
      frameID: frame)
  }

  func action(
    _ id: String = "a",
    goalID: GoalID? = nil,
    condition: ActionCondition? = nil,
    improvement: Double = 0.8,
    damage: Double = 0,
    safety: ActionSafetyClass = .safe,
    capability: String? = nil,
    family: String = "move"
  ) -> ActionDefinition {
    let goalID = goalID ?? g
    return ActionDefinition(
      id: ActionID(id),
      actor: .subject,
      operation: .move,
      direction: .right,
      coordinateFrame: .imageSpace,
      condition: condition ?? .goalUnsatisfied(goalID),
      effects: [.init(goal: goalID, expectedImprovement: improvement, possibleDamage: damage)],
      burden: 0.1,
      family: family,
      requiredCapability: capability,
      safety: safety,
      presentationKey: "subject.move.right"
    )
  }

  func makeActive(_ engine: GoalEngine, frame: Int = 1) {
    engine.enterFramesOverride = 1
    engine.exitFramesOverride = 1
    _ = engine.ingest(obs(.boolean(false), frame: frame))
  }

  func test_initial_reliable_mid_score_becomes_active_not_unresolved() {
    let dimension = DimensionID("std.node.visual_scale")
    let definition = goal(
      dimension: dimension,
      target: .band(.init(ideal: 0.2...0.3, acceptable: 0.1...0.4)),
      stability: .init(enterThreshold: 0.9, exitThreshold: 0.7)
    )
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.continuous(0.12), dimension: dimension))
    XCTAssertEqual(engine.states[g]?.state, .active)
  }

  func test_hysteresis_keeps_satisfied_until_exit_frames() {
    let engine = GoalEngine([
      goal(stability: .init(enterThreshold: 0.8, exitThreshold: 0.6, enterFrames: 1, exitFrames: 2))
    ])
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)
    _ = engine.ingest(obs(.boolean(false), frame: 2))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)
    _ = engine.ingest(obs(.boolean(false), frame: 3))
    XCTAssertEqual(engine.states[g]?.state, .drifted)
  }

  func test_low_confidence_is_unknown_not_failure() {
    let engine = GoalEngine([goal()])
    _ = engine.ingest(obs(.boolean(false), confidence: 0.2))
    XCTAssertEqual(engine.states[g]?.state, .unknown)
    XCTAssertNil(engine.states[g]?.score)
  }

  func test_soft_goal_does_not_block_ready() {
    let coreID = GoalID("core")
    let softID = GoalID("soft")
    let core = goal(id: coreID, constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let soft = goal(id: softID, constraint: .soft, stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(
      goals: [core, soft], actions: [action("fix-soft", goalID: softID)])
    session.engine.enterFramesOverride = 1
    session.engine.exitFramesOverride = 1
    _ = session.ingest(obs(.boolean(true), frame: 1))
    // Both goals share dimension/binding, so mark soft active explicitly for the readiness semantics test.
    session.engine.setState(.active, for: softID)
    XCTAssertEqual(session.tick(), .ready)
  }

  func test_hard_goal_blocks_user_satisfied() {
    let hard = goal(constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(goals: [hard], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false)))
    session.handle(.satisfied)
    XCTAssertEqual(session.tick(), .propose(action()))
  }

  func test_hard_goal_cannot_be_skipped_by_default() {
    let hard = goal(constraint: .hard)
    let session = GuidanceSession(goals: [hard], actions: [action()])
    session.handle(.skip(g))
    XCTAssertEqual(session.engine.states[g]?.policy, .normal)
  }

  func test_cancel_never_rolls_back_and_requests_reobserve() {
    let session = GuidanceSession(goals: [goal()], actions: [action()])
    makeActive(session.engine)
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.cancel)
    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.state, .cancelled)
    XCTAssertTrue(session.planner.needsReobserve)
  }

  func test_done_verifies_effect_and_detects_opposite() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.done)
    XCTAssertEqual(session.currentTransaction?.state, .verifyRequested)
    // Still false => no effect.
    _ = session.ingest(obs(.boolean(false), frame: 2))
    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.verification, .noEffect)
  }

  func test_action_condition_filters_wrong_direction() {
    let dim = DimensionID("std.node.position_x")
    let definition = goal(
      dimension: dim, target: .band(.init(ideal: 0.5...0.6, acceptable: 0.4...0.7)),
      stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.continuous(0.2), dimension: dim))
    let correct = action("right", condition: .continuousBelow(g, 0.5))
    let wrong = action("left", condition: .continuousAbove(g, 0.6))
    let planner = ActionPlanner()
    XCTAssertEqual(planner.rank([wrong, correct], engine: engine).map(\.id), [ActionID("right")])
  }

  func test_capability_required_action_is_filtered() {
    let engine = GoalEngine([goal()])
    makeActive(engine)
    let planner = ActionPlanner()
    let zoom = action("zoom", capability: "zoom.2x")
    XCTAssertTrue(planner.rank([zoom], engine: engine).isEmpty)
    planner.capabilities.insert("zoom.2x")
    XCTAssertEqual(planner.rank([zoom], engine: engine).first?.id, ActionID("zoom"))
  }

  func test_locked_goal_rejects_damaging_action() {
    let engine = GoalEngine([goal()])
    makeActive(engine)
    let planner = ActionPlanner()
    planner.lockedGoals.insert(g)
    XCTAssertTrue(planner.rank([action(damage: 0.5)], engine: engine).isEmpty)
  }

  func test_impossible_blocks_family() {
    let session = GuidanceSession(goals: [goal()], actions: [action()])
    makeActive(session.engine)
    _ = session.tick()
    session.handle(.impossible)
    XCTAssertTrue(session.planner.constraints.contains(.init(family: "move")))
    XCTAssertEqual(session.tick(), .unreachable)
  }

  func test_decline_prefers_alternative() {
    let a = action("a", family: "a")
    let b = action("b", family: "b")
    let session = GuidanceSession(goals: [goal()], actions: [a, b])
    makeActive(session.engine)
    XCTAssertEqual(session.tick(), .propose(a))
    session.handle(.anotherWay)
    XCTAssertEqual(session.tick(), .propose(b))
  }

  func test_freshness_rejects_binding_and_scene_changes() {
    let result = Observation(
      dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 10,
      bindingVersion: 2, sceneRevision: 3)
    let gate = FreshnessEvaluator()
    XCTAssertTrue(
      gate.accepts(
        result: result, currentFrame: 12, currentBindingVersion: 2, currentSceneRevision: 3))
    XCTAssertFalse(
      gate.accepts(
        result: result, currentFrame: 12, currentBindingVersion: 3, currentSceneRevision: 3))
    XCTAssertFalse(
      gate.accepts(
        result: result, currentFrame: 12, currentBindingVersion: 2, currentSceneRevision: 4))
  }

  func test_validator_rejects_unknown_dimension() {
    let unknown = GoalDefinition(
      id: g, dimension: DimensionID("nope"), binding: .node(n), target: .boolean(true),
      constraint: .core)
    let issues = RecipeValidator().validate(
      goals: [unknown], actions: [action()], registry: testRegistry())
    XCTAssertTrue(
      issues.contains { $0.rule == .missingDimensionReference && $0.severity == .error })
  }

  func test_validator_rejects_scope_mismatch() {
    let goal = GoalDefinition(
      id: g, dimension: DimensionID("std.relation.relative_scale"), binding: .node(n),
      target: .ordinal(0), constraint: .core)
    let issues = RecipeValidator().validate(
      goals: [goal], actions: [action()], registry: testRegistry())
    XCTAssertTrue(issues.contains { $0.rule == .incompatibleBindingScope })
  }

  func test_ordinal_distribution_is_normalized() {
    let observation = Observation(
      dimension: DimensionID("std.pose.body_orientation"),
      binding: .node(n),
      value: .ordinal(2),
      confidence: 1,
      evaluator: EvaluatorID("djev.semantic"),
      distribution: ["0": 3, "2": 1],
      frameID: 1
    )
    let result = Scoring.evaluate(observation, target: .ordinal(0))
    XCTAssertGreaterThan(result.score, 0.8)
    XCTAssertLessThan(result.score, 1)
  }

  func test_evaluation_planner_batches_semantic_slots() {
    let poseGoal = GoalDefinition(
      id: GoalID("pose"),
      dimension: DimensionID("std.pose.body_orientation"),
      binding: .node(n),
      target: .ordinal(0),
      constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([poseGoal])
    _ = engine.ingest(
      Observation(
        dimension: poseGoal.dimension,
        binding: poseGoal.binding,
        value: .ordinal(2),
        confidence: 0.60,
        evaluator: EvaluatorID("vision.local"),
        frameID: 1
      ))
    let plan = EvaluationPlanner().plan(engine: engine, registry: testRegistry())
    XCTAssertTrue(plan.local.contains { $0.dimension == poseGoal.dimension })
    XCTAssertTrue(plan.semantic.contains { $0.dimension == poseGoal.dimension })
  }

  func test_dependency_keeps_downstream_inactive_until_parent_satisfied() {
    let parentID = GoalID("parent")
    let childID = GoalID("child")
    let parent = goal(id: parentID, stability: .init(enterFrames: 1, exitFrames: 1))
    let child = GoalDefinition(
      id: childID,
      dimension: d,
      binding: .node(n),
      target: .boolean(true),
      constraint: .core,
      dependencies: [parentID],
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([parent, child])
    _ = engine.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(engine.states[childID]?.state, .inactive)
    _ = engine.ingest(obs(.boolean(true), frame: 2))
    XCTAssertEqual(engine.states[parentID]?.state, .satisfied)
    // Same observation also updates child after parent in the next ingest pass.
    _ = engine.ingest(obs(.boolean(true), frame: 3))
    XCTAssertEqual(engine.states[childID]?.state, .satisfied)
  }

  func test_unknown_core_does_not_block_known_actionable_core() {
    let activeID = GoalID("active")
    let unknownID = GoalID("unknown")
    let activeDimension = DimensionID("std.node.exists")
    let semanticDimension = DimensionID("std.pose.body_orientation")
    let activeGoal = GoalDefinition(
      id: activeID,
      dimension: activeDimension,
      binding: .node(n),
      target: .boolean(true),
      constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let unknownGoal = GoalDefinition(
      id: unknownID,
      dimension: semanticDimension,
      binding: .node(n),
      target: .ordinal(0),
      constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let fix = action("fix-active", goalID: activeID)
    let session = GuidanceSession(goals: [activeGoal, unknownGoal], actions: [fix])
    _ = session.ingest(obs(.boolean(false), dimension: activeDimension, frame: 1))
    _ = session.ingest(
      Observation(
        dimension: semanticDimension,
        binding: .node(n),
        value: .ordinal(0),
        confidence: 0.1,
        frameID: 1
      ))

    XCTAssertEqual(session.engine.states[activeID]?.state, .active)
    XCTAssertEqual(session.engine.states[unknownID]?.state, .unknown)
    XCTAssertEqual(session.tick(), .propose(fix))
  }

  func test_no_feasible_core_action_is_best_reachable_ready_when_hard_is_satisfied() {
    let hardID = GoalID("hard")
    let coreID = GoalID("core")
    let hard = goal(
      id: hardID, constraint: .hard,
      stability: .init(enterFrames: 1, exitFrames: 1))
    let core = goal(
      id: coreID, constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(goals: [hard, core], actions: [])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(true), frame: 1))
    session.engine.setState(.active, for: coreID)

    XCTAssertEqual(session.tick(), .ready)
  }

  func test_current_instruction_stays_stable_while_target_remains_active() {
    let definition = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let first = action("first", improvement: 0.9)
    let second = action("second", improvement: 0.8)
    let session = GuidanceSession(goals: [definition], actions: [first, second])
    makeActive(session.engine)
    XCTAssertEqual(session.tick(), .propose(first))

    // Make the second action look better after the proposal. The visible
    // instruction should still stay pinned until the current target resolves
    // or the user asks for another method.
    session.planner.memory.declinePenalty[second.id] = 0
    XCTAssertEqual(session.tick(), .propose(first))
  }

  func test_unknown_parent_invalidates_satisfied_dependent() {
    let parentID = GoalID("parent")
    let childID = GoalID("child")
    let parent = goal(
      id: parentID, stability: .init(enterFrames: 1, exitFrames: 1))
    let child = GoalDefinition(
      id: childID,
      dimension: d,
      binding: .node(n),
      target: .boolean(true),
      constraint: .core,
      dependencies: [parentID],
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([parent, child])
    engine.enterFramesOverride = 1
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    _ = engine.ingest(obs(.boolean(true), frame: 2))
    XCTAssertEqual(engine.states[parentID]?.state, .satisfied)
    XCTAssertEqual(engine.states[childID]?.state, .satisfied)

    _ = engine.ingest(obs(.boolean(true), confidence: 0.1, frame: 3))
    XCTAssertEqual(engine.states[parentID]?.state, .unknown)
    XCTAssertEqual(engine.states[childID]?.state, .inactive)
  }

  func test_same_frame_multiple_evaluators_do_not_double_count_stability() {
    let definition = goal(
      stability: .init(enterThreshold: 0.8, exitThreshold: 0.6, enterFrames: 2, exitFrames: 2))
    let engine = GoalEngine([definition])

    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95,
        evaluator: EvaluatorID("vision.local"), frameID: 10))
    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95,
        evaluator: EvaluatorID("djev.semantic"), frameID: 10))

    XCTAssertNotEqual(engine.states[g]?.state, .satisfied)
    XCTAssertEqual(engine.states[g]?.enterCounter, 1)

    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95,
        evaluator: EvaluatorID("vision.local"), frameID: 11))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)
  }

  func test_out_of_order_observation_is_ignored() {
    let definition = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.boolean(true), frame: 20))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)

    let updated = engine.ingest(obs(.boolean(false), frame: 19))
    XCTAssertTrue(updated.isEmpty)
    XCTAssertEqual(engine.states[g]?.state, .satisfied)
    XCTAssertEqual(engine.observation(for: g)?.frameID, 20)
  }

  func test_binding_revision_resets_prior_satisfaction() {
    let definition = goal(stability: .init(enterFrames: 2, exitFrames: 1))
    let engine = GoalEngine([definition])
    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1,
        frameID: 1, bindingVersion: 1))
    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1,
        frameID: 2, bindingVersion: 1))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)

    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1,
        frameID: 3, bindingVersion: 2))
    XCTAssertEqual(engine.states[g]?.state, .unresolved)
    XCTAssertEqual(engine.states[g]?.enterCounter, 1)

    _ = engine.ingest(
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1,
        frameID: 4, bindingVersion: 2))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)
  }

  func test_observation_fusion_reduces_confidence_on_disagreement() {
    let vision = Observation(
      dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.9,
      evaluator: EvaluatorID("vision.local"), frameID: 1)
    let semantic = Observation(
      dimension: d, binding: .node(n), value: .boolean(false), confidence: 0.9,
      evaluator: EvaluatorID("djev.semantic"), frameID: 1)
    let fused = ObservationFusion().fuse([vision, semantic])
    XCTAssertNotNil(fused)
    XCTAssertLessThan(fused?.confidence ?? 1, 0.6)
  }

  func test_topological_evaluation_allows_child_to_update_in_same_ingest() {
    let parentID = GoalID("parent")
    let childID = GoalID("child")
    let parent = goal(id: parentID, stability: .init(enterFrames: 1, exitFrames: 1))
    let child = GoalDefinition(
      id: childID,
      dimension: d,
      binding: .node(n),
      target: .boolean(true),
      constraint: .core,
      dependencies: [parentID],
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([child, parent])
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    XCTAssertEqual(engine.states[parentID]?.state, .satisfied)
    XCTAssertEqual(engine.states[childID]?.state, .satisfied)
  }

  func test_context_dependent_action_requires_explicit_safety_clearance() {
    let engine = GoalEngine([goal(stability: .init(enterFrames: 1, exitFrames: 1))])
    makeActive(engine)
    let risky = action("back", safety: .contextDependent, family: "camera.backward")
    let planner = ActionPlanner()
    XCTAssertTrue(planner.rank([risky], engine: engine).isEmpty)
    planner.grantSafetyClearance(for: "camera.backward")
    XCTAssertEqual(planner.rank([risky], engine: engine).first?.id, risky.id)
  }

  func test_repeated_opposite_effects_pause_guidance() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))],
      actions: [action()]
    )
    makeActive(session.engine)
    session.planner.memory.oppositeEffects = 2
    XCTAssertEqual(session.tick(), .paused)
  }

  func test_readiness_floor_prevents_good_goals_hiding_one_bad_core_goal() {
    let ids = [GoalID("a"), GoalID("b"), GoalID("c")]
    let dims = [DimensionID("a"), DimensionID("b"), DimensionID("c")]
    let goals = zip(ids, dims).map { id, dim in
      GoalDefinition(
        id: id, dimension: dim, binding: .node(n),
        target: .band(.init(ideal: 0.8...1.0, acceptable: 0.0...1.0)),
        constraint: .core, importance: 1,
        stability: .init(enterThreshold: 0.95, exitThreshold: 0.5, enterFrames: 1, exitFrames: 1)
      )
    }
    let engine = GoalEngine(goals)
    _ = engine.ingest(
      Observation(
        dimension: dims[0], binding: .node(n), value: .continuous(0.99), confidence: 1, frameID: 1))
    _ = engine.ingest(
      Observation(
        dimension: dims[1], binding: .node(n), value: .continuous(0.99), confidence: 1, frameID: 1))
    _ = engine.ingest(
      Observation(
        dimension: dims[2], binding: .node(n), value: .continuous(0.10), confidence: 1, frameID: 1))
    let assessment = ReadinessPolicy().assess(engine: engine)
    XCTAssertFalse(assessment.automaticReady)
    XCTAssertLessThan(assessment.minimumCoreScore ?? 1, 0.62)
  }

  func test_hard_failure_preempts_higher_total_core_gain() {
    let hardID = GoalID("hard")
    let coreA = GoalID("coreA")
    let coreB = GoalID("coreB")
    let hard = goal(id: hardID, constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let a = goal(id: coreA, constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let b = goal(id: coreB, constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let hardAction = action("hard-fix", goalID: hardID, improvement: 0.3, family: "hard")
    let coreAction = ActionDefinition(
      id: ActionID("core-fix"), actor: .subject, operation: .move,
      condition: .always,
      effects: [
        .init(goal: coreA, expectedImprovement: 1),
        .init(goal: coreB, expectedImprovement: 1),
      ],
      family: "core", presentationKey: "core"
    )
    let session = GuidanceSession(goals: [hard, a, b], actions: [hardAction, coreAction])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(session.tick(), .propose(hardAction))
  }

  func test_reset_user_overrides_clears_locks_skips_constraints_and_safety() {
    let session = GuidanceSession(goals: [goal(skippable: true)], actions: [action()])
    makeActive(session.engine)
    _ = session.tick()
    session.handle(.lock(g))
    session.handle(.skip(g))
    session.planner.constraints.insert(.init(family: "x"))
    session.grantSafetyClearance(for: "camera.backward")

    session.resetUserOverrides()
    XCTAssertEqual(session.engine.states[g]?.policy, .normal)
    XCTAssertTrue(session.planner.lockedGoals.isEmpty)
    XCTAssertTrue(session.planner.constraints.isEmpty)
    XCTAssertTrue(session.planner.safetyClearances.isEmpty)
  }

  func test_session_snapshot_and_trace_are_deterministic_debug_surfaces() {
    let session = GuidanceSession(goals: [goal()], actions: [action()])
    makeActive(session.engine)
    _ = session.tick()
    let snapshot = session.snapshot()
    XCTAssertEqual(snapshot.currentActionID, ActionID("a"))
    XCTAssertEqual(snapshot.lastObservedFrame, 0)
    XCTAssertTrue(session.trace.contains { $0.category == .decision })
  }

  func test_validator_detects_duplicate_registry_and_evaluator_mismatch() {
    let badDimension = DimensionDefinition(
      id: DimensionID("custom"), name: "x", description: "x", scope: .node,
      valueType: .boolean, evaluatorIDs: [EvaluatorID("wrong")])
    let wrongEvaluator = EvaluatorDefinition(
      id: EvaluatorID("wrong"), supportedDimensions: [DimensionID("other")],
      kind: .localVision, latency: .realtime, cost: .low)
    let node = NodeDefinition(id: n, type: .entity)
    let registry = GuidanceRegistry(
      nodes: [node, node], dimensions: [badDimension], evaluators: [wrongEvaluator])
    let definition = GoalDefinition(
      id: g, dimension: badDimension.id, binding: .node(n), target: .boolean(true),
      constraint: .core)
    let issues = RecipeValidator().validate(
      goals: [definition], actions: [action()], registry: registry)
    XCTAssertTrue(issues.contains { $0.rule == .duplicateRegistryID })
    XCTAssertTrue(issues.contains { $0.rule == .evaluatorDoesNotSupportDimension })
  }

  func test_temporal_stabilizer_turns_semantic_flapping_into_low_confidence() {
    var stabilizer = ObservationStabilizer()
    let dim = DimensionID("semantic")
    let evaluator = EvaluatorID("djev.semantic")
    var latest: StabilizedObservation?
    for (frame, value) in [(1, -2), (2, 2), (3, -2), (4, 2)] {
      latest = stabilizer.ingest(
        Observation(
          dimension: dim, binding: .node(n), value: .ordinal(value), confidence: 0.95,
          evaluator: evaluator, frameID: frame))
    }
    XCTAssertFalse(latest?.isStable ?? true)
    XCTAssertLessThan(latest?.observation.confidence ?? 1, 0.5)
    XCTAssertGreaterThan(latest?.instability ?? 0, 0.7)
  }

  func test_temporal_stabilizer_accepts_consistent_semantic_evidence() {
    var stabilizer = ObservationStabilizer()
    let dim = DimensionID("semantic")
    let evaluator = EvaluatorID("djev.semantic")
    var latest: StabilizedObservation?
    for frame in 1...4 {
      latest = stabilizer.ingest(
        Observation(
          dimension: dim, binding: .node(n), value: .ordinal(0), confidence: 0.9,
          evaluator: evaluator, distribution: ["0": 0.9, "1": 0.1], frameID: frame))
    }
    XCTAssertTrue(latest?.isStable ?? false)
    XCTAssertGreaterThan(latest?.observation.confidence ?? 0, 0.6)
  }

  func test_role_binding_store_does_not_silently_swap_sticky_subject() {
    var store = RoleBindingStore(defaultPolicy: .sticky)
    XCTAssertTrue(store.bind(node: n, to: TrackID("person-1"), confidence: 0.9))
    let version = store.version
    XCTAssertFalse(store.bind(node: n, to: TrackID("person-2"), confidence: 0.95))
    XCTAssertEqual(store.binding(for: n)?.track, TrackID("person-1"))
    XCTAssertEqual(store.version, version)
    XCTAssertTrue(store.bind(node: n, to: TrackID("person-2"), confidence: 0.95, confirmed: true))
    XCTAssertGreaterThan(store.version, version)
  }

  func test_freshness_rejects_wall_clock_stale_result() {
    let old = Observation(
      dimension: d, binding: .node(n), value: .boolean(true), confidence: 1,
      frameID: 10, timestamp: Date(timeIntervalSince1970: 100))
    var gate = FreshnessEvaluator()
    gate.maxAge = 1
    XCTAssertFalse(
      gate.accepts(
        result: old, currentFrame: 10, currentBindingVersion: 0, currentSceneRevision: 0,
        now: Date(timeIntervalSince1970: 102)))
  }

  func test_delayed_semantic_evidence_can_fuse_with_newer_local_frame() {
    let poseDimension = DimensionID("std.pose.body_orientation")
    let definition = GoalDefinition(
      id: g, dimension: poseDimension, binding: .node(n), target: .ordinal(0),
      constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    engine.maximumFusionFrameDelta = 6

    _ = engine.ingest(
      Observation(
        dimension: poseDimension, binding: .node(n), value: .ordinal(2), confidence: 0.65,
        evaluator: EvaluatorID("vision.local"), frameID: 12))
    let updated = engine.ingest(
      Observation(
        dimension: poseDimension, binding: .node(n), value: .ordinal(0), confidence: 0.95,
        evaluator: EvaluatorID("djev.semantic"), distribution: ["0": 0.9, "1": 0.1], frameID: 9))

    XCTAssertEqual(updated, [g])
    XCTAssertEqual(engine.observation(for: g)?.frameID, 12)
    XCTAssertEqual(engine.observation(for: g)?.evaluator, EvaluatorID("core.fusion"))
  }

  func test_delayed_semantic_evidence_beyond_fusion_window_is_rejected() {
    let poseDimension = DimensionID("std.pose.body_orientation")
    let definition = GoalDefinition(
      id: g, dimension: poseDimension, binding: .node(n), target: .ordinal(0),
      constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    engine.maximumFusionFrameDelta = 3
    _ = engine.ingest(
      Observation(
        dimension: poseDimension, binding: .node(n), value: .ordinal(2), confidence: 0.8,
        evaluator: EvaluatorID("vision.local"), frameID: 20))
    let updated = engine.ingest(
      Observation(
        dimension: poseDimension, binding: .node(n), value: .ordinal(0), confidence: 0.95,
        evaluator: EvaluatorID("djev.semantic"), frameID: 10))
    XCTAssertTrue(updated.isEmpty)
  }

  func test_runtime_actor_serializes_session_mutation() async {
    let runtime = GuidanceRuntimeActor(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))],
      actions: [action()])
    _ = await runtime.ingest(obs(.boolean(false), frame: 1))
    let decision = await runtime.tick()
    XCTAssertEqual(decision, .propose(action()))
    let snapshot = await runtime.snapshot()
    XCTAssertEqual(snapshot.currentActionID, ActionID("a"))
  }

  func test_batch_evaluates_cross_dimension_dependencies_in_topological_order() {
    let parentID = GoalID("parent.cross")
    let childID = GoalID("child.cross")
    let parentDimension = DimensionID("z.parent")
    let childDimension = DimensionID("a.child")
    let parent = GoalDefinition(
      id: parentID, dimension: parentDimension, binding: .node(n), target: .boolean(true),
      constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let child = GoalDefinition(
      id: childID, dimension: childDimension, binding: .node(n),
      target: .band(.init(ideal: 0.4...0.6, acceptable: 0.2...0.8)),
      constraint: .core, dependencies: [parentID],
      stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([child, parent])

    _ = engine.ingestBatch([
      Observation(
        dimension: childDimension, binding: .node(n), value: .continuous(0.5),
        confidence: 1, frameID: 10),
      Observation(
        dimension: parentDimension, binding: .node(n), value: .boolean(true),
        confidence: 1, frameID: 10),
    ])

    XCTAssertEqual(engine.states[parentID]?.state, .satisfied)
    XCTAssertEqual(engine.states[childID]?.state, .satisfied)
  }

  func test_reenabling_skipped_parent_restores_dependency_gate() {
    let parentID = GoalID("parent.skip")
    let childID = GoalID("child.skip")
    let parent = goal(
      id: parentID, stability: .init(enterFrames: 1, exitFrames: 1),
      skippable: true)
    let child = GoalDefinition(
      id: childID, dimension: d, binding: .node(n), target: .boolean(true),
      constraint: .core, dependencies: [parentID],
      stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([parent, child])
    _ = engine.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(engine.states[childID]?.state, .inactive)

    engine.setPolicy(.skipped, for: parentID)
    XCTAssertEqual(engine.states[childID]?.state, .unresolved)
    engine.setPolicy(.normal, for: parentID)
    XCTAssertEqual(engine.states[childID]?.state, .inactive)
  }

  func test_observation_contract_rejects_wrong_type_range_and_evaluator() {
    let registry = testRegistry()
    let validator = ObservationValidator()
    let observation = Observation(
      dimension: DimensionID("std.node.position_x"), binding: .node(n),
      value: .continuous(1.5), confidence: 0.9,
      evaluator: EvaluatorID("djev.semantic"), frameID: 1)
    let issues = validator.validate(observation, registry: registry)
    XCTAssertTrue(issues.contains { $0.rule == .valueOutsideDimensionSpace })
    XCTAssertTrue(issues.contains { $0.rule == .evaluatorDoesNotSupportDimension })

    let wrongType = Observation(
      dimension: DimensionID("std.node.position_x"), binding: .node(n),
      value: .boolean(true), confidence: 1,
      evaluator: EvaluatorID("vision.local"), frameID: 1)
    XCTAssertTrue(
      validator.validate(wrongType, registry: registry).contains { $0.rule == .valueTypeMismatch })
  }

  func test_session_rejects_invalid_runtime_observation_before_goal_engine() {
    let dimension = DimensionID("std.node.position_x")
    let definition = GoalDefinition(
      id: g, dimension: dimension, binding: .node(n),
      target: .band(.init(ideal: 0.4...0.6, acceptable: 0.2...0.8)),
      constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(goals: [definition], actions: [], registry: testRegistry())
    let updated = session.ingest(
      Observation(
        dimension: dimension, binding: .node(n), value: .continuous(1.4), confidence: 1,
        evaluator: EvaluatorID("vision.local"), frameID: 1))

    XCTAssertTrue(updated.isEmpty)
    XCTAssertEqual(session.rejectedObservations, 1)
    XCTAssertNil(session.engine.states[g]?.score)
    XCTAssertTrue(session.trace.contains { $0.category == .validation })
  }

  func test_verification_times_out_instead_of_holding_controller_forever() {
    let missingID = GoalID("missing-effect")
    let missingDimension = DimensionID("missing.dimension")
    let primary = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let missing = GoalDefinition(
      id: missingID, dimension: missingDimension, binding: .node(n), target: .boolean(true),
      constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let compound = ActionDefinition(
      id: ActionID("compound"), actor: .subject, operation: .move,
      effects: [
        .init(goal: g, expectedImprovement: 0.8),
        .init(goal: missingID, expectedImprovement: 0.5),
      ], family: "compound", presentationKey: "compound")
    let session = GuidanceSession(goals: [primary, missing], actions: [compound])
    session.verificationFrameTimeout = 2
    session.engine.enterFramesOverride = 1
    _ = session.ingestBatch([
      obs(.boolean(false), frame: 1),
      Observation(
        dimension: missingDimension, binding: .node(n), value: .boolean(false),
        confidence: 1, frameID: 1),
    ])
    XCTAssertEqual(session.tick(), .propose(compound))
    session.handle(.done)

    _ = session.ingest(obs(.boolean(true), frame: 2))
    XCTAssertNotNil(session.currentTransaction)
    _ = session.ingest(obs(.boolean(true), frame: 3))

    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.verification, .inconclusive)
    XCTAssertFalse(session.planner.needsReobserve)
  }

  func test_runtime_invariant_checker_accepts_dependency_gated_initial_state() {
    let parentID = GoalID("parent.invariant")
    let childID = GoalID("child.invariant")
    let parent = goal(id: parentID)
    let child = GoalDefinition(
      id: childID, dimension: DimensionID("child"), binding: .node(n), target: .boolean(true),
      constraint: .core, dependencies: [parentID])
    let engine = GoalEngine([parent, child])
    XCTAssertEqual(engine.states[childID]?.state, .inactive)
    XCTAssertTrue(RuntimeInvariantChecker().check(engine: engine, planner: ActionPlanner()).isEmpty)
  }

  func test_action_numeric_inputs_are_defensively_normalized() {
    let effect = ActionEffect(goal: g, expectedImprovement: 4, possibleDamage: .nan)
    XCTAssertEqual(effect.expectedImprovement, 1)
    XCTAssertEqual(effect.possibleDamage, 1)
    let definition = ActionDefinition(
      id: ActionID("numeric"), actor: .camera, operation: .zoom,
      effects: [effect], burden: .infinity, risk: -3, uncertainty: 2,
      family: "numeric", presentationKey: "numeric")
    XCTAssertEqual(definition.burden, 1)
    XCTAssertEqual(definition.risk, 0)
    XCTAssertEqual(definition.uncertainty, 1)
  }

  func test_validator_rejects_target_outside_dimension_value_space_and_safe_backward_motion() {
    let dimension = DimensionDefinition(
      id: DimensionID("bounded"), name: "bounded", description: "bounded", scope: .node,
      valueType: .continuous, valueSpace: .continuous(min: 0, max: 1, unit: nil),
      evaluatorIDs: [EvaluatorID("e")])
    let evaluator = EvaluatorDefinition(
      id: EvaluatorID("e"), supportedDimensions: [dimension.id], kind: .localVision,
      latency: .realtime, cost: .low)
    let registry = GuidanceRegistry(
      nodes: [NodeDefinition(id: n, type: .entity)], dimensions: [dimension],
      evaluators: [evaluator])
    let definition = GoalDefinition(
      id: g, dimension: dimension.id, binding: .node(n),
      target: .band(.init(ideal: 0.8...1.2, acceptable: 0.7...1.3)), constraint: .core)
    let backward = ActionDefinition(
      id: ActionID("unsafe-back"), actor: .photographer, operation: .move,
      direction: .backward, coordinateFrame: .photographerSpace,
      effects: [.init(goal: g, expectedImprovement: 0.5)], family: "back",
      safety: .safe, presentationKey: "back")
    let issues = RecipeValidator().validate(
      goals: [definition], actions: [backward], registry: registry)
    XCTAssertTrue(issues.contains { $0.rule == .targetOutsideDimensionSpace })
    XCTAssertTrue(issues.contains { $0.rule == .unsafeMovementDeclaredSafe })
  }

  func test_semantic_batch_validator_rejects_unsolicited_and_wrong_context_output() {
    let registry = testRegistry()
    let expected = EvaluationSlot(
      goalID: GoalID("pose"), dimension: DimensionID("std.pose.body_orientation"),
      binding: .node(n), cadence: .focus)
    let good = Observation(
      dimension: expected.dimension, binding: expected.binding, value: .ordinal(0), confidence: 0.9,
      evaluator: EvaluatorID("djev.semantic"), distribution: ["0": 0.9, "1": 0.1],
      frameID: 20, bindingVersion: 3, sceneRevision: 4)
    let unsolicited = Observation(
      dimension: DimensionID("std.relation.visual_balance"),
      binding: .relation(RelationID("other")), value: .ordinal(0), confidence: 0.9,
      evaluator: EvaluatorID("djev.semantic"), frameID: 20,
      bindingVersion: 3, sceneRevision: 4)
    let stale = Observation(
      dimension: expected.dimension, binding: expected.binding, value: .ordinal(0), confidence: 0.9,
      evaluator: EvaluatorID("djev.semantic"), frameID: 19,
      bindingVersion: 2, sceneRevision: 4)

    let result = SemanticBatchValidator().validate(
      observations: [good, unsolicited, stale], expectedSlots: [expected],
      frameID: 20, bindingVersion: 3, sceneRevision: 4, registry: registry)

    XCTAssertEqual(result.accepted, [good])
    XCTAssertTrue(result.issues.contains { $0.rule == .unsolicitedSlot })
    XCTAssertTrue(result.issues.contains { $0.rule == .duplicateSlot })
    XCTAssertTrue(result.issues.contains { $0.rule == .wrongFrame })
    XCTAssertTrue(result.issues.contains { $0.rule == .wrongBindingVersion })
  }

  func test_action_verifier_does_not_learn_success_when_hard_guard_regresses() {
    let coreID = GoalID("core.verify")
    let hardID = GoalID("hard.verify")
    let coreDim = DimensionID("core.dim")
    let hardDim = DimensionID("hard.dim")
    let core = GoalDefinition(
      id: coreID, dimension: coreDim, binding: .node(n),
      target: .band(.init(ideal: 0.8...1, acceptable: 0...1)), constraint: .core,
      stability: .init(enterThreshold: 0.9, exitThreshold: 0.5, enterFrames: 1, exitFrames: 1))
    let hard = GoalDefinition(
      id: hardID, dimension: hardDim, binding: .node(n), target: .boolean(true),
      constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([core, hard])
    _ = engine.ingestBatch([
      Observation(
        dimension: coreDim, binding: .node(n), value: .continuous(0.2), confidence: 1, frameID: 1),
      Observation(
        dimension: hardDim, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 1),
    ])
    let definition = ActionDefinition(
      id: ActionID("fix-core-break-hard"), actor: .subject, operation: .move,
      effects: [
        .init(goal: coreID, expectedImprovement: 0.9),
        .init(goal: hardID, expectedImprovement: 0, possibleDamage: 0.02),
      ], family: "verify", presentationKey: "verify")
    let planner = ActionPlanner()
    let instance = ActionInstance(
      definition,
      baselineScores: planner.baseline(for: definition, engine: engine),
      baselineEvidence: planner.baselineEvidence(for: definition, engine: engine))

    _ = engine.ingestBatch([
      Observation(
        dimension: coreDim, binding: .node(n), value: .continuous(0.9), confidence: 1, frameID: 2),
      Observation(
        dimension: hardDim, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 2),
    ])
    XCTAssertEqual(ActionVerifier().verify(instance, engine: engine), .oppositeEffect)
  }

  func test_observation_fusion_respects_evaluator_reliability_and_recency() {
    let dim = DimensionID("fusion.continuous")
    let local = Observation(
      dimension: dim, binding: .node(n), value: .continuous(0.2), confidence: 0.9,
      evaluator: EvaluatorID("local"), frameID: 20)
    let olderWeak = Observation(
      dimension: dim, binding: .node(n), value: .continuous(0.9), confidence: 0.9,
      evaluator: EvaluatorID("weak"), frameID: 15)
    let fused = ObservationFusion(
      evaluatorTrust: [EvaluatorID("local"): 1, EvaluatorID("weak"): 0.2],
      frameRecencyDecay: 0.8
    ).fuse([local, olderWeak], allowFrameSkew: 6)
    guard case .continuous(let value)? = fused?.value else {
      return XCTFail("Expected continuous fusion")
    }
    XCTAssertLessThan(value, 0.3)
    XCTAssertEqual(fused?.frameID, 20)
  }

  func test_session_effect_model_learns_repeated_no_effect_and_prefers_fresh_alternative() {
    let engine = GoalEngine([goal(stability: .init(enterFrames: 1, exitFrames: 1))])
    makeActive(engine)
    let planner = ActionPlanner()
    let stale = action("stale", improvement: 0.8, family: "stale-family")
    let fresh = action("fresh", improvement: 0.72, family: "fresh-family")

    XCTAssertEqual(planner.rank([stale, fresh], engine: engine).first?.id, stale.id)
    planner.recordVerification(.noEffect, action: stale)
    planner.recordVerification(.noEffect, action: stale)
    planner.recordVerification(.noEffect, action: stale)

    XCTAssertLessThan(planner.memory.effectModel.gainMultiplier(for: stale), 0.8)
    XCTAssertEqual(planner.rank([stale, fresh], engine: engine).first?.id, fresh.id)
  }

  func test_session_effect_model_is_session_local_and_does_not_mutate_action_definition() {
    let original = action("learned", improvement: 0.8)
    let planner = ActionPlanner()
    planner.recordVerification(.oppositeEffect, action: original)
    planner.recordVerification(.oppositeEffect, action: original)

    XCTAssertEqual(original.effects.first?.expectedImprovement, 0.8)
    XCTAssertLessThan(planner.memory.effectModel.gainMultiplier(for: original), 1)
    XCTAssertEqual(ActionPlanner().memory.effectModel.gainMultiplier(for: original), 1)
  }

  func test_shared_root_cause_action_gets_small_coverage_bonus() {
    let g1 = GoalID("cluster.one")
    let g2 = GoalID("cluster.two")
    let d1 = DimensionID("cluster.dim.one")
    let d2 = DimensionID("cluster.dim.two")
    let first = GoalDefinition(
      id: g1, dimension: d1, binding: .node(n), target: .boolean(true), constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1))
    let second = GoalDefinition(
      id: g2, dimension: d2, binding: .node(n), target: .boolean(true), constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([first, second])
    _ = engine.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: d2, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])

    let shared = ActionDefinition(
      id: ActionID("shared"), actor: .camera, operation: .reframe,
      effects: [
        .init(goal: g1, expectedImprovement: 0.38),
        .init(goal: g2, expectedImprovement: 0.38),
      ], burden: 0.10, family: "shared", presentationKey: "shared")
    let one = ActionDefinition(
      id: ActionID("single"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g1, expectedImprovement: 0.72)],
      burden: 0.10, family: "single", presentationKey: "single")

    let planner = ActionPlanner()
    XCTAssertGreaterThan(
      planner.utility(shared, engine: engine), planner.utility(one, engine: engine))
  }

  func test_unknown_hard_goal_requests_evidence_instead_of_corrective_action() {
    let hard = goal(constraint: .hard)
    let session = GuidanceSession(goals: [hard], actions: [action()])
    let decision = session.tick()

    guard case .requestEvidence(let request) = decision else {
      return XCTFail("Expected explicit evidence request, got \(decision)")
    }
    XCTAssertEqual(request.reason, .hardGuardUnknown)
    XCTAssertEqual(request.goals, [g])
    XCTAssertEqual(session.readiness().state, .unknown)
  }

  func test_reachability_distinguishes_runtime_blocked_goal_from_unknown_goal() {
    let engine = GoalEngine([goal(stability: .init(enterFrames: 1, exitFrames: 1))])
    makeActive(engine)
    let planner = ActionPlanner()
    let unavailable = action("requires-lens", capability: "lens.2x")
    let assessment = ReachabilityAnalyzer().assess(
      engine: engine, planner: planner, actions: [unavailable])

    XCTAssertEqual(assessment.blockedCriticalGoals, [g])
    XCTAssertTrue(assessment.unknownCriticalGoals.isEmpty)
    planner.capabilities.insert("lens.2x")
    let reachable = ReachabilityAnalyzer().assess(
      engine: engine, planner: planner, actions: [unavailable])
    XCTAssertEqual(reachable.reachableCriticalGoals, [g])
    XCTAssertTrue(reachable.blockedCriticalGoals.isEmpty)
  }

  func test_action_reversal_pattern_triggers_oscillation_recovery() {
    let planner = ActionPlanner()
    let left = ActionDefinition(
      id: ActionID("left.osc"), actor: .photographer, operation: .move,
      direction: .left, coordinateFrame: .photographerSpace,
      effects: [.init(goal: g, expectedImprovement: 0.5)],
      family: "horizontal", presentationKey: "left")
    let right = ActionDefinition(
      id: ActionID("right.osc"), actor: .photographer, operation: .move,
      direction: .right, coordinateFrame: .photographerSpace,
      effects: [.init(goal: g, expectedImprovement: 0.5)],
      family: "horizontal", presentationKey: "right")

    planner.recordProposal(left)
    planner.recordProposal(right)
    planner.recordProposal(left)
    planner.recordProposal(right)

    XCTAssertEqual(planner.memory.oscillationEvents, 1)
    XCTAssertGreaterThanOrEqual(planner.memory.fatigue, 2)
  }

  func test_tradeoff_group_penalizes_imbalance_and_recovers_when_balanced() {
    let g1 = GoalID("tradeoff.one")
    let g2 = GoalID("tradeoff.two")
    let d1 = DimensionID("tradeoff.dim.one")
    let d2 = DimensionID("tradeoff.dim.two")
    let band = TargetBand(ideal: 0.4...0.6, acceptable: 0...1)
    let goals = [
      GoalDefinition(
        id: g1, dimension: d1, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: g2, dimension: d2, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let engine = GoalEngine(goals)
    _ = engine.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .continuous(-0.10), confidence: 1, frameID: 1),  // outside acceptable => 0
      Observation(
        dimension: d2, binding: .node(n), value: .continuous(0.36), confidence: 1, frameID: 1),  // ~0.9
    ])
    let group = GoalGroupDefinition(
      id: GoalGroupID("tradeoff.balance"), kind: .tradeoff,
      members: [.init(goal: g1), .init(goal: g2)],
      minimumMemberScore: 0.15, targetScore: 0.45, balanceTolerance: 0.20)

    let imbalanced = GoalGroupEvaluator().assess(group, engine: engine)
    XCTAssertTrue(imbalanced.known)
    XCTAssertFalse(imbalanced.satisfied)
    XCTAssertGreaterThan(imbalanced.spread ?? 0, 0.8)

    _ = engine.ingest(
      Observation(
        dimension: d1, binding: .node(n), value: .continuous(0.30), confidence: 1, frameID: 2))
    let balanced = GoalGroupEvaluator().assess(group, engine: engine)
    XCTAssertGreaterThan(balanced.score ?? 0, imbalanced.score ?? 0)
    XCTAssertTrue(balanced.satisfied)
  }

  func test_tradeoff_group_biases_planner_toward_weaker_member() {
    let weak = GoalID("tradeoff.weak")
    let strong = GoalID("tradeoff.strong")
    let d1 = DimensionID("tradeoff.weak.dim")
    let d2 = DimensionID("tradeoff.strong.dim")
    let band = TargetBand(ideal: 0.4...0.6, acceptable: 0...1)
    let engine = GoalEngine([
      GoalDefinition(
        id: weak, dimension: d1, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: strong, dimension: d2, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ])
    _ = engine.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .continuous(-0.10), confidence: 1, frameID: 1),
      Observation(
        dimension: d2, binding: .node(n), value: .continuous(0.36), confidence: 1, frameID: 1),
    ])
    let group = GoalGroupDefinition(
      id: GoalGroupID("tradeoff"), kind: .tradeoff,
      members: [.init(goal: weak), .init(goal: strong)], balanceTolerance: 0.15)
    let helpWeak = ActionDefinition(
      id: ActionID("help.weak"), actor: .camera, operation: .reframe,
      effects: [.init(goal: weak, expectedImprovement: 0.38)],
      family: "weak", presentationKey: "weak")
    let helpStrong = ActionDefinition(
      id: ActionID("help.strong"), actor: .camera, operation: .reframe,
      effects: [.init(goal: strong, expectedImprovement: 0.48)],
      family: "strong", presentationKey: "strong")

    XCTAssertEqual(
      ActionPlanner().rank([helpStrong, helpWeak], engine: engine, goalGroups: [group]).first?.id,
      helpWeak.id
    )
  }

  func test_readiness_uses_tradeoff_surface_instead_of_independent_member_floor() {
    let g1 = GoalID("ready.tradeoff.one")
    let g2 = GoalID("ready.tradeoff.two")
    let d1 = DimensionID("ready.tradeoff.dim.one")
    let d2 = DimensionID("ready.tradeoff.dim.two")
    let band = TargetBand(ideal: 0.4...0.6, acceptable: 0...1)
    let engine = GoalEngine([
      GoalDefinition(
        id: g1, dimension: d1, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: g2, dimension: d2, binding: .node(n), target: .band(band), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ])
    _ = engine.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .continuous(0.00), confidence: 1, frameID: 1),  // acceptable edge => 0.55
      Observation(
        dimension: d2, binding: .node(n), value: .continuous(0.36), confidence: 1, frameID: 1),  // 0.9
    ])
    let noGroup = ReadinessPolicy().assess(engine: engine)
    XCTAssertFalse(noGroup.automaticReady)

    let group = GoalGroupDefinition(
      id: GoalGroupID("ready.tradeoff"), kind: .tradeoff,
      members: [.init(goal: g1), .init(goal: g2)],
      minimumMemberScore: 0.55, targetScore: 0.68, balanceTolerance: 0.30)
    let grouped = ReadinessPolicy().assess(engine: engine, goalGroups: [group])
    XCTAssertTrue(grouped.automaticReady)
  }

  func test_validator_rejects_invalid_and_overlapping_goal_groups() {
    let first = goal(id: GoalID("group.first"))
    let second = goal(id: GoalID("group.second"))
    let groups = [
      GoalGroupDefinition(
        id: GoalGroupID("one"), kind: .joint,
        members: [.init(goal: first.id), .init(goal: second.id)]),
      GoalGroupDefinition(
        id: GoalGroupID("two"), kind: .tradeoff,
        members: [.init(goal: first.id), .init(goal: GoalID("missing"))]),
    ]
    let actions = [
      action("first.action", goalID: first.id),
      action("second.action", goalID: second.id),
    ]
    let issues = RecipeValidator().validate(
      goals: [first, second], actions: actions, registry: testRegistry(), goalGroups: groups)

    XCTAssertTrue(issues.contains { $0.rule == .missingGoalGroupMember })
    XCTAssertTrue(issues.contains { $0.rule == .overlappingCriticalGoalGroups })
  }

  func test_recipe_simulation_warns_when_declared_effects_cannot_converge() {
    let slow = action("slow", improvement: 0.001)
    let issues = RecipeValidator().validate(
      goals: [goal()], actions: [slow], registry: testRegistry())
    XCTAssertTrue(issues.contains { $0.rule == .simulationCannotConverge })
  }

  func test_action_effect_graph_finds_shared_root_cause() {
    let g1 = GoalID("graph.one")
    let g2 = GoalID("graph.two")
    let shared = ActionDefinition(
      id: ActionID("shared.root"), actor: .camera, operation: .reframe,
      effects: [
        .init(goal: g1, expectedImprovement: 0.4),
        .init(goal: g2, expectedImprovement: 0.4),
      ], family: "shared", presentationKey: "shared")
    let single = ActionDefinition(
      id: ActionID("single.root"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g1, expectedImprovement: 0.8)],
      family: "single", presentationKey: "single")

    let graph = ActionEffectGraph(actions: [single, shared])
    XCTAssertEqual(graph.sharedCauses(for: [g1, g2]).map(\.id), [shared.id])
    XCTAssertEqual(graph.touchedGoals(by: [shared]), [g1, g2])
  }

  func test_sequence_planner_builds_short_plan_anchored_to_scheduler_first_step() {
    let g1 = GoalID("plan.one")
    let g2 = GoalID("plan.two")
    let d1 = DimensionID("plan.dim.one")
    let d2 = DimensionID("plan.dim.two")
    let goals = [
      GoalDefinition(
        id: g1, dimension: d1, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: g2, dimension: d2, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let engine = GoalEngine(goals)
    _ = engine.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: d2, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])
    let first = ActionDefinition(
      id: ActionID("plan.first"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g1, expectedImprovement: 0.75)], burden: 0.03,
      family: "first", presentationKey: "first")
    let second = ActionDefinition(
      id: ActionID("plan.second"), actor: .subject, operation: .move,
      effects: [.init(goal: g2, expectedImprovement: 0.75)], burden: 0.03,
      family: "second", presentationKey: "second")
    var horizon = ActionSequencePlanner()
    horizon.minimumPlanAdvantage = -100

    let plan = horizon.bestPlan(
      engine: engine, planner: ActionPlanner(), actions: [first, second], startingWith: first)
    XCTAssertEqual(plan?.steps.map(\.id), [first.id, second.id])
    XCTAssertEqual(plan?.steps.count, 2)
  }

  func test_session_advances_verified_multi_step_plan_one_step_at_a_time() {
    let g1 = GoalID("tx.one")
    let g2 = GoalID("tx.two")
    let d1 = DimensionID("tx.dim.one")
    let d2 = DimensionID("tx.dim.two")
    let goals = [
      GoalDefinition(
        id: g1, dimension: d1, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: g2, dimension: d2, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let first = ActionDefinition(
      id: ActionID("tx.first"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g1, expectedImprovement: 0.9)], burden: 0.02,
      family: "first", presentationKey: "first")
    let second = ActionDefinition(
      id: ActionID("tx.second"), actor: .subject, operation: .move,
      effects: [.init(goal: g2, expectedImprovement: 0.9)], burden: 0.02,
      family: "second", presentationKey: "second")
    let session = GuidanceSession(goals: goals, actions: [first, second])
    session.sequencePlanner.minimumPlanAdvantage = -100
    _ = session.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: d2, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])

    guard case .propose(let proposedFirst) = session.tick() else {
      return XCTFail("expected first step")
    }
    XCTAssertNotNil(session.activePlan)
    session.handle(.done)
    _ = session.ingest(
      Observation(
        dimension: d1, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 2))
    XCTAssertEqual(session.lastAction?.verification, .improved)
    XCTAssertEqual(session.activePlan?.stepIndex, 1)

    guard case .propose(let proposedSecond) = session.tick() else {
      return XCTFail("expected second step")
    }
    XCTAssertNotEqual(proposedFirst.id, proposedSecond.id)
    XCTAssertEqual(proposedSecond.id, second.id)
    session.handle(.done)
    _ = session.ingest(
      Observation(
        dimension: d2, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 3))
    XCTAssertNil(session.activePlan)
    XCTAssertEqual(session.lastAction?.verification, .improved)
  }

  func test_cancel_aborts_entire_multi_step_plan_without_rollback() {
    let g1 = GoalID("cancel.plan.one")
    let g2 = GoalID("cancel.plan.two")
    let d1 = DimensionID("cancel.plan.dim.one")
    let d2 = DimensionID("cancel.plan.dim.two")
    let goals = [
      GoalDefinition(
        id: g1, dimension: d1, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: g2, dimension: d2, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let a = ActionDefinition(
      id: ActionID("cancel.a"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g1, expectedImprovement: 0.9)], family: "a", presentationKey: "a")
    let b = ActionDefinition(
      id: ActionID("cancel.b"), actor: .subject, operation: .move,
      effects: [.init(goal: g2, expectedImprovement: 0.9)], family: "b", presentationKey: "b")
    let session = GuidanceSession(goals: goals, actions: [a, b])
    session.sequencePlanner.minimumPlanAdvantage = -100
    _ = session.ingestBatch([
      Observation(
        dimension: d1, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: d2, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])
    _ = session.tick()
    XCTAssertNotNil(session.activePlan)

    session.handle(.cancel)
    XCTAssertNil(session.activePlan)
    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.state, .cancelled)
    XCTAssertTrue(session.planner.needsReobserve)
  }

  func test_new_hard_regression_preempts_remaining_plan_steps() {
    let hardID = GoalID("plan.guard")
    let coreA = GoalID("plan.core.a")
    let coreB = GoalID("plan.core.b")
    let hardDim = DimensionID("plan.guard.dim")
    let aDim = DimensionID("plan.a.dim")
    let bDim = DimensionID("plan.b.dim")
    let goals = [
      GoalDefinition(
        id: hardID, dimension: hardDim, binding: .node(n), target: .boolean(true),
        constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: coreA, dimension: aDim, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: coreB, dimension: bDim, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let first = ActionDefinition(
      id: ActionID("guard.plan.first"), actor: .camera, operation: .reframe,
      effects: [.init(goal: coreA, expectedImprovement: 0.9)], family: "first",
      presentationKey: "first")
    let second = ActionDefinition(
      id: ActionID("guard.plan.second"), actor: .subject, operation: .move,
      effects: [.init(goal: coreB, expectedImprovement: 0.9)], family: "second",
      presentationKey: "second")
    let fixGuard = ActionDefinition(
      id: ActionID("guard.fix"), actor: .camera, operation: .reframe,
      effects: [.init(goal: hardID, expectedImprovement: 0.9)], family: "guard",
      presentationKey: "guard")
    let session = GuidanceSession(goals: goals, actions: [first, second, fixGuard])
    session.sequencePlanner.minimumPlanAdvantage = -100
    _ = session.ingestBatch([
      Observation(
        dimension: hardDim, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 1),
      Observation(
        dimension: aDim, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: bDim, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])
    _ = session.tick()
    let originalPlanID = session.activePlan?.definition.id
    session.handle(.done)
    _ = session.ingestBatch([
      Observation(
        dimension: aDim, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 2),
      Observation(
        dimension: hardDim, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 2),
    ])
    XCTAssertEqual(session.activePlan?.stepIndex, 1)

    XCTAssertEqual(session.tick(), .propose(fixGuard))
    XCTAssertNotEqual(session.activePlan?.definition.id, originalPlanID)
    XCTAssertEqual(session.currentTransaction?.definition.id, fixGuard.id)
  }

  func test_multi_step_plan_allows_declared_temporary_core_regression_then_repairs_it() {
    let target = GoalID("temporary.target")
    let preserved = GoalID("temporary.preserved")
    let targetDim = DimensionID("temporary.target.dim")
    let preservedDim = DimensionID("temporary.preserved.dim")
    let goals = [
      GoalDefinition(
        id: target, dimension: targetDim, binding: .node(n), target: .boolean(true),
        constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: preserved, dimension: preservedDim, binding: .node(n), target: .boolean(true),
        constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let disturbThenImprove = ActionDefinition(
      id: ActionID("temporary.step.one"), actor: .camera, operation: .reframe,
      effects: [
        .init(goal: target, expectedImprovement: 1.0),
        .init(goal: preserved, expectedImprovement: 0, possibleDamage: 1.0),
      ], burden: 0.02, family: "temporary.one", presentationKey: "one")
    let repair = ActionDefinition(
      id: ActionID("temporary.step.two"), actor: .camera, operation: .reframe,
      effects: [.init(goal: preserved, expectedImprovement: 1.0)],
      burden: 0.02, family: "temporary.two", presentationKey: "two")
    let session = GuidanceSession(goals: goals, actions: [disturbThenImprove, repair])
    session.sequencePlanner.minimumPlanAdvantage = -100
    _ = session.ingestBatch([
      Observation(
        dimension: targetDim, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: preservedDim, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 1
      ),
    ])

    XCTAssertEqual(session.tick(), .propose(disturbThenImprove))
    XCTAssertNotNil(session.activePlan)
    session.handle(.done)
    _ = session.ingestBatch([
      Observation(
        dimension: targetDim, binding: .node(n), value: .boolean(true), confidence: 1, frameID: 2),
      Observation(
        dimension: preservedDim, binding: .node(n), value: .boolean(false), confidence: 1,
        frameID: 2),
    ])
    XCTAssertEqual(session.lastAction?.verification, .improved)
    XCTAssertEqual(session.activePlan?.stepIndex, 1)
    XCTAssertEqual(session.tick(), .propose(repair))
  }

  func test_value_of_information_prefers_hold_over_blind_correction_for_unknown_hard_goal() {
    let hard = goal(constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([hard])
    _ = engine.ingest(obs(.boolean(false), confidence: 0.15, frame: 1))
    let planner = ActionPlanner()
    let hold = ActionDefinition(
      id: ActionID("evidence.hold"), actor: .system, operation: .hold,
      effects: [],
      informationEffects: [.init(goal: g, confidenceGain: 0.55, resolutionProbability: 0.9)],
      burden: 0.01, uncertainty: 0.03, family: "evidence.hold", presentationKey: "hold")
    let correction = action("blind.correction", improvement: 1.0)

    XCTAssertEqual(
      GuidanceScheduler().decide(engine: engine, planner: planner, actions: [correction, hold]),
      .propose(hold)
    )
  }

  func test_low_value_information_action_falls_back_to_evidence_request() {
    let hard = goal(constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([hard])
    _ = engine.ingest(obs(.boolean(false), confidence: 0.15, frame: 1))
    let expensiveWait = ActionDefinition(
      id: ActionID("evidence.expensive"), actor: .system, operation: .wait,
      effects: [],
      informationEffects: [.init(goal: g, confidenceGain: 0.01, resolutionProbability: 0.02)],
      burden: 0.95, uncertainty: 0.5, family: "evidence.expensive", presentationKey: "wait")

    let decision = GuidanceScheduler().decide(
      engine: engine, planner: ActionPlanner(), actions: [expensiveWait])
    guard case .requestEvidence(let request) = decision else {
      return XCTFail("Expected explicit evidence request, got \(decision)")
    }
    XCTAssertEqual(request.goals, [g])
    XCTAssertEqual(request.reason, .hardGuardUnknown)
  }

  func test_information_action_verification_uses_new_confidence_evidence() {
    let definition = goal(constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1))
    let hold = ActionDefinition(
      id: ActionID("evidence.verify"), actor: .system, operation: .hold,
      effects: [],
      informationEffects: [.init(goal: g, confidenceGain: 0.5, resolutionProbability: 0.9)],
      burden: 0.01, family: "evidence.verify", presentationKey: "hold")
    let session = GuidanceSession(goals: [definition], actions: [hold])
    _ = session.ingest(obs(.boolean(true), confidence: 0.2, frame: 1))
    XCTAssertEqual(session.tick(), .propose(hold))
    session.handle(.done)
    _ = session.ingest(obs(.boolean(true), confidence: 0.95, frame: 2))

    XCTAssertEqual(session.lastAction?.definition.id, hold.id)
    XCTAssertEqual(session.lastAction?.verification, .improved)
  }

  func test_plan_uncertainty_grows_with_horizon_and_action_uncertainty() {
    let planner = ActionPlanner()
    let certain = ActionDefinition(
      id: ActionID("certain"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g, expectedImprovement: 0.5)], uncertainty: 0.05,
      family: "certain", presentationKey: "certain")
    let uncertain = ActionDefinition(
      id: ActionID("uncertain"), actor: .camera, operation: .reframe,
      effects: [.init(goal: g, expectedImprovement: 0.5)], uncertainty: 0.65,
      family: "uncertain", presentationKey: "uncertain")
    let model = PlanningUncertaintyModel()

    let one = model.sequenceUncertainty([certain], planner: planner)
    let two = model.sequenceUncertainty([certain, uncertain], planner: planner)
    XCTAssertGreaterThan(two, one)
    XCTAssertGreaterThan(
      model.actionUncertainty(uncertain, planner: planner),
      model.actionUncertainty(certain, planner: planner))
  }

  func test_sequence_plan_exposes_confidence_adjusted_utility() {
    let coreA = GoalID("uncertainty.a")
    let coreB = GoalID("uncertainty.b")
    let dimA = DimensionID("uncertainty.a.dim")
    let dimB = DimensionID("uncertainty.b.dim")
    let goals = [
      GoalDefinition(
        id: coreA, dimension: dimA, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: coreB, dimension: dimB, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let engine = GoalEngine(goals)
    _ = engine.ingestBatch([
      Observation(
        dimension: dimA, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: dimB, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])
    let first = ActionDefinition(
      id: ActionID("uncertainty.first"), actor: .camera, operation: .reframe,
      effects: [.init(goal: coreA, expectedImprovement: 0.9)], burden: 0.01, uncertainty: 0.35,
      family: "u.first", presentationKey: "first")
    let second = ActionDefinition(
      id: ActionID("uncertainty.second"), actor: .camera, operation: .reframe,
      effects: [.init(goal: coreB, expectedImprovement: 0.9)], burden: 0.01, uncertainty: 0.35,
      family: "u.second", presentationKey: "second")
    var sequence = ActionSequencePlanner()
    sequence.minimumPlanAdvantage = -100
    let plan = sequence.bestPlan(
      engine: engine, planner: ActionPlanner(), actions: [first, second], startingWith: first)

    XCTAssertNotNil(plan)
    XCTAssertGreaterThan(plan?.utilityUncertainty ?? 0, 0)
    XCTAssertLessThan(plan?.confidenceAdjustedUtility ?? 0, plan?.expectedUtility ?? 0)
  }

  func test_validator_checks_information_effect_goal_references_and_duplicates() {
    let unknown = GoalID("missing.info.goal")
    let information = ActionDefinition(
      id: ActionID("bad.info"), actor: .system, operation: .hold,
      effects: [],
      informationEffects: [
        .init(goal: unknown, confidenceGain: 0.4),
        .init(goal: unknown, confidenceGain: 0.5),
      ], family: "bad.info", presentationKey: "bad.info")
    let issues = RecipeValidator().validate(
      goals: [goal()], actions: [information], registry: testRegistry())

    XCTAssertTrue(issues.contains { $0.rule == .invalidActionGoalReference })
    XCTAssertTrue(issues.contains { $0.rule == .duplicateInformationEffectGoal })
  }

  func test_information_actions_are_not_inserted_into_quality_action_sequences() {
    let a = GoalID("sequence.quality.a")
    let b = GoalID("sequence.quality.b")
    let da = DimensionID("sequence.quality.da")
    let db = DimensionID("sequence.quality.db")
    let goals = [
      GoalDefinition(
        id: a, dimension: da, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: b, dimension: db, binding: .node(n), target: .boolean(true), constraint: .core,
        stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let engine = GoalEngine(goals)
    _ = engine.ingestBatch([
      Observation(
        dimension: da, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
      Observation(
        dimension: db, binding: .node(n), value: .boolean(false), confidence: 1, frameID: 1),
    ])
    let one = ActionDefinition(
      id: ActionID("quality.one"), actor: .camera, operation: .reframe,
      effects: [.init(goal: a, expectedImprovement: 1)], burden: 0.01, family: "quality.one",
      presentationKey: "one")
    let two = ActionDefinition(
      id: ActionID("quality.two"), actor: .camera, operation: .reframe,
      effects: [.init(goal: b, expectedImprovement: 1)], burden: 0.01, family: "quality.two",
      presentationKey: "two")
    let hold = ActionDefinition(
      id: ActionID("quality.hold"), actor: .system, operation: .hold, effects: [],
      informationEffects: [.init(goal: a, confidenceGain: 1)], family: "quality.hold",
      presentationKey: "hold")
    var sequence = ActionSequencePlanner()
    sequence.minimumPlanAdvantage = -100
    let plan = sequence.bestPlan(
      engine: engine, planner: ActionPlanner(), actions: [one, hold, two], startingWith: one)

    XCTAssertNotNil(plan)
    XCTAssertFalse(plan?.steps.contains(where: { $0.id == hold.id }) ?? true)
  }

  func test_hold_information_action_does_not_replace_initial_missing_observation() {
    let hard = goal(constraint: .hard)
    let engine = GoalEngine([hard])
    let hold = ActionDefinition(
      id: ActionID("evidence.initial.hold"), actor: .system, operation: .hold,
      effects: [],
      informationEffects: [.init(goal: g, confidenceGain: 0.8, resolutionProbability: 1)],
      burden: 0.01, family: "evidence.initial", presentationKey: "hold")

    let decision = GuidanceScheduler().decide(
      engine: engine, planner: ActionPlanner(), actions: [hold])
    guard case .requestEvidence(let request) = decision else {
      return XCTFail(
        "Initial unobserved goal should request evidence instead of telling the user to hold")
    }
    XCTAssertEqual(request.goals, [g])
  }

  func test_information_action_verifies_only_goals_that_needed_new_evidence() {
    let unknownID = GoalID("info.unknown")
    let stableID = GoalID("info.stable")
    let unknownDim = DimensionID("info.unknown.dim")
    let stableDim = DimensionID("info.stable.dim")
    let goals = [
      GoalDefinition(
        id: unknownID, dimension: unknownDim, binding: .node(n), target: .boolean(true),
        constraint: .hard, stability: .init(enterFrames: 1, exitFrames: 1)),
      GoalDefinition(
        id: stableID, dimension: stableDim, binding: .node(n), target: .boolean(true),
        constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1)),
    ]
    let observe = ActionDefinition(
      id: ActionID("info.selective"), actor: .system, operation: .hold, effects: [],
      informationEffects: [
        .init(goal: unknownID, confidenceGain: 0.7, resolutionProbability: 0.9),
        .init(goal: stableID, confidenceGain: 0.2, resolutionProbability: 0.2),
      ], burden: 0.01, family: "info.selective", presentationKey: "hold")
    let session = GuidanceSession(goals: goals, actions: [observe])
    _ = session.ingestBatch([
      Observation(
        dimension: unknownDim, binding: .node(n), value: .boolean(true), confidence: 0.2, frameID: 1
      ),
      Observation(
        dimension: stableDim, binding: .node(n), value: .boolean(true), confidence: 0.95, frameID: 1
      ),
    ])

    XCTAssertEqual(session.tick(), .propose(observe))
    XCTAssertEqual(session.currentTransaction?.verificationGoals, [unknownID])
    session.handle(.done)
    _ = session.ingest(
      Observation(
        dimension: unknownDim, binding: .node(n), value: .boolean(true), confidence: 0.95,
        frameID: 2))

    XCTAssertEqual(session.lastAction?.verification, .improved)
    XCTAssertNil(session.currentTransaction)
  }

  func test_evaluation_coordinator_throttles_watch_goals_but_keeps_periodic_refresh() {
    let definition = goal(
      constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    XCTAssertEqual(engine.states[g]?.state, .satisfied)

    var coordinator = EvaluationCoordinator()
    let registry = testRegistry()
    let first = coordinator.plan(frameID: 1, engine: engine, registry: registry)
    XCTAssertEqual(first.local.map(\.goalID), [g])

    let tooSoon = coordinator.plan(frameID: 2, engine: engine, registry: registry)
    XCTAssertTrue(tooSoon.local.isEmpty)

    let periodic = coordinator.plan(frameID: 13, engine: engine, registry: registry)
    XCTAssertEqual(periodic.local.map(\.goalID), [g])
  }

  func test_evaluation_coordinator_invalidated_watch_goal_runs_immediately() {
    let definition = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    var coordinator = EvaluationCoordinator()
    let registry = testRegistry()
    _ = coordinator.plan(frameID: 1, engine: engine, registry: registry)

    coordinator.invalidate([g], engine: engine)
    let immediate = coordinator.plan(frameID: 2, engine: engine, registry: registry)
    XCTAssertEqual(immediate.local.map(\.goalID), [g])
  }

  func test_evaluation_coordinator_focus_goal_uses_tighter_cadence_than_watch() {
    let definition = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let engine = GoalEngine([definition])
    _ = engine.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(engine.states[g]?.state, .active)
    var coordinator = EvaluationCoordinator()
    let registry = testRegistry()

    XCTAssertEqual(coordinator.plan(frameID: 1, engine: engine, registry: registry).local.count, 1)
    XCTAssertEqual(coordinator.plan(frameID: 2, engine: engine, registry: registry).local.count, 0)
    XCTAssertEqual(coordinator.plan(frameID: 3, engine: engine, registry: registry).local.count, 1)
  }

  func test_evaluation_coordinator_hard_guard_can_run_every_frame() {
    let hard = goal(
      constraint: .hard,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([hard])
    _ = engine.ingest(obs(.boolean(true), frame: 1))
    var coordinator = EvaluationCoordinator()
    let registry = testRegistry()

    XCTAssertEqual(coordinator.plan(frameID: 1, engine: engine, registry: registry).local.count, 1)
    XCTAssertEqual(coordinator.plan(frameID: 2, engine: engine, registry: registry).local.count, 1)
  }

  func test_replay_reproduces_decisions_and_final_snapshot() throws {
    let definition = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let fix = action("replay.fix")
    let session = GuidanceSession(goals: [definition], actions: [fix])
    _ = session.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(session.tick(), .propose(fix))
    session.handle(.done)
    _ = session.ingest(obs(.boolean(true), frame: 2))
    XCTAssertEqual(session.tick(), .ready)

    let encoded = try JSONEncoder().encode(session.replayEvents)
    let decoded = try JSONDecoder().decode([GuidanceReplayEvent].self, from: encoded)
    XCTAssertEqual(decoded, session.replayEvents)

    let replay = GuidanceReplayer().replay(decoded, goals: [definition], actions: [fix])
    XCTAssertEqual(replay.decisions, [.propose(fix.id), .ready])
    XCTAssertEqual(replay.snapshot.captureState, session.snapshot().captureState)
    XCTAssertEqual(replay.snapshot.goalStates, session.snapshot().goalStates)
    XCTAssertTrue(replay.invariantIssues.isEmpty)
  }

  func test_replay_records_rejected_observation_so_validation_is_reproducible() {
    let registry = testRegistry()
    let session = GuidanceSession(goals: [goal()], actions: [action()], registry: registry)
    let invalid = Observation(
      dimension: d, binding: .node(n), value: .continuous(999), confidence: 1,
      evaluator: EvaluatorID("vision.local"), frameID: 1
    )
    _ = session.ingest(invalid)
    _ = session.tick()
    XCTAssertEqual(session.rejectedObservations, 1)

    let replay = GuidanceReplayer().replay(
      session.replayEvents, goals: [goal()], actions: [action()], registry: registry)
    XCTAssertEqual(replay.snapshot.rejectedObservations, 1)
  }

  func test_tick_detailed_exposes_frozen_phase_order_and_work_sets() {
    let hard = goal(
      constraint: .hard,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let session = GuidanceSession(goals: [hard], actions: [action()])
    _ = session.ingest(obs(.boolean(false), frame: 1))

    let report = session.tickDetailed()
    XCTAssertEqual(report.sequence, 1)
    XCTAssertEqual(report.phases, RuntimeTickPhase.allCases)
    XCTAssertTrue(report.workSets.guardGoals.contains(g))
    XCTAssertTrue(report.workSets.focusGoals.contains(g))
    XCTAssertEqual(report.decision, .propose(ActionID("a")))
    XCTAssertTrue(report.invariantIssues.isEmpty)
  }

  func test_replay_capacity_bounds_debug_memory() {
    let session = GuidanceSession(goals: [goal()], actions: [action()])
    session.replayCapacity = 3
    for frame in 1...5 {
      _ = session.ingest(obs(.boolean(false), frame: frame))
    }
    XCTAssertEqual(session.replayEvents.count, 3)
    if case .observation(let first)? = session.replayEvents.first {
      XCTAssertEqual(first.frameID, 3)
    } else {
      XCTFail("Expected retained replay observation")
    }
  }

  func test_conflicting_evaluators_collapse_fusion_to_unknown() {
    let engine = GoalEngine([
      goal(stability: .init(enterFrames: 1, exitFrames: 1))
    ])
    engine.evaluatorTrust = [EvaluatorID("vision"): 0.9, EvaluatorID("semantic"): 0.9]
    engine.evaluatorReliability = EvaluatorReliabilityModel(baseReliability: engine.evaluatorTrust)

    let observations = [
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95,
        evaluator: EvaluatorID("vision"), frameID: 1),
      Observation(
        dimension: d, binding: .node(n), value: .boolean(false), confidence: 0.95,
        evaluator: EvaluatorID("semantic"), frameID: 1),
    ]
    _ = engine.ingestBatch(observations)

    XCTAssertEqual(engine.latestConflictReports[g]?.level, .severe)
    XCTAssertLessThan(engine.latestObservations[g]?.confidence ?? 1, engine.minimumConfidence)
    XCTAssertEqual(engine.states[g]?.state, .unknown)
  }

  func test_reliability_model_downweights_persistent_outlier() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    let c = EvaluatorID("c")
    var model = EvaluatorReliabilityModel(
      baseReliability: [a: 0.9, b: 0.9, c: 0.9], learningRate: 0.12)

    for frame in 1...18 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95, evaluator: a,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95, evaluator: b,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 0.95, evaluator: c,
          frameID: frame),
      ])
    }

    let ar = model.reliability(for: a, dimension: d)
    let br = model.reliability(for: b, dimension: d)
    let cr = model.reliability(for: c, dimension: d)
    XCTAssertLessThan(cr, ar)
    XCTAssertLessThan(cr, br)
    XCTAssertGreaterThan(
      model.states[EvaluatorReliabilityKey(evaluator: c, dimension: d)]?.conflictCount ?? 0, 0)
  }

  func test_reliability_learning_is_dimension_specific() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    let other = DimensionID("other")
    var model = EvaluatorReliabilityModel(baseReliability: [a: 0.9, b: 0.9], learningRate: 0.2)

    for frame in 1...10 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 1, evaluator: b,
          frameID: frame),
      ])
    }

    XCTAssertLessThan(model.reliability(for: b, dimension: d), 0.9)
    XCTAssertEqual(model.reliability(for: b, dimension: other), 0.9, accuracy: 0.0001)
  }

  func test_single_evaluator_cannot_self_confirm_reliability() {
    let a = EvaluatorID("a")
    var model = EvaluatorReliabilityModel(baseReliability: [a: 0.77])
    for frame in 1...20 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
          frameID: frame)
      ])
    }
    XCTAssertEqual(model.reliability(for: a, dimension: d), 0.77, accuracy: 0.0001)
    XCTAssertTrue(model.states.isEmpty)
  }

  func test_learned_reliability_changes_fusion_winner() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    let outlier = EvaluatorID("outlier")
    var model = EvaluatorReliabilityModel(
      baseReliability: [a: 0.92, b: 0.92, outlier: 0.92], learningRate: 0.15)

    for frame in 1...24 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: b,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 1,
          evaluator: outlier, frameID: frame),
      ])
    }

    let result = ObservationFusion().fuseDetailed(
      [
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.72, evaluator: a,
          frameID: 30),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 1.0,
          evaluator: outlier, frameID: 30),
      ], reliabilityModel: model)

    XCTAssertEqual(result?.observation.value, .boolean(true))
    XCTAssertGreaterThan(
      model.reliability(for: a, dimension: d), model.reliability(for: outlier, dimension: d))
  }

  func test_evaluator_reliability_recovers_after_consistent_evidence() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    let c = EvaluatorID("c")
    var model = EvaluatorReliabilityModel(
      baseReliability: [a: 0.9, b: 0.9, c: 0.9], learningRate: 0.12)

    for frame in 1...15 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: b,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 1, evaluator: c,
          frameID: frame),
      ])
    }
    let degraded = model.reliability(for: c, dimension: d)

    for frame in 16...45 {
      model.observe([
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: b,
          frameID: frame),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: c,
          frameID: frame),
      ])
    }
    XCTAssertGreaterThan(model.reliability(for: c, dimension: d), degraded)
  }

  func test_agreeing_evaluators_preserve_high_fusion_confidence() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    let model = EvaluatorReliabilityModel(baseReliability: [a: 0.9, b: 0.9])
    let result = ObservationFusion().fuseDetailed(
      [
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.92, evaluator: a,
          frameID: 1),
        Observation(
          dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.90, evaluator: b,
          frameID: 1),
      ], reliabilityModel: model)

    XCTAssertEqual(result?.conflict.level, ObservationConflictLevel.none)
    XCTAssertEqual(result?.observation.value, .boolean(true))
    XCTAssertGreaterThan(result?.observation.confidence ?? 0, 0.85)
  }

  func test_snapshot_exposes_evaluator_conflicts_and_learned_reliability() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.evaluatorTrust = [EvaluatorID("a"): 0.9, EvaluatorID("b"): 0.9]
    session.engine.evaluatorReliability = EvaluatorReliabilityModel(
      baseReliability: session.engine.evaluatorTrust)
    _ = session.ingestBatch([
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 0.95,
        evaluator: EvaluatorID("a"), frameID: 1),
      Observation(
        dimension: d, binding: .node(n), value: .boolean(false), confidence: 0.95,
        evaluator: EvaluatorID("b"), frameID: 1),
    ])

    let snapshot = session.snapshot()
    XCTAssertFalse(snapshot.evaluatorReliability.isEmpty)
    XCTAssertEqual(snapshot.conflicts.first?.report.level, .severe)
    XCTAssertTrue(session.trace.contains { $0.detail.contains("evaluator.conflict") })
  }

  func test_reliability_does_not_train_twice_on_identical_evidence_pair() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    var model = EvaluatorReliabilityModel(baseReliability: [a: 0.9, b: 0.9], learningRate: 0.2)
    let evidence = [
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
        frameID: 10),
      Observation(
        dimension: d, binding: .node(n), value: .boolean(false), confidence: 1, evaluator: b,
        frameID: 10),
    ]
    model.observe(evidence)
    let firstCount = model.states[EvaluatorReliabilityKey(evaluator: a, dimension: d)]?.sampleCount
    model.observe(evidence)
    let secondCount = model.states[EvaluatorReliabilityKey(evaluator: a, dimension: d)]?.sampleCount
    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, firstCount)
  }

  func test_stale_cross_evaluator_pair_does_not_train_reliability() {
    let a = EvaluatorID("a")
    let b = EvaluatorID("b")
    var model = EvaluatorReliabilityModel(
      baseReliability: [a: 0.9, b: 0.9], maximumCalibrationFrameDelta: 2)
    model.observe([
      Observation(
        dimension: d, binding: .node(n), value: .boolean(true), confidence: 1, evaluator: a,
        frameID: 20),
      Observation(
        dimension: d, binding: .node(n), value: .boolean(false), confidence: 1, evaluator: b,
        frameID: 10),
    ])
    XCTAssertTrue(model.states.isEmpty)
  }

  func test_scene_condition_temporarily_reduces_pose_vision_reliability() {
    let registry = GuidanceRegistry.standardPhotography
    let model = EvaluatorReliabilityModel(
      baseReliability: [EvaluatorID("vision.local"): 0.92])
    let dimension = DimensionID("std.pose.body_orientation")
    let clear = model.resolvedReliability(
      for: EvaluatorID("vision.local"), dimension: dimension,
      sceneConditions: SceneConditionProfile(), registry: registry)
    let difficult = model.resolvedReliability(
      for: EvaluatorID("vision.local"), dimension: dimension,
      sceneConditions: SceneConditionProfile(
        severities: [.motionBlur: 0.9, .subjectOccluded: 0.8]),
      registry: registry)

    XCTAssertGreaterThan(clear, difficult)
    XCTAssertGreaterThan(clear, 0.85)
    XCTAssertLessThan(difficult, 0.40)
  }

  func test_scene_condition_penalty_does_not_mutate_learned_reliability() {
    let registry = GuidanceRegistry.standardPhotography
    let evaluator = EvaluatorID("djev.semantic")
    let dimension = DimensionID("std.relation.visual_balance")
    let model = EvaluatorReliabilityModel(baseReliability: [evaluator: 0.9])
    let baseline = model.reliability(for: evaluator, dimension: dimension)
    _ = model.resolvedReliability(
      for: evaluator, dimension: dimension,
      sceneConditions: SceneConditionProfile(severities: [.inputCompression: 1]),
      registry: registry)

    XCTAssertEqual(
      model.reliability(for: evaluator, dimension: dimension), baseline, accuracy: 0.0001)
  }

  func test_input_compression_can_shift_conflict_dominance_toward_local_vision() {
    let registry = GuidanceRegistry.standardPhotography
    let dimension = DimensionID("std.pose.body_orientation")
    let binding = Binding.node(NodeID("person"))
    let model = EvaluatorReliabilityModel(baseReliability: [
      EvaluatorID("vision.local"): 0.92,
      EvaluatorID("djev.semantic"): 0.92,
    ])
    let observations = [
      Observation(
        dimension: dimension, binding: binding, value: .ordinal(0), confidence: 0.90,
        evaluator: EvaluatorID("vision.local"), frameID: 1),
      Observation(
        dimension: dimension, binding: binding, value: .ordinal(2), confidence: 0.95,
        evaluator: EvaluatorID("djev.semantic"), frameID: 1),
    ]
    let report = ObservationConflictArbitrator().report(
      observations,
      reliability: model,
      sceneConditions: SceneConditionProfile(severities: [.inputCompression: 1]),
      registry: registry)

    XCTAssertEqual(report.strongestEvaluator, EvaluatorID("vision.local"))
    XCTAssertGreaterThan(report.strongestShare, 0.55)
  }

  func test_known_bad_scene_does_not_overtrain_reliability_from_disagreement() {
    let registry = GuidanceRegistry.standardPhotography
    let dimension = DimensionID("std.pose.body_orientation")
    let binding = Binding.node(NodeID("person"))
    var model = EvaluatorReliabilityModel(baseReliability: [
      EvaluatorID("vision.local"): 0.9,
      EvaluatorID("djev.semantic"): 0.9,
    ])
    model.observe(
      [
        Observation(
          dimension: dimension, binding: binding, value: .ordinal(0), confidence: 1,
          evaluator: EvaluatorID("vision.local"), frameID: 1),
        Observation(
          dimension: dimension, binding: binding, value: .ordinal(2), confidence: 1,
          evaluator: EvaluatorID("djev.semantic"), frameID: 1),
      ],
      sceneConditions: SceneConditionProfile(
        severities: [.motionBlur: 1, .subjectOccluded: 1]), registry: registry)

    XCTAssertTrue(model.states.isEmpty)
  }

  func test_scene_condition_profile_is_replayed_deterministically() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let events: [GuidanceReplayEvent] = [
      .sceneConditions(
        SceneConditionProfile(
          severities: [.lowLight: 0.8, .cameraMotion: 0.4], confidence: 0.9,
          frameID: 10, sceneRevision: 2)),
      .observation(
        Observation(
          dimension: d, binding: .node(n), value: .boolean(false), confidence: 1,
          frameID: 10, sceneRevision: 2)),
      .tick,
    ]
    let result = GuidanceReplayer().replay(events, goals: [g], actions: [action()])

    XCTAssertEqual(
      result.snapshot.sceneConditions?.severity(.lowLight) ?? -1, 0.8, accuracy: 0.0001)
    XCTAssertEqual(result.snapshot.sceneConditions?.sceneRevision, 2)
  }

  func test_scene_condition_reset_is_recorded_and_replayed() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(goals: [g], actions: [action()])
    session.updateSceneConditions(
      SceneConditionProfile(
        severities: [.lowLight: 0.8], confidence: 0.9, frameID: 10, sceneRevision: 2))
    session.updateSceneConditions(nil)
    _ = session.tick()

    let result = GuidanceReplayer().replay(session.replayEvents, goals: [g], actions: [action()])

    XCTAssertNil(session.snapshot().sceneConditions)
    XCTAssertNil(result.snapshot.sceneConditions)
  }

  func test_single_source_confidence_is_reduced_by_scene_condition_reliability() {
    let registry = GuidanceRegistry.standardPhotography
    let dimension = DimensionID("std.pose.body_orientation")
    let observation = Observation(
      dimension: dimension, binding: .node(NodeID("person")), value: .ordinal(0), confidence: 1,
      evaluator: EvaluatorID("vision.local"), frameID: 1)
    let clear = ObservationFusion().fuseDetailed(
      [observation],
      reliabilityModel: EvaluatorReliabilityModel(
        baseReliability: [EvaluatorID("vision.local"): 0.92]),
      registry: registry)
    let difficult = ObservationFusion().fuseDetailed(
      [observation],
      reliabilityModel: EvaluatorReliabilityModel(
        baseReliability: [EvaluatorID("vision.local"): 0.92]),
      sceneConditions: SceneConditionProfile(
        severities: [.motionBlur: 1, .subjectOccluded: 1]),
      registry: registry)

    XCTAssertGreaterThan(clear?.observation.confidence ?? 0, difficult?.observation.confidence ?? 1)
    XCTAssertLessThan(difficult?.observation.confidence ?? 1, 0.5)
  }

  func test_bad_scene_can_turn_single_pose_observation_into_unknown_in_goal_engine() {
    let dimension = DimensionID("std.pose.body_orientation")
    let subject = NodeID("primary")
    let g = GoalDefinition(
      id: GoalID("pose"), dimension: dimension, binding: .node(subject), target: .ordinal(0),
      constraint: .core, stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(
      goals: [g], actions: [], registry: GuidanceRegistry.standardPhotography)
    session.updateSceneConditions(
      SceneConditionProfile(
        severities: [.motionBlur: 1, .subjectOccluded: 1], confidence: 1, frameID: 1))
    _ = session.ingest(
      Observation(
        dimension: dimension, binding: .node(subject), value: .ordinal(0), confidence: 1,
        evaluator: EvaluatorID("vision.local"), frameID: 1))

    XCTAssertEqual(session.engine.states[g.id]?.state, .unknown)
  }

  func test_scene_condition_merge_preserves_worst_known_severity() {
    let first = SceneConditionProfile(
      severities: [.lowLight: 0.7, .cameraMotion: 0.1], confidence: 0.6, frameID: 1)
    let second = SceneConditionProfile(
      severities: [.lowLight: 0.2, .cameraMotion: 0.8], confidence: 0.9, frameID: 2)
    let merged = first.merged(with: second)

    XCTAssertEqual(merged.severity(.lowLight), 0.7, accuracy: 0.0001)
    XCTAssertEqual(merged.severity(.cameraMotion), 0.8, accuracy: 0.0001)
    XCTAssertEqual(merged.frameID, 2)
    XCTAssertEqual(merged.confidence, 0.9, accuracy: 0.0001)
  }

  func test_evaluator_circuit_opens_quarantines_and_recovers_after_probe() {
    let evaluator = EvaluatorID("remote")
    var monitor = EvaluatorHealthMonitor(
      policy: .init(degradeAfterFailures: 1, openAfterFailures: 2, cooldownFrames: 3))

    monitor.recordFailure(evaluator, kind: .timeout, frameID: 10)
    XCTAssertEqual(monitor.state(for: evaluator).circuit, .degraded)
    monitor.recordFailure(evaluator, kind: .transport, frameID: 11)
    XCTAssertEqual(monitor.state(for: evaluator).circuit, .open)
    XCTAssertFalse(monitor.isSchedulable(evaluator, frameID: 13))
    XCTAssertTrue(monitor.isSchedulable(evaluator, frameID: 14))

    monitor.recordSuccess(evaluator, frameID: 14)
    XCTAssertEqual(monitor.state(for: evaluator).circuit, .closed)
    XCTAssertTrue(monitor.isSchedulable(evaluator, frameID: 15))
  }

  func test_evaluation_coordinator_quarantines_failed_semantic_evaluator_until_probe_frame() {
    let pose = GoalDefinition(
      id: GoalID("pose"),
      dimension: DimensionID("std.pose.body_orientation"),
      binding: .node(NodeID("primary")),
      target: .ordinal(0),
      constraint: .core,
      stability: .init(enterFrames: 1, exitFrames: 1)
    )
    let engine = GoalEngine([pose])
    _ = engine.ingest(
      Observation(
        dimension: pose.dimension, binding: pose.binding, value: .ordinal(2), confidence: 0.9,
        evaluator: EvaluatorID("vision.local"), frameID: 1))
    var coordinator = EvaluationCoordinator()
    coordinator.evaluatorHealth.policy = .init(
      degradeAfterFailures: 1, openAfterFailures: 2, cooldownFrames: 5)
    coordinator.recordEvaluatorFailure(EvaluatorID("djev.semantic"), kind: .timeout, frameID: 2)
    coordinator.recordEvaluatorFailure(EvaluatorID("djev.semantic"), kind: .timeout, frameID: 3)

    let quarantined = coordinator.plan(
      frameID: 4, engine: engine, registry: GuidanceRegistry.standardPhotography)
    XCTAssertTrue(quarantined.semantic.isEmpty)

    coordinator.resetCadenceOnly()
    let probe = coordinator.plan(
      frameID: 8, engine: engine, registry: GuidanceRegistry.standardPhotography)
    XCTAssertFalse(probe.semantic.isEmpty)
  }

  func test_critical_runtime_budget_never_drops_hard_guard_slots() {
    let goals = (0..<9).map { index in
      GoalDefinition(
        id: GoalID("hard_\(index)"),
        dimension: DimensionID("std.node.exists"),
        binding: .node(NodeID("person_\(index)")),
        target: .boolean(true),
        constraint: .hard
      )
    }
    let engine = GoalEngine(goals)
    var coordinator = EvaluationCoordinator(resourcePressure: .critical)
    let plan = coordinator.plan(
      frameID: 1, engine: engine, registry: GuidanceRegistry.standardPhotography)

    XCTAssertEqual(plan.local.count, 9)
    XCTAssertTrue(plan.local.allSatisfy { $0.cadence == .guardFast })
  }

  func test_critical_runtime_budget_caps_non_guard_semantic_work() {
    let semanticID = EvaluatorID("semantic.only")
    let dimensionID = DimensionID("custom.semantic")
    let registry = GuidanceRegistry(
      dimensions: [
        DimensionDefinition(
          id: dimensionID, name: "semantic", description: "semantic", scope: .node,
          valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
          evaluatorIDs: [semanticID])
      ],
      evaluators: [
        EvaluatorDefinition(
          id: semanticID, supportedDimensions: [dimensionID], kind: .semanticRemote,
          latency: .medium, cost: .medium, defaultReliability: 0.9)
      ]
    )
    let goals = (0..<4).map { index in
      GoalDefinition(
        id: GoalID("semantic_\(index)"), dimension: dimensionID,
        binding: .node(NodeID("n_\(index)")), target: .ordinal(0), constraint: .core)
    }
    let engine = GoalEngine(goals)
    var coordinator = EvaluationCoordinator(resourcePressure: .critical)
    let plan = coordinator.plan(frameID: 1, engine: engine, registry: registry)

    XCTAssertEqual(plan.semantic.count, 1)
    XCTAssertEqual(plan.semantic.first?.cadence, .focus)
  }

  func test_checkpoint_round_trips_through_json() throws {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let a = action()
    let session = GuidanceSession(goals: [g], actions: [a])
    session.planner.constraints.insert(SessionConstraint(family: "tripod"))
    session.handle(.lock(g.id))
    session.planner.recordVerification(.noEffect, action: a)

    let checkpoint = session.checkpoint()
    let data = try JSONEncoder().encode(checkpoint)
    let decoded = try JSONDecoder().decode(GuidanceSessionCheckpoint.self, from: data)

    XCTAssertEqual(decoded, checkpoint)
  }

  func test_checkpoint_restore_preserves_session_preferences_but_discards_physical_context() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let a = action()
    let original = GuidanceSession(goals: [g], actions: [a])
    original.engine.enterFramesOverride = 1
    original.engine.exitFramesOverride = 1
    _ = original.ingest(obs(.boolean(false), frame: 10))
    XCTAssertEqual(original.tick(), .propose(a))
    original.handle(.lock(g.id))
    original.planner.constraints.insert(SessionConstraint(family: "blocked-family"))
    original.planner.capabilities.insert("zoom.2x")
    original.planner.grantSafetyClearance(for: a.family)
    original.planner.recordVerification(.noEffect, action: a)
    let checkpoint = original.checkpoint()

    let restored = GuidanceSession(goals: [g], actions: [a])
    restored.planner.capabilities.insert("stale-capability")
    restored.planner.grantSafetyClearance(for: a.family)
    XCTAssertEqual(restored.restore(from: checkpoint), .restored)

    XCTAssertEqual(restored.engine.states[g.id]?.policy, .locked)
    XCTAssertEqual(restored.engine.states[g.id]?.state, .unresolved)
    XCTAssertNil(restored.engine.observation(for: g.id))
    XCTAssertNil(restored.currentTransaction)
    XCTAssertTrue(
      restored.planner.constraints.contains(SessionConstraint(family: "blocked-family")))
    XCTAssertTrue(restored.planner.capabilities.isEmpty)
    XCTAssertTrue(restored.planner.safetyClearances.isEmpty)
    XCTAssertGreaterThan(restored.planner.memory.effectModel.byAction[a.id]?.attempts ?? 0, 0)
    XCTAssertEqual(restored.readiness().state, .unknown)
    XCTAssertNotEqual(restored.tick(), .ready)
  }

  func test_checkpoint_restore_rejects_different_recipe_signature_without_mutating_session() {
    let g = goal()
    let source = GuidanceSession(goals: [g], actions: [action("a")])
    let checkpoint = source.checkpoint()
    let target = GuidanceSession(goals: [g], actions: [action("different")])

    XCTAssertEqual(target.restore(from: checkpoint), .rejectedDefinitionMismatch)
    XCTAssertTrue(target.planner.constraints.isEmpty)
    XCTAssertEqual(target.engine.states[g.id]?.policy, .normal)
  }

  func test_runtime_pause_and_resume_requires_fresh_evidence_before_ready() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let session = GuidanceSession(goals: [g], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(true), frame: 5))
    XCTAssertEqual(session.tick(), .ready)

    session.pauseRuntime(.cameraInterrupted)
    XCTAssertEqual(session.tick(), .paused)
    XCTAssertEqual(session.snapshot().runtimePauseReason, .cameraInterrupted)

    session.resumeRuntime()
    XCTAssertNil(session.snapshot().runtimePauseReason)
    XCTAssertNil(session.engine.observation(for: g.id))
    XCTAssertEqual(session.engine.states[g.id]?.state, .unresolved)
    XCTAssertNotEqual(session.tick(), .ready)

    _ = session.ingest(obs(.boolean(true), frame: 1))
    XCTAssertEqual(session.tick(), .ready)
  }

  func test_runtime_pause_resume_replays_deterministically() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let events: [GuidanceReplayEvent] = [
      .observation(obs(.boolean(true), frame: 1)),
      .tick,
      .runtimePause(.appBackgrounded),
      .tick,
      .runtimeResume,
      .tick,
    ]
    let result = GuidanceReplayer().replay(events, goals: [g], actions: [action()]) { session in
      session.engine.enterFramesOverride = 1
    }

    XCTAssertEqual(result.decisions[0], .ready)
    XCTAssertEqual(result.decisions[1], .paused)
    XCTAssertNotEqual(result.decisions[2], .ready)
    XCTAssertNil(result.snapshot.runtimePauseReason)
  }

  func test_processed_frame_clock_times_out_verification_without_new_goal_observation() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    session.verificationFrameTimeout = 3
    _ = session.ingest(obs(.boolean(false), frame: 10))
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.done)
    XCTAssertEqual(session.currentTransaction?.state, .verifyRequested)

    session.advanceFrame(11)
    session.advanceFrame(12)
    XCTAssertNotNil(session.currentTransaction)
    session.advanceFrame(13)

    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.verification, .inconclusive)
    XCTAssertFalse(session.planner.needsReobserve)
    XCTAssertEqual(session.lastObservedFrame, 13)
  }

  func test_valid_unmatched_observation_still_advances_controller_frame_clock() {
    let session = GuidanceSession(goals: [goal()], actions: [action()])
    let unrelated = Observation(
      dimension: DimensionID("unbound.dimension"), binding: .frame, value: .boolean(true),
      confidence: 1, frameID: 27)

    XCTAssertTrue(session.ingest(unrelated).isEmpty)
    XCTAssertEqual(session.lastObservedFrame, 27)
  }

  func test_user_satisfied_cancels_pending_verification_immediately() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.done)
    XCTAssertTrue(session.planner.needsReobserve)

    session.handle(.satisfied)

    XCTAssertNil(session.currentTransaction)
    XCTAssertFalse(session.planner.needsReobserve)
    XCTAssertNil(session.verificationRequestedAfterFrame)
    XCTAssertEqual(session.tick(), .readyByUser)
  }

  func test_skip_goal_cancels_transaction_and_clears_pending_verification() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.done)
    XCTAssertTrue(session.planner.needsReobserve)

    session.handle(.skip(g))

    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.state, .cancelled)
    XCTAssertFalse(session.planner.needsReobserve)
    XCTAssertNil(session.verificationRequestedAfterFrame)
    XCTAssertEqual(session.engine.states[g]?.policy, .skipped)
  }

  func test_replay_includes_capability_safety_and_processed_frame_inputs() {
    let guardedAction = action(
      "guarded", safety: .contextDependent, capability: "zoom.2x", family: "camera.backward")
    let session = GuidanceSession(goals: [goal()], actions: [guardedAction])
    session.engine.enterFramesOverride = 1
    session.updateCapabilities(["zoom.2x"])
    session.grantSafetyClearance(for: "camera.backward")
    session.advanceFrame(4)
    _ = session.ingest(obs(.boolean(false), frame: 4))
    XCTAssertEqual(session.tick(), .propose(guardedAction))

    let replay = GuidanceReplayer().replay(
      session.replayEvents, goals: [goal()], actions: [guardedAction]
    ) { replaySession in
      replaySession.engine.enterFramesOverride = 1
    }

    XCTAssertEqual(replay.decisions.last, .propose(guardedAction.id))
    XCTAssertEqual(replay.snapshot.capabilities, ["zoom.2x"])
    XCTAssertEqual(replay.snapshot.safetyClearances, ["camera.backward"])
    XCTAssertEqual(replay.snapshot.lastObservedFrame, 4)
  }

  func test_checkpoint_restore_event_makes_post_restore_replay_self_contained() {
    let g = goal(stability: .init(enterFrames: 1, exitFrames: 1))
    let a = action(family: "blocked")
    let source = GuidanceSession(goals: [g], actions: [a])
    source.planner.constraints.insert(SessionConstraint(family: "blocked"))
    let checkpoint = source.checkpoint()

    let resumed = GuidanceSession(goals: [g], actions: [a])
    resumed.engine.enterFramesOverride = 1
    XCTAssertEqual(resumed.restore(from: checkpoint), .restored)
    _ = resumed.ingest(obs(.boolean(false), frame: 1))
    XCTAssertEqual(resumed.tick(), .unreachable)

    let replay = GuidanceReplayer().replay(resumed.replayEvents, goals: [g], actions: [a]) {
      replaySession in
      replaySession.engine.enterFramesOverride = 1
    }
    XCTAssertEqual(replay.decisions.last, .unreachable)
    XCTAssertEqual(replay.snapshot.constraints, [SessionConstraint(family: "blocked")])
  }

  func test_snapshot_exposes_transaction_and_runtime_context_for_failure_audit() {
    let a = action(capability: "move.allowed")
    let session = GuidanceSession(goals: [goal()], actions: [a])
    session.engine.enterFramesOverride = 1
    session.updateCapabilities(["move.allowed"])
    _ = session.ingest(obs(.boolean(false), frame: 2))
    XCTAssertEqual(session.tick(), .propose(a))
    session.handle(.done)

    let snapshot = session.snapshot()
    XCTAssertEqual(snapshot.currentActionID, a.id)
    XCTAssertEqual(snapshot.currentActionState, .verifyRequested)
    XCTAssertTrue(snapshot.verificationPending)
    XCTAssertEqual(snapshot.capabilities, ["move.allowed"])
    XCTAssertEqual(snapshot.tickSequence, 1)
  }

  func test_runtime_invariant_checker_detects_broken_verification_lifecycle() {
    let g = goal()
    let a = action()
    let engine = GoalEngine([g])
    let planner = ActionPlanner()
    var instance = ActionInstance(a)
    instance.state = .verifyRequested

    let issues = RuntimeInvariantChecker().check(
      engine: engine,
      planner: planner,
      currentAction: instance,
      verificationRequestedAfterFrame: nil
    )

    XCTAssertTrue(issues.contains { $0.rule == .verificationLifecycleMismatch })
  }

  func test_session_lifecycle_invariants_remain_clean_across_done_and_user_satisfied() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    _ = session.ingest(obs(.boolean(false), frame: 1))
    _ = session.tick()
    session.handle(.done)
    XCTAssertFalse(
      session.invariantIssues().contains { $0.rule == .verificationLifecycleMismatch })

    session.handle(.satisfied)
    _ = session.tick()
    XCTAssertFalse(
      session.invariantIssues().contains {
        $0.rule == .verificationLifecycleMismatch
          || $0.rule == .userSatisfiedWithPendingAction
          || $0.rule == .readyWithPendingAction
      })
  }

  func test_same_frame_batch_verifies_before_timeout_boundary() {
    let session = GuidanceSession(
      goals: [goal(stability: .init(enterFrames: 1, exitFrames: 1))], actions: [action()])
    session.engine.enterFramesOverride = 1
    session.verificationFrameTimeout = 3
    _ = session.ingest(obs(.boolean(false), frame: 10))
    XCTAssertEqual(session.tick(), .propose(action()))
    session.handle(.done)

    let unrelated = Observation(
      dimension: DimensionID("other"), binding: .frame, value: .boolean(true), confidence: 1,
      frameID: 13)
    _ = session.ingestBatch([
      unrelated,
      obs(.boolean(true), frame: 13),
    ])

    XCTAssertNil(session.currentTransaction)
    XCTAssertEqual(session.lastAction?.verification, .improved)
    XCTAssertEqual(session.lastObservedFrame, 13)
  }

  func test_extended_replay_events_round_trip_through_json() throws {
    let g = goal()
    let a = action()
    let source = GuidanceSession(goals: [g], actions: [a])
    let checkpoint = source.checkpoint()
    let events: [GuidanceReplayEvent] = [
      .frame(9),
      .capabilities(["zoom.2x"]),
      .safetyClearance(family: "camera.backward", granted: true),
      .resetUserOverrides,
      .restore(checkpoint),
    ]

    let data = try JSONEncoder().encode(events)
    let decoded = try JSONDecoder().decode([GuidanceReplayEvent].self, from: data)
    XCTAssertEqual(decoded, events)
  }

  func test_checkpoint_v2_rejects_registry_contract_change() {
    let g = goal()
    let a = action()
    let registryA = testRegistry()
    let source = GuidanceSession(goals: [g], actions: [a], registry: registryA)
    let checkpoint = source.checkpoint()
    XCTAssertEqual(checkpoint.schemaVersion, 2)

    let changedEvaluator = EvaluatorDefinition(
      id: EvaluatorID("vision.local"),
      supportedDimensions: [d],
      kind: .localVision,
      latency: .realtime,
      cost: .veryLow,
      defaultReliability: 0.33
    )
    let changedRegistry = GuidanceRegistry(
      nodes: Array(registryA.nodes.values),
      relations: Array(registryA.relations.values),
      dimensions: Array(registryA.dimensions.values),
      evaluators: Array(registryA.evaluators.values.filter { $0.id != changedEvaluator.id })
        + [changedEvaluator]
    )
    let target = GuidanceSession(goals: [g], actions: [a], registry: changedRegistry)

    XCTAssertEqual(target.restore(from: checkpoint), .rejectedDefinitionMismatch)
  }

  func test_checkpoint_v1_migration_sanitizes_stale_evaluator_priors() {
    let g = goal()
    let a = action()
    let registry = testRegistry()
    let legacySignature = SessionDefinitionSignature(
      goals: [g], actions: [a], goalGroups: [], registry: nil)
    let staleModel = EvaluatorReliabilityModel(
      baseReliability: [EvaluatorID("removed.evaluator"): 0.12])
    let legacy = GuidanceSessionCheckpoint(
      schemaVersion: 1,
      signature: legacySignature,
      goalPolicies: [g.id: .normal],
      planner: PlannerCheckpoint(constraints: [], lockedGoals: [], memory: .init()),
      evaluatorReliability: staleModel,
      sourceFrameID: 0
    )
    let target = GuidanceSession(goals: [g], actions: [a], registry: registry)

    XCTAssertEqual(target.restore(from: legacy), .restored)
    XCTAssertNil(
      target.engine.evaluatorReliability.baseReliability[EvaluatorID("removed.evaluator")])
    XCTAssertEqual(
      target.engine.evaluatorReliability.baseReliability[EvaluatorID("vision.local")],
      registry.evaluators[EvaluatorID("vision.local")]?.defaultReliability
    )
  }

  private func testRegistry() -> GuidanceRegistry {
    let standard = GuidanceRegistry.standardPhotography
    return GuidanceRegistry(
      nodes: [
        NodeDefinition(
          id: n, type: .entity, semanticClass: "person", roles: ["PRIMARY_SUBJECT"],
          presence: .required)
      ],
      relations: [],
      dimensions: Array(standard.dimensions.values),
      evaluators: Array(standard.evaluators.values)
    )
  }

}
