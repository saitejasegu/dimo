import Foundation

enum EmailGemmaModelVariant: String, Codable, CaseIterable, Hashable, Sendable {
  case gemma3_270m = "gemma3-270m"
  case gemma3_1b = "gemma3-1b"

  static let defaultValue: EmailGemmaModelVariant = .gemma3_270m

  var resourceName: String {
    switch self {
    case .gemma3_270m: return "GemmaModelManifest-270m"
    case .gemma3_1b: return "GemmaModelManifest-1b"
    }
  }

  var title: String {
    switch self {
    case .gemma3_270m: return "Gemma 3 270M"
    case .gemma3_1b: return "Gemma 3 1B"
    }
  }

  var subtitle: String {
    switch self {
    case .gemma3_270m: return "Smaller · faster · 8-bit GGUF"
    case .gemma3_1b: return "Larger · stronger · 4-bit GGUF"
    }
  }
}

struct GemmaModelManifest: Codable, Hashable, Sendable {
  static let defaultRuntimeContextTokens = EmailPromptBuilder.defaultRuntimeContextTokens

  var variant: EmailGemmaModelVariant
  var modelName: String
  var version: String
  var runtimeFormatVersion: String
  var familyDirectoryName: String
  var backgroundSessionIdentifier: String
  var downloadURL: URL
  var exactByteCount: Int64
  var sha256: String
  var minimumFreeStorageBytes: Int64
  /// llama.cpp `n_ctx` for this artifact. Larger values need more RAM/heat.
  var runtimeContextTokens: Int
  var promptSchemaVersion: Int
  var termsURL: URL
  var attributionURL: URL

  enum CodingKeys: String, CodingKey {
    case variant
    case modelName
    case version = "modelVersion"
    case runtimeFormatVersion
    case familyDirectoryName
    case backgroundSessionIdentifier
    case downloadURL
    case exactByteCount
    case sha256
    case minimumFreeStorageBytes
    case runtimeContextTokens
    case promptSchemaVersion
    case termsURL
    case attributionURL
  }

  init(
    variant: EmailGemmaModelVariant,
    modelName: String,
    version: String,
    runtimeFormatVersion: String,
    familyDirectoryName: String,
    backgroundSessionIdentifier: String,
    downloadURL: URL,
    exactByteCount: Int64,
    sha256: String,
    minimumFreeStorageBytes: Int64,
    runtimeContextTokens: Int = defaultRuntimeContextTokens,
    promptSchemaVersion: Int,
    termsURL: URL,
    attributionURL: URL
  ) {
    self.variant = variant
    self.modelName = modelName
    self.version = version
    self.runtimeFormatVersion = runtimeFormatVersion
    self.familyDirectoryName = familyDirectoryName
    self.backgroundSessionIdentifier = backgroundSessionIdentifier
    self.downloadURL = downloadURL
    self.exactByteCount = exactByteCount
    self.sha256 = sha256
    self.minimumFreeStorageBytes = minimumFreeStorageBytes
    self.runtimeContextTokens = runtimeContextTokens
    self.promptSchemaVersion = promptSchemaVersion
    self.termsURL = termsURL
    self.attributionURL = attributionURL
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    variant = try container.decode(EmailGemmaModelVariant.self, forKey: .variant)
    modelName = try container.decode(String.self, forKey: .modelName)
    version = try container.decode(String.self, forKey: .version)
    runtimeFormatVersion = try container.decode(String.self, forKey: .runtimeFormatVersion)
    familyDirectoryName = try container.decode(String.self, forKey: .familyDirectoryName)
    backgroundSessionIdentifier = try container.decode(String.self, forKey: .backgroundSessionIdentifier)
    downloadURL = try container.decode(URL.self, forKey: .downloadURL)
    exactByteCount = try container.decode(Int64.self, forKey: .exactByteCount)
    sha256 = try container.decode(String.self, forKey: .sha256)
    minimumFreeStorageBytes = try container.decode(Int64.self, forKey: .minimumFreeStorageBytes)
    runtimeContextTokens = try container.decodeIfPresent(Int.self, forKey: .runtimeContextTokens)
      ?? Self.defaultRuntimeContextTokens
    promptSchemaVersion = try container.decode(Int.self, forKey: .promptSchemaVersion)
    termsURL = try container.decode(URL.self, forKey: .termsURL)
    attributionURL = try container.decode(URL.self, forKey: .attributionURL)
  }

  static func load(
    variant: EmailGemmaModelVariant,
    from bundle: Bundle = .main
  ) throws -> GemmaModelManifest {
    guard let url = bundle.url(forResource: variant.resourceName, withExtension: "json") else {
      throw GemmaModelManifestError.missing(variant)
    }
    let manifest: GemmaModelManifest
    do {
      manifest = try JSONDecoder().decode(GemmaModelManifest.self, from: Data(contentsOf: url))
    } catch {
      throw GemmaModelManifestError.invalid(error.localizedDescription)
    }
    try manifest.validate()
    guard manifest.variant == variant else {
      throw GemmaModelManifestError.invalid("Manifest variant does not match \(variant.rawValue).")
    }
    return manifest
  }

  static func loadAll(from bundle: Bundle = .main) throws -> [EmailGemmaModelVariant: GemmaModelManifest] {
    var manifests: [EmailGemmaModelVariant: GemmaModelManifest] = [:]
    for variant in EmailGemmaModelVariant.allCases {
      manifests[variant] = try load(variant: variant, from: bundle)
    }
    return manifests
  }

  func validate() throws {
    guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !runtimeFormatVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !familyDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !backgroundSessionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          downloadURL.scheme?.lowercased() == "https",
          termsURL.scheme?.lowercased() == "https",
          attributionURL.scheme?.lowercased() == "https",
          exactByteCount > 0,
          exactByteCount <= Int64.max / 2,
          minimumFreeStorageBytes >= exactByteCount * 2,
          runtimeContextTokens >= 2_048,
          runtimeContextTokens <= 32_768,
          promptSchemaVersion == EmailAnalysisResult.schemaVersion,
          sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
      throw GemmaModelManifestError.invalid("One or more manifest fields are invalid.")
    }
  }
}

enum GemmaModelManifestError: LocalizedError {
  case missing(EmailGemmaModelVariant)
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .missing(let variant):
      return "\(variant.resourceName).json is missing from the app bundle."
    case .invalid(let message):
      return "The Gemma model manifest is invalid: \(message)"
    }
  }
}
