package app.dimo.android.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dimo.android.sync.AcceptedLendInvite
import app.dimo.android.sync.IncomingLendInvite
import app.dimo.android.sync.LendConnectionSummary
import app.dimo.android.sync.LendHistoryChoice
import app.dimo.android.sync.LendInviteCode
import app.dimo.android.sync.LendInviteLinks
import app.dimo.android.sync.LendInvitePreview
import app.dimo.android.sync.LendingSharingTransport
import app.dimo.android.sync.OutgoingLendInvite
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Which sharing sheet is open. */
sealed interface LedgerSharingSheet {
  /** Invite someone to share a ledger, optionally for an existing contact. */
  data class Invite(val contactId: String?, val contactName: String) : LedgerSharingSheet

  /** Join a ledger with a code, optionally prefilled from a link or email invite. */
  data class Join(val code: String) : LedgerSharingSheet
}

/**
 * Invite codes from `dimo://invite/...` links, held until a signed-in shell can
 * open the join sheet.
 */
object LendInviteLinkBus {
  var pendingCode by mutableStateOf<String?>(null)
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

  /** False when the server cannot look up verified emails (no WorkOS API key). */
  var emailInvitesAvailable by mutableStateOf(true)
    private set
  var sheet by mutableStateOf<LedgerSharingSheet?>(null)

  private var transport: LendingSharingTransport? = null
  private var didRefreshEmail = false

  /** Pulls fresh lends after the ledger changed on the server. */
  var onLedgerChanged: (() -> Unit)? = null

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

  fun pendingInvite(contactId: String, nowMillis: Long = System.currentTimeMillis()): OutgoingLendInvite? =
    outgoingInvites.firstOrNull { it.contactId == contactId && it.expiresAt > nowMillis }

  fun liveIncomingInvites(nowMillis: Long = System.currentTimeMillis()): List<IncomingLendInvite> =
    incomingInvites.filter { it.expiresAt > nowMillis }

  /**
   * Reloads invites and connections, and records the verified email once per
   * session so email-addressed invites can reach this account.
   */
  suspend fun refresh() {
    val transport = transport ?: return
    if (!didRefreshEmail) {
      didRefreshEmail = true
      runCatching { transport.refreshVerifiedEmail() }
        .onSuccess {
          emailInvitesAvailable = it.available
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

  suspend fun createInvite(contactId: String?, contactName: String, email: String?): LendInviteCode {
    val invite = requireTransport().createInvite(
      contactId = contactId,
      contactName = contactName.trim(),
      email = email?.trim()?.takeIf { it.isNotEmpty() },
    )
    refresh()
    return invite
  }

  suspend fun preview(code: String): LendInvitePreview? =
    requireTransport().preview(LendInviteLinks.normalize(code))

  suspend fun accept(
    code: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice,
  ): AcceptedLendInvite {
    val accepted = requireTransport().accept(
      code = LendInviteLinks.normalize(code),
      contactId = contactId,
      contactName = contactName,
      history = history,
    )
    refresh()
    onLedgerChanged?.invoke()
    return accepted
  }

  suspend fun decline(code: String) {
    requireTransport().decline(code)
    refresh()
  }

  suspend fun cancel(code: String) {
    requireTransport().cancel(code)
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
