import CameraRuntime
import Foundation
import GuidanceCore
import RecipeKit
import SwiftUI
import UIKit

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

  public var body: some View {
    GeometryReader { geometry in
      ZStack {
        cameraViewport

        if showRecipeQuickPicker {
          recipeQuickPickerOverlay(in: geometry)
            .zIndex(30)
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity))
        }
      }
      .background(Color.black.ignoresSafeArea())
      .foregroundStyle(.white)
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

  private var cameraViewport: some View {
    GeometryReader { cameraGeometry in
      ZStack {
        preview
        safeScrims(in: cameraGeometry)
        if gridEnabled { compositionGrid.allowsHitTesting(false) }
        if model.subjectStrategy != .scene && !model.subjectPresent {
          searchScan(in: cameraGeometry).allowsHitTesting(false)
        }
        cameraChrome

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
    GeometryReader { geometry in
      ZStack {
        LinearGradient(
          colors: [Color(red: 0.12, green: 0.16, blue: 0.18), .black],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: "mountain.2.fill")
          .resizable().scaledToFit()
          .frame(width: geometry.size.width * 0.92)
          .foregroundStyle(.white.opacity(0.10))
          .offset(y: -70)
        Image(systemName: "camera.aperture")
          .font(.system(size: 54, weight: .ultraLight))
          .foregroundStyle(.white.opacity(0.18))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  private var cameraChrome: some View {
    VStack(spacing: 0) {
      topBar
        .padding(.horizontal, 16)
        .padding(.top, 8)

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

      liveGuidanceSurface
        .padding(.horizontal, 14)
        .padding(.bottom, 7)

      lensSelector
        .padding(.bottom, 8)

      captureBar
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
    .animation(reduceMotion ? nil : PGMotion.state, value: model.instruction)
    .animation(reduceMotion ? nil : PGMotion.micro, value: model.currentIssueQuestionID)
  }

  private var topBar: some View {
    HStack {
      Spacer()
      cameraUtilityCluster
    }
  }

  private var cameraUtilityCluster: some View {
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
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .background(.black.opacity(0.44), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.7))
    }
    .accessibilityLabel(L("相机控制"))
    .accessibilityIdentifier("camera.controls")
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
    HStack(spacing: 11) {
      Image(systemName: "viewfinder")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(PGTheme.accent)
        .frame(width: 38, height: 38)
        .background(PGTheme.accent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(L("选择 Recipe 开始"))
          .font(.system(size: 16, weight: .bold, design: .rounded))
        Text(L("使用左下角 Recipe 按钮"))
          .font(.system(size: 12))
          .foregroundStyle(PGTheme.secondaryText)
      }
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 68)
    .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10), lineWidth: 0.7))
    .accessibilityElement(children: .combine)
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
        .frame(height: 96)
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
        .frame(width: 44, height: 44)
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
              .frame(width: 44, height: 44)
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
    .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
          .font(.system(size: 18, weight: .bold, design: .rounded))
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
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.06), in: Circle())
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("跳过当前问题"))
      .accessibilityIdentifier("camera.skipQuestion")
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 82)
    .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(PGTheme.hairline, lineWidth: 0.7))
    .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    .accessibilityLabel("\(L(item.title)). \(L(item.issue ?? item.title))")
    .accessibilityIdentifier("camera.questionIssue.\(item.id)")
  }

  private var zoomReadout: some View {
    Text(formatZoom(model.zoomFactor))
      .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
      .padding(.horizontal, 13)
      .frame(height: 36)
      .background(.black.opacity(0.38), in: Capsule())
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
      .background(.black.opacity(0.42), in: Capsule())
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
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.44), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.7))
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
    .accessibilityLabel(L("选择 Recipe"))
    .accessibilityValue(model.recipe.source.id == "camera.shell" ? L("未选择") : model.title)
    .accessibilityIdentifier("camera.recipe")
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
      Button(action: closeRecipeQuickPicker) {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L("关闭 Recipe 选择器"))
      .accessibilityIdentifier("camera.recipeDismiss")

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
              .frame(height: 44)
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
                .frame(width: 44, height: 44)
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
