import SwiftUI

public enum PGTheme {
  public static let accent = Color(red: 0.66, green: 0.95, blue: 0.86)
  public static let accentStrong = Color(red: 0.48, green: 0.85, blue: 0.76)
  public static let accent2 = Color(red: 0.67, green: 0.78, blue: 0.96)
  public static let warning = Color(red: 0.96, green: 0.74, blue: 0.38)
  public static let canvas = Color(red: 0.025, green: 0.030, blue: 0.038)
  public static let panel = Color.black.opacity(0.52)
  public static let panelStrong = Color.black.opacity(0.66)
  public static let secondaryText = Color.white.opacity(0.66)
  public static let tertiaryText = Color.white.opacity(0.44)
  public static let hairline = Color.white.opacity(0.085)

  public static func glass<S: Shape>(_ shape: S) -> some View {
    shape
      .fill(.ultraThinMaterial)
      .overlay(shape.stroke(hairline, lineWidth: 0.7))
  }
}

/// Shared motion language for the app. The values are deliberately restrained:
/// fast enough to feel direct, with only a small amount of spring so camera UI
/// never feels playful or unstable.
enum PGMotion {
  static let micro = Animation.easeOut(duration: 0.16)
  static let state = Animation.snappy(duration: 0.28, extraBounce: 0.02)
  static let settle = Animation.spring(duration: 0.42, bounce: 0.08)
  static let navigation = Animation.spring(duration: 0.48, bounce: 0.06)
  static let reveal = Animation.spring(duration: 0.52, bounce: 0.06)
  static let breathing = Animation.easeInOut(duration: 1.65).repeatForever(autoreverses: true)
}

struct PGPressButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.982 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(reduceMotion ? nil : PGMotion.micro, value: configuration.isPressed)
  }
}

private struct PGRevealModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let delay: Double
  let distance: CGFloat
  @State private var visible = false

  func body(content: Content) -> some View {
    content
      .opacity(visible ? 1 : 0)
      .offset(y: visible || reduceMotion ? 0 : distance)
      .scaleEffect(visible || reduceMotion ? 1 : 0.992, anchor: .center)
      .onAppear {
        if reduceMotion {
          visible = true
        } else {
          withAnimation(PGMotion.reveal.delay(delay)) { visible = true }
        }
      }
  }
}

private struct GlassCapsule: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(Capsule().stroke(PGTheme.hairline, lineWidth: 0.7))
  }
}

private struct GlassCircle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(.ultraThinMaterial, in: Circle())
      .overlay(Circle().stroke(PGTheme.hairline, lineWidth: 0.7))
  }
}

private struct GlassRounded: ViewModifier {
  let radius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(
        .ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous)
      )
      .background(PGTheme.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(PGTheme.hairline, lineWidth: 0.7))
  }
}

extension View {
  func pgGlassCapsule() -> some View { modifier(GlassCapsule()) }
  func pgGlassCircle() -> some View { modifier(GlassCircle()) }
  func pgGlassRounded(radius: CGFloat = 24) -> some View { modifier(GlassRounded(radius: radius)) }
  func pgReveal(delay: Double = 0, distance: CGFloat = 12) -> some View {
    modifier(PGRevealModifier(delay: delay, distance: distance))
  }
}
