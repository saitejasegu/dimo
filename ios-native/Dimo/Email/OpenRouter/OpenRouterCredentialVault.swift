import CryptoKit
import Foundation
import Security

struct OpenRouterCredential: Codable, Hashable, Sendable {
  static let currentVersion = 1

  var version: Int
  var apiKey: String

  init(apiKey: String) {
    version = Self.currentVersion
    self.apiKey = apiKey
  }
}

actor OpenRouterCredentialVault {
  private static let service = "app.dimo.ios.openrouter"

  func credential(dimoUserId: String) throws -> OpenRouterCredential? {
    let query = baseQuery(dimoUserId: dimoUserId).merging([
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]) { _, new in new }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw OpenRouterCredentialVaultError.keychain(status)
    }
    guard let value = try? JSONDecoder().decode(OpenRouterCredential.self, from: data),
          value.version == OpenRouterCredential.currentVersion else {
      throw OpenRouterCredentialVaultError.corruptCredential
    }
    return value
  }

  func save(apiKey: String, dimoUserId: String) throws {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw OpenRouterCredentialVaultError.invalidKey }
    let data = try JSONEncoder().encode(OpenRouterCredential(apiKey: trimmed))
    let query = baseQuery(dimoUserId: dimoUserId)
    let update = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else {
      throw OpenRouterCredentialVaultError.keychain(update)
    }
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(insert as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw OpenRouterCredentialVaultError.keychain(status)
    }
  }

  func remove(dimoUserId: String) throws {
    let status = SecItemDelete(baseQuery(dimoUserId: dimoUserId) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw OpenRouterCredentialVaultError.keychain(status)
    }
  }

  private func baseQuery(dimoUserId: String) -> [String: Any] {
    let digest = SHA256.hash(data: Data(dimoUserId.utf8))
    let account = "openrouter.credentials." + digest.map { String(format: "%02x", $0) }.joined()
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
    ]
  }
}

enum OpenRouterCredentialVaultError: LocalizedError {
  case invalidKey
  case corruptCredential
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidKey: return "Enter an OpenRouter API key."
    case .corruptCredential: return "The saved OpenRouter credential is corrupt."
    case .keychain(let status): return "OpenRouter credentials could not be accessed (\(status))."
    }
  }
}
