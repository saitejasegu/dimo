package app.dimo.android.sync

import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.WORKSPACE_ID
import app.dimo.android.data.model.entityKey
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.LendEntity
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.PaymentMethodEntity
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.PreferencesEntity
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI

/**
 * Wire contract for the typed Convex sync API, ported from
 * `ios-native/Dimo/Sync/ConvexAPI.swift` and `ConvexSyncTransport`.
 *
 * Two rules this file exists to enforce:
 *  1. every numeric field goes out as a JSON **double** — an integer encoding
 *     becomes Convex `$integer` and fails validation;
 *  2. `emailMessage` never appears, because Android is not an email writer and
 *     must not touch those rows.
 */
object ConvexAPI {
  fun pullPath(type: EntityType): String = when (type) {
    EntityType.CATEGORY -> "syncTyped:pullCategories"
    EntityType.PAYMENT_METHOD -> "syncTyped:pullPaymentMethods"
    EntityType.TRANSACTION -> "syncTyped:pullTransactions"
    EntityType.RECURRING -> "syncTyped:pullRecurring"
    EntityType.LEND -> "syncTyped:pullLends"
    EntityType.PREFERENCES -> "syncTyped:pullPreferences"
  }

  fun pushPath(type: EntityType): String = when (type) {
    EntityType.CATEGORY -> "syncTyped:pushCategories"
    EntityType.PAYMENT_METHOD -> "syncTyped:pushPaymentMethods"
    EntityType.TRANSACTION -> "syncTyped:pushTransactions"
    EntityType.RECURRING -> "syncTyped:pushRecurring"
    EntityType.LEND -> "syncTyped:pushLends"
    EntityType.PREFERENCES -> "syncTyped:pushPreferences"
  }

  fun pullArgs(workspaceId: String, afterRevision: Long, limit: Int): Map<String, Any?> = mapOf(
    "workspaceId" to workspaceId,
    "afterRevision" to afterRevision.toDouble(),
    "limit" to limit.toDouble(),
  )

  fun pushArgs(workspaceId: String, operations: List<SyncOperation>): Map<String, Any?> = mapOf(
    "workspaceId" to workspaceId,
    "operations" to operations.map { wireTypedOperation(it) },
  )

  fun profileArgs(workspaceId: String, name: String?, email: String?): Map<String, Any?> =
    buildMap {
      put("workspaceId", workspaceId)
      if (name != null) put("name", name)
      if (email != null) put("email", email)
    }

  fun clearArgs(workspaceId: String, entityTypes: List<EntityType>, limit: Int): Map<String, Any?> =
    mapOf(
      "workspaceId" to workspaceId,
      "entityTypes" to entityTypes.map { it.wire },
      "limit" to limit.toDouble(),
    )

  fun revisionArgs(workspaceId: String): Map<String, Any?> = mapOf("workspaceId" to workspaceId)

  /** One push operation, flattened the way the typed `push*` validators expect. */
  fun wireTypedOperation(op: SyncOperation): Map<String, Any?> {
    val dict = mutableMapOf<String, Any?>(
      "operationId" to op.operationId,
      "workspaceId" to op.workspaceId,
      "entityId" to op.entityId,
      "version" to mapOf(
        "timestamp" to op.version.timestamp.toDouble(),
        "counter" to op.version.counter.toDouble(),
        "deviceId" to op.version.deviceId,
      ),
      "deleted" to op.deleted,
    )
    when (val payload = op.payload) {
      is EntityPayload.Category -> {
        val e = payload.value
        dict["name"] = e.name
        dict["emoji"] = e.emoji
        dict["monthlyBudgetMinor"] = e.monthlyBudgetMinor?.toDouble()
        dict["tint"] = e.tint.wire
        dict["sortOrder"] = e.sortOrder.toDouble()
        dict["system"] = e.system
      }

      is EntityPayload.PaymentMethod -> {
        val e = payload.value
        dict["name"] = e.name
        dict["type"] = e.type.wire
        dict["detail"] = e.detail
        dict["archived"] = e.archived
      }

      is EntityPayload.Transaction -> {
        val e = payload.value
        dict["name"] = e.name
        dict["amountMinor"] = e.amountMinor.toDouble()
        dict["occurredAt"] = e.occurredAt.toDouble()
        dict["categoryId"] = e.categoryId
        dict["paymentMethodId"] = e.paymentMethodId
        // Optional currency keys are omitted rather than sent as null, matching
        // the iOS encoder — Convex validators reject unexpected nulls.
        if (!e.currency.isNullOrEmpty()) dict["currency"] = e.currency
        if (!e.sourceCurrency.isNullOrEmpty()) {
          dict["sourceCurrency"] = e.sourceCurrency
          dict["sourceAmountMinor"] = (e.sourceAmountMinor ?: 0L).toDouble()
          e.exchangeRate?.let { dict["exchangeRate"] = it }
        }
      }

      is EntityPayload.Recurring -> {
        val e = payload.value
        dict["name"] = e.name
        dict["amountMinor"] = e.amountMinor.toDouble()
        dict["categoryId"] = e.categoryId
        dict["paymentMethodId"] = e.paymentMethodId
        dict["frequency"] = e.frequency.wire
        dict["anchorDate"] = e.anchorDate
        dict["paused"] = e.paused
        if (!e.currency.isNullOrEmpty()) dict["currency"] = e.currency
      }

      is EntityPayload.Lend -> {
        val e = payload.value
        dict["contactName"] = e.contactName
        dict["contactId"] = e.contactId
        dict["amountMinor"] = e.amountMinor.toDouble()
        dict["occurredAt"] = e.occurredAt.toDouble()
        dict["comment"] = e.comment
        dict["kind"] = (e.kind ?: LendKind.LENT).wire
      }

      is EntityPayload.Preferences -> {
        val e = payload.value
        dict["profileName"] = e.profileName
        dict["profileEmail"] = e.profileEmail
        dict["currency"] = e.currency.wire
        dict["weekStart"] = e.weekStart.wire
        dict["theme"] = e.theme.wire
        dict["navGlassOpacity"] = e.navGlassOpacity.toDouble()
        dict["defaultView"] = e.defaultView.wire
        dict["defaultStatsRange"] = e.defaultStatsRange.wire
        dict["notifications"] = mapOf(
          "bills" to e.notifications.bills,
          "budget" to e.notifications.budget,
          "weekly" to e.notifications.weekly,
          "large" to e.notifications.large,
        )
        dict["defaultPaymentMethodId"] = e.defaultPaymentMethodId
      }
    }
    return dict
  }

  /** Rebuilds a [StoredEntity] from one pulled row. */
  fun storedEntityFrom(type: EntityType, row: Map<String, Any?>): StoredEntity {
    val entityId = row.string("entityId")
    val workspaceId = row["workspaceId"] as? String ?: WORKSPACE_ID
    val versionMap = row["version"] as? Map<*, *> ?: emptyMap<String, Any?>()
    val version = LogicalVersion(
      timestamp = versionMap["timestamp"].asLong(),
      counter = versionMap["counter"].asLong(),
      deviceId = versionMap["deviceId"] as? String ?: "",
    )
    val payload: EntityPayload = when (type) {
      EntityType.CATEGORY -> EntityPayload.Category(
        CategoryEntity(
          id = entityId,
          name = row.string("name"),
          emoji = row["emoji"] as? String ?: DEFAULT_CATEGORY_EMOJI,
          monthlyBudgetMinor = row["monthlyBudgetMinor"].asLongOrNull(),
          tint = CategoryTint.fromWire(row["tint"] as? String),
          sortOrder = row["sortOrder"].asLong().toInt(),
          system = row["system"] as? Boolean ?: false,
        ),
      )

      EntityType.PAYMENT_METHOD -> EntityPayload.PaymentMethod(
        PaymentMethodEntity(
          id = entityId,
          name = row.string("name"),
          type = PaymentMethodType.fromWire(row["type"] as? String),
          detail = row["detail"] as? String ?: "",
          archived = row["archived"] as? Boolean ?: false,
        ),
      )

      EntityType.TRANSACTION -> EntityPayload.Transaction(
        TransactionEntity(
          id = entityId,
          name = row.string("name"),
          amountMinor = row["amountMinor"].asLong(),
          occurredAt = row["occurredAt"].asLong(),
          categoryId = row.string("categoryId"),
          paymentMethodId = row["paymentMethodId"] as? String,
          currency = row["currency"] as? String,
          sourceCurrency = row["sourceCurrency"] as? String,
          sourceAmountMinor = row["sourceAmountMinor"].asLongOrNull(),
          exchangeRate = row["exchangeRate"].asDoubleOrNull(),
        ),
      )

      EntityType.RECURRING -> EntityPayload.Recurring(
        RecurringEntity(
          id = entityId,
          name = row.string("name"),
          amountMinor = row["amountMinor"].asLong(),
          categoryId = row.string("categoryId"),
          paymentMethodId = row["paymentMethodId"] as? String,
          frequency = RecurringFrequency.fromWire(row["frequency"] as? String),
          anchorDate = row["anchorDate"] as? String ?: "",
          paused = row["paused"] as? Boolean ?: false,
          currency = row["currency"] as? String,
        ),
      )

      EntityType.LEND -> {
        val contactName = row.string("contactName")
        EntityPayload.Lend(
          LendEntity(
            id = entityId,
            contactName = contactName,
            // Legacy rows may omit contactId; fall back to the name.
            contactId = (row["contactId"] as? String)?.takeIf { it.isNotBlank() } ?: contactName,
            amountMinor = row["amountMinor"].asLong(),
            occurredAt = row["occurredAt"].asLong(),
            comment = row["comment"] as? String ?: "",
            kind = LendKind.fromWire(row["kind"] as? String),
          ),
        )
      }

      EntityType.PREFERENCES -> {
        val notifications = row["notifications"] as? Map<*, *> ?: emptyMap<String, Any?>()
        EntityPayload.Preferences(
          PreferencesEntity(
            id = entityId,
            profileName = row["profileName"] as? String ?: "",
            profileEmail = row["profileEmail"] as? String ?: "",
            currency = Currency.fromWire(row["currency"] as? String),
            weekStart = WeekStart.fromWire(row["weekStart"] as? String),
            theme = ThemePreference.fromWire(row["theme"] as? String),
            navGlassOpacity = row["navGlassOpacity"].asLongOrNull()?.toInt() ?: 40,
            defaultView = ViewKey.fromWire(row["defaultView"] as? String),
            defaultStatsRange = StatsRange.fromWire(row["defaultStatsRange"] as? String),
            notifications = NotificationSettings(
              bills = notifications["bills"] as? Boolean ?: true,
              budget = notifications["budget"] as? Boolean ?: true,
              weekly = notifications["weekly"] as? Boolean ?: false,
              large = notifications["large"] as? Boolean ?: true,
            ),
            defaultPaymentMethodId = row["defaultPaymentMethodId"] as? String ?: "",
          ),
        )
      }
    }
    return StoredEntity(
      key = entityKey(type, entityId),
      workspaceId = workspaceId,
      entityType = type,
      entityId = entityId,
      version = version,
      payload = payload,
      deleted = row["deleted"] as? Boolean ?: false,
      serverRevision = row["serverRevision"].asLong(),
    )
  }

  private fun Map<String, Any?>.string(key: String): String = this[key] as? String ?: ""

  private fun Any?.asLong(): Long = when (this) {
    is Number -> this.toLong()
    is String -> this.toLongOrNull() ?: 0L
    else -> 0L
  }

  private fun Any?.asLongOrNull(): Long? = when (this) {
    is Number -> this.toLong()
    is String -> this.toLongOrNull()
    else -> null
  }

  private fun Any?.asDoubleOrNull(): Double? = when (this) {
    is Number -> this.toDouble()
    is String -> this.toDoubleOrNull()
    else -> null
  }
}

/** One page of a typed pull. */
data class PullResult(
  val entities: List<StoredEntity>,
  val latestRevision: Long,
  val hasMore: Boolean,
)

data class PushResult(val acknowledgedOperationIds: List<String>)

data class ClearResult(val hasMore: Boolean)
