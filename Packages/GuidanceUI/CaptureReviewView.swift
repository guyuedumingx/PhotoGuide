import GuidanceCore
import SwiftUI
import UIKit

struct CaptureReviewView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var photoSettled = false

  let image: UIImage
  let saved: Bool
  let conformance: Conformance
  let onContinue: () -> Void
  let onDone: () -> Void

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      GeometryReader { geometry in
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()
          .scaleEffect(photoSettled || reduceMotion ? 1 : 1.018)
      }
      .ignoresSafeArea()

      LinearGradient(
        colors: [.black.opacity(0.24), .clear, .black.opacity(0.90)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar.pgReveal(delay: 0.03, distance: 8)
        Spacer()
        resultCard.pgReveal(delay: 0.08, distance: 12)
      }
    }
    .foregroundStyle(.white)
    .onAppear {
      if reduceMotion {
        photoSettled = true
      } else {
        withAnimation(PGMotion.navigation) { photoSettled = true }
      }
    }
    .transition(.opacity)
  }

  private var topBar: some View {
    HStack {
      Text(L("刚刚拍下"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))

      Spacer()

      Button(action: onContinue) {
        Image(systemName: "xmark")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
          .pgGlassCircle()
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("关闭照片预览"))
    }
    .padding(.top, 8)
    .padding(.horizontal, 18)
  }

  private var resultCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      resultHeader

      HStack(spacing: 8) {
        conformanceChip
        saveStatusChip
      }

      VStack(spacing: 10) {
        continueButton
        doneButton
      }
    }
    .padding(20)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .background(
      Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 28, style: .continuous)
    )
    .overlay(RoundedRectangle(cornerRadius: 28).stroke(PGTheme.hairline, lineWidth: 0.7))
    .padding(.horizontal, 14)
    .padding(.bottom, 18)
  }

  private var headline: String {
    switch conformance {
    case .full: L("这张很到位")
    case .high: L("这张很好看")
    case .partial: L("这张很自然")
    case .low: L("这一刻已经留下来了")
    case .notApplicable: L("拍好了")
    }
  }

  private var subheadline: String {
    if saved { return L("已经保存到系统相册") }
    return L("照片已拍下；保存状态还在确认")
  }

  private var conformanceText: String {
    switch conformance {
    case .full: L("很到位")
    case .high: L("很好")
    case .partial: L("自然")
    case .low: L("自由")
    case .notApplicable: L("完成")
    }
  }

  private var statusIcon: String {
    conformance == .full || conformance == .high ? "checkmark.circle.fill" : "camera.fill"
  }

  private var statusColor: Color {
    conformance == .full || conformance == .high ? PGTheme.accent : .white.opacity(0.76)
  }

  private var resultHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      statusBadge
      resultCopy
    }
  }

  private var resultCopy: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(headline)
        .font(.system(.title, design: .rounded, weight: .bold))
        .tracking(-0.5)
        .fixedSize(horizontal: false, vertical: true)
      Text(subheadline)
        .font(.subheadline)
        .foregroundStyle(PGTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var statusBadge: some View {
    Image(systemName: statusIcon)
      .font(.system(size: 22, weight: .semibold))
      .foregroundStyle(statusColor)
      .frame(width: 42, height: 42)
      .background(.white.opacity(0.055), in: Circle())
  }

  private var continueButton: some View {
    Button(action: onContinue) {
      HStack {
        Text(L("继续拍"))
          .font(.headline)
        Spacer()
        Image(systemName: "camera.fill")
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(.black)
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 52)
      .background(PGTheme.accent, in: Capsule())
    }
    .buttonStyle(PGPressButtonStyle())
    .accessibilityIdentifier("capture.review.continue")
  }

  private var doneButton: some View {
    Button(action: onDone) {
      Text(L("完成"))
        .font(.headline)
        .foregroundStyle(.white.opacity(0.90))
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 18)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
    }
    .buttonStyle(PGPressButtonStyle())
    .accessibilityIdentifier("capture.review.done")
  }

  private var conformanceChip: some View {
    ReviewChip(icon: "viewfinder", title: L("构图"), value: conformanceText)
  }

  private var saveStatusChip: some View {
    ReviewChip(
      icon: saved ? "checkmark" : "camera",
      title: L("照片"),
      value: saved ? L("已保存") : L("已拍摄"),
      accessibilityIdentifier: "capture.review.saveStatus")
  }
}

private struct ReviewChip: View {
  let icon: String
  let title: String
  let value: String
  var accessibilityIdentifier = "capture.review.conformance"

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
      Text(title)
        .foregroundStyle(PGTheme.tertiaryText)
      Text(value)
        .foregroundStyle(.white.opacity(0.88))
    }
    .font(.caption.weight(.semibold))
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .frame(minHeight: 31)
    .background(.white.opacity(0.07), in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.7))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}
