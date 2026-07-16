import Foundation

/// Wire DTOs use Double for all numeric fields — ConvexMobile encodes Swift Int as $integer,
/// which fails Convex `v.number()` validators.
struct WireVersion: Codable, Sendable {
  var timestamp: Double
  var counter: Double
  var deviceId: String

  init(_ version: LogicalVersion) {
    timestamp = Double(version.timestamp)
    counter = Double(version.counter)
    deviceId = version.deviceId
  }

  func toDomain() -> LogicalVersion {
    LogicalVersion(timestamp: Int(timestamp), counter: Int(counter), deviceId: deviceId)
  }
}

struct WireCategory: Codable, Sendable {
  var id: String
  var name: String
  var emoji: String?
  var monthlyBudgetMinor: Double?
  var tint: String
  var sortOrder: Double
  var system: Bool
}

struct WirePaymentMethod: Codable, Sendable {
  var id: String
  var name: String
  var type: String
  var detail: String
  var archived: Bool
}

struct WireTransaction: Codable, Sendable {
  var id: String
  var name: String
  var amountMinor: Double
  var occurredAt: Double
  var categoryId: String
  var paymentMethodId: String?
}

struct WireRecurring: Codable, Sendable {
  var id: String
  var name: String
  var amountMinor: Double
  var categoryId: String
  var paymentMethodId: String?
  var frequency: String
  var anchorDate: String
  var paused: Bool
}

struct WireLend: Codable, Sendable {
  var id: String
  var contactName: String
  /// Optional so older server rows written before contact linking still decode.
  var contactId: String?
  var amountMinor: Double
  var occurredAt: Double
  var comment: String
  var kind: String?
}

struct WireEmailMessage: Codable, Sendable {
  var id: String
  var accountId: String
  var accountEmail: String
  var gmailMessageId: String
  var threadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Double
  var normalizedBodyText: String?
  var analyzerType: String?
  var modelVersion: String?
  var promptVersion: Double?
  var classification: String?
  var merchant: String?
  var amount: String?
  var currency: String?
  var occurredAt: Double?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
  var state: String
  var linkedTransactionId: String?
  var analyzedAt: Double?
  var reviewedAt: Double?
  var createdAt: Double
  var updatedAt: Double
}

struct WireNotifications: Codable, Sendable {
  var bills: Bool
  var budget: Bool
  var weekly: Bool
  var large: Bool
}

struct WirePreferences: Codable, Sendable {
  var id: String
  var profileName: String
  var profileEmail: String
  var currency: String
  var weekStart: String
  var theme: String?
  var navGlassOpacity: Double?
  var defaultView: String
  var defaultStatsRange: String?
  var notifications: WireNotifications
  var defaultPaymentMethodId: String
}

enum WirePayload {
  static func encode(_ payload: EntityPayload) -> [String: Any] {
    switch payload {
    case .category(let e):
      return [
        "id": e.id,
        "name": e.name,
        "emoji": e.emoji,
        "monthlyBudgetMinor": e.monthlyBudgetMinor.map { Double($0) as Any } ?? NSNull(),
        "tint": e.tint.rawValue,
        "sortOrder": Double(e.sortOrder),
        "system": e.system,
      ]
    case .paymentMethod(let e):
      return [
        "id": e.id,
        "name": e.name,
        "type": e.type.rawValue,
        "detail": e.detail,
        "archived": e.archived,
      ]
    case .transaction(let e):
      return [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "occurredAt": Double(e.occurredAt),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId as Any? ?? NSNull(),
      ]
    case .recurring(let e):
      return [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId as Any? ?? NSNull(),
        "frequency": e.frequency.rawValue,
        "anchorDate": e.anchorDate,
        "paused": e.paused,
      ]
    case .lend(let e):
      return [
        "id": e.id,
        "contactName": e.contactName,
        "contactId": e.contactId,
        "amountMinor": Double(e.amountMinor),
        "occurredAt": Double(e.occurredAt),
        "comment": e.comment,
        "kind": (e.kind ?? .lent).rawValue,
      ]
    case .emailMessage(let e):
      return [
        "id": e.id,
        "accountId": e.accountId,
        "accountEmail": e.accountEmail,
        "gmailMessageId": e.gmailMessageId,
        "threadId": e.threadId,
        "rfcMessageId": e.rfcMessageId as Any? ?? NSNull(),
        "senderName": e.senderName as Any? ?? NSNull(),
        "senderAddress": e.senderAddress,
        "subject": e.subject,
        "snippet": e.snippet,
        "internalDate": Double(e.internalDate),
        "normalizedBodyText": e.normalizedBodyText as Any? ?? NSNull(),
        "analyzerType": e.analyzerType as Any? ?? NSNull(),
        "modelVersion": e.modelVersion as Any? ?? NSNull(),
        "promptVersion": e.promptVersion.map { Double($0) as Any } ?? NSNull(),
        "classification": e.classification as Any? ?? NSNull(),
        "merchant": e.merchant as Any? ?? NSNull(),
        "amount": e.amount as Any? ?? NSNull(),
        "currency": e.currency as Any? ?? NSNull(),
        "occurredAt": e.occurredAt.map { Double($0) as Any } ?? NSNull(),
        "categoryId": e.categoryId as Any? ?? NSNull(),
        "paymentMethodId": e.paymentMethodId as Any? ?? NSNull(),
        "paymentLastFour": e.paymentLastFour as Any? ?? NSNull(),
        "reference": e.reference as Any? ?? NSNull(),
        "state": e.state,
        "linkedTransactionId": e.linkedTransactionId as Any? ?? NSNull(),
        "analyzedAt": e.analyzedAt.map { Double($0) as Any } ?? NSNull(),
        "reviewedAt": e.reviewedAt.map { Double($0) as Any } ?? NSNull(),
        "createdAt": Double(e.createdAt),
        "updatedAt": Double(e.updatedAt),
      ]
    case .preferences(let e):
      return [
        "id": e.id,
        "profileName": e.profileName,
        "profileEmail": e.profileEmail,
        "currency": e.currency.rawValue,
        "weekStart": e.weekStart.rawValue,
        "theme": e.theme.rawValue,
        "navGlassOpacity": Double(e.navGlassOpacity),
        "defaultView": e.defaultView.rawValue,
        "defaultStatsRange": e.defaultStatsRange.rawValue,
        "notifications": [
          "bills": e.notifications.bills,
          "budget": e.notifications.budget,
          "weekly": e.notifications.weekly,
          "large": e.notifications.large,
        ],
        "defaultPaymentMethodId": e.defaultPaymentMethodId,
      ]
    }
  }

  static func decode(entityType: EntityType, dict: [String: Any]) throws -> EntityPayload {
    let data = try JSONSerialization.data(withJSONObject: dict)
    switch entityType {
    case .category:
      let wire = try JSONDecoder().decode(WireCategory.self, from: data)
      return .category(CategoryEntity(
        id: wire.id,
        name: wire.name,
        emoji: wire.emoji?.isEmpty == false ? wire.emoji! : defaultCategoryEmoji,
        monthlyBudgetMinor: wire.monthlyBudgetMinor.map { Int($0) },
        tint: CategoryTint(rawValue: wire.tint) ?? .neutral,
        sortOrder: Int(wire.sortOrder),
        system: wire.system
      ))
    case .paymentMethod:
      let wire = try JSONDecoder().decode(WirePaymentMethod.self, from: data)
      return .paymentMethod(PaymentMethodEntity(
        id: wire.id,
        name: wire.name,
        type: PaymentMethodType(rawValue: wire.type) ?? .Cash,
        detail: wire.detail,
        archived: wire.archived
      ))
    case .transaction:
      let wire = try JSONDecoder().decode(WireTransaction.self, from: data)
      return .transaction(TransactionEntity(
        id: wire.id,
        name: wire.name,
        amountMinor: Int(wire.amountMinor),
        occurredAt: Int(wire.occurredAt),
        categoryId: wire.categoryId,
        paymentMethodId: wire.paymentMethodId
      ))
    case .recurring:
      let wire = try JSONDecoder().decode(WireRecurring.self, from: data)
      return .recurring(RecurringEntity(
        id: wire.id,
        name: wire.name,
        amountMinor: Int(wire.amountMinor),
        categoryId: wire.categoryId,
        paymentMethodId: wire.paymentMethodId,
        frequency: RecurringFrequency(rawValue: wire.frequency) ?? .monthly,
        anchorDate: wire.anchorDate,
        paused: wire.paused
      ))
    case .lend:
      let wire = try JSONDecoder().decode(WireLend.self, from: data)
      let contactId = wire.contactId?.trimmingCharacters(in: .whitespacesAndNewlines)
      return .lend(LendEntity(
        id: wire.id,
        contactName: wire.contactName,
        // Legacy rows keyed by name only; fall back so grouping still works.
        contactId: (contactId?.isEmpty == false) ? contactId! : wire.contactName,
        amountMinor: Int(wire.amountMinor),
        occurredAt: Int(wire.occurredAt),
        comment: wire.comment,
        kind: wire.kind.flatMap(LendKind.init) ?? .lent
      ))
    case .emailMessage:
      let wire = try JSONDecoder().decode(WireEmailMessage.self, from: data)
      return .emailMessage(EmailMessageEntity(
        id: wire.id,
        accountId: wire.accountId,
        accountEmail: wire.accountEmail,
        gmailMessageId: wire.gmailMessageId,
        threadId: wire.threadId,
        rfcMessageId: wire.rfcMessageId,
        senderName: wire.senderName,
        senderAddress: wire.senderAddress,
        subject: wire.subject,
        snippet: wire.snippet,
        internalDate: Int(wire.internalDate),
        normalizedBodyText: wire.normalizedBodyText,
        analyzerType: wire.analyzerType,
        modelVersion: wire.modelVersion,
        promptVersion: wire.promptVersion.map { Int($0) },
        classification: wire.classification,
        merchant: wire.merchant,
        amount: wire.amount,
        currency: wire.currency,
        occurredAt: wire.occurredAt.map { Int($0) },
        categoryId: wire.categoryId,
        paymentMethodId: wire.paymentMethodId,
        paymentLastFour: wire.paymentLastFour,
        reference: wire.reference,
        state: wire.state,
        linkedTransactionId: wire.linkedTransactionId,
        analyzedAt: wire.analyzedAt.map { Int($0) },
        reviewedAt: wire.reviewedAt.map { Int($0) },
        createdAt: Int(wire.createdAt),
        updatedAt: Int(wire.updatedAt)
      ))
    case .preferences:
      let wire = try JSONDecoder().decode(WirePreferences.self, from: data)
      return .preferences(PreferencesEntity(
        id: "preferences",
        profileName: wire.profileName,
        profileEmail: wire.profileEmail,
        currency: Currency(rawValue: wire.currency) ?? .INR,
        weekStart: WeekStart(rawValue: wire.weekStart) ?? .Mon,
        theme: ThemePreference(rawValue: wire.theme ?? "light") ?? .light,
        navGlassOpacity: Int(wire.navGlassOpacity ?? 40),
        defaultView: ViewKey(rawValue: wire.defaultView) ?? .home,
        defaultStatsRange: StatsRange(rawValue: wire.defaultStatsRange ?? "1Y") ?? .oneYear,
        notifications: NotificationSettings(
          bills: wire.notifications.bills,
          budget: wire.notifications.budget,
          weekly: wire.notifications.weekly,
          large: wire.notifications.large
        ),
        defaultPaymentMethodId: wire.defaultPaymentMethodId
      ))
    }
  }
}

struct WirePushOperation: Encodable {
  var operationId: String
  var workspaceId: String
  var entityType: String
  var entityId: String
  var version: WireVersion
  var payload: [String: AnyCodableValue]
  var deleted: Bool

  init(_ op: SyncOperation) {
    operationId = op.operationId
    workspaceId = op.workspaceId
    entityType = op.entityType.rawValue
    entityId = op.entityId
    version = WireVersion(op.version)
    let raw = WirePayload.encode(op.payload)
    payload = raw.mapValues { AnyCodableValue($0) }
    deleted = op.deleted
  }
}

enum AnyCodableValue: Encodable {
  case string(String)
  case double(Double)
  case bool(Bool)
  case null
  case object([String: AnyCodableValue])

  init(_ value: Any) {
    switch value {
    case let s as String: self = .string(s)
    case let d as Double: self = .double(d)
    case let i as Int: self = .double(Double(i))
    case let b as Bool: self = .bool(b)
    case let dict as [String: Any]:
      self = .object(dict.mapValues { AnyCodableValue($0) })
    case is NSNull: self = .null
    default: self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let v): try container.encode(v)
    case .double(let v): try container.encode(v)
    case .bool(let v): try container.encode(v)
    case .null: try container.encodeNil()
    case .object(let v): try container.encode(v)
    }
  }
}

struct PullResultDTO: Decodable {
  var entities: [RemoteEntityDTO]
  var latestRevision: Double
  var hasMore: Bool
}

struct RemoteEntityDTO: Decodable {
  var workspaceId: String
  var entityType: String
  var entityId: String
  var version: WireVersion
  var payload: [String: AnyDecodableValue]
  var deleted: Bool
  var serverRevision: Double

  func toStoredEntity() throws -> StoredEntity {
    let type = EntityType(rawValue: entityType) ?? .transaction
    let dict = payload.mapValues(\.rawValue)
    let payload = try WirePayload.decode(entityType: type, dict: dict)
    return StoredEntity(
      key: entityKey(type: type, id: entityId),
      workspaceId: workspaceId,
      entityType: type,
      entityId: entityId,
      version: version.toDomain(),
      payload: payload,
      deleted: deleted,
      serverRevision: Int(serverRevision)
    )
  }
}

struct PushResultDTO: Decodable {
  struct Ack: Decodable {
    var operationId: String
    var applied: Bool
    var revision: Double
  }
  var acknowledgements: [Ack]
  var latestRevision: Double
}

struct ClearResultDTO: Decodable {
  var deleted: Double
  var hasMore: Bool
}

enum AnyDecodableValue: Decodable {
  case string(String)
  case double(Double)
  case bool(Bool)
  case null
  case object([String: AnyDecodableValue])
  case array([AnyDecodableValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let b = try? container.decode(Bool.self) {
      self = .bool(b)
    } else if let d = try? container.decode(Double.self) {
      self = .double(d)
    } else if let s = try? container.decode(String.self) {
      self = .string(s)
    } else if let o = try? container.decode([String: AnyDecodableValue].self) {
      self = .object(o)
    } else if let a = try? container.decode([AnyDecodableValue].self) {
      self = .array(a)
    } else {
      self = .null
    }
  }

  var rawValue: Any {
    switch self {
    case .string(let v): return v
    case .double(let v): return v
    case .bool(let v): return v
    case .null: return NSNull()
    case .object(let v): return v.mapValues(\.rawValue)
    case .array(let v): return v.map(\.rawValue)
    }
  }
}

func isPermanentSyncError(_ message: String) -> Bool {
  let pattern =
    #"ArgumentValidationError|Payload does not match|Entity ID mismatch|Workspace mismatch|Unsupported workspace|Invalid logical version|Invalid minor-unit amount|Invalid recurring anchor date|A push may contain at most 50"#
  return message.range(of: pattern, options: .regularExpression) != nil
}
