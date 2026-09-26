package app.dimo.android.sync

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
/** A Dimo account found by its verified email. */
@Serializable
data class LendUser(
  val userId: String,
  val name: String,
  val email: String,
  /** `none`, `self`, `connected`, `invited` or `invitedYou`. */
  val relation: String,
  /**
   * Your contactId for them: the shared ledger when connected, or the contact
   * a pending invite is for.
   */
  val contactId: String? = null,
)

/** An invite waiting for this account to accept or decline. */
@Serializable
data class IncomingLendInvite(
  val inviteId: String,
  val inviterName: String,
  val inviterEmail: String? = null,
  val createdAt: Double,
)

/** An invite this account sent that hasn't been accepted yet. */
@Serializable
data class OutgoingLendInvite(
  val inviteId: String,
  val contactName: String,
  val contactId: String? = null,
  val inviteeEmail: String? = null,
  val createdAt: Double,
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

class LendingSharingTransport(
  private val client: ConvexClientWithAuth<WorkOSSession>,
) {
  private val json = Json { ignoreUnknownKeys = true }

  suspend fun findUser(email: String): LendUser? {
    val element = query("lending:findLendUser", mapOf("email" to email))
    if (element == null || element is JsonNull) return null
    return decode(LendUser.serializer(), element)
  }

  suspend fun sendInvite(userId: String, contactId: String, contactName: String) {
    mutation(
      "lending:sendLendInvite",
      mapOf("userId" to userId, "contactId" to contactId, "contactName" to contactName),
    )
  }

  suspend fun accept(
    inviteId: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice,
  ): AcceptedLendInvite {
    val args = buildMap<String, Any?> {
      put("inviteId", inviteId)
      put("history", history.wire)
      if (contactId != null) put("contactId", contactId)
      if (!contactName.isNullOrEmpty()) put("contactName", contactName)
    }
    return decode(AcceptedLendInvite.serializer(), mutation("lending:acceptLendInvite", args))
  }

  suspend fun decline(inviteId: String) {
    mutation("lending:declineLendInvite", mapOf("inviteId" to inviteId))
  }

  suspend fun cancel(inviteId: String) {
    mutation("lending:cancelLendInvite", mapOf("inviteId" to inviteId))
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
