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

/**
 * Server-side state for lending shared with other Dimo accounts. Port of
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

  private var transport: LendingSharingTransport? = null
  private var photoPublished = false
  private var lastPublishedPhoto: String? = null

  /** Pulls fresh lends after sharing changed on the server. */
  var onLedgerChanged: (() -> Unit)? = null

  /** This account's sign-in photo, published so people it shares with see it. */
  var profilePhotoUrl: (() -> String?)? = null

  val isOnline: Boolean get() = transport != null

  fun attach(next: LendingSharingTransport?) {
    transport = next
    if (next == null) {
      connections = emptyList()
      incomingInvites = emptyList()
      outgoingInvites = emptyList()
      photoPublished = false
    }
  }

  /** Active connection whose shared contactId is [contactId]. */
  fun activeConnection(contactId: String): LendConnectionSummary? =
    connections.firstOrNull { it.contactId == contactId && it.isActive }

  /** Was shared with this contact, and one side stopped. */
  fun stoppedConnection(contactId: String): LendConnectionSummary? =
    connections.firstOrNull { it.contactId == contactId && !it.isActive }

  /** A pending invite already sent for this local contact. */
  fun pendingInvite(contactId: String): OutgoingLendInvite? =
    outgoingInvites.firstOrNull { it.contactId == contactId }

  /** Profile photo for a shared or invited contact, if they have one. */
  fun photoUrl(contactId: String): String? =
    connections.firstOrNull { it.contactId == contactId }?.photoUrl
      ?: outgoingInvites.firstOrNull { it.contactId == contactId }?.inviteePhotoUrl

  /** Reloads invites and connections, and publishes this account's photo. */
  suspend fun refresh() {
    val transport = transport ?: return
    val photo = profilePhotoUrl?.invoke()
    if (!photoPublished || lastPublishedPhoto != photo) {
      runCatching { transport.setProfilePhoto(photo) }.onSuccess {
        photoPublished = true
        lastPublishedPhoto = photo
      }
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

  /** Dimo accounts (never this one) matching a name or email. */
  suspend fun searchUsers(query: String): List<LendUser> = requireTransport().searchUsers(query.trim())

  /** Invites [user]; entries with [contactId] are shared once they accept. */
  suspend fun sendInvite(user: LendUser, contactId: String, contactName: String) {
    requireTransport().sendInvite(
      userId = user.userId,
      contactId = contactId,
      contactName = contactName.trim().ifEmpty { user.name },
    )
    refresh()
  }

  /**
   * Accepts, keeping both sides' history; [mergeWith] joins a contact you
   * already track into the shared one.
   */
  suspend fun accept(invite: IncomingLendInvite, mergeWith: String?) {
    requireTransport().accept(
      inviteId = invite.inviteId,
      contactId = mergeWith,
      contactName = invite.inviterName,
      history = LendHistoryChoice.BOTH,
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

  /** Invites the other person to share a stopped connection again. */
  suspend fun shareAgain(contactId: String) {
    val connection = stoppedConnection(contactId) ?: return
    requireTransport().reshare(connection.connectionId)
    refresh()
  }

  private fun requireTransport(): LendingSharingTransport =
    transport ?: throw IllegalStateException("Sharing needs an online Dimo sync session.")
}
