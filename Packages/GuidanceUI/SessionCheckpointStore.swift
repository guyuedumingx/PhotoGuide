import Foundation
import GuidanceCore

/// Small crash/background recovery store. Checkpoints are intentionally short-
/// lived because "can't do this here" and learned action effectiveness are
/// session context, not permanent user preferences.
struct SessionCheckpointStore {
  private struct Envelope: Codable {
    let savedAt: Date
    let checkpoint: GuidanceSessionCheckpoint
  }

  var maximumAge: TimeInterval = 30 * 60

  func save(_ checkpoint: GuidanceSessionCheckpoint, key: String) throws {
    let url = try fileURL(for: key, createDirectory: true)
    let data = try JSONEncoder().encode(Envelope(savedAt: .now, checkpoint: checkpoint))
    try data.write(to: url, options: [.atomic])
  }

  func load(key: String) -> GuidanceSessionCheckpoint? {
    guard let url = try? fileURL(for: key, createDirectory: false),
      let data = try? Data(contentsOf: url),
      let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
    else { return nil }

    guard Date().timeIntervalSince(envelope.savedAt) <= maximumAge else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return envelope.checkpoint
  }

  func clear(key: String) {
    guard let url = try? fileURL(for: key, createDirectory: false) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private func fileURL(for key: String, createDirectory: Bool) throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: createDirectory
    )
    let directory = base.appendingPathComponent("PhotoGuide/SessionRecovery", isDirectory: true)
    if createDirectory {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let safeKey = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
    return directory.appendingPathComponent(String(safeKey) + ".json")
  }
}
