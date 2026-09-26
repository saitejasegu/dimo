package app.dimo.android.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dimo.android.sync.IncomingLendInvite
import app.dimo.android.sync.LendConnectionSummary
import app.dimo.android.sync.LendHistoryChoice
import app.dimo.android.sync.LendUser
import app.dimo.android.sync.LendingSharingTransport
import app.dimo.android.sync.OutgoingLendInvite
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Which sharing sheet is open. */
sealed interface LedgerSharingSheet {
  /** Accept or decline an invite someone sent. */
  data class Accept(val invite: IncomingLendInvite) : LedgerSharingSheet
}

/**
 * Server-side state for ledgers shared with other Dimo accounts. Port of
 * `ios-native/Dimo/Store/LendingSharingStore.swift`. Entries arrive through
 * normal sync because the server mirrors them into this account's `lends`.
 */
class LendingSharingStore {
  var connections by mutableStateOf<List<LendConnectionSummary>>(emptyList())
    private set
  var incomingInvites by mutableStateOf<List<IncomingLendInvite>>(emptyList())
    private set
  var outgoingInvites by mutableStateOf<List<OutgoingLendInvite>>(emptyList())
    private set
  var verifiedEmail by mutableStateOf<String?>(null)
    private set

  /**
   * False when the server cannot look up verified emails (no WorkOS API key),
   * in which case nobody can be found to share with.
   */
  var sharingAvailable by mutableStateOf(true)
    private set
  var sheet by mutableStateOf<LedgerSharingSheet?>(null)

  private var transport: LendingSharingTransport? = null
  private var didRefreshEmail = false

  /** Pulls fresh lends after the ledger changed on the server. */
  var onLedgerChanged: (() -> Unit)? = null

  val isOnline: Boolean get() = transport != null

  fun attach(next: LendingSharingTransport?) {
    transport = next
    if (next == null) {
      connections = emptyList()
      incomingInvites = emptyList()
      outgoingInvites = emptyList()
      didRefreshEmail = false
    }
  }

  fun activeConnection(contactId: String): LendConnectionSummary? =
    connections.firstOrNull { it.contactId == contactId && it.isActive }

  fun pendingInvite(contactId: String): OutgoingLendInvite? =
    outgoingInvites.firstOrNull { it.contactId == contactId }

  /**
   * Reloads invites and connections, and records the verified email once per
   * session so other people can find this account.
   */
  suspend fun refresh() {
    val transport = transport ?: return
    if (!didRefreshEmail) {
      didRefreshEmail = true
      runCatching { transport.refreshVerifiedEmail() }
        .onSuccess {
          sharingAvailable = it.available
          verifiedEmail = it.email
        }
        .onFailure { didRefreshEmail = false }
    }
    coroutineScope {
      val nextConnections = async { runCatching { transport.connections() }.getOrNull() }
      val nextIncoming = async { runCatching { transport.incomingInvites() }.getOrNull() }
      val nextOutgoing = async { runCatching { transport.outgoingInvites() }.getOrNull() }
      nextConnections.await()?.let { connections = it }
      nextIncoming.await()?.let { incomingInvites = it }
      nextOutgoing.await()?.let { outgoingInvites = it }
    }
  }

  suspend fun findUser(email: String): LendUser? = requireTransport().findUser(email.trim())

  /** Invites [user]; entries with [contactId] are shared once they accept. */
  suspend fun sendInvite(user: LendUser, contactId: String, contactName: String) {
    requireTransport().sendInvite(
      userId = user.userId,
      contactId = contactId,
      contactName = contactName.trim().ifEmpty { user.name },
    )
    refresh()
  }

  suspend fun accept(
    invite: IncomingLendInvite,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice,
  ) {
    requireTransport().accept(
      inviteId = invite.inviteId,
      contactId = contactId,
      contactName = contactName,
      history = history,
    )
    refresh()
    onLedgerChanged?.invoke()
  }

  suspend fun decline(invite: IncomingLendInvite) {
    requireTransport().decline(invite.inviteId)
    refresh()
  }

  suspend fun cancel(invite: OutgoingLendInvite) {
    requireTransport().cancel(invite.inviteId)
    refresh()
  }

  suspend fun stopSharing(contactId: String) {
    val connection = activeConnection(contactId) ?: return
    requireTransport().revoke(connection.connectionId)
    refresh()
  }

  private fun requireTransport(): LendingSharingTransport =
    transport ?: throw IllegalStateException("Shared ledgers need an online Dimo sync session.")
}
