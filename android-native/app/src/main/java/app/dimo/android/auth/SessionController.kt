package app.dimo.android.auth

import android.content.Context
import android.net.Uri
import app.dimo.android.data.db.AppDatabase
import app.dimo.android.store.AppStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

sealed class SessionPhase {
  data object Loading : SessionPhase()
  data object SignedOut : SessionPhase()
  data class SignedIn(val session: WorkOSSession, val store: AppStore) : SessionPhase()
}

class SessionController(
  private val appContext: Context,
  private val api: WorkOSAPI = WorkOSAPI(),
) {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val mutex = Mutex()
  private val _phase = MutableStateFlow<SessionPhase>(SessionPhase.Loading)
  val phase: StateFlow<SessionPhase> = _phase.asStateFlow()

  private var tokenStore: TokenStore? = null
  private var pendingVerifier: String? = null
  private var pendingState: String? = null
  private var refresherJob: Job? = null
  private var cached: WorkOSSession? = null

  init {
    scope.launch { restore() }
  }

  fun beginSignIn(): String {
    val verifier = PKCE.verifier()
    val state = PKCE.state()
    pendingVerifier = verifier
    pendingState = state
    return api.authorizeUrl(
      provider = "GoogleOAuth",
      state = state,
      challenge = PKCE.challenge(verifier),
    )
  }

  fun handleRedirect(uri: Uri) {
    scope.launch {
      val code = uri.getQueryParameter("code") ?: return@launch
      val state = uri.getQueryParameter("state")
      if (state != pendingState) return@launch
      val verifier = pendingVerifier ?: return@launch
      val session = withContext(Dispatchers.IO) { api.exchangeCode(code, verifier) }
      persist(session)
      enterSignedIn(session)
    }
  }

  suspend fun refreshIfNeeded(force: Boolean = false): WorkOSSession {
    return mutex.withLock {
      val current = cached
      val now = System.currentTimeMillis() / 1000
      if (!force && current != null && current.expiresAtEpochSeconds - now > 60) {
        return@withLock current
      }
      val refresh = current?.refreshToken ?: store().refreshToken
        ?: throw IllegalStateException("Not signed in")
      val session = withContext(Dispatchers.IO) { api.refresh(refresh) }
      persist(session)
      cached = session
      session
    }
  }

  fun signOut() {
    scope.launch {
      refresherJob?.cancel()
      val signedIn = _phase.value as? SessionPhase.SignedIn
      signedIn?.store?.tearDown()
      store().clear()
      cached = null
      withContext(Dispatchers.IO) { AppDatabase.deleteAllLocalDatabases(appContext) }
      _phase.value = SessionPhase.SignedOut
    }
  }

  fun deleteAccount() {
    scope.launch {
      val signedIn = _phase.value as? SessionPhase.SignedIn ?: return@launch
      signedIn.store.clearCloudWorkspace()
      refresherJob?.cancel()
      signedIn.store.tearDown()
      store().clear()
      cached = null
      withContext(Dispatchers.IO) { AppDatabase.deleteAllLocalDatabases(appContext) }
      _phase.value = SessionPhase.SignedOut
    }
  }

  private suspend fun restore() {
    val store = withContext(Dispatchers.IO) { store() }
    val refresh = store.refreshToken
    val userJson = store.userJson
    if (refresh == null || userJson == null) {
      _phase.value = SessionPhase.SignedOut
      return
    }
    try {
      val session = withContext(Dispatchers.IO) { api.refresh(refresh) }
      persist(session)
      enterSignedIn(session)
    } catch (_: Exception) {
      store.clear()
      _phase.value = SessionPhase.SignedOut
    }
  }

  private fun store(): TokenStore {
    tokenStore?.let { return it }
    return TokenStore(appContext).also { tokenStore = it }
  }

  private fun persist(session: WorkOSSession) {
    cached = session
    val store = store()
    store.refreshToken = session.refreshToken
    store.userJson = WorkOSJson.json.encodeToString(WorkOSUser.serializer(), session.user)
  }

  private suspend fun enterSignedIn(session: WorkOSSession) {
    val appStore = withContext(Dispatchers.IO) {
      AppStore(appContext, session) { refreshIfNeeded(it) }.also { it.start() }
    }
    _phase.value = SessionPhase.SignedIn(session, appStore)
    startRefresher()
  }

  private fun startRefresher() {
    refresherJob?.cancel()
    refresherJob = scope.launch {
      while (isActive) {
        try {
          val session = refreshIfNeeded(force = false)
          val delaySec = maxOf(5L, session.expiresAtEpochSeconds - System.currentTimeMillis() / 1000 - 60)
          delay(delaySec * 1000)
        } catch (_: Exception) {
          delay(30_000)
        }
      }
    }
  }
}
