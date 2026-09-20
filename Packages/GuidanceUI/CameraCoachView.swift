import CameraRuntime
import Foundation
import GuidanceCore
import SwiftUI

public struct GuidanceCameraView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var model = GuidanceViewModel()
  @State private var showOptions = false
  @State private var gridEnabled = true
  @State private var shutterPulse = false
  @State private var captureFlashOpacity = 0.0
  @Namespace private var lensSelection

  public init() {}

  public var body: some View {
    ZStack {
      preview
      if gridEnabled { contextualGuideLine.allowsHitTesting(false) }
      chrome

      Color.white
        .opacity(captureFlashOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .zIndex(8)

      if model.isPermissionBlocked { permissionOverlay.zIndex(12) }

      if let photo = model.lastPhoto {
        CaptureReviewView(
          image: photo,
          saved: model.photoSaved,
          conformance: model.conformance,
          onContinue: model.dismissReview,
          onDone: {
            model.dismissReview()
            dismiss()
          }
        )
        .transition(
          .asymmetric(insertion: .scale(scale: 1.015).combined(with: .opacity), removal: .opacity)
        )
        .zIndex(20)
      }
    }
    .background(.black)
    .foregroundStyle(.white)
    .task { model.start() }
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
    .sheet(isPresented: $showOptions) {
      CameraControlSheet(model: model, gridEnabled: $gridEnabled)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(PGTheme.canvas)
    }
  }

  private var preview: some View {
    Group {
      if model.isDemoMode {
        demoPreview
      } else {
        CameraPreviewRepresentable(
          session: model.camera.session,
          personRect: model.personBounds,
          anchorRect: model.anchorBounds,
          anchorPoint: model.anchorPoint,
          guideCue: model.previewCue,
          onTap: model.selectAnchor,
          onZoomGesture: model.handleZoomGesture)
      }
    }
    .ignoresSafeArea()
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [.black.opacity(0.48), .clear], startPoint: .top, endPoint: .bottom
      )
      .frame(height: 148)
      .allowsHitTesting(false)
    }
    .overlay(alignment: .bottom) {
      LinearGradient(
        colors: [.clear, .black.opacity(0.68)], startPoint: .top, endPoint: .bottom
      )
      .frame(height: passiveCoachMode ? 285 : 340)
      .allowsHitTesting(false)
    }
  }

  private var demoPreview: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.16, green: 0.22, blue: 0.25), .black],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: "mountain.2.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 440)
        .foregroundStyle(.white.opacity(0.12))
        .offset(y: -90)
      Image(systemName: "person.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 86)
        .foregroundStyle(.white.opacity(0.34))
        .offset(x: 92, y: 36)
    }
  }

  @ViewBuilder
  private var contextualGuideLine: some View {
    GeometryReader { geo in
      if model.compositionGuide != .none {
        let x = geo.size.width * (model.compositionGuide == .rightThird ? 2.0 / 3.0 : 1.0 / 3.0)
        Path { path in
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x, y: geo.size.height))
        }
        .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.7, dash: [6, 8]))
        .transition(.opacity)
      }
    }
    .ignoresSafeArea()
    .animation(reduceMotion ? nil : PGMotion.settle, value: model.compositionGuide)
  }

  private var chrome: some View {
    VStack(spacing: 0) {
      topBar
        .padding(.horizontal, 18)
        .padding(.top, 8)

      if let notice = model.transientNotice {
        transientNotice(notice)
          .padding(.top, 8)
          .transition(
            .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
      }

      Spacer()

      if model.isInteractiveZooming {
        zoomReadout
          .padding(.bottom, 10)
          .transition(.scale(scale: 0.96).combined(with: .opacity))
      }

      if shouldShowSafetyHint {
        safetyHint
          .transition(
            .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
          )
          .padding(.bottom, 8)
      }

      coachSurface
        .padding(.horizontal, 14)

      lensSelector
        .padding(.top, passiveCoachMode ? 10 : 13)

      captureBar
        .padding(.horizontal, 25)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    .animation(reduceMotion ? nil : PGMotion.state, value: model.instruction)
    .animation(reduceMotion ? nil : PGMotion.settle, value: model.isReady)
    .animation(reduceMotion ? nil : PGMotion.state, value: model.currentAction?.id)
    .animation(reduceMotion ? nil : PGMotion.micro, value: model.isInteractiveZooming)
    .animation(reduceMotion ? nil : PGMotion.state, value: model.transientNotice)
    .animation(reduceMotion ? nil : PGMotion.state, value: model.zoomFactor)
    .animation(reduceMotion ? nil : PGMotion.navigation, value: model.lastPhoto != nil)
  }

  private var topBar: some View {
    ZStack {
      HStack {
        glassCircle(
          "xmark",
          size: 44,
          accessibilityLabel: L("关闭拍摄"),
          accessibilityIdentifier: "camera.close"
        ) { dismiss() }
        Spacer()
        HStack(spacing: 9) {
          glassCircle(
            flashIcon,
            size: 44,
            disabled: model.isDemoMode || model.cameraPosition == .front,
            accessibilityLabel: L("闪光灯"),
            accessibilityIdentifier: "camera.flash"
          ) {
            model.cycleFlash()
          }
          glassCircle(
            gridEnabled ? "square.grid.3x3" : "square",
            size: 44,
            selected: gridEnabled,
            accessibilityLabel: L("构图辅助线"),
            accessibilityIdentifier: "camera.grid"
          ) {
            if reduceMotion {
              gridEnabled.toggle()
            } else {
              withAnimation(PGMotion.micro) { gridEnabled.toggle() }
            }
          }
        }
      }

      Button {
        showOptions = true
      } label: {
        HStack(spacing: 6) {
          Text(model.title)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.horizontal, 15)
        .frame(height: 36)
        .frame(maxWidth: 132)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("拍摄控制"))
      .accessibilityIdentifier("camera.recipeControls")
    }
  }

  private var safetyHint: some View {
    HStack(spacing: 7) {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(PGTheme.accent)
      Text(L("移动前留意脚下"))
    }
    .font(.system(size: 12, weight: .medium))
    .padding(.horizontal, 12)
    .frame(height: 32)
    .background(.ultraThinMaterial, in: Capsule())
    .background(.black.opacity(0.18), in: Capsule())
    .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
  }

  private var shouldShowSafetyHint: Bool {
    model.currentAction != nil && model.isCurrentActionSafetySensitive
  }

  private var passiveCoachMode: Bool {
    model.currentAction == nil && !model.needsAnchorSelection
  }

  @ViewBuilder
  private var coachSurface: some View {
    if passiveCoachMode {
      passiveCoachCard
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.985, anchor: .bottom).combined(with: .opacity),
            removal: .opacity))
    } else {
      actionableCoachCard
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.985, anchor: .bottom).combined(with: .opacity),
            removal: .opacity))
    }
  }

  private var actionableCoachCard: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: model.instructionSymbol)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(directionTint)
          .frame(width: 32)

        Text(model.instruction)
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .tracking(-0.45)
          .lineLimit(2)
          .minimumScaleFactor(0.80)
          .id("instruction.title.\(model.instruction)")
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.985, anchor: .leading).combined(with: .opacity),
              removal: .opacity))

        Spacer(minLength: 8)

        Text(coachStateLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(PGTheme.secondaryText)
          .lineLimit(1)
          .padding(.horizontal, 9)
          .frame(height: 27)
          .background(.white.opacity(0.055), in: Capsule())
      }

      Text(model.instructionDetail)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(PGTheme.secondaryText)
        .lineLimit(3)
        .id("instruction.detail.\(model.instructionDetail)")
        .transition(.opacity)

      coachActions
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 15)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .background(
      PGTheme.panelStrong.opacity(0.84), in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
    .overlay(RoundedRectangle(cornerRadius: 26).stroke(PGTheme.hairline, lineWidth: 0.7))
    .shadow(color: .black.opacity(0.13), radius: 16, y: 8)
  }

  private var passiveCoachCard: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(model.isReady ? PGTheme.accent.opacity(0.16) : .white.opacity(0.055))
          .frame(width: 44, height: 44)
        Image(systemName: model.instructionSymbol)
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(model.isReady ? PGTheme.accent : .white.opacity(0.90))
      }

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(model.instruction)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.86)
            .id("passive.title.\(model.instruction)")
          if model.isReady {
            Circle()
              .fill(PGTheme.accent)
              .frame(width: 5, height: 5)
          }
        }
        Text(model.instructionDetail)
          .font(.system(size: 12.5, weight: .regular))
          .foregroundStyle(PGTheme.secondaryText)
          .lineLimit(2)
          .id("passive.detail.\(model.instructionDetail)")
      }

      Spacer(minLength: 8)

      if model.isPausedByUser {
        Button(L("继续优化"), action: model.resumeGuidance)
          .buttonStyle(.plain)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
          .padding(.horizontal, 10)
          .frame(height: 32)
          .background(PGTheme.accent.opacity(0.09), in: Capsule())
      } else if model.isReady {
        Text(L("可以拍了"))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
          .padding(.horizontal, 10)
          .frame(height: 30)
          .background(PGTheme.accent.opacity(0.09), in: Capsule())
      } else {
        ProgressView()
          .tint(PGTheme.accent)
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 15)
    .frame(minHeight: 72)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .background(
      PGTheme.panel.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay(RoundedRectangle(cornerRadius: 24).stroke(PGTheme.hairline, lineWidth: 0.7))
    .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
  }

  @ViewBuilder
  private var coachActions: some View {
    if model.needsAnchorSelection {
      HStack(spacing: 8) {
        Image(systemName: "hand.tap")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
        Text(L("点画面里的山、建筑、树或地标"))
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(PGTheme.secondaryText)
        Spacer()
      }
      .frame(height: 32)
    } else if model.currentAction != nil {
      HStack(spacing: 0) {
        primaryCoachAction
        Spacer(minLength: 16)
        textAction(L("换一个"), model.handleAnotherWay)
        Spacer().frame(width: 24)
        textAction(L("做不到"), model.handleImpossible)
      }
    }
  }

  private var primaryCoachAction: some View {
    Button(action: model.performPrimaryAction) {
      HStack(spacing: 7) {
        if model.isApplyingAutomaticAction {
          ProgressView().tint(.black).controlSize(.small)
        }
        Text(model.primaryActionTitle)
          .lineLimit(1)
      }
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.black)
      .padding(.horizontal, 18)
      .frame(minWidth: 122, minHeight: 46)
      .background(PGTheme.accent, in: Capsule())
    }
    .buttonStyle(PGPressButtonStyle())
    .disabled(model.isApplyingAutomaticAction)
    .accessibilityLabel(model.primaryActionTitle)
  }

  private var coachStateLabel: String {
    if model.needsAnchorSelection { return L("先选背景") }
    if model.currentAction != nil { return model.progress > 0.65 ? L("接近理想") : L("继续微调") }
    return ""
  }

  private var directionTint: Color {
    if model.previewCue != .none || model.isCurrentActionSafetySensitive { return PGTheme.accent }
    return .white
  }

  private var zoomReadout: some View {
    Text(formatZoom(model.zoomFactor))
      .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 38)
      .background(.black.opacity(0.44), in: Capsule())
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.7))
  }

  private var lensSelector: some View {
    HStack(spacing: 1) {
      ForEach(model.zoomFactors, id: \.self) { factor in
        let selected = abs(model.zoomFactor - factor) < 0.08
        Button {
          model.setZoom(factor)
        } label: {
          Text(formatZoom(factor))
            .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(selected ? .black : .white.opacity(0.68))
            .frame(width: 40, height: 30)
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
    .background(.black.opacity(0.34), in: Capsule())
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
    .opacity(model.zoomFactors.count > 1 ? 1 : 0)
  }

  private var captureBar: some View {
    HStack {
      recentPhotoButton

      Spacer()

      Button(action: triggerCapture) {
        ZStack {
          Circle()
            .stroke(model.isReady ? PGTheme.accent : .white.opacity(0.70), lineWidth: 2.5)
            .frame(width: 82, height: 82)
            .scaleEffect(model.isReady && shutterPulse ? 1.022 : 1)
            .opacity(model.isReady && shutterPulse ? 0.84 : 1)
          Circle()
            .fill(.white)
            .frame(width: model.isSaving ? 64 : 68, height: model.isSaving ? 64 : 68)
            .animation(reduceMotion ? nil : PGMotion.micro, value: model.isSaving)
          if model.isSaving { ProgressView().tint(.black) }
        }
      }
      .buttonStyle(PGPressButtonStyle())
      .disabled(model.isSaving)
      .accessibilityLabel(L("拍摄"))
      .accessibilityIdentifier("camera.shutter")
      .shadow(color: model.isReady ? PGTheme.accent.opacity(0.15) : .clear, radius: 13)

      Spacer()

      Button(action: model.switchCamera) {
        Image(systemName: "arrow.triangle.2.circlepath.camera")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 50, height: 50)
          .background(.ultraThinMaterial, in: Circle())
          .background(.black.opacity(0.16), in: Circle())
          .overlay(Circle().stroke(PGTheme.hairline, lineWidth: 0.7))
      }
      .buttonStyle(PGPressButtonStyle())
      .disabled(model.isDemoMode)
      .opacity(model.isDemoMode ? 0.35 : 1)
      .accessibilityLabel(L("切换相机"))
      .accessibilityIdentifier("camera.switch")
    }
  }

  @ViewBuilder
  private var recentPhotoButton: some View {
    if let image = model.recentPhoto {
      Button(action: model.openRecentPhotoReview) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 50, height: 50)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.36), lineWidth: 0.8))
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("查看最近拍摄"))
    } else {
      Button(action: model.handleLooksGood) {
        Image(systemName: model.isPausedByUser ? "heart.fill" : "heart")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(model.isPausedByUser ? PGTheme.accent : .white)
          .frame(width: 50, height: 50)
          .background(
            .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous)
          )
          .background(
            .black.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous)
          )
          .overlay(RoundedRectangle(cornerRadius: 15).stroke(PGTheme.hairline, lineWidth: 0.7))
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("这样可以了"))
    }
  }

  private func triggerCapture() {
    guard !model.isSaving else { return }
    if !reduceMotion {
      captureFlashOpacity = 0.16
      withAnimation(PGMotion.micro) { captureFlashOpacity = 0 }
    }
    model.capture()
  }

  private func transientNotice(_ text: String) -> some View {
    HStack(spacing: 7) {
      Circle()
        .fill(PGTheme.accent)
        .frame(width: 5, height: 5)
      Text(text)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.80))
        .lineLimit(1)
    }
    .padding(.horizontal, 11)
    .frame(height: 30)
    .background(.black.opacity(0.34), in: Capsule())
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.065), lineWidth: 0.7))
  }

  private var permissionOverlay: some View {
    ZStack {
      Color.black.opacity(0.88).ignoresSafeArea()
      VStack(spacing: 18) {
        Image(systemName: "camera.fill")
          .font(.system(size: 27))
          .foregroundStyle(PGTheme.accent)
          .frame(width: 66, height: 66)
          .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 21))
        Text(L("需要相机权限"))
          .font(.system(size: 23, weight: .bold, design: .rounded))
        Text(L("实时取景和本地视觉分析需要访问相机。"))
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
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(selected ? PGTheme.accent : .white)
        .frame(width: size, height: size)
        .background(.ultraThinMaterial, in: Circle())
        .background(.black.opacity(0.16), in: Circle())
        .background(selected ? PGTheme.accent.opacity(0.12) : .clear, in: Circle())
        .overlay(Circle().stroke(PGTheme.hairline, lineWidth: 0.7))
    }
    .buttonStyle(PGPressButtonStyle())
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier(accessibilityIdentifier)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func textAction(_ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
      .buttonStyle(PGPressButtonStyle())
      .font(.system(size: 14.5, weight: .medium))
      .foregroundStyle(.white.opacity(0.82))
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
