import CameraRuntime
import GuidanceCore
import SwiftUI

public enum CompositionGuide: Equatable, Sendable {
  case none
  case leftThird
  case rightThird
}

public struct PresentedGuidance: Equatable, Sendable {
  public let title: String
  public let detail: String
  public let symbol: String
  public let isSafetySensitive: Bool
  public let previewCue: CameraGuideCue
  public let compositionGuide: CompositionGuide

  public init(
    title: String,
    detail: String,
    symbol: String,
    isSafetySensitive: Bool = false,
    previewCue: CameraGuideCue = .none,
    compositionGuide: CompositionGuide = .none
  ) {
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.isSafetySensitive = isSafetySensitive
    self.previewCue = previewCue
    self.compositionGuide = compositionGuide
  }
}

public enum ActionPresenter {
  public static func present(_ action: ActionDefinition) -> PresentedGuidance {
    let base: PresentedGuidance =
      switch action.presentationKey {
      case "subject.enter_frame":
        .init(title: L("让人物进入画面"), detail: L("先完整看到人物，再继续调构图"), symbol: "person.crop.rectangle")
      case "camera.keep_subject_inside":
        .init(title: L("把人物完整留在画面里"), detail: L("稍微重新取景，不用追求一次到位"), symbol: "viewfinder")
      case "photographer.backward":
        .init(
          title: L("往后一点"), detail: L("人物现在偏大，退一小步就够"), symbol: "arrow.down.forward",
          isSafetySensitive: true)
      case "camera.zoom_out":
        .init(title: L("切到更广的焦段"), detail: L("减少人物占比，机位先别动"), symbol: "minus.magnifyingglass")
      case "photographer.forward":
        .init(title: L("靠近一点"), detail: L("让人物在画面里更有存在感"), symbol: "arrow.up.backward")
      case "camera.zoom_2x":
        .init(title: L("试试 2×"), detail: L("不动机位，先把人物拉近一点"), symbol: "2.circle.fill")
      case "subject.move_right":
        .init(
          title: L("人物往右一点"), detail: L("靠近右侧三分线就好"), symbol: "arrow.right",
          previewCue: .right, compositionGuide: .rightThird)
      case "subject.move_left":
        .init(
          title: L("人物往左一点"), detail: L("靠近左侧三分线就好"), symbol: "arrow.left",
          previewCue: .left, compositionGuide: .leftThird)
      case "camera.aim_up":
        .init(title: L("镜头抬一点"), detail: L("让人物在画面里往下落一点"), symbol: "arrow.up", previewCue: .up)
      case "camera.aim_down":
        .init(title: L("镜头压一点"), detail: L("让人物在画面里往上提一点"), symbol: "arrow.down", previewCue: .down)
      case "subject.turn_toward_camera":
        .init(
          title: L("肩膀再朝镜头一点"), detail: L("动作小一点，会更自然"),
          symbol: "arrow.trianglehead.2.clockwise.rotate.90")
      case "photographer.backward_anchor":
        .init(
          title: L("往后一点，让景更有存在感"), detail: L("人物先保持位置和姿势"), symbol: "mountain.2",
          isSafetySensitive: true)
      case "subject.away_from_camera":
        .init(title: L("人物离镜头远一点"), detail: L("让背景主体相对更突出"), symbol: "arrow.up.right")
      case "photographer.forward_subject":
        .init(title: L("靠近人物一点"), detail: L("让人物相对背景更突出"), symbol: "figure.walk")
      case "subject.toward_camera":
        .init(title: L("人物靠近镜头一点"), detail: L("背景先别动，人物会更突出"), symbol: "arrow.down.left")
      case "camera.balance_right":
        .init(title: L("机位轻轻往右"), detail: L("只修一点画面重心"), symbol: "arrow.right", previewCue: .right)
      case "camera.balance_left":
        .init(title: L("机位轻轻往左"), detail: L("只修一点画面重心"), symbol: "arrow.left", previewCue: .left)
      case "system.hold_evidence":
        .init(title: L("保持一下"), detail: L("先别动，我需要一帧更稳定的画面"), symbol: "viewfinder.circle")
      case "system.wait_semantic":
        .init(title: L("保持一秒"), detail: L("正在补充人物和背景关系判断"), symbol: "eye.circle")
      case "user.reselect_anchor":
        .init(title: L("重新点一下背景主体"), detail: L("点你真正想保留的山、建筑、树或地标"), symbol: "scope")
      default:
        .init(title: L("轻微调整一下"), detail: L("保持其它部分不变"), symbol: "scope")
      }

    if action.safety == .contextDependent {
      return .init(
        title: base.title,
        detail: base.detail + L(" · 先确认脚下和身后安全"),
        symbol: base.symbol,
        isSafetySensitive: true,
        previewCue: base.previewCue,
        compositionGuide: base.compositionGuide)
    }
    return base
  }
}
