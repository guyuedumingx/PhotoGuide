@preconcurrency import AVFoundation
import CameraRuntime
import Combine
import GuidanceCore
import PerceptionRuntime
import RecipeKit
import SwiftUI
import UIKit

@MainActor
public final class GuidanceViewModel: ObservableObject {
    @Published public private(set) var instruction = "把人物放进画面"
    @Published public private(set) var status = "正在准备相机"
    @Published public private(set) var isDemoMode = false
    @Published public private(set) var isPermissionBlocked = false
    @Published public private(set) var localReady = false
    @Published public private(set) var compositionReady = false
    @Published public private(set) var recipeReady = false
    @Published public private(set) var progress = 0.0
    @Published public private(set) var progressLabel = "0 / 0"
    @Published public private(set) var lastPhoto: UIImage?
    @Published public private(set) var photoSaved = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var currentAction: ActionDefinition?
    @Published public private(set) var anchorPoint: CGPoint?
    @Published public private(set) var personBounds: CGRect?
    @Published public private(set) var anchorBounds: CGRect?
    @Published public private(set) var isReady = false
    @Published public private(set) var cameraPosition: CameraPosition = .back
    @Published public private(set) var flashMode: CameraFlashMode = .off

    public let camera = CameraService()
    public let recipe: CompiledRecipe

    private let localEvaluator = LocalPersonEvaluator(maximumFramesPerSecond: 8)
    private var session: GuidanceSession
    private var transaction: ActionInstance?
    private var currentFrameID = 0
    private var cameraTask: Task<Void, Never>?
    private var completedDemoGoals = Set<GoalID>()
    private var bindingVersion = 0
    private var sceneRevision = 0
    private var lastValues = [DimensionID: DimensionValue]()
    private var lastDecisionWasReady = false
    private var statusHoldUntil = Date.distantPast

    public init() {
        let loaded = RecipeLoader().loadEnvironmentalPortrait()
        recipe = loaded
        session = GuidanceSession(goals: loaded.goals, actions: loaded.actions)
        recipeReady = loaded.isValid
        updateProgress()
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
                status = "本地视觉正在观察"
                camera.start()
                await consumeFrames()
            case .denied:
                isPermissionBlocked = true
                status = "需要相机权限才能开始"
            case .unavailable:
                if camera.authorizationStatus == .restricted {
                    isPermissionBlocked = true
                    status = "此设备限制了相机访问"
                } else {
                    // The simulator has no capture device. It remains a useful
                    // deterministic controller harness, but is visibly labelled.
                    enterDemoMode()
                }
            case .unknown:
                status = "相机尚未就绪"
            }
        }
    }

    public func stop() {
        cameraTask?.cancel()
        cameraTask = nil
        camera.stop()
    }

    public func resumeAfterForegrounding() {
        stop()
        start()
    }

    public func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    public func handleDone() {
        if isDemoMode, let goal = currentAction?.affects.first {
            completedDemoGoals.insert(goal)
        }
        handle(.done)
        status = "保持不动，正在复核"
    }

    public func handleAnotherWay() { handle(.anotherWay) }

    public func handleImpossible() {
        guard let action = currentAction else { return }
        handle(.impossible(action.id))
    }

    public func handleCancel() { handle(.cancel) }

    public func handleLooksGood() {
        handle(.satisfied)
        if !isReady {
            showStatus("人物完整进入画面后即可拍摄", holdFor: 2)
        }
    }

    public func selectAnchor(x: Double, y: Double) {
        let point = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        anchorPoint = point
        anchorBounds = nil
        bindingVersion += 1
        sceneRevision += 1
        showStatus("已选择背景主体，正在分析构图", holdFor: 1.5)
        Task { try? await camera.focus(at: point) }
    }

    public func switchCamera() {
        guard !isDemoMode else { return }
        let requested: CameraPosition = cameraPosition == .back ? .front : .back
        Task { [weak self] in
            guard let self else { return }
            do {
                try await camera.switchCamera(to: requested)
                cameraPosition = requested
                anchorPoint = nil
                anchorBounds = nil
                bindingVersion += 1
                sceneRevision += 1
                restartGuidance(keepCamera: true)
                showStatus(requested == .back ? "已切换到后置相机" : "已切换到前置相机", holdFor: 2)
            } catch {
                showStatus(localized(error), holdFor: 3)
            }
        }
    }

    public func cycleFlash() {
        guard !isDemoMode, cameraPosition == .back else { return }
        let requested: CameraFlashMode
        switch flashMode {
        case .off: requested = .auto
        case .auto: requested = .on
        case .on: requested = .off
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await camera.setFlashMode(requested)
                flashMode = requested
            } catch {
                flashMode = .off
                showStatus(localized(error), holdFor: 3)
            }
        }
    }

    public func capture() {
        guard isReady, !isSaving else {
            showStatus("先完成关键构图，再拍摄", holdFor: 2)
            return
        }
        guard !isDemoMode else {
            showStatus("模拟器只验证控制闭环，请在 iPhone 上拍摄", holdFor: 2.5)
            return
        }
        isSaving = true
        photoSaved = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await camera.capturePhoto()
                lastPhoto = image
                let result = await camera.savePhotoToLibrary(image)
                switch result {
                case .success:
                    photoSaved = true
                    showStatus("照片已保存到相册", holdFor: 3)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure(let error):
                    photoSaved = false
                    showStatus(localized(error), holdFor: 4)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                showStatus(localized(error), holdFor: 4)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isSaving = false
        }
    }

    public func dismissReview() {
        lastPhoto = nil
        photoSaved = false
        restartGuidance(keepCamera: true)
        showStatus("继续观察下一张照片", holdFor: 2)
    }

    public func lockCurrentComposition() {
        let satisfied = session.engine.states.compactMap { entry in
            entry.value.state == .satisfied ? entry.key : nil
        }
        for goalID in satisfied {
            session.handle(.lock(goalID), transaction: &transaction)
        }
        showStatus(satisfied.isEmpty ? "当前还没有可锁定的构图目标" : "已锁定当前构图，后续建议会避开破坏它", holdFor: 2.5)
        refreshDecision()
    }

    public func skipCurrentGoal() {
        guard recipe.source.author_policy.allow_goal_skip,
              let goalID = currentAction?.affects.first else { return }
        session.handle(.skip(goalID), transaction: &transaction)
        transaction = nil
        showStatus("已跳过这一项，匹配度会相应降低", holdFor: 2.5)
        refreshDecision()
    }

    public func resetAll() {
        anchorPoint = nil
        anchorBounds = nil
        bindingVersion += 1
        sceneRevision += 1
        restartGuidance(keepCamera: false)
        showStatus("已重新开始，请选择背景主体", holdFor: 2)
    }

    public func restartGuidance(keepCamera: Bool = true) {
        session = GuidanceSession(goals: recipe.goals, actions: recipe.actions)
        transaction = nil
        currentAction = nil
        completedDemoGoals.removeAll()
        lastValues.removeAll()
        personBounds = nil
        isReady = false
        lastDecisionWasReady = false
        if !keepCamera {
            anchorPoint = nil
            anchorBounds = nil
        }
        updateProgress()
    }

    private func handle(_ event: UserEvent) {
        session.handle(event, transaction: &transaction)
        refreshDecision()
    }

    private func enterDemoMode() {
        isDemoMode = true
        isPermissionBlocked = false
        localReady = true
        compositionReady = true
        anchorPoint = CGPoint(x: 0.75, y: 0.44)
        status = "模拟器交互模式 · 真机将使用实时相机"
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
        for goal in recipe.goals {
            let isComplete = completedDemoGoals.contains(goal.id)
            let value: DimensionValue
            switch goal.dimension.rawValue {
            case "std.node.exists", "std.node.visibility":
                value = .boolean(true)
            case "std.node.visual_scale":
                value = .continuous(isComplete ? 0.20 : 0.35)
            case "std.node.position_x":
                value = .continuous(isComplete ? 0.65 : 0.40)
            case "std.node.position_y":
                value = .continuous(isComplete ? 0.50 : 0.72)
            default:
                value = .ordinal(isComplete ? 0 : 2)
            }
            ingest(
                dimension: goal.dimension,
                binding: goal.binding,
                value: value,
                confidence: 0.96,
                frameID: currentFrameID,
                evaluator: EvaluatorID("simulator.demo")
            )
        }
        refreshDecision()
    }

    private func consumeFrames() async {
        for await frame in camera.frames() {
            if Task.isCancelled { return }
            let selectedAnchor = anchorPoint.map { NormalizedPoint(x: $0.x, y: $0.y) }
            guard let scene = await localEvaluator.evaluateScene(
                frame.pixelBuffer,
                orientation: .up,
                anchorPoint: selectedAnchor
            ) else { continue }
            ingestLocal(scene, frameID: frame.id)
        }
    }

    private func ingestLocal(_ scene: SceneObservation, frameID: Int) {
        currentFrameID = frameID
        let person = scene.person
        let primary = GuidanceCore.Binding([NodeID("primary")])
        let relation = GuidanceCore.Binding([NodeID("primary"), NodeID("anchor")])
        let confidence = max(0.55, person.confidence)

        ingest(dimension: DimensionID("std.node.exists"), binding: primary, value: .boolean(person.present), confidence: confidence, frameID: frameID)
        ingest(dimension: DimensionID("std.node.visibility"), binding: primary, value: .boolean(person.visible), confidence: confidence, frameID: frameID)
        ingest(dimension: DimensionID("std.node.visual_scale"), binding: primary, value: .continuous(person.scale), confidence: confidence, frameID: frameID)
        ingest(dimension: DimensionID("std.node.position_x"), binding: primary, value: .continuous(person.x), confidence: confidence, frameID: frameID)
        ingest(dimension: DimensionID("std.node.position_y"), binding: primary, value: .continuous(person.y), confidence: confidence, frameID: frameID)

        if let bodyOrientation = person.bodyOrientation {
            ingest(dimension: DimensionID("std.pose.body_orientation"), binding: primary, value: .ordinal(bodyOrientation), confidence: person.confidence * 0.86, frameID: frameID, evaluator: EvaluatorID("vision.body_pose"))
        } else {
            ingest(dimension: DimensionID("std.pose.body_orientation"), binding: primary, value: .ordinal(0), confidence: 0, frameID: frameID, evaluator: EvaluatorID("vision.body_pose"))
        }

        if let composition = scene.composition {
            ingest(dimension: DimensionID("std.relation.relative_scale"), binding: relation, value: .ordinal(composition.relativeScale), confidence: composition.confidence, frameID: frameID, evaluator: EvaluatorID("vision.saliency_relation"))
            ingest(dimension: DimensionID("std.relation.visual_balance"), binding: relation, value: .ordinal(composition.visualBalance), confidence: composition.confidence, frameID: frameID, evaluator: EvaluatorID("vision.saliency_relation"))
        }

        localReady = person.present
        compositionReady = scene.composition != nil
        personBounds = person.bounds.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        anchorBounds = scene.anchor.map { CGRect(x: $0.bounds.x, y: $0.bounds.y, width: $0.bounds.width, height: $0.bounds.height) }
        refreshDecision()
    }

    private func ingest(
        dimension: DimensionID,
        binding: GuidanceCore.Binding,
        value: DimensionValue,
        confidence: Double,
        frameID: Int,
        evaluator: EvaluatorID = EvaluatorID("vision.local")
    ) {
        lastValues[dimension] = value
        _ = session.ingest(Observation(
            dimension: dimension,
            binding: binding,
            value: value,
            confidence: confidence,
            evaluator: evaluator,
            frameID: frameID,
            timestamp: .now,
            bindingVersion: bindingVersion,
            sceneRevision: sceneRevision
        ))
    }

    private func refreshDecision() {
        if !isDemoMode, localReady, anchorPoint == nil {
            currentAction = nil
            transaction = nil
            isReady = false
            instruction = "点一下画面中的背景主体"
            showDefaultStatus("例如建筑、树木或地标")
            updateProgress()
            return
        }

        let decision = session.tick()
        switch decision {
        case .propose(let action):
            currentAction = action
            if transaction?.definition.id != action.id {
                transaction = ActionInstance(action)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            isReady = false
            instruction = message(for: action)
            showDefaultStatus(isDemoMode ? "模拟器交互模式" : "完成后点“好了”，我会重新检查")
        case .ready, .readyByUser:
            currentAction = nil
            transaction = nil
            isReady = true
            instruction = "构图可以了，拍吧"
            showDefaultStatus(decision == .readyByUser ? "已按你的选择停止继续优化" : "关键目标已稳定满足")
        case .unknown:
            currentAction = nil
            isReady = false
            instruction = localReady ? "保持一下，我正在确认" : "把人物完整放进画面"
            showDefaultStatus(localReady ? "需要连续两帧稳定结果" : "人物应从头到脚尽量完整可见")
        case .wait:
            currentAction = nil
            isReady = false
            instruction = "保持不动，正在复核"
            showDefaultStatus("已收到操作，等待新画面")
        case .unreachable:
            currentAction = nil
            isReady = false
            instruction = "当前条件下无法继续优化"
            showDefaultStatus("可以换个位置，或在关键目标满足后点“满意”")
        }

        if isReady, !lastDecisionWasReady {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        lastDecisionWasReady = isReady
        updateProgress()
    }

    private func message(for action: ActionDefinition) -> String {
        guard let goalID = action.affects.first,
              let goal = recipe.goals.first(where: { $0.id == goalID }) else {
            return "轻微调整画面"
        }
        let alternate = action.id.rawValue.hasSuffix(".alternative")
        switch goal.dimension.rawValue {
        case "std.node.exists":
            return "让人物进入画面"
        case "std.node.visibility":
            return alternate ? "把相机稍微拿远一点" : "让人物完整留在画面内"
        case "std.node.visual_scale":
            guard case .continuous(let value) = lastValues[goal.dimension] else { return "调整人物在画面中的大小" }
            if value > 0.30 { return alternate ? "切到更广的镜头" : "向后退一小步" }
            return alternate ? "切到 2× 镜头" : "向人物靠近一点"
        case "std.node.position_x":
            guard case .continuous(let value) = lastValues[goal.dimension] else { return "调整人物左右位置" }
            return value < 0.58 ? "让人物往画面右边一点" : "让人物往画面左边一点"
        case "std.node.position_y":
            guard case .continuous(let value) = lastValues[goal.dimension] else { return "调整人物上下位置" }
            return value < 0.42 ? "镜头稍微往下" : "镜头稍微往上"
        case "std.pose.body_orientation":
            return alternate ? "摄影者横向移动一点" : "让人物肩膀稍微转向镜头"
        case "std.relation.relative_scale":
            guard case .ordinal(let value) = lastValues[goal.dimension] else { return "调整人物与背景主体的比例" }
            if value < 0 { return alternate ? "让人物离背景主体近一点" : "后退并适当拉近焦段" }
            return alternate ? "换一个更开阔的背景主体" : "靠近人物，让背景主体少占一些画面"
        case "std.relation.visual_balance":
            guard case .ordinal(let value) = lastValues[goal.dimension] else { return "平衡人物和背景主体" }
            return value < 0 ? "镜头稍微向右平移" : "镜头稍微向左平移"
        default:
            return "轻微调整画面"
        }
    }

    private func updateProgress() {
        let relevant = session.engine.states.values.filter { $0.policy != .skipped }
        let satisfied = relevant.filter { $0.state == .satisfied }.count
        progress = relevant.isEmpty ? 0 : Double(satisfied) / Double(relevant.count)
        progressLabel = "\(satisfied) / \(relevant.count)"
    }

    private func showStatus(_ message: String, holdFor seconds: TimeInterval) {
        status = message
        statusHoldUntil = Date().addingTimeInterval(seconds)
    }

    private func showDefaultStatus(_ message: String) {
        guard Date() >= statusHoldUntil else { return }
        status = message
    }

    private func localized(_ error: Error) -> String {
        if let cameraError = error as? CameraRuntimeError {
            switch cameraError {
            case .authorizationDenied: return "相机权限已关闭，请到设置中开启"
            case .authorizationRestricted: return "此设备限制了相机访问"
            case .photoLibraryDenied: return "照片已拍下，但没有相册写入权限"
            case .photoLibraryRestricted: return "此设备限制了相册写入"
            case .flashUnavailable: return "当前摄像头不支持闪光灯"
            default: return cameraError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

@MainActor
public struct GuidanceCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = GuidanceViewModel()
    @State private var showOptions = false

    public init() {}

    public var body: some View {
        ZStack {
            previewSurface
            overlayChrome
            if model.isPermissionBlocked { permissionOverlay }
            if let photo = model.lastPhoto { reviewOverlay(photo) }
        }
        .preferredColorScheme(.dark)
        .task { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.resumeAfterForegrounding()
            case .background: model.stop()
            default: break
            }
        }
        .confirmationDialog("控制选项", isPresented: $showOptions, titleVisibility: .visible) {
            Button("保持当前构图", systemImage: "lock.fill", action: model.lockCurrentComposition)
            Button("跳过当前目标", systemImage: "forward.fill", action: model.skipCurrentGoal)
            Button("重新开始", systemImage: "arrow.counterclockwise", role: .destructive, action: model.resetAll)
            Button("关闭", role: .cancel) {}
        }
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            ZStack {
                if model.isDemoMode {
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.12, blue: 0.18), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 150, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.13))
                } else {
                    CameraPreviewRepresentable(session: model.camera.session)
                }

                guideRect(model.personBounds, color: .white, in: proxy.size)
                guideRect(model.anchorBounds, color: .mint, in: proxy.size)

                if let anchor = model.anchorPoint {
                    ZStack {
                        Circle().stroke(.mint, lineWidth: 2).frame(width: 34, height: 34)
                        Circle().fill(.mint).frame(width: 5, height: 5)
                    }
                    .shadow(color: .black.opacity(0.7), radius: 3)
                    .position(x: anchor.x * proxy.size.width, y: anchor.y * proxy.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    model.selectAnchor(
                        x: value.location.x / max(proxy.size.width, 1),
                        y: value.location.y / max(proxy.size.height, 1)
                    )
                }
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func guideRect(_ rect: CGRect?, color: Color, in size: CGSize) -> some View {
        if let rect {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.78), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .frame(width: rect.width * size.width, height: rect.height * size.height)
                .position(x: rect.midX * size.width, y: rect.midY * size.height)
                .animation(.easeOut(duration: 0.16), value: rect)
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            instructionCard
            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("环境人像").font(.headline.weight(.bold))
                HStack(spacing: 6) {
                    StatusChip(title: "人物", active: model.localReady)
                    StatusChip(title: "构图", active: model.compositionReady)
                    if model.isDemoMode { StatusChip(title: "模拟", active: false) }
                }
            }
            Spacer()
            Button(action: model.cycleFlash) {
                Image(systemName: flashIcon).frame(width: 38, height: 38)
            }
            .disabled(model.isDemoMode || model.cameraPosition == .front)
            Button(action: model.switchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 38, height: 38)
            }
            .disabled(model.isDemoMode)
            Button {
                showOptions = true
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 38, height: 38)
            }
            .accessibilityLabel("更多")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.42), in: Capsule())
    }

    private var flashIcon: String {
        switch model.flashMode {
        case .off: "bolt.slash.fill"
        case .auto: "bolt.badge.a.fill"
        case .on: "bolt.fill"
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.instruction)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(model.progressLabel).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
            }
            ProgressView(value: model.progress)
                .tint(model.isReady ? .mint : .white)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.13)))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if model.currentAction != nil {
                HStack(spacing: 9) {
                    GuidanceButton(title: "好了", icon: "checkmark", action: model.handleDone)
                    GuidanceButton(title: "换方法", icon: "arrow.triangle.2.circlepath", action: model.handleAnotherWay)
                    GuidanceButton(title: "做不到", icon: "hand.raised", action: model.handleImpossible)
                    GuidanceButton(title: "取消", icon: "xmark", action: model.handleCancel, subdued: true)
                }
            }
            HStack(spacing: 12) {
                Button(action: model.handleLooksGood) {
                    Label("我满意了", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.68))
                Button(action: model.capture) {
                    ZStack {
                        Circle().fill(.white).frame(width: 68, height: 68)
                        Circle().stroke(.black.opacity(0.25), lineWidth: 2).frame(width: 56, height: 56)
                        if model.isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "camera.fill").foregroundStyle(.black).font(.title2)
                        }
                    }
                }
                .accessibilityLabel("拍摄")
                .disabled(!model.isReady || model.isSaving)
                .opacity(model.isReady ? 1 : 0.48)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("需要相机权限").font(.title2.bold())
            Text("PhotoGuide 只在设备上分析取景画面。请到系统设置中允许相机访问。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("打开设置", action: model.openSettings).buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func reviewOverlay(_ image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Label(
                    model.photoSaved ? "已保存到相册" : "照片尚未保存",
                    systemImage: model.photoSaved ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(model.photoSaved ? .mint : .orange)
                Button("继续拍摄", action: model.dismissReview)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .padding(24)
        }
    }
}

private struct StatusChip: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(active ? .mint : .orange).frame(width: 5, height: 5)
            Text(title).font(.system(size: 9, weight: .bold))
        }
    }
}

private struct GuidanceButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var subdued = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(subdued ? 0.55 : 0.92))
    }
}

@MainActor
private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewView { CameraPreviewView(session: session) }
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}
