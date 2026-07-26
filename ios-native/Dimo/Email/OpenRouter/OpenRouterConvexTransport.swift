import ConvexMobile
import Foundation

protocol OpenRouterConvexTransporting: AnyObject, Sendable {
  func listFreeModels() async throws -> [OpenRouterModel]
  func analyzeEmail(
    modelId: String,
    privacyMode: OpenRouterPrivacyMode,
    prompt: String,
    outputTokenLimit: Int
  ) async throws -> OpenRouterConvexAnalyzeResult
}

struct OpenRouterConvexAnalyzeResult: Decodable, Sendable {
  var content: String
  var modelId: String
  var requestId: String?
}

enum OpenRouterConvexTransportError: LocalizedError, Sendable {
  case notReady
  case remote(String)

  var errorDescription: String? {
    switch self {
    case .notReady:
      return "Free OpenRouter analysis needs an online Dimo sync session."
    case .remote(let message):
      return message
    }
  }

  var openRouterClientError: OpenRouterClientError {
    switch self {
    case .notReady:
      return .transport("convex-not-ready")
    case .remote(let message):
      let lowered = message.lowercased()
      if lowered.contains("rate limit") {
        let seconds = Self.parseRetrySeconds(from: message)
        return .rateLimited(retryAfter: seconds)
      }
      if lowered.contains("insufficient") || lowered.contains("credits") {
        return .insufficientCredits
      }
      if lowered.contains("unavailable") || lowered.contains("no zero-data-retention") {
        return .modelUnavailable
      }
      if lowered.contains("timed out") || lowered.contains("timeout") {
        return .timedOut
      }
      if lowered.contains("could not be reached") || lowered.contains("network") {
        return .transport(message)
      }
      return .invalidRequest(message)
    }
  }

  private static func parseRetrySeconds(from message: String) -> TimeInterval? {
    let pattern = /Retry in (\d+) seconds/
    guard let match = message.firstMatch(of: pattern),
          let value = TimeInterval(match.1) else {
      return nil
    }
    return value
  }
}

/// Authenticated Convex proxy for the shared free-model OpenRouter key.
final class OpenRouterConvexTransport: OpenRouterConvexTransporting, @unchecked Sendable {
  private let client: ConvexClientWithAuth<WorkOSSession>

  init(client: ConvexClientWithAuth<WorkOSSession>) {
    self.client = client
  }

  func listFreeModels() async throws -> [OpenRouterModel] {
    do {
      let rows: [OpenRouterFreeModelWire] = try await client.action(
        "openRouter:listFreeModels",
        with: [:]
      )
      return rows.map(\.asModel)
    } catch {
      throw OpenRouterConvexTransportError.remote(error.localizedDescription)
    }
  }

  func analyzeEmail(
    modelId: String,
    privacyMode: OpenRouterPrivacyMode,
    prompt: String,
    outputTokenLimit: Int
  ) async throws -> OpenRouterConvexAnalyzeResult {
    do {
      return try await client.action(
        "openRouter:analyzeEmail",
        with: [
          "modelId": modelId,
          "privacyMode": privacyMode.rawValue,
          "prompt": prompt,
          "outputTokenLimit": Double(outputTokenLimit),
        ]
      )
    } catch {
      throw OpenRouterConvexTransportError.remote(error.localizedDescription)
    }
  }
}

private struct OpenRouterFreeModelWire: Decodable, Sendable {
  var id: String
  var name: String
  var contextLength: Int
  var pricing: OpenRouterModel.Pricing
  var supportedParameters: [String]
  var hasZDREndpoint: Bool
  var zdrSupportedParameters: [String]

  var asModel: OpenRouterModel {
    var model = OpenRouterModel(
      id: id,
      name: name,
      contextLength: contextLength,
      pricing: pricing,
      supportedParameters: supportedParameters
    )
    model.hasZDREndpoint = hasZDREndpoint
    model.zdrSupportedParameters = zdrSupportedParameters
    return model
  }
}
