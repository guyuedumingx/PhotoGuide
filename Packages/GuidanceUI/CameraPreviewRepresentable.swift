@preconcurrency import AVFoundation
import CameraRuntime
import SwiftUI

@MainActor
struct CameraPreviewRepresentable: UIViewRepresentable {
  let session: AVCaptureSession
  let subjectRect: CGRect?
  let faceRect: CGRect?
  let anchorRect: CGRect?
  let anchorPoint: CGPoint?
  let guideCue: CameraGuideCue
  let onTap: (CameraTapPoint) -> Void
  let onZoomGesture: (CameraZoomGesture) -> Void

  func makeUIView(context: Context) -> CameraPreviewView {
    let view = CameraPreviewView(session: session)
    view.onTap = onTap
    view.onZoomGesture = onZoomGesture
    return view
  }

  func updateUIView(_ uiView: CameraPreviewView, context: Context) {
    uiView.onTap = onTap
    uiView.onZoomGesture = onZoomGesture
    uiView.updateOverlays(
      subject: subjectRect,
      face: faceRect,
      anchor: anchorRect,
      selectedImagePoint: anchorPoint,
      cue: guideCue)
  }
}
