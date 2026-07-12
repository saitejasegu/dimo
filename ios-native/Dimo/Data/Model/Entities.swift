import Foundation

enum EntityType: String, Codable, CaseIterable, Sendable {
  case category
  case paymentMethod
  case transaction
  case recurring
  case preferences
}

struct LogicalVersion: Codable, Hashable, Sendable, Comparable {
  var timestamp: Int
  var counter: Int
  var deviceId: String

  static func < (lhs: LogicalVersion, rhs: LogicalVersion) -> Bool {
    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
    if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
    return lhs.deviceId < rhs.deviceId
  }
}

func compareVersions(_ a: LogicalVersion, _ b: LogicalVersion) -> Int {
  if a.timestamp != b.timestamp { return a.timestamp - b.timestamp }
  if a.counter != b.counter { return a.counter - b.counter }
  return a.deviceId.compare(b.deviceId).rawValue
}

let workspaceID = "global"
let defaultCategoryEmoji = "🙂"
let bootstrapVersion = 2

func entityKey(type: EntityType, id: String) -> String {
  "\(workspaceID):\(type.rawValue):\(id)"
}

enum CategoryTint: String, Codable, Sendable {
  case green
  case neutral
}

enum PaymentMethodType: String, Codable, CaseIterable, Sendable {
  case UPI, Card, Wallet, Cash, Bank
}

enum RecurringFrequency: String, Codable, Sendable {
  case monthly
  case yearly
}

enum Currency: String, Codable, CaseIterable, Sendable {
  case INR, USD, EUR
}

enum WeekStart: String, Codable, CaseIterable, Sendable {
  case Mon, Sun
}

enum ThemePreference: String, Codable, CaseIterable, Sendable {
  case system, light, dark
}

enum StatsRange: String, Codable, CaseIterable, Sendable {
  case oneWeek = "1W"
  case month = "M"
  case threeMonths = "3M"
  case sixMonths = "6M"
  case oneYear = "1Y"
  case twoYears = "2Y"
}

enum ViewKey: String, Codable, CaseIterable, Sendable {
  case home, tx, stats, recurring, budgets, sms, settings, account
}

struct NotificationSettings: Codable, Hashable, Sendable {
  var bills: Bool
  var budget: Bool
  var weekly: Bool
  var large: Bool
}

struct CategoryEntity: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var emoji: String
  var monthlyBudgetMinor: Int?
  var tint: CategoryTint
  var sortOrder: Int
  var system: Bool
}

struct PaymentMethodEntity: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var type: PaymentMethodType
  var detail: String
  var archived: Bool
}

struct TransactionEntity: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var amountMinor: Int
  var occurredAt: Int
  var categoryId: String
  var paymentMethodId: String?
}

struct RecurringEntity: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var amountMinor: Int
  var categoryId: String
  var paymentMethodId: String?
  var frequency: RecurringFrequency
  var anchorDate: String
  var paused: Bool
}

struct PreferencesEntity: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var profileName: String
  var profileEmail: String
  var currency: Currency
  var weekStart: WeekStart
  var theme: ThemePreference
  var navGlassOpacity: Int
  var defaultView: ViewKey
  var defaultStatsRange: StatsRange
  var notifications: NotificationSettings
  var defaultPaymentMethodId: String
}

enum EntityPayload: Codable, Hashable, Sendable {
  case category(CategoryEntity)
  case paymentMethod(PaymentMethodEntity)
  case transaction(TransactionEntity)
  case recurring(RecurringEntity)
  case preferences(PreferencesEntity)

  var id: String {
    switch self {
    case .category(let e): return e.id
    case .paymentMethod(let e): return e.id
    case .transaction(let e): return e.id
    case .recurring(let e): return e.id
    case .preferences(let e): return e.id
    }
  }

  var entityType: EntityType {
    switch self {
    case .category: return .category
    case .paymentMethod: return .paymentMethod
    case .transaction: return .transaction
    case .recurring: return .recurring
    case .preferences: return .preferences
    }
  }
}

struct StoredEntity: Hashable, Sendable, Identifiable {
  var key: String
  var workspaceId: String
  var entityType: EntityType
  var entityId: String
  var version: LogicalVersion
  var payload: EntityPayload
  var deleted: Bool
  var serverRevision: Int

  var id: String { key }
}

enum OutboxStatus: String, Codable, Sendable {
  case pending
  case blocked
}

struct SyncOperation: Hashable, Sendable, Identifiable {
  var operationId: String
  var key: String
  var workspaceId: String
  var entityType: EntityType
  var entityId: String
  var version: LogicalVersion
  var payload: EntityPayload
  var deleted: Bool
  var status: OutboxStatus
  var attempts: Int
  var lastError: String?
  var createdAt: Int

  var id: String { operationId }
}

struct SyncMeta: Hashable, Sendable {
  var workspaceId: String
  var lastPulledRevision: Int
  var lastSyncedAt: Int?
  var error: String?
  var syncing: Bool
}

struct DeviceMeta: Hashable, Sendable {
  var id: String
  var deviceId: String
  var clockTimestamp: Int
  var clockCounter: Int
  var bootstrapVersion: Int
  var lastPaymentMethodId: String?
}

// MARK: - UI models (ports of app/lib/types.ts)

struct PaymentMethodOption: Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var type: PaymentMethodType
  var detail: String
  var isDefault: Bool
  var archived: Bool

  var label: String {
    if type == .Cash { return name }
    return [type.rawValue, name, detail].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

struct Transaction: Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var category: String
  var time: String
  var day: String
  var amount: Double
  var paymentMethod: String?
  var green: Bool?
  var emoji: String?
  var amountMinor: Int?
  var occurredAt: Int?
  var categoryId: String?
  var paymentMethodId: String?
}

struct Recurring: Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var category: String
  var due: String
  var amount: Double
  var paused: Bool
  var urgent: Bool?
  var green: Bool?
  var emoji: String?
  var amountMinor: Int?
  var categoryId: String?
  var paymentMethodId: String?
  var anchorDate: String?
  var frequency: RecurringFrequency?
}

typealias CategoryLimits = [String: Double?]
