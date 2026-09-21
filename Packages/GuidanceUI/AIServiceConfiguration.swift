import Foundation
import GuidanceCore

/// Runtime gates for optional remote intelligence and the development-only
/// preview critic. No credential is stored in the app bundle.
enum PGAIServiceConfiguration {
  static var previewCriticEnabled: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("-usePreviewCritic")
        || UserDefaults.standard.bool(forKey: "photoguide.previewCriticEnabled")
    #else
      false
    #endif
  }

  static var remoteAIConsentGranted: Bool {
    UserDefaults.standard.bool(forKey: "photoguide.remoteAIConsentGranted")
  }

  static var endpoint: URL? {
    let environment = ProcessInfo.processInfo.environment
    let candidates = [
      environment["MULTIMODAL_CRITIC_ENDPOINT"],
      environment["DJEV_ENDPOINT"],
      Bundle.main.object(forInfoDictionaryKey: "MultimodalCriticEndpoint") as? String,
      Bundle.main.object(forInfoDictionaryKey: "DJEVEndpoint") as? String,
    ]

    for candidate in candidates {
      guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty,
        let url = URL(string: value)
      else { continue }
      #if DEBUG
        if url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" {
          return url
        }
      #else
        if url.scheme == "https" { return url }
      #endif
    }
    return nil
  }
}

#if DEBUG
/// Deterministic mock used only to exercise the camera UI and semantic state
/// machine. It deliberately does not inspect image bytes or claim visual quality.
struct PreviewMultimodalCriticEvaluator: MultimodalCritic {
  func critique(
    profile: CriticProfile,
    samples: [CriticImageSample],
    locale: String
  ) async throws -> SemanticCritique {
    Self.makeCritique(profile: profile, seed: samples.last?.frameID ?? 0, locale: locale)
  }

  static func makeCritique(
    profile: CriticProfile,
    seed: Int,
    locale: String
  ) -> SemanticCritique {
    let assessments = profile.dimensions.enumerated().map { index, dimension in
      let variation = Double(abs(seed &+ index &* 17) % 37) / 100
      let score = min(0.86, 0.50 + variation)
      return CriticDimensionAssessment(
        dimensionID: dimension.id,
        score: score,
        confidence: 0.91,
        rationale: "Preview-only deterministic result",
        evidenceFrameIDs: [seed])
    }
    let weakest = zip(profile.dimensions, assessments).min { $0.1.score < $1.1.score }
    let advice = weakest.map { dimension, assessment in
      CriticAdvice(
        dimensionID: dimension.id,
        kind: .other,
        title: dimension.name,
        detail: assessment.rationale,
        confidence: assessment.confidence)
    }
    let overall = assessments.isEmpty
      ? nil
      : assessments.reduce(0) { $0 + $1.score } / Double(assessments.count)
    return SemanticCritique(
      assessments: assessments,
      advice: advice.map { [$0] } ?? [],
      overallScore: overall,
      captureReady: false,
      modelID: "preview-no-vision")
  }
}
#endif
