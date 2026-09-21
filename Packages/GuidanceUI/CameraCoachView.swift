import CameraRuntime
import Foundation
import GuidanceCore
import RecipeKit
import SwiftUI
import UIKit

private enum CameraGuidanceLayout: String {
  case overlay
  case split
}

public struct GuidanceCameraView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @StateObject private var model: GuidanceViewModel
  @ObservedObject private var recipeStore = RecipeAssetStore.shared
  @AppStorage("photoguide.camera.gridEnabled.v1") private var gridEnabled = true
  @State private var shutterPulse = false
  @State private var captureFlashOpacity = 0.0
  @State private var scanProgress: CGFloat = 0
  @State private var showRecipeQuickPicker = false
  @AppStorage("photoguide.camera.guidanceLayout.v1") private var guidanceLayoutRaw = CameraGuidanceLayout.overlay.rawValue
  @Namespace private var lensSelection

  private let onMenu: () -> Void
  private let onSelectRecipe: (RecipeDTO) -> Void

  public init(
    recipe: RecipeDTO,
    onMenu: @escaping () -> Void = {},
    onSelectRecipe: @escaping (RecipeDTO) -> Void = { _ in }
  ) {
    _model = StateObject(wrappedValue: GuidanceViewModel(recipeDTO: recipe))
    self.onMenu = onMenu
    self.onSelectRecipe = onSelectRecipe
  }

  public init(
    preset: RecipePreset = .environmentPortrait,
    onMenu: @escaping () -> Void = {},
    onSelectRecipe: @escaping (RecipeDTO) -> Void = { _ in }
  ) {
    _model = StateObject(wrappedValue: GuidanceViewModel(preset: preset))
    self.onMenu = onMenu
    self.onSelectRecipe = onSelectRecipe
  }

  private var guidanceLayout: CameraGuidanceLayout {
    CameraGuidanceLayout(rawValue: guidanceLayoutRaw) ?? .overlay
  }

  public var body: some View {
    GeometryReader { geometry in
      ZStack {
        Group {
          if guidanceLayout == .split {
            splitLayout(in: geometry)
          } else {
            overlayLayout(in: geometry)
          }
        }

        if showRecipeQuickPicker {
          recipeQuickPickerOverlay(in: geometry)
            .zIndex(30)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .background(.black)
      .foregroundStyle(.white)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: showRecipeQuickPicker)
    }
    .task {
      model.start()
      guard !reduceMotion else { return }
      scanProgress = 0
      withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
        scanProgress = 1
      }
    }
    .onDisappear { model.stop() }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active: model.resumeAfterForegrounding()
      case .background: model.pauseForBackground()
      default: break
      }
    }
    .onChange(of: model.isReady) { _, ready in
      guard ready, !reduceMotion else {
        shutterPulse = false
        return
      }
      shutterPulse = false
      withAnimation(PGMotion.breathing) { shutterPulse = true }
    }
  }

  private func overlayLayout(in geometry: GeometryProxy) -> some View {
    cameraViewport(showGuidance: true)
  }

  private func splitLayout(in geometry: GeometryProxy) -> some View {
    let cameraHeight = geometry.size.height * 0.70
    return VStack(spacing: 0) {
      cameraViewport(showGuidance: false)
        .frame(height: cameraHeight)
        .clipped()

      splitGuidancePanel(safeBottom: geometry.safeAreaInsets.bottom)
        .frame(height: max(geometry.size.height - cameraHeight, 0))
    }
  }

  private func cameraViewport(showGuidance: Bool) -> some View {
    GeometryReader { cameraGeometry in
      ZStack {
        preview
        safeScrims(in: cameraGeometry)
        if gridEnabled { compositionGrid.allowsHitTesting(false) }
        if model.subjectStrategy != .scene && !model.subjectPresent {
          searchScan(in: cameraGeometry).allowsHitTesting(false)
        }
        cameraChrome(showGuidance: showGuidance, safeArea: cameraGeometry.safeAreaInsets)

        Color.white
          .opacity(captureFlashOpacity)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .zIndex(8)

        if model.isPermissionBlocked { permissionOverlay.zIndex(12) }
      }
    }
  }

  private var preview: some View {
    Group {
      if model.isDemoMode {
        demoPreview
      } else {
        CameraPreviewRepresentable(
          session: model.camera.session,
          subjectRect: model.subjectBounds,
          faceRect: model.faceBounds,
          anchorRect: model.anchorBounds,
          anchorPoint: model.anchorPoint,
          guideCue: model.previewCue,
          onTap: model.selectAnchor,
          onZoomGesture: model.handleZoomGesture)
      }
    }
    .ignoresSafeArea()
  }

  private var demoPreview: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.12, green: 0.16, blue: 0.18), .black],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: "mountain.2.fill")
        .resizable().scaledToFit()
        .frame(width: 430)
        .foregroundStyle(.white.opacity(0.10))
        .offset(y: -70)
      Image(systemName: "camera.aperture")
        .font(.system(size: 54, weight: .ultraLight))
        .foregroundStyle(.white.opacity(0.18))
    }
  }

  @ViewBuilder
  private func safeScrims(in geometry: GeometryProxy) -> some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [.black.opacity(0.40), .black.opacity(0.10), .clear],
        startPoint: .top, endPoint: .bottom)
        .frame(height: max(geometry.safeAreaInsets.top, 18) + 72)
      Spacer()
      LinearGradient(
        colors: [.clear, .black.opacity(0.10), .black.opacity(0.50)],
        startPoint: .top, endPoint: .bottom)
        .frame(height: max(geometry.safeAreaInsets.bottom, 8) + 132)
    }
    .allowsHitTesting(false)
  }

  private var compositionGrid: some View {
    GeometryReader { geo in
      ZStack {
        Path { path in
          for ratio in [1.0 / 3.0, 2.0 / 3.0] {
            let x = geo.size.width * ratio
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: geo.size.height))
            let y = geo.size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: geo.size.width, y: y))
          }
        }
        .stroke(.white.opacity(0.10), lineWidth: 0.55)
      }
    }
  }

  @ViewBuilder
  private func searchScan(in geometry: GeometryProxy) -> some View {
    if !reduceMotion && !model.isPermissionBlocked {
      let usableHeight = max(geometry.size.height - 180, 1)
      Rectangle()
        .fill(
          LinearGradient(
            colors: [.clear, PGTheme.accent.opacity(0.16), .clear],
            startPoint: .leading,
            endPoint: .trailing)
        )
        .frame(height: 1)
        .shadow(color: PGTheme.accent.opacity(0.26), radius: 5)
        .offset(y: -geometry.size.height / 2 + 90 + usableHeight * scanProgress)
        .opacity(0.7)
    }
  }

  private func cameraChrome(showGuidance: Bool, safeArea: EdgeInsets) -> some View {
    VStack(spacing: 0) {
      topBar
        .padding(.horizontal, 14)
        .padding(.top, max(safeArea.top, 10) + 6)

      if let notice = model.transientNotice {
        transientNotice(notice)
          .padding(.top, 7)
          .transition(.opacity)
      }

      Spacer(minLength: 12)

      if model.isInteractiveZooming {
        zoomReadout
          .padding(.bottom, 7)
          .transition(.scale(scale: 0.97).combined(with: .opacity))
      }

      if showGuidance {
        liveGuidanceSurface
          .padding(.horizontal, 14)
          .padding(.bottom, 7)
      }

      lensSelector
        .padding(.bottom, 8)

      captureBar
        .padding(.horizontal, 24)
        .padding(.bottom, max(showGuidance ? safeArea.bottom : 6, 6) + 4)
    }
    .animation(reduceMotion ? nil : PGMotion.state, value: model.instruction)
    .animation(reduceMotion ? nil : PGMotion.micro, value: model.currentIssueQuestionID)
  }

  private var topBar: some View {
    HStack(spacing: 9) {
      glassCircle(
        "line.3.horizontal",
        size: 43,
        accessibilityLabel: L("Recipe 菜单"),
        accessibilityIdentifier: "camera.menu",
        action: onMenu)

      Button(action: toggleRecipeQuickPicker) {
        HStack(spacing: 7) {
          Image(systemName: model.recipe.source.resolvedPresentation.icon)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(PGTheme.accent)
          Text(model.recipe.source.id == "camera.shell" ? L("选择 Recipe") : model.title)
            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityIdentifier("camera.recipe")

      cameraUtilityCluster
    }
  }

  private var cameraUtilityCluster: some View {
    HStack(spacing: 0) {
      Button(action: toggleGuidanceLayout) {
        Image(systemName: guidanceLayout == .overlay ? "rectangle.split.2x1" : "rectangle.inset.filled")
          .font(.system(size: 14.5, weight: .semibold))
          .foregroundStyle(guidanceLayout == .split ? PGTheme.accent : .white)
          .frame(width: 38, height: 38)
          .background(guidanceLayout == .split ? PGTheme.accent.opacity(0.10) : .clear, in: Circle())
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(guidanceLayout == .overlay ? L("切换到 7:3 提示布局") : L("切换到悬浮提示布局"))
      .accessibilityIdentifier("camera.guidanceLayout")
      .accessibilityAddTraits(guidanceLayout == .split ? .isSelected : [])

      Rectangle()
        .fill(.white.opacity(0.08))
        .frame(width: 0.7, height: 18)
        .accessibilityHidden(true)

      Menu {
        Menu {
          Button {
            model.setFlashMode(.off)
            UISelectionFeedbackGenerator().selectionChanged()
          } label: {
            Label(L("关闭"), systemImage: model.flashMode == .off ? "checkmark" : "bolt.slash.fill")
          }
          Button {
            model.setFlashMode(.auto)
            UISelectionFeedbackGenerator().selectionChanged()
          } label: {
            Label(L("自动"), systemImage: model.flashMode == .auto ? "checkmark" : "bolt.badge.a.fill")
          }
          Button {
            model.setFlashMode(.on)
            UISelectionFeedbackGenerator().selectionChanged()
          } label: {
            Label(L("开启"), systemImage: model.flashMode == .on ? "checkmark" : "bolt.fill")
          }
        } label: {
          Label(L("闪光灯"), systemImage: flashIcon)
        }
        .disabled(model.isDemoMode || model.cameraPosition == .front)

        Button {
          if reduceMotion { gridEnabled.toggle() }
          else { withAnimation(PGMotion.micro) { gridEnabled.toggle() } }
          UISelectionFeedbackGenerator().selectionChanged()
        } label: {
          Label(gridEnabled ? L("关闭构图网格") : L("打开构图网格"), systemImage: "grid")
        }
      } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 14.5, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
      }
      .accessibilityLabel(L("相机控制"))
      .accessibilityIdentifier("camera.controls")
    }
    .padding(3)
    .background(.ultraThinMaterial, in: Capsule())
    .background(.black.opacity(0.14), in: Capsule())
    .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
  }

  private func splitGuidancePanel(safeBottom: CGFloat) -> some View {
    ZStack {
      PGTheme.canvas
      VStack(spacing: 8) {
        HStack(spacing: 8) {
          HStack(spacing: 6) {
            Circle()
              .fill(model.isQuestionMode ? PGTheme.accent : .white.opacity(0.30))
              .frame(width: 6, height: 6)
            Text(model.recipe.source.id == "camera.shell" ? L("未选择 Recipe") : model.title)
              .font(.system(size: 11.5, weight: .semibold, design: .rounded))
              .foregroundStyle(PGTheme.secondaryText)
              .lineLimit(1)
          }
          Spacer()
          if model.issueQuestionSnapshots.count > 1 {
            Text(L("左右滑动切换问题"))
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(PGTheme.tertiaryText)
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)

        liveGuidanceSurface
          .padding(.horizontal, 14)

        Spacer(minLength: 6)
      }
      .padding(.bottom, max(safeBottom, 8))
    }
    .overlay(alignment: .top) {
      Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("camera.splitGuidancePanel")
  }

  @ViewBuilder
  private var liveGuidanceSurface: some View {
    if model.recipe.source.id == "camera.shell" {
      emptyRecipeCard
    } else if model.isQuestionMode {
      questionGuidanceSurface
    } else {
      emptyRecipeCard
    }
  }

  private var emptyRecipeCard: some View {
    Button(action: toggleRecipeQuickPicker) {
      HStack(spacing: 12) {
        Image(systemName: "square.grid.2x2")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
          .frame(width: 42, height: 42)
          .background(PGTheme.accent.opacity(0.11), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(L("选择一个 Recipe"))
            .font(.system(size: 17, weight: .bold, design: .rounded))
          Text(L("参考图和问题会直接出现在这个相机界面"))
            .font(.system(size: 12.5))
            .foregroundStyle(PGTheme.secondaryText)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(PGTheme.tertiaryText)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .background(PGTheme.panel.opacity(0.76), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(PGTheme.hairline, lineWidth: 0.7))
    }
    .buttonStyle(PGPressButtonStyle())
  }

  @ViewBuilder
  private var questionGuidanceSurface: some View {
    let issues = model.issueQuestionSnapshots
    if issues.isEmpty {
      questionStatusCard
    } else {
      VStack(spacing: 7) {
        TabView(
          selection: Binding(
            get: { model.currentIssueQuestionID ?? issues[0].id },
            set: { id in
              if id != model.currentIssueQuestionID { UISelectionFeedbackGenerator().selectionChanged() }
              model.selectIssueQuestion(id)
            }
          )
        ) {
          ForEach(Array(issues.enumerated()), id: \.element.id) { index, item in
            questionIssueCard(item, index: index, total: issues.count)
              .tag(item.id)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: guidanceLayout == .split ? 112 : 96)
        .accessibilityIdentifier("camera.questionCarousel")

        questionPager(issues)
      }
    }
  }

  private func questionPager(_ issues: [QuestionRuntimeSnapshot]) -> some View {
    let selectedIndex = max(issues.firstIndex(where: { $0.id == model.currentIssueQuestionID }) ?? 0, 0)
    return HStack(spacing: 8) {
      if issues.count <= 7 {
        HStack(spacing: 5) {
          ForEach(issues) { item in
            Capsule()
              .fill(item.id == model.currentIssueQuestionID ? Color.white.opacity(0.82) : Color.white.opacity(0.20))
              .frame(width: item.id == model.currentIssueQuestionID ? 15 : 5, height: 5)
              .animation(reduceMotion ? nil : PGMotion.micro, value: model.currentIssueQuestionID)
          }
        }
      } else {
        Text("\(selectedIndex + 1) / \(issues.count)")
          .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(PGTheme.tertiaryText)
      }

      Spacer()

      HStack(spacing: 10) {
        if model.skippedQuestionCount > 0 {
          Button {
            model.restoreAllQuestions()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "arrow.uturn.backward")
              Text("\(L("恢复")) \(model.skippedQuestionCount)")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(PGTheme.secondaryText)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("camera.restoreSkippedQuestions")
        }

        questionManagementMenu
      }
    }
    .padding(.horizontal, 4)
  }

  private var questionManagementMenu: some View {
    Menu {
      ForEach(model.questionSnapshots) { item in
        let skipped = item.status == .skipped
        Button {
          model.setQuestionSkipped(item.id, skipped: !skipped)
          UISelectionFeedbackGenerator().selectionChanged()
        } label: {
          Label(
            L(item.title),
            systemImage: skipped ? "arrow.uturn.backward.circle" : "eye.slash")
        }
      }
    } label: {
      Image(systemName: "list.bullet")
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(PGTheme.secondaryText)
        .frame(width: 28, height: 28)
        .background(.white.opacity(0.05), in: Circle())
    }
    .accessibilityLabel(L("管理问题"))
    .accessibilityIdentifier("camera.questionManager")
  }

  private var questionStatusCard: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(.white.opacity(0.06)).frame(width: 40, height: 40)
        Image(systemName: model.instructionSymbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white.opacity(0.88))
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(model.instruction)
          .font(.system(size: 16.5, weight: .bold, design: .rounded))
          .lineLimit(2)
        if !model.instructionDetail.isEmpty {
          Text(model.instructionDetail)
            .font(.system(size: 12))
            .foregroundStyle(PGTheme.secondaryText)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 4)
      HStack(spacing: 7) {
        if model.skippedQuestionCount > 0 {
          Button {
            model.restoreAllQuestions()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
          } label: {
            Image(systemName: "arrow.uturn.backward")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(PGTheme.secondaryText)
              .frame(width: 34, height: 34)
              .background(.white.opacity(0.06), in: Circle())
          }
          .buttonStyle(PGPressButtonStyle())
          .accessibilityLabel(L("恢复已跳过问题"))
        }
        questionManagementMenu
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 82)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .background(PGTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(PGTheme.hairline, lineWidth: 0.7))
  }

  private func questionIssueCard(_ item: QuestionRuntimeSnapshot, index: Int, total: Int) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 7) {
          Text(L(item.title))
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(PGTheme.secondaryText)
          if total > 1 {
            Text("\(index + 1)/\(total)")
              .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
              .foregroundStyle(PGTheme.tertiaryText)
          }
        }
        Text(L(item.issue ?? item.title))
          .font(.system(size: guidanceLayout == .split ? 19 : 18, weight: .bold, design: .rounded))
          .tracking(-0.2)
          .lineLimit(2)
          .minimumScaleFactor(0.80)
      }

      Spacer(minLength: 8)

      Button {
        model.skipCurrentQuestion()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      } label: {
        Image(systemName: "forward.end")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(PGTheme.secondaryText)
          .frame(width: 36, height: 36)
          .background(.white.opacity(0.06), in: Circle())
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("跳过当前问题"))
      .accessibilityIdentifier("camera.skipQuestion")
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 82)
    .background(
      guidanceLayout == .split ? AnyShapeStyle(Color.white.opacity(0.045)) : AnyShapeStyle(.ultraThinMaterial),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .background(
      guidanceLayout == .split ? Color.clear : Color.black.opacity(0.24),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(PGTheme.hairline, lineWidth: 0.7))
    .shadow(color: guidanceLayout == .split ? .clear : .black.opacity(0.10), radius: 12, y: 5)
    .accessibilityLabel("\(L(item.title)). \(L(item.issue ?? item.title))")
    .accessibilityIdentifier("camera.questionIssue.\(item.id)")
  }

  private var zoomReadout: some View {
    Text(formatZoom(model.zoomFactor))
      .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
      .padding(.horizontal, 13)
      .frame(height: 36)
      .background(.black.opacity(0.38), in: Capsule())
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.7))
  }

  @ViewBuilder
  private var lensSelector: some View {
    if model.zoomFactors.count > 1 {
      HStack(spacing: 1) {
        ForEach(model.zoomFactors, id: \.self) { factor in
          let selected = abs(model.zoomFactor - factor) < 0.08
          Button {
            if abs(model.zoomFactor - factor) >= 0.08 { UISelectionFeedbackGenerator().selectionChanged() }
            model.setZoom(factor)
          } label: {
            Text(formatZoom(factor))
              .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
              .foregroundStyle(selected ? .black : .white.opacity(0.68))
              .frame(width: 40, height: 29)
              .background {
                if selected {
                  Capsule()
                    .fill(PGTheme.accent)
                    .matchedGeometryEffect(id: "lens.selection", in: lensSelection)
                }
              }
          }
          .buttonStyle(PGPressButtonStyle())
        }
      }
      .padding(4)
      .background(.black.opacity(0.31), in: Capsule())
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
      .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
  }

  private var captureBar: some View {
    HStack(alignment: .center) {
      recipeQuickAccessButton
        .frame(width: 64)

      Spacer()

      Button(action: triggerCapture) {
        ZStack {
          Circle()
            .stroke(.white.opacity(0.78), lineWidth: 2.2)
            .frame(width: 75, height: 75)
            .scaleEffect(shutterPulse ? 1.018 : 1)
          Circle()
            .fill(.white)
            .frame(width: model.isCapturing ? 58 : 63, height: model.isCapturing ? 58 : 63)
            .animation(reduceMotion ? nil : PGMotion.micro, value: model.isCapturing)
          if model.isCapturing { ProgressView().tint(.black) }
        }
      }
      .buttonStyle(PGPressButtonStyle())
      .disabled(model.isCapturing)
      .accessibilityLabel(L("拍摄"))
      .accessibilityIdentifier("camera.shutter")

      Spacer()

      Button(action: triggerCameraSwitch) {
        VStack(spacing: 4) {
          Image(systemName: "arrow.triangle.2.circlepath.camera")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(.ultraThinMaterial, in: Circle())
            .background(.black.opacity(0.14), in: Circle())
            .overlay(Circle().stroke(PGTheme.hairline, lineWidth: 0.7))
          Text(L("翻转"))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: 64)
      }
      .buttonStyle(PGPressButtonStyle())
      .disabled(model.isDemoMode)
      .opacity(model.isDemoMode ? 0.35 : 1)
      .accessibilityLabel(L("切换相机"))
      .accessibilityIdentifier("camera.switch")
    }
  }

  private var recipeQuickAccessButton: some View {
    Button(action: toggleRecipeQuickPicker) {
      VStack(spacing: 4) {
        ZStack {
          Circle()
            .fill(.black.opacity(0.34))
            .frame(width: 42, height: 42)

          if let image = firstReferenceImage(for: model.recipe.source) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 38, height: 38)
              .clipShape(Circle())
          } else {
            Image(systemName: "square.grid.2x2.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(PGTheme.accent)
          }
        }
        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.8))

        Text("Recipe")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.white.opacity(0.78))
      }
      .frame(width: 64)
    }
    .buttonStyle(PGPressButtonStyle())
    .accessibilityLabel(L("快速选择 Recipe"))
    .accessibilityIdentifier("camera.recipeQuick")
  }

  private var quickRecipes: [RecipeDTO] {
    recipeStore.userRecipes
      .filter {
        !$0.recipe.resolvedVisualReferences.isEmpty
          && !$0.recipe.resolvedVisualQuestions.isEmpty
      }
      .sorted { lhs, rhs in
        let lhsActive = lhs.id == model.recipe.source.id
        let rhsActive = rhs.id == model.recipe.source.id
        if lhsActive != rhsActive { return lhsActive }

        let lhsFavorite = recipeStore.isFavorite(lhs.id)
        let rhsFavorite = recipeStore.isFavorite(rhs.id)
        if lhsFavorite != rhsFavorite { return lhsFavorite }

        return lhs.updatedAt > rhs.updatedAt
      }
      .map(\.recipe)
  }

  private func recipeQuickPickerOverlay(in geometry: GeometryProxy) -> some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.28)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { closeRecipeQuickPicker() }

      VStack(spacing: 14) {
        Capsule()
          .fill(.white.opacity(0.20))
          .frame(width: 38, height: 4)
          .padding(.top, 8)

        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(L("选择 Recipe"))
              .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(L("在相机里直接切换拍摄方法"))
              .font(.system(size: 11.5))
              .foregroundStyle(PGTheme.secondaryText)
          }
          Spacer()
          Button {
            closeRecipeQuickPicker()
            onMenu()
          } label: {
            Text(L("管理"))
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(PGTheme.accent)
              .padding(.horizontal, 12)
              .frame(height: 34)
              .background(PGTheme.accent.opacity(0.10), in: Capsule())
          }
          .buttonStyle(PGPressButtonStyle())
          .accessibilityIdentifier("camera.recipeManage")
        }
        .padding(.horizontal, 18)

        if quickRecipes.isEmpty {
          HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(PGTheme.accent)
              .frame(width: 42, height: 42)
              .background(PGTheme.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
              Text(L("还没有 Recipe"))
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
              Text(L("去创建或导入一个 Recipe"))
                .font(.system(size: 11.5))
                .foregroundStyle(PGTheme.secondaryText)
            }
            Spacer()
            Button {
              closeRecipeQuickPicker()
              onMenu()
            } label: {
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(PGPressButtonStyle())
          }
          .padding(.horizontal, 18)
          .frame(height: 86)
        } else {
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
              ForEach(quickRecipes, id: \.id) { recipe in
                recipeQuickTile(recipe)
              }
            }
            .padding(.horizontal, 18)
          }
          .scrollIndicators(.hidden)
        }
      }
      .padding(.bottom, max(geometry.safeAreaInsets.bottom, 10) + 6)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 210)
      .background(.ultraThinMaterial)
      .background(Color.black.opacity(0.72))
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 28,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 28,
          style: .continuous))
      .overlay(alignment: .top) {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.7)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("camera.recipeTray")
    }
  }

  private func recipeQuickTile(_ recipe: RecipeDTO) -> some View {
    let selected = recipe.id == model.recipe.source.id
    let favorite = recipeStore.isFavorite(recipe.id)

    return Button {
      UISelectionFeedbackGenerator().selectionChanged()
      closeRecipeQuickPicker()
      onSelectRecipe(recipe)
    } label: {
      VStack(spacing: 7) {
        ZStack(alignment: .topTrailing) {
          Group {
            if let image = firstReferenceImage(for: recipe) {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            } else {
              ZStack {
                PGTheme.panel
                Image(systemName: recipe.resolvedPresentation.icon)
                  .font(.system(size: 20, weight: .semibold))
                  .foregroundStyle(PGTheme.accent)
              }
            }
          }
          .frame(width: 70, height: 76)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(selected ? PGTheme.accent : .white.opacity(0.08), lineWidth: selected ? 2 : 0.8))

          if favorite {
            Image(systemName: "star.fill")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.black)
              .frame(width: 20, height: 20)
              .background(PGTheme.accent, in: Circle())
              .padding(5)
          }

          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.black)
              .frame(width: 20, height: 20)
              .background(.white, in: Circle())
              .padding(5)
              .offset(y: favorite ? 24 : 0)
          }
        }

        Text(L(recipe.title))
          .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .rounded))
          .foregroundStyle(selected ? .white : .white.opacity(0.78))
          .lineLimit(1)
          .frame(width: 78)
      }
      .padding(.vertical, 4)
    }
    .buttonStyle(PGPressButtonStyle())
    .accessibilityLabel(L(recipe.title))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("camera.recipeTile.\(recipe.id)")
  }

  private func firstReferenceImage(for recipe: RecipeDTO) -> UIImage? {
    guard let data = recipe.resolvedVisualReferences.first?.imagePayload else { return nil }
    return UIImage(data: data)
  }

  private func toggleRecipeQuickPicker() {
    if reduceMotion {
      showRecipeQuickPicker.toggle()
    } else {
      withAnimation(.easeOut(duration: 0.20)) { showRecipeQuickPicker.toggle() }
    }
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func closeRecipeQuickPicker() {
    if reduceMotion {
      showRecipeQuickPicker = false
    } else {
      withAnimation(.easeOut(duration: 0.18)) { showRecipeQuickPicker = false }
    }
  }

  private func toggleGuidanceLayout() {
    let next: CameraGuidanceLayout = guidanceLayout == .overlay ? .split : .overlay
    if reduceMotion { guidanceLayoutRaw = next.rawValue }
    else {
      withAnimation(.easeInOut(duration: 0.24)) { guidanceLayoutRaw = next.rawValue }
    }
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func triggerCapture() {
    guard !model.isCapturing else { return }
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.72)
    if !reduceMotion {
      captureFlashOpacity = 0.14
      withAnimation(PGMotion.micro) { captureFlashOpacity = 0 }
    }
    model.capture()
  }

  private func triggerCameraSwitch() {
    guard !model.isDemoMode else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    model.switchCamera()
  }

  private func transientNotice(_ text: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(PGTheme.accent).frame(width: 5, height: 5)
      Text(text)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.80))
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .frame(height: 28)
    .background(.black.opacity(0.30), in: Capsule())
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.7))
  }

  private var permissionOverlay: some View {
    ZStack {
      Color.black.opacity(0.91).ignoresSafeArea()
      VStack(spacing: 18) {
        Image(systemName: "camera.fill")
          .font(.system(size: 27))
          .foregroundStyle(PGTheme.accent)
          .frame(width: 66, height: 66)
          .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 21))
        Text(L("需要相机权限"))
          .font(.system(size: 23, weight: .bold, design: .rounded))
        Text(L("实时取景需要访问相机。"))
          .font(.system(size: 14.5))
          .foregroundStyle(PGTheme.secondaryText)
          .multilineTextAlignment(.center)
        Button(L("打开设置"), action: model.openSettings)
          .font(.system(size: 15.5, weight: .semibold))
          .foregroundStyle(.black)
          .padding(.horizontal, 25)
          .frame(height: 47)
          .background(PGTheme.accent, in: Capsule())
      }
      .padding(30)
      .frame(maxWidth: 340)
    }
  }

  private func glassCircle(
    _ symbol: String,
    size: CGFloat,
    disabled: Bool = false,
    selected: Bool = false,
    accessibilityLabel: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15.5, weight: .semibold))
        .foregroundStyle(selected ? PGTheme.accent : .white)
        .frame(width: size, height: size)
        .background(.ultraThinMaterial, in: Circle())
        .background(selected ? PGTheme.accent.opacity(0.10) : .black.opacity(0.14), in: Circle())
        .overlay(Circle().stroke(PGTheme.hairline, lineWidth: 0.7))
    }
    .buttonStyle(PGPressButtonStyle())
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier(accessibilityIdentifier)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var flashIcon: String {
    switch model.flashMode {
    case .off: "bolt.slash.fill"
    case .auto: "bolt.badge.a.fill"
    case .on: "bolt.fill"
    }
  }

  private func formatZoom(_ value: Double) -> String {
    value.rounded() == value
      ? "\(Int(value))×" : String(format: "%.1f×", locale: Locale.current, value)
  }
}
