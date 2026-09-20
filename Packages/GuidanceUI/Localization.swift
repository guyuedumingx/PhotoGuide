import Foundation

private final class PGBundleToken: NSObject {}

enum PGL10n {
  static let bundle = Bundle(for: PGBundleToken.self)

  static func string(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
  }

  static func format(_ key: String, arguments: [CVarArg]) -> String {
    String(format: string(key), locale: Locale.current, arguments: arguments)
  }
}

@inline(__always)
func L(_ key: String) -> String { PGL10n.string(key) }

@inline(__always)
func LF(_ key: String, _ arguments: CVarArg...) -> String {
  PGL10n.format(key, arguments: arguments)
}
