package app.dimo.android.data

import app.dimo.android.data.model.CASH_PAYMENT_METHOD_ID
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.NAV_GLASS_OPACITY_MIN
import app.dimo.android.data.model.NotificationsPrefs
import app.dimo.android.data.model.PREFERENCES_ID
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.roundToInt

object PayloadCodec {
  val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

  fun encodeVersion(version: LogicalVersion): String = buildJsonObject {
    put("timestamp", version.timestamp)
    put("counter", version.counter)
    put("deviceId", version.deviceId)
  }.toString()

  fun decodeVersion(raw: String): LogicalVersion {
    val obj = json.parseToJsonElement(raw).jsonObject
    return LogicalVersion(
      timestamp = obj.long("timestamp"),
      counter = obj.int("counter"),
      deviceId = obj.string("deviceId"),
    )
  }

  fun encodePayload(payload: EntityPayload): String = when (payload) {
    is EntityPayload.Category -> buildJsonObject {
      put("id", payload.id)
      put("name", payload.name)
      put("emoji", payload.emoji)
      if (payload.monthlyBudgetMinor == null) put("monthlyBudgetMinor", JsonNull)
      else put("monthlyBudgetMinor", payload.monthlyBudgetMinor)
      put("tint", payload.tint.name)
      put("sortOrder", payload.sortOrder)
      put("system", payload.system)
    }.toString()
    is EntityPayload.PaymentMethod -> buildJsonObject {
      put("id", payload.id)
      put("name", payload.name)
      put("type", payload.type.name)
      put("detail", payload.detail)
      put("archived", payload.archived)
    }.toString()
    is EntityPayload.Transaction -> buildJsonObject {
      put("id", payload.id)
      put("name", payload.name)
      put("amountMinor", payload.amountMinor)
      put("occurredAt", payload.occurredAt)
      put("categoryId", payload.categoryId)
      if (payload.paymentMethodId == null) put("paymentMethodId", JsonNull)
      else put("paymentMethodId", payload.paymentMethodId)
    }.toString()
    is EntityPayload.Recurring -> buildJsonObject {
      put("id", payload.id)
      put("name", payload.name)
      put("amountMinor", payload.amountMinor)
      put("categoryId", payload.categoryId)
      if (payload.paymentMethodId == null) put("paymentMethodId", JsonNull)
      else put("paymentMethodId", payload.paymentMethodId)
      put("frequency", payload.frequency.name)
      put("anchorDate", payload.anchorDate)
      put("paused", payload.paused)
    }.toString()
    is EntityPayload.Lend -> buildJsonObject {
      put("id", payload.id)
      put("contactName", payload.contactName)
      put("contactId", payload.contactId)
      put("amountMinor", payload.amountMinor)
      put("occurredAt", payload.occurredAt)
      put("comment", payload.comment)
      put("kind", (payload.kind ?: LendKind.lent).name)
    }.toString()
    is EntityPayload.Preferences -> buildJsonObject {
      put("id", payload.id)
      put("profileName", payload.profileName)
      put("profileEmail", payload.profileEmail)
      put("currency", payload.currency.name)
      put("weekStart", payload.weekStart.name)
      put("theme", payload.theme.name)
      put("navGlassOpacity", payload.navGlassOpacity)
      put("defaultView", payload.defaultView.name)
      put("defaultStatsRange", payload.defaultStatsRange.wire)
      put("notifications", buildJsonObject {
        put("bills", payload.notifications.bills)
        put("budget", payload.notifications.budget)
        put("weekly", payload.notifications.weekly)
        put("large", payload.notifications.large)
      })
      put("defaultPaymentMethodId", payload.defaultPaymentMethodId)
    }.toString()
  }.let { it }

  fun decodePayload(type: EntityType, raw: String): EntityPayload {
    val obj = json.parseToJsonElement(raw).jsonObject
    return when (type) {
      EntityType.Category -> EntityPayload.Category(
        id = obj.string("id"),
        name = obj.string("name"),
        emoji = obj.stringOrNull("emoji")?.ifBlank { DEFAULT_CATEGORY_EMOJI } ?: DEFAULT_CATEGORY_EMOJI,
        monthlyBudgetMinor = obj.intOrNull("monthlyBudgetMinor"),
        tint = if (obj.stringOrNull("tint") == "green") CategoryTint.green else CategoryTint.neutral,
        sortOrder = obj.int("sortOrder"),
        system = obj.boolean("system"),
      )
      EntityType.PaymentMethod -> EntityPayload.PaymentMethod(
        id = obj.string("id"),
        name = obj.string("name"),
        type = PaymentMethodType.entries.firstOrNull { it.name == obj.stringOrNull("type") }
          ?: PaymentMethodType.Cash,
        detail = obj.stringOrNull("detail").orEmpty(),
        archived = obj.boolean("archived"),
      )
      EntityType.Transaction -> EntityPayload.Transaction(
        id = obj.string("id"),
        name = obj.string("name"),
        amountMinor = obj.int("amountMinor"),
        occurredAt = obj.long("occurredAt"),
        categoryId = obj.string("categoryId"),
        paymentMethodId = obj.stringOrNull("paymentMethodId"),
      )
      EntityType.Recurring -> EntityPayload.Recurring(
        id = obj.string("id"),
        name = obj.string("name"),
        amountMinor = obj.int("amountMinor"),
        categoryId = obj.string("categoryId"),
        paymentMethodId = obj.stringOrNull("paymentMethodId"),
        frequency = if (obj.stringOrNull("frequency") == "yearly") RecurringFrequency.yearly
        else RecurringFrequency.monthly,
        anchorDate = obj.string("anchorDate"),
        paused = obj.boolean("paused"),
      )
      EntityType.Lend -> {
        val contactName = obj.string("contactName")
        val contactId = obj.stringOrNull("contactId")?.trim().orEmpty().ifEmpty { contactName }
        EntityPayload.Lend(
          id = obj.string("id"),
          contactName = contactName,
          contactId = contactId,
          amountMinor = obj.int("amountMinor"),
          occurredAt = obj.long("occurredAt"),
          comment = obj.stringOrNull("comment").orEmpty(),
          kind = LendKind.entries.firstOrNull { it.name == obj.stringOrNull("kind") } ?: LendKind.lent,
        )
      }
      EntityType.Preferences -> {
        val notifications = obj["notifications"]?.jsonObject
        EntityPayload.Preferences(
          id = PREFERENCES_ID,
          profileName = obj.stringOrNull("profileName").orEmpty(),
          profileEmail = obj.stringOrNull("profileEmail").orEmpty(),
          currency = Currency.entries.firstOrNull { it.name == obj.stringOrNull("currency") } ?: Currency.INR,
          weekStart = if (obj.stringOrNull("weekStart") == "Sun") WeekStart.Sun else WeekStart.Mon,
          theme = ThemePreference.entries.firstOrNull { it.name == obj.stringOrNull("theme") }
            ?: ThemePreference.light,
          navGlassOpacity = obj.intOrNull("navGlassOpacity") ?: NAV_GLASS_OPACITY_MIN,
          defaultView = ViewKey.home,
          defaultStatsRange = StatsRange.fromWire(obj.stringOrNull("defaultStatsRange")),
          notifications = NotificationsPrefs(
            bills = notifications?.get("bills")?.jsonPrimitive?.booleanOrNull ?: true,
            budget = notifications?.get("budget")?.jsonPrimitive?.booleanOrNull ?: true,
            weekly = notifications?.get("weekly")?.jsonPrimitive?.booleanOrNull ?: false,
            large = notifications?.get("large")?.jsonPrimitive?.booleanOrNull ?: true,
          ),
          defaultPaymentMethodId = obj.stringOrNull("defaultPaymentMethodId")?.ifBlank { null }
            ?: CASH_PAYMENT_METHOD_ID,
        )
      }
    }
  }

  /** Wire map for Convex mutations — numbers as Double. */
  fun toWireMap(type: EntityType, payload: EntityPayload, version: LogicalVersion, deleted: Boolean, operationId: String, entityId: String): Map<String, Any?> {
    val payloadMap = json.parseToJsonElement(encodePayload(payload)).jsonObject.toAnyMap()
    return mapOf(
      "operationId" to operationId,
      "workspaceId" to "global",
      "entityType" to type.wire,
      "entityId" to entityId,
      "version" to mapOf(
        "timestamp" to version.timestamp.toDouble(),
        "counter" to version.counter.toDouble(),
        "deviceId" to version.deviceId,
      ),
      "payload" to payloadMap,
      "deleted" to deleted,
    )
  }

  private fun JsonObject.toAnyMap(): Map<String, Any?> = entries.associate { (k, v) -> k to v.toAny() }

  private fun JsonElement.toAny(): Any? = when (this) {
    is JsonNull -> null
    is JsonPrimitive -> when {
      isString -> content
      booleanOrNull != null -> boolean
      content.contains('.') || content.contains('e', true) -> doubleOrNull
      else -> doubleOrNull ?: content
    }
    is JsonObject -> toAnyMap()
    is JsonArray -> map { it.toAny() }
    else -> null
  }

  private fun JsonObject.string(key: String): String = this[key]?.jsonPrimitive?.content
    ?: error("Missing $key")
  private fun JsonObject.stringOrNull(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
  private fun JsonObject.boolean(key: String): Boolean = this[key]?.jsonPrimitive?.booleanOrNull ?: false
  private fun JsonObject.int(key: String): Int =
    this[key]?.jsonPrimitive?.doubleOrNull?.roundToInt() ?: 0
  private fun JsonObject.intOrNull(key: String): Int? =
    this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.doubleOrNull?.roundToInt()
  private fun JsonObject.long(key: String): Long =
    this[key]?.jsonPrimitive?.doubleOrNull?.toLong() ?: 0L
}
