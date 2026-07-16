import CryptoKit
import Foundation
import Security

struct ConnectedGmailAccount: Codable, Hashable, Sendable, Identifiable {
  var subject: String
  var emailAddress: String
  var connectedAt: Date

  var id: String { subject }
}

struct GmailStoredCredential: Codable, Hashable, Sendable {
  var subject: String
  var emailAddress: String
  var refreshToken: String
  var connectedAt: Date

  var account: ConnectedGmailAccount {
    ConnectedGmailAccount(
      subject: subject,
      emailAddress: emailAddress,
      connectedAt: connectedAt
    )
  }
}

private struct GmailCredentialBundle: Codable, Sendable {
  static let currentVersion = 1

  var version: Int
  var credentials: [GmailStoredCredential]
}

/// Stores Gmail refresh tokens in a device-only, Dimo-user-scoped Keychain item.
/// Access tokens are intentionally absent from this type and remain in memory.
actor GmailCredentialVault {
  private static let service = "app.dimo.ios.gmail"
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init() {
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
  }

  func accounts(dimoUserId: String) throws -> [ConnectedGmailAccount] {
    try loadBundle(dimoUserId: dimoUserId).credentials
      .map(\.account)
      .sorted { $0.emailAddress.localizedCaseInsensitiveCompare($1.emailAddress) == .orderedAscending }
  }

  func credential(subject: String, dimoUserId: String) throws -> GmailStoredCredential? {
    try loadBundle(dimoUserId: dimoUserId).credentials.first { $0.subject == subject }
  }

  func upsert(_ credential: GmailStoredCredential, dimoUserId: String) throws {
    var bundle = try loadBundle(dimoUserId: dimoUserId)
    bundle.credentials.removeAll { $0.subject == credential.subject }
    bundle.credentials.append(credential)
    try save(bundle, dimoUserId: dimoUserId)
  }

  func remove(subject: String, dimoUserId: String) throws {
    var bundle = try loadBundle(dimoUserId: dimoUserId)
    bundle.credentials.removeAll { $0.subject == subject }
    if bundle.credentials.isEmpty {
      try deleteBundle(dimoUserId: dimoUserId)
    } else {
      try save(bundle, dimoUserId: dimoUserId)
    }
  }

  func removeAll(dimoUserId: String) throws {
    try deleteBundle(dimoUserId: dimoUserId)
  }

  private func loadBundle(dimoUserId: String) throws -> GmailCredentialBundle {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: accountKey(for: dimoUserId),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return GmailCredentialBundle(version: GmailCredentialBundle.currentVersion, credentials: [])
    }
    guard status == errSecSuccess, let data = item as? Data else {
      throw GmailCredentialVaultError.keychain(status)
    }
    let bundle: GmailCredentialBundle
    do {
      bundle = try decoder.decode(GmailCredentialBundle.self, from: data)
    } catch {
      throw GmailCredentialVaultError.corruptBundle
    }
    guard bundle.version == GmailCredentialBundle.currentVersion else {
      throw GmailCredentialVaultError.unsupportedBundleVersion(bundle.version)
    }
    return bundle
  }

  private func save(_ bundle: GmailCredentialBundle, dimoUserId: String) throws {
    let data = try encoder.encode(bundle)
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: accountKey(for: dimoUserId),
    ]
    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw GmailCredentialVaultError.keychain(updateStatus)
    }
    var insert = baseQuery
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(insert as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw GmailCredentialVaultError.keychain(addStatus)
    }
  }

  private func deleteBundle(dimoUserId: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: accountKey(for: dimoUserId),
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GmailCredentialVaultError.keychain(status)
    }
  }

  private func accountKey(for dimoUserId: String) -> String {
    let digest = SHA256.hash(data: Data(dimoUserId.utf8))
    return "gmail.credentials." + digest.map { String(format: "%02x", $0) }.joined()
  }
}

enum GmailCredentialVaultError: LocalizedError {
  case keychain(OSStatus)
  case corruptBundle
  case unsupportedBundleVersion(Int)

  var errorDescription: String? {
    switch self {
    case .keychain(let status): return "Gmail credentials could not be accessed (\(status))."
    case .corruptBundle: return "The saved Gmail credentials are corrupt."
    case .unsupportedBundleVersion(let version):
      return "The saved Gmail credential format (\(version)) is unsupported."
    }
  }
}
