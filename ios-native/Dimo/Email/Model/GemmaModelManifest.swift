import Foundation

struct GemmaModelManifest: Codable, Hashable, Sendable {
  var modelName: String
  var version: String
  var runtimeFormatVersion: String
  var downloadURL: URL
  var exactByteCount: Int64
  var sha256: String
  var minimumFreeStorageBytes: Int64
  var promptSchemaVersion: Int
  var termsURL: URL
  var attributionURL: URL

  enum CodingKeys: String, CodingKey {
    case modelName
    case version = "modelVersion"
    case runtimeFormatVersion
    case downloadURL
    case exactByteCount
    case sha256
    case minimumFreeStorageBytes
    case promptSchemaVersion
    case termsURL
    case attributionURL
  }

  static func load(
    from bundle: Bundle = .main,
    resourceName: String = "GemmaModelManifest"
  ) throws -> GemmaModelManifest {
    guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
      throw GemmaModelManifestError.missing
    }
    let manifest: GemmaModelManifest
    do {
      manifest = try JSONDecoder().decode(GemmaModelManifest.self, from: Data(contentsOf: url))
    } catch {
      throw GemmaModelManifestError.invalid(error.localizedDescription)
    }
    try manifest.validate()
    return manifest
  }

  func validate() throws {
    guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !runtimeFormatVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          downloadURL.scheme?.lowercased() == "https",
          termsURL.scheme?.lowercased() == "https",
          attributionURL.scheme?.lowercased() == "https",
          exactByteCount > 0,
          exactByteCount <= Int64.max / 2,
          minimumFreeStorageBytes >= exactByteCount * 2,
          promptSchemaVersion == EmailAnalysisResult.schemaVersion,
          sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
      throw GemmaModelManifestError.invalid("One or more manifest fields are invalid.")
    }
  }
}

enum GemmaModelManifestError: LocalizedError {
  case missing
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .missing: return "GemmaModelManifest.json is missing from the app bundle."
    case .invalid(let message): return "The Gemma model manifest is invalid: \(message)"
    }
  }
}
