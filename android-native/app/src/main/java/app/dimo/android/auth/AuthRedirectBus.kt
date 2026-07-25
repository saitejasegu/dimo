package app.dimo.android.auth

import android.net.Uri
import kotlinx.coroutines.CompletableDeferred

/**
 * Bridges the `dimo://callback` intent back to the suspending sign-in call.
 *
 * iOS gets the callback URL directly from `ASWebAuthenticationSession`'s
 * completion handler. On Android the browser hands the redirect to
 * `MainActivity` as a new intent, so the pending sign-in parks on this deferred
 * and the activity completes it.
 */
object AuthRedirectBus {
  @Volatile
  private var pending: CompletableDeferred<Uri>? = null

  fun expectRedirect(): CompletableDeferred<Uri> {
    // A previous attempt the user abandoned must not hold the next one hostage.
    pending?.cancel()
    val deferred = CompletableDeferred<Uri>()
    pending = deferred
    return deferred
  }

  /** Returns true when this URI was consumed by a waiting sign-in. */
  fun publish(uri: Uri): Boolean {
    val deferred = pending ?: return false
    pending = null
    return deferred.complete(uri)
  }

  /**
   * Called when the activity resumes with no redirect delivered, which is what a
   * dismissed Custom Tab looks like.
   */
  fun cancelPending() {
    pending?.completeExceptionally(AuthException.Cancelled)
    pending = null
  }

  fun hasPending(): Boolean = pending?.isActive == true
}
