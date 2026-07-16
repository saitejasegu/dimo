import Foundation
import Security

enum KeychainStore {
  private static let service = "app.dimo.ios"
  private static let lock = NSLock()

  static func set(_ value: String, account: String) throws {
    try lock.withLock {
      try setUnlocked(value, account: account)
    }
  }

  private static func setUnlocked(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.unhandled(updateStatus)
    }

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(attributes as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.unhandled(addStatus)
    }
  }

  static func get(account: String) -> String? {
    lock.withLock {
      getUnlocked(account: account)
    }
  }

  private static func getUnlocked(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(account: String) {
    lock.withLock {
      deleteUnlocked(account: account)
    }
  }

  private static func deleteUnlocked(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }

  enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
      switch self {
      case .unhandled(let status):
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Security error"
        return "Keychain access failed: \(detail) (OSStatus \(status))."
      }
    }
  }
}
