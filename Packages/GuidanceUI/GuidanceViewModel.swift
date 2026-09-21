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
  @Published public private(set) var instruction = L("把主体放进画面")
  @Published public private(set) var instructionDetail = L("Recipe 会逐项比较当前画面与参考图")
  @Published public private(set) var instructionSymbol = "viewfinder"
  @Published public private(set) var status = L("正在准备相机")
  @Published public private(set) var isDemoMode = false
  @Published public private(set) var isPermissionBlocked = false
  @Published public private(set) var isCameraReady = false
  @Published public private(set) var progress = 0.0
  @Published public private(set) var progressLabel = "0 / 8"
  @Published public private(set) var currentAction: ActionDefinition?
  @Published public private(set) var subjectBounds: CGRect?
  @Published public private(set) var faceBounds: CGRect?
  @Published public private(set) var facePresent = false
  @Published public private(set) var anchorBounds: CGRect?
  @Published public private(set) var anchorPoint: CGPoint?
  @Published public private(set) var subjectPresent = false
  @Published public private(set) var isReady = false
  @Published public private(set) var isPausedByUser = false
  @Published public private(set) var cameraPosition: CameraPosition = .back
  @Published public private(set) var flashMode: CameraFlashMode = .off
  @Published public private(set) var zoomFactors: [Double] = [1]
  @Published public private(set) var zoomFactor: Double = 1
  @Published public private(set) var isInteractiveZooming = false
  @Published public private(set) var isCapturing = false
  @Published public private(set) var captureCount = 0
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
  @Published public private(set) var questionSnapshots: [QuestionRuntimeSnapshot] = []
  @Published public private(set) var currentIssueQuestionID: String?

  public let camera = CameraService()
  public let preset: RecipePreset?
  public let recipe: CompiledRecipe
  private let checkpointStore = SessionCheckpointStore()
  private var questionCoordinator: QuestionGuidanceCoordinator!

  private let localEvaluator: LocalSceneEvaluator
  private var evaluationCoordinator = EvaluationCoordinator()
  private var criticSession: SemanticCriticSession
  private var semanticSampleBuffer = SemanticSampleBuffer(capacity: 5)
  private var latestCritique: SemanticCritique? { criticSession.latestCritique }
  private var latestCritiqueAt: Date { criticSession.lastAcceptedAt ?? .distantPast }
  private var activeSemanticAdvice: CriticAdvice? { criticSession.activeAdvice }
  private var semanticEvaluator: (any MultimodalCritic)?
  private var semanticInFlight = false
  private var semanticTask: Task<Void, Never>?
  private var lastSemanticRequestAt = Date.distantPast
  private var semanticSuppressedUntil = Date.distantPast
  private var semanticFailureCount = 0
  private var semanticGeneration = 0
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
  private var lastDecisionRefreshAt = Date.distantPast
  private var verificationStartedAt: Date?
  private var manualAnchorSelectionRequested = false
  private var manualSubjectSelectionRequested = false
  private var subjectPoint: CGPoint?
  private var evidenceWaitSignature: String?
  private var evidenceWaitStartedAt: Date?
  private var cameraObservers = Set<AnyCancellable>()
  @Published public private(set) var semanticEnhanced = false
  @Published public private(set) var semanticFaulted = false
  @Published public private(set) var semanticOverallScore: Double?
  @Published public private(set) var semanticAssessmentCount = 0

  public convenience init(preset: RecipePreset = .environmentPortrait) {
    self.init(compiledRecipe: RecipeLoader().load(preset), preset: preset)
  }

  public convenience init(recipeDTO: RecipeDTO) {
    self.init(compiledRecipe: RecipeLoader().compile(recipeDTO), preset: nil)
  }

  private init(compiledRecipe loaded: CompiledRecipe, preset: RecipePreset?) {
    self.preset = preset
    criticSession = SemanticCriticSession(profile: loaded.source.resolvedCritic)
    localEvaluator = LocalSceneEvaluator(profile: Self.localPerceptionProfile(loaded.source.resolvedPerception))
    let configuredSemanticEvaluator = Self.makeSemanticEvaluator()
    let runtimeActions = Self.runtimeActions(from: loaded, semanticEnabled: configuredSemanticEvaluator != nil)
    recipe = loaded
    semanticEvaluator = configuredSemanticEvaluator
    questionCoordinator = QuestionGuidanceCoordinator(
      recipe: loaded.source,
      judge: Self.makeQuestionJudge(for: loaded.source))
    session = GuidanceSession(
      goals: loaded.goals, actions: runtimeActions, registry: loaded.registry)
    if let checkpoint = checkpointStore.load(key: loaded.source.id) {
      let result = session.restore(from: checkpoint)
      if result == .restored { checkpointStore.clear(key: loaded.source.id) }
    }
    if questionCoordinator.isConfigured { syncQuestionRuntime() }
    else { updateProgress() }
    installCameraObservers()
  }

  public var title: String { L(recipe.source.title) }

  public var subtitle: String { L(recipe.source.subtitle) }

  public var isQuestionMode: Bool { questionCoordinator.isConfigured }
  public var questionJudgeAvailable: Bool { questionCoordinator.canEvaluate }
  public var issueQuestionSnapshots: [QuestionRuntimeSnapshot] {
    questionSnapshots.filter { $0.status == .issue && $0.issue != nil }
  }
  public var selectedIssueSnapshot: QuestionRuntimeSnapshot? {
    guard let id = currentIssueQuestionID else { return nil }
    return issueQuestionSnapshots.first(where: { $0.id == id })
  }
  public var canSkipCurrentQuestion: Bool { selectedIssueSnapshot != nil }
  public var activeQuestionCount: Int { questionSnapshots.filter { $0.status != .skipped }.count }
  public var skippedQuestionCount: Int { questionSnapshots.filter { $0.status == .skipped }.count }

  public func selectIssueQuestion(_ id: String) {
    guard issueQuestionSnapshots.contains(where: { $0.id == id }) else { return }
    currentIssueQuestionID = id
    applyQuestionGuidance(now: .now)
  }

  public var subjectStrategy: RecipeSubjectStrategy { recipe.source.resolvedPerception.subjectStrategy }
  public var needsAnchorSelection: Bool {
    (recipe.source.resolvedPerception.anchorStrategy ?? .none) != .none
      && manualAnchorSelectionRequested
  }
  public var needsSubjectSelection: Bool { manualSubjectSelectionRequested }
  public var canReselectSubject: Bool {
    recipe.source.resolvedPerception.allowsManualSubjectSelection == true
      && recipe.source.resolvedPerception.subjectStrategy != .scene
  }
  public var faceAssistEnabled: Bool { recipe.source.resolvedPerception.faceAssist == true }
  public var semanticConfigured: Bool { semanticEvaluator != nil }
  public var intelligenceLabel: String {
    if isQuestionMode { return questionJudgeAvailable ? L("Recipe 视觉判断") : L("Recipe 已就绪") }
    if semanticFaulted { return L("AI 暂不可用") }
    if semanticEnhanced { return L("AI 摄影引擎") }
    if semanticConfigured { return L("AI 正在连接") }
    return L("基础模式")
  }
  public var semanticScoreLabel: String? {
    guard semanticEnhanced, let score = semanticOverallScore else { return nil }
    return "AI \(Int((score * 100).rounded()))"
  }

  public var detectionLabel: String {
    switch subjectStrategy {
    case .human:
      if facePresent { return L("人脸已识别") }
      if subjectPresent { return L("人物已识别") }
      return L("寻找人物")
    case .saliency:
      return subjectPresent ? L("主体已识别") : L("寻找主体")
    case .scene:
      return L("场景分析中")
    }
  }
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
        isCameraReady = true
        camera.start()
        syncCameraCapabilities()
        status = isQuestionMode ? (questionJudgeAvailable ? L("正在与参考图比较") : L("Recipe 问题已就绪，等待 DJev")) : (semanticConfigured ? L("AI 摄影引擎正在观察画面") : L("基础模式已开启"))
        await consumeFrames()
      case .denied:
        isCameraReady = false
        isPermissionBlocked = true
        status = L("需要相机权限才能开始")
      case .unavailable:
        isCameraReady = false
        if camera.authorizationStatus == .restricted {
          isPermissionBlocked = true
          status = L("此设备限制了相机访问")
        } else {
          enterDemoMode()
        }
      case .unknown:
        isCameraReady = false
        status = L("相机尚未就绪")
      }
    }
  }

  public func stop() {
    cameraTask?.cancel()
    cameraTask = nil
    resetSemanticContext(clearResult: true)
    interactiveZoomTask?.cancel()
    interactiveZoomTask = nil
    isInteractiveZooming = false
    camera.stop()
    isCameraReady = false
  }

  public func pauseForBackground() {
    try? checkpointStore.save(session.checkpoint(), key: recipe.source.id)
    session.pauseRuntime(.appBackgrounded)
    stop()
  }

  public func resumeAfterForegrounding() {
    session.resumeRuntime()
    evaluationCoordinator.resetCadenceOnly()
    resetSemanticContext(clearResult: true)
    stop()
    start()
  }

  public func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  public func selectAnchor(_ tap: CameraTapPoint) {
    if manualSubjectSelectionRequested {
      subjectPoint = tap.imageNormalized
      manualSubjectSelectionRequested = false
      localEvaluator.resetTracking()
      sceneRevision += 1
      invalidateSemanticAfterOpticalChange()
      showStatus(L("主体已锁定"), holdFor: 1.2)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      if currentAction?.operation == .selectSubject { handleDone() }
    } else if (recipe.source.resolvedPerception.anchorStrategy ?? .none) != .none
      && manualAnchorSelectionRequested
    {
      anchorPoint = tap.imageNormalized
      anchorBounds = nil
      manualAnchorSelectionRequested = false
      sceneRevision += 1
      invalidateSemanticAfterOpticalChange()
      showStatus(L("背景主体已锁定"), holdFor: 1.4)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      if currentAction?.operation == .selectAnchor { handleDone() }
    } else {
      showStatus(L("已对焦"), holdFor: 0.9)
      UISelectionFeedbackGenerator().selectionChanged()
    }
    Task { try? await camera.focus(atDevicePoint: tap.deviceFocus) }
  }

  public func reselectAnchor() {
    guard (recipe.source.resolvedPerception.anchorStrategy ?? .none) != .none else { return }
    anchorPoint = nil
    anchorBounds = nil
    manualAnchorSelectionRequested = true
    sceneRevision += 1
    resetSemanticContext(clearResult: true)
    showStatus(L("点一下你想保留的背景主体"), holdFor: 2)
    refreshDecision()
  }

  public func reselectSubject() {
    guard recipe.source.resolvedPerception.allowsManualSubjectSelection == true else { return }
    subjectPoint = nil
    manualSubjectSelectionRequested = true
    subjectBounds = nil
    subjectPresent = false
    localEvaluator.resetTracking()
    sceneRevision += 1
    invalidateSemanticAfterOpticalChange()
    showStatus(L("点一下你要拍的主体"), holdFor: 1.8)
    refreshDecision()
  }

  public func performPrimaryAction() {
    guard !isApplyingAutomaticAction else { return }
    guard let action = currentAction, isCurrentActionAutomatable else {
      handleDone()
      return
    }

    if isDemoMode {
      if action.operation == .zoom, let target = automaticZoomTarget() { zoomFactor = target }
      if action.operation == .adjustExposure, let target = automaticExposureTarget() { exposureBias = target }
      handleDone()
      return
    }

    isApplyingAutomaticAction = true
    Task { [weak self] in
      guard let self else { return }
      do {
        switch action.operation {
        case .zoom:
          guard let targetZoom = automaticZoomTarget() else {
            isApplyingAutomaticAction = false
            return
          }
          try await camera.setZoomFactor(targetZoom)
          zoomFactor = targetZoom
          showStatus(L("焦段已调整，正在复核"), holdFor: 1.2)
        case .adjustExposure:
          guard let targetExposure = automaticExposureTarget() else {
            isApplyingAutomaticAction = false
            return
          }
          try await camera.setExposureBias(Float(targetExposure))
          exposureBias = Double(camera.exposureBias)
          showStatus(L("亮度已调整，正在复核"), holdFor: 1.2)
        default:
          isApplyingAutomaticAction = false
          handleDone()
          return
        }
        syncCameraCapabilities()
        // This optical change is the Action being verified, not a scene swap.
        // Cancel semantic work captured before the device state changed.
        resetSemanticContext(clearResult: true)
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
    verificationStartedAt = .now
    instruction = L("正在复核")
    instructionDetail = L("先保持画面，我会用下一帧确认变化")
    instructionSymbol = "waveform.path.ecg"
    showStatus(L("复核新画面"), holdFor: 0.8)
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

  public func skipCurrentQuestion() {
    guard let id = currentIssueQuestionID else { return }
    questionCoordinator.skip(id)
    syncQuestionRuntime()
    showStatus(L("已跳过这个问题"), holdFor: 1.5)
    refreshDecision()
  }

  public func setQuestionSkipped(_ id: String, skipped: Bool) {
    if skipped { questionCoordinator.skip(id) }
    else { questionCoordinator.restore(id) }
    syncQuestionRuntime()
    refreshDecision()
  }

  public func restoreAllQuestions() {
    questionCoordinator.restoreAll()
    syncQuestionRuntime()
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
    subjectPoint = nil
    subjectBounds = nil
    subjectPresent = false
    faceBounds = nil
    facePresent = false
    manualAnchorSelectionRequested = false
    manualSubjectSelectionRequested = false
    sceneRevision += 1
    localEvaluator.resetTracking()
    questionCoordinator.reset()
    syncQuestionRuntime()
    rebuildSession()
    showStatus(subjectStrategy == .scene ? L("重新开始 · 正在分析场景") : L("重新开始 · 先把主体放进画面"), holdFor: 1.8)
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
        subjectPoint = nil
        subjectBounds = nil
        subjectPresent = false
        sceneRevision += 1
        localEvaluator.resetTracking()
        if isQuestionMode {
          questionCoordinator.invalidateAnswersPreservingSkips()
          syncQuestionRuntime()
        }
        rebuildSession()
        syncCameraCapabilities()
        showStatus(target == .back ? L("后置相机") : L("前置相机"), holdFor: 1.4)
      } catch { showStatus(localized(error), holdFor: 3) }
    }
  }

  public func cycleFlash() {
    let target: CameraFlashMode =
      switch flashMode {
      case .off: .auto
      case .auto: .on
      case .on: .off
      }
    setFlashMode(target)
  }

  public func setFlashMode(_ target: CameraFlashMode) {
    guard !isDemoMode, cameraPosition == .back else { return }
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

  /// The shutter never becomes a workflow lock. Once the camera returns an image,
  /// the next capture is enabled immediately while persistence continues independently.
  public func capture() {
    guard !isCapturing else { return }
    if isDemoMode {
      _ = makeDemoCaptureImage()
      captureCount += 1
      return
    }

    isCapturing = true
    Task { [weak self] in
      guard let self else { return }
      do {
        let image = try await camera.capturePhoto()
        captureCount += 1
        isCapturing = false

        // Saving is deliberately detached from the shutter lifecycle. A successful
        // capture never opens a review/report surface and never blocks the next shot.
        Task { [weak self] in
          guard let self else { return }
          let result = await camera.savePhotoToLibrary(image)
          if case .failure(let error) = result {
            showStatus(localized(error), holdFor: 2.4)
          }
        }
      } catch {
        isCapturing = false
        showStatus(localized(error), holdFor: 2.2)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
      }
    }
  }

  private var interactiveZoomRange: ClosedRange<Double> {
    let factors = camera.capabilities.displayZoomFactors
    let lower = factors.min() ?? 1
    let upper = factors.max() ?? max(lower, 1)
    return lower...max(lower, upper)
  }

  private func invalidateSemanticAfterOpticalChange() {
    if isQuestionMode {
      questionCoordinator.invalidateAnswersPreservingSkips()
      syncQuestionRuntime()
      return
    }
    resetSemanticContext(clearResult: true)
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
    guard let action = currentAction, action.actor == .camera else { return false }
    switch action.operation {
    case .zoom:
      return automaticZoomTarget() != nil
    case .adjustExposure:
      return supportsExposureBias && automaticExposureTarget() != nil
    default:
      return false
    }
  }

  private func automaticZoomTarget() -> Double? {
    guard let action = currentAction, action.actor == .camera, action.operation == .zoom else {
      return nil
    }

    switch action.presentationKey {
    case "camera.zoom_2x", "camera.zoom_in_subject":
      let preferred = zoomFactors.filter { $0 > zoomFactor + 0.08 }
      if let nearTwo = preferred.min(by: { abs($0 - 2) < abs($1 - 2) }), abs(nearTwo - 2) <= 0.35 {
        return nearTwo
      }
      return preferred.min()
    case "camera.zoom_out", "camera.zoom_out_subject":
      return zoomFactors.filter { $0 < zoomFactor - 0.08 }.max() ?? zoomFactors.min()
    default:
      return nil
    }
  }

  private func automaticExposureTarget() -> Double? {
    guard let action = currentAction, action.actor == .camera, action.operation == .adjustExposure,
      supportsExposureBias
    else { return nil }
    let step: Double = switch action.magnitude {
    case .tiny: 0.20
    case .small: 0.35
    case .medium: 0.55
    case .large: 0.80
    }
    let target: Double
    switch action.direction {
    case .up: target = exposureBias + step
    case .down: target = exposureBias - step
    default: return nil
    }
    return min(max(target, exposureBiasRange.lowerBound), exposureBiasRange.upperBound)
  }

  private func consumeFrames() async {
    for await frame in camera.frames() {
      if Task.isCancelled { return }
      currentFrameID = frame.id
      updateExposureTelemetry(frame.exposure)
      if !isInteractiveZooming, abs(zoomFactor - frame.zoomFactor) > 0.01 {
        zoomFactor = frame.zoomFactor
      }
      if isQuestionMode {
        questionCoordinator.schedule(frame: frame) { [weak self] in
          guard let self else { return }
          syncQuestionRuntime()
          refreshDecision()
        }
      } else {
        // Legacy v0.8 compatibility path. New Recipes use bounded questions.
        scheduleSemanticEvaluation(for: frame)
      }

      let anchor = anchorPoint.map { NormalizedPoint(x: $0.x, y: $0.y) }
      let subject = subjectPoint.map { NormalizedPoint(x: $0.x, y: $0.y) }
      guard
        let scene = await localEvaluator.evaluateScene(
          frame.pixelBuffer, orientation: .up, subjectPoint: subject, anchorPoint: anchor,
          frameID: frame.id)
      else { continue }
      if bindingVersion != 0, scene.bindingVersion != bindingVersion {
        bindingVersion = scene.bindingVersion
        rebuildSession(keepAnchor: true)
        showStatus(L("拍摄主体发生变化，已重新评估"), holdFor: 1.8)
      } else {
        bindingVersion = scene.bindingVersion
      }
      session.updateSceneConditions(
        scene.conditions.withContext(frameID: frame.id, sceneRevision: sceneRevision))
      ingestLocal(scene, frameID: frame.id)
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

  private func resetSemanticContext(clearResult: Bool) {
    semanticTask?.cancel()
    semanticTask = nil
    semanticInFlight = false
    semanticSampleBuffer.reset()
    semanticGeneration &+= 1
    if clearResult {
      criticSession.reset()
      semanticOverallScore = nil
      semanticAssessmentCount = 0
      semanticEnhanced = false
    }
  }

  private func scheduleSemanticEvaluation(for frame: CameraFrame) {
    guard let evaluator = semanticEvaluator,
      !semanticInFlight,
      Date() >= semanticSuppressedUntil,
      Date().timeIntervalSince(lastSemanticRequestAt) >= 0.55
    else { return }

    let criticProfile = recipe.source.resolvedCritic
    guard !criticProfile.dimensions.isEmpty else { return }

    semanticInFlight = true
    lastSemanticRequestAt = .now
    let requestGeneration = semanticGeneration
    let requestFrame = frame.id
    let requestStartedAt = Date()
    let frameForEncoding = frame

    semanticTask = Task { [weak self] in
      guard let self else { return }
      defer {
        semanticInFlight = false
        semanticTask = nil
      }

      let payload = await Task.detached(priority: .utility) {
        SemanticFrameEncoder.jpegData(
          from: frameForEncoding.pixelBuffer,
          maxDimension: 640,
          quality: 0.62)
      }.value
      guard !Task.isCancelled, let payload else { return }

      semanticSampleBuffer.append(
        CriticImageSample(
          frameID: requestFrame,
          timestamp: frameForEncoding.capturedAt.timeIntervalSince1970,
          imagePayload: payload))
      let samples = semanticSampleBuffer.selected(
        count: criticProfile.preferredSampleCount,
        minimumSpacing: criticProfile.minimumSampleSpacing)
      guard !samples.isEmpty else { return }

      do {
        let critique = try await evaluator.critique(
          profile: criticProfile,
          samples: samples,
          locale: Locale.preferredLanguages.first ?? Locale.current.identifier)
        guard !Task.isCancelled else { return }
        guard requestGeneration == semanticGeneration else { return }
        guard Date().timeIntervalSince(requestStartedAt) <= 2.8 else { return }
        guard currentFrameID >= requestFrame, currentFrameID - requestFrame <= 90 else { return }

        if acceptSemanticCritique(critique) {
          semanticFailureCount = 0
          semanticEnhanced = true
          semanticFaulted = false
          refreshDecision()
        } else {
          recordSemanticFailure()
        }
      } catch {
        recordSemanticFailure()
      }
    }
  }

  private func recordSemanticFailure() {
    semanticFailureCount = min(semanticFailureCount + 1, 6)
    semanticFaulted = semanticFailureCount >= 2
    let retryDelay = min(pow(2.0, Double(max(semanticFailureCount - 1, 0))) * 0.55, 8.0)
    semanticSuppressedUntil = Date().addingTimeInterval(retryDelay)
    refreshDecision()
  }

  private func ingestLocal(_ scene: SceneObservation, frameID: Int) {
    let primaryID = NodeID("primary")
    let primary: GuidanceCore.Binding = .node(primaryID)
    let relationID = RelationID("primary_anchor")
    let relation: GuidanceCore.Binding = .relation(relationID)
    let subject = scene.subject
    var observations: [Observation] = []

    if recipe.registry.nodes[primaryID] != nil {
      let nodeEvaluator = EvaluatorID(
        subjectStrategy == .human ? "vision.local" : "vision.saliency_subject")
      let confidence = subject.confidence
      observations.append(contentsOf: [
        .init(
          dimension: DimensionID("std.node.exists"), binding: primary,
          value: .boolean(subject.present), confidence: confidence,
          evaluator: nodeEvaluator, frameID: frameID, bindingVersion: bindingVersion,
          sceneRevision: sceneRevision),
        .init(
          dimension: DimensionID("std.node.visibility"), binding: primary,
          value: .boolean(subject.visible), confidence: confidence,
          evaluator: nodeEvaluator, frameID: frameID, bindingVersion: bindingVersion,
          sceneRevision: sceneRevision),
        .init(
          dimension: DimensionID("std.node.visual_scale"), binding: primary,
          value: .continuous(subject.scale), confidence: confidence,
          evaluator: nodeEvaluator, frameID: frameID, bindingVersion: bindingVersion,
          sceneRevision: sceneRevision),
        .init(
          dimension: DimensionID("std.node.position_x"), binding: primary,
          value: .continuous(subject.x), confidence: confidence,
          evaluator: nodeEvaluator, frameID: frameID, bindingVersion: bindingVersion,
          sceneRevision: sceneRevision),
        .init(
          dimension: DimensionID("std.node.position_y"), binding: primary,
          value: .continuous(subject.y), confidence: confidence,
          evaluator: nodeEvaluator, frameID: frameID, bindingVersion: bindingVersion,
          sceneRevision: sceneRevision),
      ])

      if subjectStrategy == .human, let bodyOrientation = subject.bodyOrientation,
        recipe.registry.dimensions[DimensionID("std.pose.body_orientation")] != nil
      {
        observations.append(
          .init(
            dimension: DimensionID("std.pose.body_orientation"), binding: primary,
            value: .ordinal(bodyOrientation), confidence: confidence * 0.82,
            evaluator: EvaluatorID("vision.local"), frameID: frameID,
            bindingVersion: bindingVersion, sceneRevision: sceneRevision))
      }
    }

    if recipe.registry.relations[relationID] != nil, let composition = scene.composition {
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

    if let frame = scene.frame {
      let evaluator = EvaluatorID("vision.frame")
      let confidence = frame.confidence
      func appendFrame(_ id: String, _ value: Double?) {
        guard let value, recipe.registry.dimensions[DimensionID(id)] != nil else { return }
        observations.append(
          .init(
            dimension: DimensionID(id), binding: .frame, value: .continuous(value),
            confidence: confidence, evaluator: evaluator, frameID: frameID,
            bindingVersion: bindingVersion, sceneRevision: sceneRevision))
      }
      appendFrame("std.frame.luminance", frame.luminance)
      appendFrame("std.frame.shadow_fraction", frame.shadowFraction)
      appendFrame("std.frame.highlight_fraction", frame.highlightFraction)
      appendFrame("std.frame.detail_energy", frame.detailEnergy)
      appendFrame("std.frame.saliency_x", frame.saliencyX)
      appendFrame("std.frame.saliency_y", frame.saliencyY)
    }

    if observations.isEmpty {
      session.advanceFrame(frameID)
    } else {
      _ = session.ingestBatch(observations)
    }

    if subjectPresent != subject.present {
      subjectPresent = subject.present
      resetEvidenceWait()
    }
    let nextSubjectBounds = subject.bounds?.cgRect
    if Self.rectChangedSignificantly(subjectBounds, nextSubjectBounds, epsilon: 0.006) {
      subjectBounds = nextSubjectBounds
    }

    let nextFacePresent = subjectStrategy == .human ? (scene.face?.present ?? false) : false
    if facePresent != nextFacePresent {
      facePresent = nextFacePresent
      resetEvidenceWait()
    }
    let nextFaceBounds = subjectStrategy == .human ? scene.face?.bounds.cgRect : nil
    if Self.rectChangedSignificantly(faceBounds, nextFaceBounds, epsilon: 0.008) {
      faceBounds = nextFaceBounds
    }

    let nextAnchorBounds = scene.anchor?.bounds.cgRect
    if Self.rectChangedSignificantly(anchorBounds, nextAnchorBounds, epsilon: 0.008) {
      let hadAnchor = anchorBounds != nil
      anchorBounds = nextAnchorBounds
      if hadAnchor != (nextAnchorBounds != nil) { resetEvidenceWait() }
    }
    refreshDecision(force: false)
  }

  private func refreshDecision(force: Bool = true) {
    let now = Date()
    if !force, now.timeIntervalSince(lastDecisionRefreshAt) < 0.22 { return }
    lastDecisionRefreshAt = now
    if isQuestionMode {
      applyQuestionGuidance(now: now)
      return
    }
    let wasReady = isReady
    previewCue = .none
    compositionGuide = .none
    isCurrentActionSafetySensitive = false

    // The multimodal critic is the product's primary photography intelligence.
    // Local Vision remains an optional fast assist/fallback and must not gate the
    // professional guidance path when a fresh critic result exists.
    if applyFreshSemanticGuidance(now: now, wasReady: wasReady) {
      updateProgress()
      return
    }

    if semanticConfigured && !semanticFaulted {
      // Semantic-first invariant: while the professional critic is healthy but
      // waiting for a fresh sampled-frame result, local heuristics may draw
      // overlays but must not take over as the photography authority.
      currentAction = nil
      instruction = L("正在分析画面")
      instructionDetail = L("AI 正在从构图、光线、主体、色彩等维度判断当前画面")
      instructionSymbol = "sparkles.rectangle.stack"
      isReady = false
      defaultStatus(L("AI 摄影引擎正在分析"))
      updateProgress()
      return
    }

    if needsSubjectSelection {
      currentAction = session.currentTransaction?.definition
      isReady = false
      instruction = L("点一下你要拍的主体")
      instructionDetail = L("花、食物、物品、宠物都可以，点一下就会锁定")
      instructionSymbol = "hand.tap"
      defaultStatus(L("等待选择拍摄主体"))
      updateProgress()
      return
    }
    if needsAnchorSelection {
      currentAction = nil
      isReady = false
      instruction = L("点一下想保留的背景")
      instructionDetail = L("我会锁定它，再继续判断人物和环境关系")
      instructionSymbol = "scope"
      defaultStatus(L("等待选择背景主体"))
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
      resetEvidenceWait()
      if action.operation == .selectSubject { manualSubjectSelectionRequested = true }
      if action.operation == .selectAnchor { manualAnchorSelectionRequested = true }
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
      resetEvidenceWait()
      instruction = L("现在就很好")
      instructionDetail = L("关键部分已经到位，保持住直接拍")
      instructionSymbol = "checkmark.circle.fill"
      isReady = true
      isPausedByUser = false
      if !wasReady { UINotificationFeedbackGenerator().notificationOccurred(.success) }
      defaultStatus(L("已达到可拍状态"))
    case .readyByUser:
      resetEvidenceWait()
      instruction = L("按你喜欢的样子拍")
      instructionDetail = L("我先不继续打扰；想再优化可以恢复指导")
      instructionSymbol = "heart.fill"
      isReady = true
      isPausedByUser = true
      defaultStatus(L("已暂停主动优化"))
    case .paused:
      resetEvidenceWait()
      instruction = L("先拍也可以")
      instructionDetail = L("刚才连续调整有点多，我先停一下；想继续时再恢复指导")
      instructionSymbol = "pause.circle.fill"
      isReady = false
      isPausedByUser = true
      defaultStatus(L("主动指导已暂停"))
    case .requestEvidence(let request):
      applyEvidenceGuidance(reason: request.reason)
    case .wait:
      if let started = verificationStartedAt, Date().timeIntervalSince(started) < 0.9 {
        instruction = L("正在复核")
        instructionDetail = L("先保持画面，我会用下一帧确认变化")
        instructionSymbol = "waveform.path.ecg"
      } else {
        verificationStartedAt = nil
        applyLocalFallbackGuidance()
      }
      isReady = false
      defaultStatus(L("正在确认新画面"))
    case .unknown:
      applyLocalFallbackGuidance()
      isReady = false
      defaultStatus(L("本机视觉正在判断"))
    case .unreachable:
      resetEvidenceWait()
      instruction = L("先按现在这样拍也可以")
      instructionDetail = L("当前条件下没有低成本的下一步，你随时可以按快门")
      instructionSymbol = "camera.fill"
      isReady = false
      defaultStatus(L("没有可执行的进一步调整"))
    }
    updateProgress()
  }

  private func installCameraObservers() {
    NotificationCenter.default.publisher(
      for: AVCaptureSession.wasInterruptedNotification, object: camera.session
    )
    .sink { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.isCameraReady = false
        self.session.pauseRuntime(.cameraInterrupted)
        self.showStatus(L("相机暂时被系统占用"), holdFor: 2.0)
      }
    }
    .store(in: &cameraObservers)

    NotificationCenter.default.publisher(
      for: AVCaptureSession.interruptionEndedNotification, object: camera.session
    )
    .sink { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.session.resumeRuntime()
        self.evaluationCoordinator.resetCadenceOnly()
        self.resetSemanticContext(clearResult: true)
        self.camera.start()
        self.isCameraReady = true
        self.showStatus(L("相机已恢复，正在重新判断"), holdFor: 1.5)
      }
    }
    .store(in: &cameraObservers)

    NotificationCenter.default.publisher(
      for: AVCaptureSession.runtimeErrorNotification, object: camera.session
    )
    .sink { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.isCameraReady = false
        self.showStatus(L("相机正在恢复"), holdFor: 1.5)
        try? await Task.sleep(for: .milliseconds(250))
        self.camera.start()
        self.isCameraReady = true
      }
    }
    .store(in: &cameraObservers)
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
    if supportsExposureBias { caps.insert("exposure.bias") }
    else { caps.remove("exposure.bias") }
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
    isCameraReady = true
    subjectPresent = subjectStrategy != .scene
    facePresent = subjectStrategy == .human && faceAssistEnabled
    anchorPoint = recipe.source.resolvedPerception.anchorStrategy == .automatic
      ? CGPoint(x: 0.73, y: 0.40) : nil
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
    let observations = recipe.goals.compactMap { goal -> Observation? in
      guard !goal.dimension.rawValue.hasPrefix("std.semantic.") else { return nil }
      let done = completedDemoGoals.contains(goal.id)
      let value: DimensionValue
      let evaluator: EvaluatorID
      switch goal.dimension.rawValue {
      case "std.node.exists", "std.node.visibility":
        value = .boolean(true)
        evaluator = EvaluatorID(subjectStrategy == .human ? "vision.local" : "vision.saliency_subject")
      case "std.node.visual_scale":
        value = .continuous(done ? 0.24 : 0.36)
        evaluator = EvaluatorID(subjectStrategy == .human ? "vision.local" : "vision.saliency_subject")
      case "std.node.position_x":
        value = .continuous(done ? 0.50 : 0.34)
        evaluator = EvaluatorID(subjectStrategy == .human ? "vision.local" : "vision.saliency_subject")
      case "std.node.position_y":
        value = .continuous(done ? 0.50 : 0.70)
        evaluator = EvaluatorID(subjectStrategy == .human ? "vision.local" : "vision.saliency_subject")
      case "std.pose.body_orientation":
        value = .ordinal(done ? 0 : 1)
        evaluator = EvaluatorID("vision.local")
      case "std.relation.relative_scale", "std.relation.visual_balance":
        value = .ordinal(done ? 0 : 1)
        evaluator = EvaluatorID("vision.saliency_relation")
      case "std.frame.luminance":
        value = .continuous(done ? 0.52 : 0.35)
        evaluator = EvaluatorID("vision.frame")
      case "std.frame.highlight_fraction":
        value = .continuous(done ? 0.08 : 0.26)
        evaluator = EvaluatorID("vision.frame")
      case "std.frame.shadow_fraction":
        value = .continuous(done ? 0.12 : 0.25)
        evaluator = EvaluatorID("vision.frame")
      case "std.frame.detail_energy":
        value = .continuous(done ? 0.42 : 0.20)
        evaluator = EvaluatorID("vision.frame")
      case "std.frame.saliency_x", "std.frame.saliency_y":
        value = .continuous(done ? 0.50 : 0.28)
        evaluator = EvaluatorID("vision.frame")
      default:
        return nil
      }
      return .init(
        dimension: goal.dimension, binding: goal.binding, value: value, confidence: 0.97,
        evaluator: evaluator, frameID: currentFrameID)
    }
    if observations.isEmpty { session.advanceFrame(currentFrameID) }
    else { _ = session.ingestBatch(observations) }
    #if DEBUG
      if PGAIServiceConfiguration.previewCriticEnabled, currentFrameID.isMultiple(of: 3) {
        let critique = PreviewMultimodalCriticEvaluator.makeCritique(
          profile: criticSession.profile,
          seed: currentFrameID,
          locale: Locale.current.identifier)
        _ = acceptSemanticCritique(critique)
      }
    #endif
    refreshDecision()
  }

  private func rebuildSession(keepAnchor: Bool = false) {
    resetSemanticContext(clearResult: true)
    evaluationCoordinator.resetCadenceOnly()
    session = GuidanceSession(
      goals: recipe.goals,
      actions: Self.runtimeActions(from: recipe, semanticEnabled: semanticEvaluator != nil),
      registry: recipe.registry)
    completedDemoGoals.removeAll()
    currentAction = nil
    subjectBounds = nil
    subjectPresent = false
    subjectPoint = nil
    manualSubjectSelectionRequested = false
    faceBounds = nil
    facePresent = false
    if !keepAnchor {
      anchorPoint = nil
      anchorBounds = nil
      manualAnchorSelectionRequested = false
    }
    isReady = false
    isPausedByUser = false
    previewCue = .none
    compositionGuide = .none
    isCurrentActionSafetySensitive = false
    syncCameraCapabilities()
    updateProgress()
  }

  private func applyEvidenceGuidance(reason: EvidenceReason) {
    let signature = reason.rawValue
    let now = Date()
    if evidenceWaitSignature != signature {
      evidenceWaitSignature = signature
      evidenceWaitStartedAt = now
    }
    let waitingFor = evidenceWaitStartedAt.map { now.timeIntervalSince($0) } ?? 0
    let perception = recipe.source.resolvedPerception

    switch perception.subjectStrategy {
    case .human:
      if !subjectPresent {
        instruction = L("把人物放进画面")
        instructionDetail = L("先让人物进入取景范围，我再继续判断构图")
        instructionSymbol = "person.crop.rectangle"
        isReady = false
        return
      }
      if perception.faceAssist == true, !facePresent, waitingFor < 1.8 {
        instruction = L("让脸露出来一点")
        instructionDetail = L("稍微转向镜头，脸部轮廓清楚后我会继续判断")
        instructionSymbol = "face.smiling"
        isReady = false
        return
      }
    case .saliency:
      if !subjectPresent {
        if waitingFor >= 1.2, perception.allowsManualSubjectSelection == true {
          manualSubjectSelectionRequested = true
          instruction = L("点一下你要拍的主体")
          instructionDetail = L("花、食物、物品、宠物都可以，点一下就会锁定")
          instructionSymbol = "hand.tap"
        } else {
          instruction = L("正在寻找主体")
          instructionDetail = L("把主要对象放进画面，我会自动锁定最显眼的区域")
          instructionSymbol = "scope"
        }
        isReady = false
        return
      }
    case .scene:
      break
    }

    let anchorStrategy = perception.anchorStrategy ?? .none
    if anchorStrategy != .none, anchorStrategy != .optional,
      anchorBounds == nil, waitingFor < 2.4
    {
      instruction = L("把背景重点带进画面")
      instructionDetail = L("明显的景物或空间层次出现后，我会继续判断关系")
      instructionSymbol = "mountain.2"
      isReady = false
      return
    }

    if waitingFor >= 2.4 {
      let readiness = session.scheduler.readinessPolicy.assess(
        engine: session.engine,
        goalGroups: session.goalGroups)
      if readiness.hardSatisfied {
        instruction = semanticEvaluator == nil ? L("基础构图已经可拍") : L("可以先拍，AI 还在细化")
        instructionDetail = semanticEvaluator == nil
          ? L("关键本机指标已经稳定；可选信息不会继续卡住快门。")
          : L("当前关键构图已经成立，语义判断返回后会继续更新。")
        instructionSymbol = "camera.fill"
        isReady = true
        defaultStatus(L("快门随时可用"))
        return
      }
    }

    if semanticEvaluator == nil {
      switch reason {
      case .hardGuardUnknown:
        instruction = L("画面稳一点")
        instructionDetail = L("关键位置刚刚变化，我在确认当前画面")
      case .coreUnknown:
        instruction = L("先保持当前构图")
        instructionDetail = L("本机视觉正在补充位置、比例和光线判断")
      case .lowConfidence:
        instruction = L("让主体更清楚一点")
        instructionDetail = L("光线或移动会降低识别稳定性，稍停一下就会继续")
      case .staleOrMissing:
        instruction = L("重新对准画面")
        instructionDetail = L("保持主要内容清楚，我会马上更新指导")
      }
      instructionSymbol = "eye"
    } else {
      switch reason {
      case .hardGuardUnknown:
        instruction = L("画面再稳一点")
        instructionDetail = L("关键目标刚刚变化，我在确认新位置")
      case .coreUnknown:
        instruction = L("保持这个构图")
        instructionDetail = L("AI 正在补充主体关系、层次和画面判断")
      case .lowConfidence:
        instruction = L("镜头稳一点")
        instructionDetail = L("当前识别置信度偏低，稳定后会自动继续")
      case .staleOrMissing:
        instruction = L("重新对准画面")
        instructionDetail = L("保持主体和场景清楚，我会马上更新指导")
      }
      instructionSymbol = "eye"
    }
    isReady = false
  }

  private func syncQuestionRuntime() {
    questionSnapshots = questionCoordinator.snapshots
    let issues = questionSnapshots.filter { $0.status == .issue && $0.issue != nil }
    if let selected = currentIssueQuestionID, issues.contains(where: { $0.id == selected }) {
      // Keep the user's manually selected card while it remains a current issue.
    } else {
      currentIssueQuestionID = issues.first?.id
    }
    let active = questionSnapshots.filter { $0.status != .skipped }
    let matched = active.filter { $0.status == .matched }.count
    progress = active.isEmpty ? 0 : Double(matched) / Double(active.count)
    progressLabel = "\(matched) / \(active.count)"
  }

  private func applyQuestionGuidance(now: Date) {
    syncQuestionRuntime()
    currentAction = nil
    previewCue = .none
    compositionGuide = .none
    isCurrentActionSafetySensitive = false
    isReady = false
    isPausedByUser = false

    if let issue = selectedIssueSnapshot, let text = issue.issue {
      instruction = L(text)
      instructionDetail = L(issue.title)
      instructionSymbol = "exclamationmark.circle.fill"
      defaultStatus(L("Recipe 发现了当前差距"))
      return
    }

    if !questionCoordinator.canEvaluate {
      instruction = L("Recipe 问题已准备好")
      instructionDetail = L("真实 DJev 接入后，会逐项比较当前帧与参考图")
      instructionSymbol = "list.bullet.rectangle"
      defaultStatus(L("等待 DJev"))
      return
    }

    let active = questionSnapshots.filter { $0.status != .skipped }
    if !active.isEmpty, active.allSatisfy({ $0.status == .matched }) {
      instruction = L("当前没有明显差距")
      instructionDetail = ""
      instructionSymbol = "checkmark.circle"
      defaultStatus(L("Recipe 当前问题均已匹配"))
      return
    }

    instruction = L("正在与参考图比较")
    instructionDetail = questionCoordinator.currentQuestion.map { L($0.title) } ?? ""
    instructionSymbol = "arrow.left.and.right.square"
    defaultStatus(L("正在判断当前问题"))
  }

  private static func makeQuestionJudge(for recipe: RecipeDTO) -> (any VisualJudge)? {
    guard recipe.questions?.isEmpty == false, !recipe.resolvedVisualReferences.isEmpty else { return nil }
    #if DEBUG
      if PGAIServiceConfiguration.previewCriticEnabled { return PreviewVisualJudge() }
    #endif
    // Intentionally nil until the real DJev System-1 endpoint is integrated.
    return nil
  }

  private func applyFreshSemanticGuidance(now: Date, wasReady: Bool) -> Bool {
    guard semanticConfigured else { return false }

    switch criticSession.decision(at: now) {
    case .evaluating, .rejected:
      return false

    case .ready(let score):
      semanticOverallScore = score
      semanticAssessmentCount = criticSession.latestCritique?.assessments.count ?? 0
      currentAction = nil
      isPausedByUser = false
      instruction = L("现在可以拍")
      instructionDetail = L("AI 已从多个画质维度复核，当前画面已经达到这个配方的可拍状态")
      instructionSymbol = "checkmark.circle.fill"
      isReady = true
      if !wasReady { UINotificationFeedbackGenerator().notificationOccurred(.success) }
      defaultStatus(L("AI 建议已更新"))
      return true

    case .advise(let advice, let score):
      semanticOverallScore = score
      semanticAssessmentCount = criticSession.latestCritique?.assessments.count ?? 0
      currentAction = nil
      isPausedByUser = false
      instruction = advice.title.isEmpty ? L("继续微调") : advice.title
      instructionDetail = advice.detail.isEmpty ? L("AI 正在持续复核调整后的画面") : advice.detail
      instructionSymbol = semanticSymbol(for: advice.kind)
      isCurrentActionSafetySensitive = advice.requiresPhysicalMovement
      isReady = false
      defaultStatus(L("AI 专业建议"))
      return true

    case .observe(let score):
      // A valid critique with no concrete adjustment should not trap the user in
      // a repeating “hold still” loop. Keep the camera live and ask for a new
      // viewpoint while the next sampled window is evaluated.
      semanticOverallScore = score
      semanticAssessmentCount = criticSession.latestCritique?.assessments.count ?? 0
      currentAction = nil
      isPausedByUser = false
      instruction = L("继续取景")
      instructionDetail = L("AI 已完成本轮评分；轻微改变角度或距离，我会继续比较下一组画面")
      instructionSymbol = "viewfinder"
      isReady = false
      defaultStatus(L("AI 正在持续评片"))
      return true
    }
  }

  private func semanticSymbol(for kind: CriticAdviceKind) -> String {
    switch kind {
    case .composition: "viewfinder"
    case .camera: "camera.aperture"
    case .lighting: "sun.max.fill"
    case .subject: "scope"
    case .scene: "mountain.2"
    case .timing: "timer"
    case .wait: "waveform.path.ecg"
    case .capture: "camera.fill"
    case .other: "sparkles"
    }
  }

  @discardableResult
  private func acceptSemanticCritique(_ critique: SemanticCritique, at date: Date = .now) -> Bool {
    let decision = criticSession.ingest(critique, at: date)
    guard case .rejected = decision else {
      semanticEnhanced = true
      semanticFaulted = false
      semanticOverallScore = criticSession.latestCritique.flatMap {
        criticSession.reducer.overallScore($0, profile: criticSession.profile)
      }
      semanticAssessmentCount = criticSession.latestCritique?.assessments.count ?? 0
      return true
    }
    return false
  }

  private func resetEvidenceWait() {
    evidenceWaitSignature = nil
    evidenceWaitStartedAt = nil
  }

  private func applyLocalFallbackGuidance() {
    let perception = recipe.source.resolvedPerception
    switch perception.subjectStrategy {
    case .human:
      if !subjectPresent {
        instruction = L("把人物放进画面")
        instructionDetail = L("人物出现后，我会自动开始构图判断")
        instructionSymbol = "person.crop.rectangle"
        return
      }
      if perception.faceAssist == true, !facePresent {
        instruction = L("让脸露出来一点")
        instructionDetail = L("稍微转向镜头，不用移动太多")
        instructionSymbol = "face.smiling"
        return
      }
    case .saliency:
      if !subjectPresent {
        instruction = L("把主体放进画面")
        instructionDetail = perception.allowsManualSubjectSelection == true
          ? L("我会先自动寻找；找不到时你也可以点一下锁定主体")
          : L("主体出现后，我会自动开始构图判断")
        instructionSymbol = "scope"
        return
      }
    case .scene:
      break
    }

    let anchorStrategy = perception.anchorStrategy ?? .none
    if anchorStrategy != .none, anchorStrategy != .optional,
      anchorBounds == nil
    {
      instruction = L("给场景重点留一点空间")
      instructionDetail = L("让明显的景物或空间层次进入画面，我会继续分析")
      instructionSymbol = "mountain.2"
    } else {
      instruction = L("画面已经被识别")
      instructionDetail = semanticEvaluator == nil
        ? L("本机视觉会继续给你构图、比例、光线和画面重心建议")
        : L("AI 正在补充主体关系、层次、色彩和氛围判断")
      instructionSymbol = "scope"
    }
  }

  private static func rectChangedSignificantly(
    _ lhs: CGRect?, _ rhs: CGRect?, epsilon: CGFloat
  ) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return false
    case (.some, nil), (nil, .some):
      return true
    case let (.some(a), .some(b)):
      return abs(a.minX - b.minX) > epsilon
        || abs(a.minY - b.minY) > epsilon
        || abs(a.width - b.width) > epsilon
        || abs(a.height - b.height) > epsilon
    }
  }

  private static func localPerceptionProfile(
    _ perception: RecipePerceptionDTO
  ) -> LocalSceneEvaluationProfile {
    let strategy: LocalSubjectAcquisitionStrategy = switch perception.subjectStrategy {
    case .human: .human
    case .saliency: .saliency
    case .scene: .scene
    }
    return LocalSceneEvaluationProfile(
      subjectStrategy: strategy,
      semanticHint: perception.semanticHint,
      faceAssist: perception.faceAssist ?? false,
      poseAssist: perception.poseAssist ?? false,
      automaticAnchor: perception.anchorStrategy == .automatic)
  }

  private static func runtimeActions(
    from recipe: CompiledRecipe, semanticEnabled: Bool
  ) -> [ActionDefinition] {
    recipe.actions.filter { action in
      if !semanticEnabled, action.presentationKey == "system.wait_semantic" { return false }
      return true
    }
  }

  private static func makeSemanticEvaluator() -> (any MultimodalCritic)? {
    #if DEBUG
      if PGAIServiceConfiguration.previewCriticEnabled {
        return PreviewMultimodalCriticEvaluator()
      }
    #endif

    guard PGAIServiceConfiguration.remoteAIConsentGranted,
      let endpoint = PGAIServiceConfiguration.endpoint
    else { return nil }

    // A long-lived bearer secret must never be embedded in the release app. Debug
    // builds may inject a temporary token from the process environment for local testing.
    #if DEBUG
      let token = ProcessInfo.processInfo.environment["MULTIMODAL_CRITIC_TOKEN"]
        ?? ProcessInfo.processInfo.environment["DJEV_TOKEN"]
    #else
      let token: String? = nil
    #endif
    return HTTPMultimodalCriticEvaluator(configuration: .init(endpoint: endpoint, bearerToken: token))
  }

  private func makeDemoCaptureImage() -> UIImage {
    let size = CGSize(width: 1170, height: 2532)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let cg = context.cgContext
      let colors = [
        UIColor(red: 0.08, green: 0.15, blue: 0.17, alpha: 1).cgColor,
        UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1).cgColor,
      ] as CFArray
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      cg.drawLinearGradient(
        gradient!, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

      cg.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor)
      let mountain = UIBezierPath()
      mountain.move(to: CGPoint(x: 0, y: 1650))
      mountain.addLine(to: CGPoint(x: 350, y: 980))
      mountain.addLine(to: CGPoint(x: 610, y: 1420))
      mountain.addLine(to: CGPoint(x: 840, y: 1030))
      mountain.addLine(to: CGPoint(x: size.width, y: 1510))
      mountain.addLine(to: CGPoint(x: size.width, y: size.height))
      mountain.addLine(to: CGPoint(x: 0, y: size.height))
      mountain.close()
      mountain.fill()

      cg.setFillColor(UIColor.white.withAlphaComponent(0.30).cgColor)
      cg.fillEllipse(in: CGRect(x: 725, y: 1080, width: 150, height: 150))
      cg.fill(CGRect(x: 758, y: 1215, width: 84, height: 420))

      cg.setStrokeColor(UIColor(red: 0.66, green: 0.95, blue: 0.86, alpha: 0.24).cgColor)
      cg.setLineWidth(2)
      cg.setLineDash(phase: 0, lengths: [16, 14])
      cg.move(to: CGPoint(x: size.width * 2 / 3, y: 140))
      cg.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height - 260))
      cg.strokePath()
    }
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
