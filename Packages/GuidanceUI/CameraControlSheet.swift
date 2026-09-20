import Foundation
import SwiftUI

struct CameraControlSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var model: GuidanceViewModel
  @Binding var gridEnabled: Bool

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(spacing: 18) {
          sessionSection.pgReveal(delay: 0.02, distance: 8)
          cameraSection.pgReveal(delay: 0.07, distance: 8)
          utilitySection.pgReveal(delay: 0.12, distance: 8)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 28)
      }
      .background(PGTheme.canvas.ignoresSafeArea())
      .navigationTitle(L("拍摄控制"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(L("完成")) { dismiss() }
            .fontWeight(.semibold)
            .foregroundStyle(PGTheme.accent)
        }
      }
    }
    .preferredColorScheme(.dark)
    .animation(reduceMotion ? nil : PGMotion.state, value: model.canSkipCurrentGoal)
  }

  private var sessionSection: some View {
    VStack(spacing: 0) {
      ControlActionRow(
        icon: model.isPausedByUser ? "sparkles" : "heart",
        title: model.isPausedByUser ? L("继续优化") : L("这样可以了"),
        subtitle: model.isPausedByUser ? L("重新开启实时指导") : L("保留现在的样子，不再主动打扰"),
        tint: PGTheme.accent
      ) {
        if model.isPausedByUser {
          model.resumeGuidance()
        } else {
          model.handleLooksGood()
        }
      }

      separator

      ControlActionRow(
        icon: "lock",
        title: L("锁住满意的部分"),
        subtitle: L("后续建议不会轻易破坏已经到位的构图")
      ) {
        model.lockCurrentComposition()
      }
      .accessibilityIdentifier("control.lockComposition")

      if model.canSkipCurrentGoal {
        separator
        ControlActionRow(
          icon: "forward.end",
          title: L("跳过当前目标"),
          subtitle: L("这一项之后不会继续追着调整")
        ) {
          model.skipCurrentGoal()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .controlPanel()
  }

  private var cameraSection: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "sun.max")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 3) {
          Text(L("画面亮度"))
            .font(.system(size: 15, weight: .semibold))
            .accessibilityIdentifier("control.exposure.title")
          Text(model.exposureReadout)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(PGTheme.tertiaryText)
        }

        Spacer()

        Text(exposureLabel)
          .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(abs(model.exposureBias) < 0.04 ? PGTheme.secondaryText : PGTheme.accent)
          .padding(.horizontal, 9)
          .frame(height: 28)
          .background(.white.opacity(0.055), in: Capsule())
      }

      if model.supportsExposureBias {
        HStack(spacing: 12) {
          Image(systemName: "sun.min")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PGTheme.tertiaryText)
          Slider(
            value: Binding(
              get: { model.exposureBias },
              set: { model.setExposureBias($0) }
            ),
            in: model.exposureBiasRange,
            step: 0.1
          )
          .tint(PGTheme.accent)
          Image(systemName: "sun.max.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PGTheme.tertiaryText)
        }
        .padding(.top, 12)

        HStack {
          Text(L("自动曝光仍在工作，这里只做曝光补偿。"))
            .font(.system(size: 11))
            .foregroundStyle(PGTheme.tertiaryText)
          Spacer()
          Button(L("归零")) { model.resetExposureBias() }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PGTheme.secondaryText)
            .buttonStyle(PGPressButtonStyle())
        }
        .padding(.top, 9)
      } else {
        Text(L("当前摄像头不提供曝光补偿"))
          .font(.system(size: 12))
          .foregroundStyle(PGTheme.tertiaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 10)
      }
    }
    .padding(16)
    .controlPanel()
  }

  private var utilitySection: some View {
    VStack(spacing: 0) {
      ControlToggleRow(
        icon: "square.grid.3x3",
        title: L("构图辅助线"),
        subtitle: L("只有当前建议需要时才显示对应参考线"),
        isOn: $gridEnabled)

      if model.anchorPoint != nil {
        separator
        ControlActionRow(
          icon: "scope",
          title: L("重新选择背景主体"),
          subtitle: L("重新点选你真正想保留的山、建筑、树或地标")
        ) {
          model.reselectAnchor()
          dismiss()
        }
        .accessibilityIdentifier("control.reselectAnchor")
      }

      separator

      ControlActionRow(
        icon: "arrow.counterclockwise",
        title: L("重新开始这次指导"),
        subtitle: L("清除当前锚点和本次会话里的调整状态"),
        tint: .white.opacity(0.76)
      ) {
        model.resetAll()
        dismiss()
      }
      .accessibilityIdentifier("control.restart")
    }
    .controlPanel()
  }

  private var separator: some View {
    Rectangle()
      .fill(PGTheme.hairline)
      .frame(height: 0.7)
      .padding(.leading, 52)
  }

  private var exposureLabel: String {
    let value = model.exposureBias
    if abs(value) < 0.04 { return "0.0 EV" }
    return String(format: "%+.1f EV", locale: Locale.current, value)
  }
}

private struct ControlActionRow: View {
  let icon: String
  let title: String
  let subtitle: String
  var tint: Color = .white.opacity(0.84)
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(PGTheme.tertiaryText)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
        }

        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.24))
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 66)
      .contentShape(Rectangle())
    }
    .buttonStyle(PGPressButtonStyle())
  }
}

private struct ControlToggleRow: View {
  let icon: String
  let title: String
  let subtitle: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white.opacity(0.82))
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(PGTheme.tertiaryText)
      }

      Spacer(minLength: 10)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(PGTheme.accent)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 66)
  }
}

private struct ControlPanelModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(.white.opacity(0.038), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(.white.opacity(0.065), lineWidth: 0.7))
  }
}

extension View {
  fileprivate func controlPanel() -> some View { modifier(ControlPanelModifier()) }
}
