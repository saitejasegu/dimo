package app.dimo.android.sync

import android.net.Uri
import app.dimo.android.auth.WorkOSSession
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull

/**
 * Collaborative lending calls (`convex/lending.ts`). Port of
 * `ios-native/Dimo/Sync/LendingSharingTransport.swift`.
 */
@Serializable
data class LendInviteCode(val code: String, val expiresAt: Double)

@Serializable
data class LendInvitePreview(
  val inviterName: String,
  /** `pending`, `accepted` or `revoked`. */
  val status: String,
  val expiresAt: Double,
  val isOwnInvite: Boolean,
) {
  fun isAcceptable(nowMillis: Long = System.currentTimeMillis()): Boolean =
    status == "pending" && !isOwnInvite && expiresAt > nowMillis
}

/** An invite addressed to this account by its verified email. */
@Serializable
data class IncomingLendInvite(val code: String, val inviterName: String, val expiresAt: Double)

/** An invite this account sent that nobody has accepted yet. */
@Serializable
data class OutgoingLendInvite(
  val code: String,
  val contactName: String,
  val contactId: String? = null,
  val expiresAt: Double,
)

@Serializable
data class LendConnectionSummary(
  val connectionId: String,
  /** `dimo:<connectionId>`, the contactId every shared entry carries. */
  val contactId: String,
  val contactName: String,
  /** `active` or `revoked`. */
  val status: String,
  val createdAt: Double,
  val revokedAt: Double? = null,
) {
  val isActive: Boolean get() = status == "active"
}

@Serializable
data class AcceptedLendInvite(val connectionId: String, val contactId: String)

@Serializable
data class VerifiedEmailResult(
  /** False when the deployment has no WorkOS API key configured. */
  val available: Boolean,
  val email: String? = null,
)

/**
 * Whose past entries make up the shared ledger when both sides already tracked
 * each other; the other side's duplicates are deleted.
 */
enum class LendHistoryChoice(val wire: String) {
  BOTH("both"),
  INVITER("inviter"),
  ACCEPTER("accepter"),
}

object LendInviteLinks {
  const val WEB_BASE = "https://dimoapp.xyz/invite"

  fun webUrl(code: String): String = "$WEB_BASE?code=$code"

  /** Same normalisation as the server: uppercase ASCII letters and digits only. */
  fun normalize(code: String): String =
    code.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }

  /** Accepts `dimo://invite/CODE`, `dimo://invite?code=CODE` and the web link. */
  fun code(scheme: String?, host: String?, path: String?, codeParam: String?): String? {
    val isInvite = when (scheme) {
      "dimo" -> host == "invite"
      "https" -> host == "dimoapp.xyz" && path.orEmpty().startsWith("/invite")
      else -> false
    }
    if (!isInvite) return null
    val pathCode = if (scheme == "dimo") {
      path.orEmpty().trim('/').split('/').lastOrNull()?.takeIf { it.isNotEmpty() && it != "invite" }
    } else {
      null
    }
    return (codeParam ?: pathCode)?.let(::normalize)?.takeIf { it.isNotEmpty() }
  }

  fun code(uri: Uri): String? =
    code(uri.scheme, uri.host, uri.path, uri.getQueryParameter("code"))

  fun grouped(code: String): String =
    if (code.length == 10) "${code.take(5)}-${code.takeLast(5)}" else code

  /** Plain-text invite for `ACTION_SEND`, matching the iOS share sheet. */
  fun message(inviterName: String, code: String): String =
    "$inviterName wants to keep a shared lending ledger with you on Dimo.\n\n" +
      "Open ${webUrl(code)}\n" +
      "or enter code ${grouped(code)} in Dimo → Lending → Join."
}

class LendingSharingTransport(
  private val client: ConvexClientWithAuth<WorkOSSession>,
) {
  private val json = Json { ignoreUnknownKeys = true }

  suspend fun createInvite(contactId: String?, contactName: String, email: String?): LendInviteCode {
    val args = buildMap<String, Any?> {
      put("contactName", contactName)
      if (contactId != null) put("contactId", contactId)
      if (!email.isNullOrEmpty()) put("email", email)
    }
    val path = if (email.isNullOrEmpty()) {
      "lending:createLendInvite"
    } else {
      "lending:inviteLendContactByEmail"
    }
    return decode(LendInviteCode.serializer(), mutation(path, args))
  }

  suspend fun preview(code: String): LendInvitePreview? {
    val element = query("lending:previewLendInvite", mapOf("code" to code))
    if (element == null || element is JsonNull) return null
    return decode(LendInvitePreview.serializer(), element)
  }

  suspend fun accept(
    code: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice,
  ): AcceptedLendInvite {
    val args = buildMap<String, Any?> {
      put("code", code)
      put("history", history.wire)
      if (contactId != null) put("contactId", contactId)
      if (!contactName.isNullOrEmpty()) put("contactName", contactName)
    }
    return decode(AcceptedLendInvite.serializer(), mutation("lending:acceptLendInvite", args))
  }

  suspend fun decline(code: String) {
    mutation("lending:declineLendInvite", mapOf("code" to code))
  }

  suspend fun cancel(code: String) {
    mutation("lending:cancelLendInvite", mapOf("code" to code))
  }

  suspend fun revoke(connectionId: String) {
    mutation("lending:revokeLendConnection", mapOf("connectionId" to connectionId))
  }

  suspend fun incomingInvites(): List<IncomingLendInvite> =
    decodeList(IncomingLendInvite.serializer(), query("lending:listIncomingLendInvites", emptyMap()))

  suspend fun outgoingInvites(): List<OutgoingLendInvite> =
    decodeList(OutgoingLendInvite.serializer(), query("lending:listOutgoingLendInvites", emptyMap()))

  suspend fun connections(): List<LendConnectionSummary> =
    decodeList(LendConnectionSummary.serializer(), query("lending:listLendConnections", emptyMap()))

  suspend fun refreshVerifiedEmail(): VerifiedEmailResult {
    val element = withTimeout(TIMEOUT_MS) {
      client.action<JsonElement>("lendingEmail:refreshVerifiedEmail", emptyMap())
    }
    return decode(VerifiedEmailResult.serializer(), element)
  }

  private suspend fun mutation(name: String, args: Map<String, Any?>): JsonElement =
    withTimeout(TIMEOUT_MS) { client.mutation<JsonElement>(name, args) }

  private suspend fun query(name: String, args: Map<String, Any?>): JsonElement? =
    withTimeout(TIMEOUT_MS) { client.subscribe<JsonElement>(name, args).first().getOrThrow() }

  private fun <T> decode(serializer: KSerializer<T>, element: JsonElement?): T =
    json.decodeFromJsonElement(serializer, element ?: JsonNull)

  private fun <T> decodeList(serializer: KSerializer<T>, element: JsonElement?): List<T> =
    if (element == null || element is JsonNull) {
      emptyList()
    } else {
      json.decodeFromJsonElement(ListSerializer(serializer), element)
    }

  private companion object {
    const val TIMEOUT_MS = 45_000L
  }
}
