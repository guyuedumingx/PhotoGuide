@preconcurrency import AVFoundation
import CameraRuntime
import Combine
import Foundation
import GuidanceCore
import ImageIO
import PerceptionRuntime
import RecipeKit
import SwiftUI
import UIKit

@MainActor
public final class GuidanceViewModel: ObservableObject {
  @Published public private(set) var instruction = L("把人物放进画面")
  @Published public private(set) var instructionDetail = L("我会一次只给你一个动作")
  @Published public private(set) var instructionSymbol = "viewfinder"
  @Published public private(set) var status = L("正在准备相机")
  @Published public private(set) var isDemoMode = false
  @Published public private(set) var isPermissionBlocked = false
  @Published public private(set) var progress = 0.0
  @Published public private(set) var progressLabel = "0 / 8"
  @Published public private(set) var currentAction: ActionDefinition?
  @Published public private(set) var personBounds: CGRect?
  @Published public private(set) var anchorBounds: CGRect?
  @Published public private(set) var anchorPoint: CGPoint?
  @Published public private(set) var personPresent = false
  @Published public private(set) var isReady = false
  @Published public private(set) var isPausedByUser = false
  @Published public private(set) var cameraPosition: CameraPosition = .back
  @Published public private(set) var flashMode: CameraFlashMode = .off
  @Published public private(set) var zoomFactors: [Double] = [1]
  @Published public private(set) var zoomFactor: Double = 1
  @Published public private(set) var isInteractiveZooming = false
  @Published public private(set) var lastPhoto: UIImage?
  @Published public private(set) var recentPhoto: UIImage?
  @Published public private(set) var recentPhotoSaved = false
  @Published public private(set) var photoSaved = false
  @Published public private(set) var isSaving = false
  @Published public private(set) var isApplyingAutomaticAction = false
  @Published public private(set) var conformance: Conformance = .low
  @Published public private(set) var previewCue: CameraGuideCue = .none
  @Published public private(set) var compositionGuide: CompositionGuide = .none
  @Published public private(set) var isCurrentActionSafetySensitive = false
  @Published public private(set) var transientNotice: String?
  @Published public private(set) var exposureBias: Double = 0
  @Published public private(set) var exposureBiasRange: ClosedRange<Double> = -2...2
  @Published public private(set) var supportsExposureBias = false
  @Published public private(set) var exposureReadout = L("自动曝光")

  public let camera = CameraService()
  public let recipe: CompiledRecipe
  private let checkpointStore = SessionCheckpointStore()

  private let localEvaluator = LocalPersonEvaluator(
    maximumFramesPerSecond: 8, anchorFramesPerSecond: 2)
  private var evaluationCoordinator = EvaluationCoordinator()
  private let semanticGate = FreshSemanticResultGate()
  private var semanticStabilizer = ObservationStabilizer()
  private let semanticBatchValidator = SemanticBatchValidator()
  private var semanticEvaluator: (any SemanticEvaluating)?
  private var semanticInFlight = false
  private var semanticTask: Task<Void, Never>?
  private var lastSemanticRequestAt = Date.distantPast
  private var semanticSuppressedUntil = Date.distantPast
  private var session: GuidanceSession
  private var cameraTask: Task<Void, Never>?
  private var currentFrameID = 0
  private var bindingVersion = 0
  private var sceneRevision = 0
  private var completedDemoGoals = Set<GoalID>()
  private var statusHoldUntil = Date.distantPast
  private var noticeTask: Task<Void, Never>?
  private var lastExposureUIUpdate = Date.distantPast
  private var interactiveZoomBase: Double = 1
  private var interactiveZoomTask: Task<Void, Never>?

  public init() {
    let loaded = RecipeLoader().loadEnvironmentalPortrait()
    recipe = loaded
    session = GuidanceSession(
      goals: loaded.goals, actions: loaded.actions, registry: loaded.registry)
    if let checkpoint = checkpointStore.load(key: loaded.source.id) {
      let result = session.restore(from: checkpoint)
      if result == .restored { checkpointStore.clear(key: loaded.source.id) }
    }
    if let endpointString = ProcessInfo.processInfo.environment["DJEV_ENDPOINT"],
      let endpoint = URL(string: endpointString),
      !endpointString.isEmpty
    {
      let token = ProcessInfo.processInfo.environment["DJEV_TOKEN"]
      semanticEvaluator = HTTPDJevEvaluator(
        configuration: .init(endpoint: endpoint, bearerToken: token))
    }
    updateProgress()
  }

  public var title: String { L("环境人像") }
  public var subtitle: String { L("人物自然，景色也有存在感") }
  public var needsAnchorSelection: Bool { personPresent && anchorPoint == nil }
  public var canSkipCurrentGoal: Bool {
    guard let goalID = currentAction?.improvedGoals.first else { return false }
    return recipe.source.authorPolicy.allowGoalSkip && session.canSkip(goalID)
  }

  public var primaryActionTitle: String {
    isCurrentActionAutomatable ? L("应用调整") : L("完成调整")
  }

  public func start() {
    guard cameraTask == nil else { return }
    cameraTask = Task { [weak self] in
      guard let self else { return }
      let availability = await camera.requestAccessAndPrepare()
      if Task.isCancelled { return }
      switch availability {
      case .ready:
        isDemoMode = false
        isPermissionBlocked = false
        camera.start()
        syncCameraCapabilities()
        status = L("本地视觉已开启")
        await consumeFrames()
      case .denied:
        isPermissionBlocked = true
        status = L("需要相机权限才能开始")
      case .unavailable:
        if camera.authorizationStatus == .restricted {
          isPermissionBlocked = true
          status = L("此设备限制了相机访问")
        } else {
          enterDemoMode()
        }
      case .unknown:
        status = L("相机尚未就绪")
      }
    }
  }

  public func stop() {
    cameraTask?.cancel()
    cameraTask = nil
    semanticTask?.cancel()
    semanticTask = nil
    semanticInFlight = false
    semanticStabilizer.reset()
    interactiveZoomTask?.cancel()
    interactiveZoomTask = nil
    isInteractiveZooming = false
    camera.stop()
  }

  public func pauseForBackground() {
    try? checkpointStore.save(session.checkpoint(), key: recipe.source.id)
    session.pauseRuntime(.appBackgrounded)
    stop()
  }

  public func resumeAfterForegrounding() {
    session.resumeRuntime()
    evaluationCoordinator.resetCadenceOnly()
    semanticStabilizer.reset()
    stop()
    start()
  }

  public func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  public func selectAnchor(_ tap: CameraTapPoint) {
    let selectingAnchor = anchorPoint == nil
    if selectingAnchor {
      anchorPoint = tap.imageNormalized
      anchorBounds = nil
      sceneRevision += 1
      showStatus(L("背景主体已选中"), holdFor: 1.4)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } else {
      showStatus(L("已对焦"), holdFor: 0.9)
      UISelectionFeedbackGenerator().selectionChanged()
    }
    Task { try? await camera.focus(atDevicePoint: tap.deviceFocus) }
  }

  public func reselectAnchor() {
    guard anchorPoint != nil else { return }
    anchorPoint = nil
    anchorBounds = nil
    sceneRevision += 1
    semanticTask?.cancel()
    semanticTask = nil
    semanticInFlight = false
    semanticStabilizer.reset()
    showStatus(L("点一下你想保留的背景主体"), holdFor: 2)
    refreshDecision()
  }

  public func performPrimaryAction() {
    guard !isApplyingAutomaticAction else { return }
    guard isCurrentActionAutomatable, let targetZoom = automaticZoomTarget() else {
      handleDone()
      return
    }

    if isDemoMode {
      zoomFactor = targetZoom
      handleDone()
      return
    }

    isApplyingAutomaticAction = true
    Task { [weak self] in
      guard let self else { return }
      do {
        try await camera.setZoomFactor(targetZoom)
        zoomFactor = targetZoom
        syncCameraCapabilities()
        // Keep the controller scene revision stable for the action verifier: this
        // camera change is the action being verified, not an unrelated scene swap.
        // Any semantic request captured before the zoom is cancelled instead.
        semanticTask?.cancel()
        semanticTask = nil
        semanticInFlight = false
        semanticStabilizer.reset()
        showStatus(L("焦段已调整，正在复核"), holdFor: 1.2)
        handleDone()
      } catch {
        showStatus(localized(error), holdFor: 2.5)
      }
      isApplyingAutomaticAction = false
    }
  }

  public func handleDone() {
    if isDemoMode, let goal = currentAction?.improvedGoals.first { completedDemoGoals.insert(goal) }
    session.handle(.done)
    currentAction = nil
    instruction = L("保持一下")
    instructionDetail = L("正在检查刚才的调整有没有起作用")
    instructionSymbol = "waveform.path.ecg"
    showStatus(L("复核新画面"), holdFor: 1.2)
    refreshDecision()
  }

  public func handleAnotherWay() {
    session.handle(.anotherWay)
    refreshDecision()
  }
  public func handleImpossible() {
    session.handle(.impossible)
    refreshDecision()
  }
  public func handleCancel() {
    session.handle(.cancel)
    refreshDecision()
  }

  public func handleLooksGood() {
    session.handle(.satisfied)
    isPausedByUser = true
    refreshDecision()
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  public func resumeGuidance() {
    session.handle(.resumeGuidance)
    isPausedByUser = false
    refreshDecision()
  }

  public func lockCurrentComposition() {
    let satisfied = session.engine.states.compactMap { entry -> GoalID? in
      guard entry.value.state == .satisfied,
        session.engine.definitions[entry.key]?.constraint != .hard
      else { return nil }
      return entry.key
    }
    for goal in satisfied { session.handle(.lock(goal)) }
    showStatus(satisfied.isEmpty ? L("现在还没有可锁定的构图") : L("已锁住当前满意的部分"), holdFor: 2)
    refreshDecision()
  }

  public func skipCurrentGoal() {
    guard let goal = currentAction?.improvedGoals.first, canSkipCurrentGoal else { return }
    session.handle(.skip(goal))
    showStatus(L("这一项已跳过，不会继续追着你调整"), holdFor: 2)
    refreshDecision()
  }

  public func resetAll() {
    checkpointStore.clear(key: recipe.source.id)
    anchorPoint = nil
    anchorBounds = nil
    sceneRevision += 1
    localEvaluator.resetTracking()
    rebuildSession()
    showStatus(L("重新开始 · 先把人物放进画面"), holdFor: 1.8)
  }

  public func switchCamera() {
    guard !isDemoMode else { return }
    let target: CameraPosition = cameraPosition == .back ? .front : .back
    Task { [weak self] in
      guard let self else { return }
      do {
        try await camera.switchCamera(to: target)
        cameraPosition = target
        anchorPoint = nil
        anchorBounds = nil
        sceneRevision += 1
        localEvaluator.resetTracking()
        rebuildSession()
        syncCameraCapabilities()
        showStatus(target == .back ? L("后置相机") : L("前置相机"), holdFor: 1.4)
      } catch { showStatus(localized(error), holdFor: 3) }
    }
  }

  public func cycleFlash() {
    guard !isDemoMode, cameraPosition == .back else { return }
    let target: CameraFlashMode =
      switch flashMode {
      case .off: .auto
      case .auto: .on
      case .on: .off
      }
    Task { [weak self] in
      guard let self else { return }
      do {
        try await camera.setFlashMode(target)
        flashMode = target
      } catch {
        flashMode = .off
        showStatus(localized(error), holdFor: 2.5)
      }
    }
  }

  public func setZoom(_ factor: Double) {
    guard !isDemoMode else {
      zoomFactor = factor
      return
    }
    let previousZoom = zoomFactor
    Task { [weak self] in
      guard let self else { return }
      do {
        try await camera.setZoomFactor(factor)
        zoomFactor = factor
        syncCameraCapabilities()
        invalidateSemanticAfterOpticalChange()
        UISelectionFeedbackGenerator().selectionChanged()
        completeZoomActionIfMatched(factor, from: previousZoom)
      } catch { showStatus(localized(error), holdFor: 2) }
    }
  }

  public func handleZoomGesture(_ gesture: CameraZoomGesture) {
    guard !isDemoMode else { return }
    switch gesture.phase {
    case .began:
      interactiveZoomBase = zoomFactor
      isInteractiveZooming = true
      invalidateSemanticAfterOpticalChange()
    case .changed:
      let range = interactiveZoomRange
      let target = min(max(interactiveZoomBase * gesture.scale, range.lowerBound), range.upperBound)
      zoomFactor = target
      interactiveZoomTask?.cancel()
      interactiveZoomTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(22))
        guard !Task.isCancelled, let self else { return }
        try? await camera.setZoomFactor(target, animated: false)
      }
    case .ended:
      let target = zoomFactor
      interactiveZoomTask?.cancel()
      interactiveZoomTask = Task { [weak self] in
        guard let self else { return }
        do {
          try await camera.setZoomFactor(target, animated: false)
          syncCameraCapabilities()
          completeZoomActionIfMatched(target, from: interactiveZoomBase)
        } catch {
          showStatus(localized(error), holdFor: 2)
          syncCameraCapabilities()
        }
        isInteractiveZooming = false
      }
    case .cancelled:
      interactiveZoomTask?.cancel()
      isInteractiveZooming = false
      syncCameraCapabilities()
    }
  }

  public func setExposureBias(_ value: Double) {
    guard supportsExposureBias, !isDemoMode else { return }
    let clamped = min(max(value, exposureBiasRange.lowerBound), exposureBiasRange.upperBound)
    exposureBias = clamped
    Task { [weak self] in
      guard let self else { return }
      do {
        try await camera.setExposureBias(Float(clamped))
        exposureBias = Double(camera.exposureBias)
      } catch {
        showStatus(localized(error), holdFor: 2)
        syncCameraCapabilities()
      }
    }
  }

  public func resetExposureBias() {
    setExposureBias(0)
    showStatus(L("亮度已回到自动基准"), holdFor: 1.1)
  }

  /// The shutter never becomes a hard lock. PhotoGuide advises; the person decides.
  public func capture() {
    guard !isSaving else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    guard !isDemoMode else {
      showStatus(L("模拟器不拍照，真机上快门始终可用"), holdFor: 2.2)
      return
    }
    isSaving = true
    photoSaved = false
    Task { [weak self] in
      guard let self else { return }
      do {
        let image = try await camera.capturePhoto()
        lastPhoto = image
        recentPhoto = image
        recentPhotoSaved = false
        let result = await camera.savePhotoToLibrary(image)
        switch result {
        case .success:
          photoSaved = true
          recentPhotoSaved = true
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure(let error):
          photoSaved = false
          recentPhotoSaved = false
          showStatus(localized(error), holdFor: 3)
        }
      } catch {
        showStatus(localized(error), holdFor: 3)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
      }
      isSaving = false
    }
  }

  public func dismissReview() {
    lastPhoto = nil
    photoSaved = false
    showStatus(L("继续拍"), holdFor: 1)
  }

  public func openRecentPhotoReview() {
    guard let recentPhoto else { return }
    lastPhoto = recentPhoto
    photoSaved = recentPhotoSaved
  }

  private var interactiveZoomRange: ClosedRange<Double> {
    let factors = camera.capabilities.displayZoomFactors
    let lower = factors.min() ?? 1
    let upper = factors.max() ?? max(lower, 1)
    return lower...max(lower, upper)
  }

  private func invalidateSemanticAfterOpticalChange() {
    semanticTask?.cancel()
    semanticTask = nil
    semanticInFlight = false
    semanticStabilizer.reset()
    semanticSuppressedUntil = Date().addingTimeInterval(0.28)
  }

  private func completeZoomActionIfMatched(_ factor: Double, from previous: Double? = nil) {
    guard let action = currentAction, action.actor == .camera, action.operation == .zoom else {
      return
    }
    let matched: Bool
    switch action.presentationKey {
    case "camera.zoom_2x":
      matched = abs(factor - 2) <= 0.20
    case "camera.zoom_out":
      matched = previous.map { factor < $0 - 0.08 } ?? false
    default:
      matched = automaticZoomTarget().map { abs($0 - factor) <= 0.10 } ?? false
    }
    guard matched else { return }
    showStatus(L("焦段已调整，正在复核"), holdFor: 1.1)
    handleDone()
  }

  private var isCurrentActionAutomatable: Bool {
    guard let action = currentAction else { return false }
    return action.actor == .camera && action.operation == .zoom && automaticZoomTarget() != nil
  }

  private func automaticZoomTarget() -> Double? {
    guard let action = currentAction, action.actor == .camera, action.operation == .zoom else {
      return nil
    }

    if action.presentationKey == "camera.zoom_2x" {
      return zoomFactors.min(by: { abs($0 - 2) < abs($1 - 2) }).flatMap { candidate in
        abs(candidate - 2) <= 0.20 ? candidate : nil
      }
    }

    if action.presentationKey == "camera.zoom_out" {
      return zoomFactors.filter { $0 < zoomFactor - 0.08 }.max() ?? zoomFactors.min()
    }

    return nil
  }

  private func consumeFrames() async {
    for await frame in camera.frames() {
      if Task.isCancelled { return }
      currentFrameID = frame.id
      updateExposureTelemetry(frame.exposure)
      if !isInteractiveZooming, abs(zoomFactor - frame.zoomFactor) > 0.01 {
        zoomFactor = frame.zoomFactor
      }
      let anchor = anchorPoint.map { NormalizedPoint(x: $0.x, y: $0.y) }
      guard
        let scene = await localEvaluator.evaluateScene(
          frame.pixelBuffer, orientation: .up, anchorPoint: anchor, frameID: frame.id)
      else { continue }
      if bindingVersion != 0, scene.bindingVersion != bindingVersion {
        bindingVersion = scene.bindingVersion
        rebuildSession(keepAnchor: true)
        showStatus(L("拍摄对象发生变化，已重新评估"), holdFor: 1.8)
      } else {
        bindingVersion = scene.bindingVersion
      }
      session.updateSceneConditions(
        scene.conditions.withContext(frameID: frame.id, sceneRevision: sceneRevision))
      ingestLocal(scene, frameID: frame.id)
      scheduleSemanticEvaluation(for: frame)
    }
  }

  private func updateRuntimePressureFromSystem() {
    let pressure: RuntimeResourcePressure
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
      pressure = .nominal
    case .fair, .serious:
      pressure = .constrained
    case .critical:
      pressure = .critical
    @unknown default:
      pressure = .constrained
    }
    evaluationCoordinator.updateResourcePressure(pressure)
  }

  private func scheduleSemanticEvaluation(for frame: CameraFrame) {
    guard let evaluator = semanticEvaluator,
      !semanticInFlight,
      Date() >= semanticSuppressedUntil,
      Date().timeIntervalSince(lastSemanticRequestAt) >= 0.45
    else { return }

    updateRuntimePressureFromSystem()
    let plan = evaluationCoordinator.plan(
      frameID: frame.id, engine: session.engine, registry: recipe.registry)
    guard !plan.semantic.isEmpty else { return }
    semanticInFlight = true
    lastSemanticRequestAt = .now
    let requestFrame = frame.id
    let requestBindingVersion = bindingVersion
    let requestSceneRevision = sceneRevision
    let slots = plan.semantic.compactMap { slot -> PerceptionRuntime.SemanticSlot? in
      guard let goal = session.engine.definitions[slot.goalID],
        let dimension = recipe.registry.dimensions[slot.dimension]
      else { return nil }
      return PerceptionRuntime.SemanticSlot(
        goalID: slot.goalID,
        dimension: slot.dimension,
        binding: slot.binding,
        target: goal.target,
        name: dimension.name,
        description: dimension.description
      )
    }
    guard !slots.isEmpty else {
      semanticInFlight = false
      return
    }
    let frameForEncoding = frame

    semanticTask = Task { [weak self] in
      guard let self else { return }
      defer {
        semanticInFlight = false
        semanticTask = nil
      }
      let payload = await Task.detached(priority: .utility) {
        SemanticFrameEncoder.jpegData(from: frameForEncoding.pixelBuffer)
      }.value
      guard !Task.isCancelled, let payload else { return }
      do {
        let response = try await evaluator.evaluate(
          .init(
            frameID: requestFrame,
            sceneRevision: requestSceneRevision,
            bindingVersion: requestBindingVersion,
            slots: slots,
            imagePayload: payload
          ))
        guard !Task.isCancelled else { return }
        if semanticGate.accepts(
          response,
          currentFrameID: currentFrameID,
          currentBindingVersion: bindingVersion,
          currentSceneRevision: sceneRevision
        ) {
          let validated = semanticBatchValidator.validate(
            observations: response.observations,
            expectedSlots: plan.semantic,
            frameID: requestFrame,
            bindingVersion: requestBindingVersion,
            sceneRevision: requestSceneRevision,
            registry: recipe.registry
          )
          if validated.accepted.isEmpty, !validated.issues.isEmpty {
            evaluationCoordinator.recordEvaluatorFailure(
              EvaluatorID("djev.semantic"), kind: .rejectedOutput, frameID: requestFrame)
          } else if !validated.accepted.isEmpty {
            evaluationCoordinator.recordEvaluatorSuccess(
              EvaluatorID("djev.semantic"), frameID: requestFrame)
          }
          let stabilized = validated.accepted.map { observation in
            semanticStabilizer.ingest(observation).observation
          }
          if !stabilized.isEmpty {
            _ = session.ingestBatch(stabilized)
            refreshDecision()
          }
        }
      } catch {
        let fault: EvaluatorFaultKind
        if let urlError = error as? URLError, urlError.code == .timedOut {
          fault = .timeout
        } else if error is DecodingError {
          fault = .invalidPayload
        } else {
          fault = .transport
        }
        evaluationCoordinator.recordEvaluatorFailure(
          EvaluatorID("djev.semantic"), kind: fault, frameID: requestFrame)
        // Remote semantics are additive. Local guidance stays live on any failure.
      }
    }
  }

  private func ingestLocal(_ scene: SceneObservation, frameID: Int) {
    let primary: GuidanceCore.Binding = .node(NodeID("primary"))
    let relation: GuidanceCore.Binding = .relation(RelationID("primary_anchor"))
    let person = scene.person
    let confidence = person.confidence
    var observations: [Observation] = [
      .init(
        dimension: DimensionID("std.node.exists"), binding: primary,
        value: .boolean(person.present), confidence: confidence,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
      .init(
        dimension: DimensionID("std.node.visibility"), binding: primary,
        value: .boolean(person.visible), confidence: confidence,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
      .init(
        dimension: DimensionID("std.node.visual_scale"), binding: primary,
        value: .continuous(person.scale), confidence: confidence,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
      .init(
        dimension: DimensionID("std.node.position_x"), binding: primary,
        value: .continuous(person.x), confidence: confidence,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
      .init(
        dimension: DimensionID("std.node.position_y"), binding: primary,
        value: .continuous(person.y), confidence: confidence,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
      .init(
        dimension: DimensionID("std.pose.body_orientation"), binding: primary,
        value: .ordinal(person.bodyOrientation ?? 0),
        confidence: person.bodyOrientation == nil ? 0 : confidence * 0.82,
        evaluator: EvaluatorID("vision.local"), frameID: frameID, bindingVersion: bindingVersion,
        sceneRevision: sceneRevision),
    ]

    if let composition = scene.composition {
      observations.append(
        .init(
          dimension: DimensionID("std.relation.relative_scale"), binding: relation,
          value: .ordinal(composition.relativeScale), confidence: composition.confidence,
          evaluator: EvaluatorID("vision.saliency_relation"), frameID: frameID,
          bindingVersion: bindingVersion, sceneRevision: sceneRevision))
      observations.append(
        .init(
          dimension: DimensionID("std.relation.visual_balance"), binding: relation,
          value: .ordinal(composition.visualBalance), confidence: composition.confidence,
          evaluator: EvaluatorID("vision.saliency_relation"), frameID: frameID,
          bindingVersion: bindingVersion, sceneRevision: sceneRevision))
    }

    // One perception frame is one atomic controller input. This prevents an
    // early observation in the frame from triggering a verification timeout
    // before a later observation from the same frame can satisfy the action.
    _ = session.ingestBatch(observations)

    personPresent = person.present
    personBounds = person.bounds?.cgRect
    anchorBounds = scene.anchor?.bounds.cgRect
    refreshDecision()
  }

  private func refreshDecision() {
    let wasReady = isReady
    syncCameraCapabilities()
    previewCue = .none
    compositionGuide = .none
    isCurrentActionSafetySensitive = false
    if !isDemoMode, personPresent, anchorPoint == nil {
      currentAction = nil
      isReady = false
      instruction = L("选一下背景主体")
      instructionDetail = L("点你想保留的山、建筑、树或地标")
      instructionSymbol = "scope"
      defaultStatus(L("人物已找到 · 还差背景主体"))
      updateProgress()
      return
    }

    let decision = session.tick()
    if let transaction = session.currentTransaction, transaction.state != .verifyRequested {
      currentAction = transaction.definition
    } else {
      currentAction = nil
    }
    conformance = session.readiness().conformance

    switch decision {
    case .propose(let action):
      let presented = ActionPresenter.present(action)
      instruction = presented.title
      instructionDetail = presented.detail
      instructionSymbol = presented.symbol
      previewCue = presented.previewCue
      compositionGuide = presented.compositionGuide
      isCurrentActionSafetySensitive = presented.isSafetySensitive
      isReady = false
      isPausedByUser = false
      defaultStatus(L("完成后点“完成”，我会看新画面"))
    case .ready:
      instruction = L("现在就很好")
      instructionDetail = L("关键部分已经到位，保持住直接拍")
      instructionSymbol = "checkmark.circle.fill"
      isReady = true
      isPausedByUser = false
      if !wasReady { UINotificationFeedbackGenerator().notificationOccurred(.success) }
      defaultStatus(L("已达到可拍状态"))
    case .readyByUser:
      instruction = L("按你喜欢的样子拍")
      instructionDetail = L("我先不继续打扰；想再优化可以恢复指导")
      instructionSymbol = "heart.fill"
      isReady = true
      isPausedByUser = true
      defaultStatus(L("已暂停主动优化"))
    case .paused:
      instruction = L("先拍也可以")
      instructionDetail = L("刚才连续调整有点多，我先停一下；想继续时再恢复指导")
      instructionSymbol = "pause.circle.fill"
      isReady = false
      isPausedByUser = true
      defaultStatus(L("主动指导已暂停"))
    case .requestEvidence(let request):
      instruction = personPresent ? L("保持一下") : L("把人物放进画面")
      switch request.reason {
      case .hardGuardUnknown:
        instructionDetail = personPresent ? L("关键画面信息还没确认，先别急着动") : L("先让人物完整进入画面")
      case .coreUnknown:
        instructionDetail = L("我正在补充构图判断，保持一秒即可")
      case .lowConfidence:
        instructionDetail = L("当前画面不够稳定，先保持一下")
      case .staleOrMissing:
        instructionDetail = L("需要一帧更新的画面再继续指导")
      }
      instructionSymbol = "eye"
      isReady = false
      defaultStatus(L("正在补充证据"))
    case .wait:
      instruction = L("保持一下")
      instructionDetail =
        session.lastAction?.verification == .oppositeEffect
        ? L("刚才的变化和预期相反，我在重新判断") : L("正在确认刚才的调整")
      instructionSymbol = "waveform.path.ecg"
      isReady = false
      defaultStatus(L("等待新画面"))
    case .unknown:
      instruction = personPresent ? L("保持一秒") : L("把人物放进画面")
      instructionDetail = personPresent ? L("当前证据还不够稳定，先别急着动") : L("尽量让人物完整出现")
      instructionSymbol = "eye"
      isReady = false
      defaultStatus(L("正在确认"))
    case .unreachable:
      instruction = L("先按现在这样拍也可以")
      instructionDetail = L("当前条件下没有低成本的下一步，你随时可以按快门")
      instructionSymbol = "camera.fill"
      isReady = false
      defaultStatus(L("没有可执行的进一步调整"))
    }
    updateProgress()
  }

  private func syncCameraCapabilities() {
    let capabilities = camera.capabilities
    zoomFactors = capabilities.displayZoomFactors
    zoomFactor = camera.zoomFactor
    if let range = capabilities.exposureBiasRange {
      supportsExposureBias = true
      exposureBiasRange = Double(range.lowerBound)...Double(range.upperBound)
      exposureBias = Double(camera.exposureBias)
    } else {
      supportsExposureBias = false
      exposureBias = 0
    }
    var caps = capabilities.coreCapabilityIDs
    if let minimum = zoomFactors.min(), zoomFactor > minimum + 0.08 {
      caps.insert("zoom.out")
    } else {
      caps.remove("zoom.out")
    }
    session.updateCapabilities(caps)
  }

  private func updateProgress() {
    let critical = session.engine.states.filter { key, state in
      state.policy != .skipped && session.engine.definitions[key]?.constraint != .soft
    }
    let satisfied = critical.values.filter { $0.state == .satisfied }.count
    let total = critical.count
    progress = total == 0 ? 0 : Double(satisfied) / Double(total)
    progressLabel = "\(satisfied) / \(total)"
    conformance = session.readiness().conformance
  }

  private func enterDemoMode() {
    isDemoMode = true
    personPresent = true
    anchorPoint = CGPoint(x: 0.73, y: 0.40)
    status = L("模拟器演示 · 真机会使用实时相机")
    cameraTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        demoTick()
        try? await Task.sleep(for: .milliseconds(650))
      }
    }
  }

  private func demoTick() {
    currentFrameID += 1
    let observations = recipe.goals.map { goal -> Observation in
      let done = completedDemoGoals.contains(goal.id)
      let value: DimensionValue =
        switch goal.dimension.rawValue {
        case "std.node.exists", "std.node.visibility": .boolean(true)
        case "std.node.visual_scale": .continuous(done ? 0.20 : 0.36)
        case "std.node.position_x": .continuous(done ? 0.65 : 0.38)
        case "std.node.position_y": .continuous(done ? 0.50 : 0.75)
        default: .ordinal(done ? 0 : 2)
        }
      let evaluator =
        goal.binding == .relation(RelationID("primary_anchor"))
        ? EvaluatorID("vision.saliency_relation")
        : EvaluatorID("vision.local")
      return .init(
        dimension: goal.dimension, binding: goal.binding, value: value, confidence: 0.97,
        evaluator: evaluator, frameID: currentFrameID)
    }
    _ = session.ingestBatch(observations)
    refreshDecision()
  }

  private func rebuildSession(keepAnchor: Bool = false) {
    semanticTask?.cancel()
    semanticTask = nil
    semanticInFlight = false
    semanticStabilizer.reset()
    evaluationCoordinator.resetCadenceOnly()
    session = GuidanceSession(
      goals: recipe.goals, actions: recipe.actions, registry: recipe.registry)
    completedDemoGoals.removeAll()
    currentAction = nil
    personBounds = nil
    if !keepAnchor {
      anchorPoint = nil
      anchorBounds = nil
    }
    isReady = false
    isPausedByUser = false
    previewCue = .none
    compositionGuide = .none
    isCurrentActionSafetySensitive = false
    syncCameraCapabilities()
    updateProgress()
  }

  private func showStatus(_ value: String, holdFor seconds: TimeInterval) {
    status = value
    statusHoldUntil = Date().addingTimeInterval(seconds)
    transientNotice = value
    noticeTask?.cancel()
    noticeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      self?.transientNotice = nil
    }
  }

  private func defaultStatus(_ value: String) {
    if Date() >= statusHoldUntil { status = value }
  }

  private func updateExposureTelemetry(_ telemetry: CameraExposureTelemetry?) {
    guard let telemetry, Date().timeIntervalSince(lastExposureUIUpdate) >= 0.25 else { return }
    lastExposureUIUpdate = .now
    exposureBias = Double(telemetry.exposureBias)
    let shutter: String
    if telemetry.exposureDurationSeconds >= 0.9 {
      shutter = String(format: "%.1fs", locale: Locale.current, telemetry.exposureDurationSeconds)
    } else if telemetry.exposureDurationSeconds > 0 {
      let denominator = max(Int((1 / telemetry.exposureDurationSeconds).rounded()), 1)
      shutter = "1/\(denominator)s"
    } else {
      shutter = L("自动")
    }
    exposureReadout = "\(shutter) · ISO \(Int(telemetry.iso.rounded()))"
  }

  private func localized(_ error: Error) -> String {
    if let cameraError = error as? CameraRuntimeError {
      return switch cameraError {
      case .authorizationDenied: L("相机权限已关闭，请到设置开启")
      case .authorizationRestricted: L("此设备限制了相机访问")
      case .photoLibraryDenied: L("照片拍好了，但没有相册写入权限")
      case .photoLibraryRestricted: L("此设备限制了相册写入")
      case .flashUnavailable: L("当前摄像头不支持闪光灯")
      case .zoomUnavailable: L("这个焦段当前不可用")
      case .exposureBiasUnavailable: L("当前摄像头不支持亮度补偿")
      default: cameraError.localizedDescription
      }
    }
    return error.localizedDescription
  }
}
