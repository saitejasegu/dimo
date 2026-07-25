package app.dimo.android.auth

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dimo.android.data.db.AppDatabase
import app.dimo.android.store.AppStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class SessionPhase {
  Loading,
  SignedOut,
  SignedIn,
}

/**
 * Port of `ios-native/Dimo/Auth/SessionController.swift` without Gmail /
 * OpenRouter / ExpenseReminder vault cleanup (those surfaces are not on Android).
 */
class SessionController(context: Context) {
  private val appContext = context.applicationContext
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val authProvider = WorkOSAuthProvider(appContext)

  var phase by mutableStateOf(SessionPhase.Loading)
    private set
  var userId by mutableStateOf<String?>(null)
    private set
  var profileName by mutableStateOf<String?>(null)
    private set
  var profileEmail by mutableStateOf<String?>(null)
    private set
  var appStore by mutableStateOf<AppStore?>(null)
    private set

  private var tokenRefresher: TokenRefresher? = null

  init {
    scope.launch { bootstrap() }
  }

  suspend fun bootstrap() {
    phase = SessionPhase.Loading
    val session = authProvider.restoreSession()
    if (session != null) {
      enterSignedIn(session)
    } else {
      phase = SessionPhase.SignedOut
    }
  }

  suspend fun signInWithGoogle() {
    val session = authProvider.signIn(provider = "GoogleOAuth")
    enterSignedIn(session)
  }

  suspend fun signOut() {
    tokenRefresher?.stop()
    tokenRefresher = null
    appStore?.tearDown()
    withContext(Dispatchers.IO) {
      AppDatabase.deleteAllLocalDatabases(appContext)
    }
    authProvider.signOut()
    appStore = null
    userId = null
    profileName = null
    profileEmail = null
    phase = SessionPhase.SignedOut
  }

  suspend fun deleteAccount() {
    val store = appStore ?: return
    store.clearCloudWorkspace()
    signOut()
  }

  private suspend fun enterSignedIn(session: WorkOSSession) {
    userId = session.user.id
    profileName = session.user.displayName
    profileEmail = session.user.email
    val store = AppStore(
      application = appContext as Application,
      userId = session.user.id,
      profileName = session.user.displayName,
      profileEmail = session.user.email,
      profilePhotoUrl = session.user.profilePictureUrl,
      authProvider = authProvider,
    )
    store.start()
    appStore = store
    tokenRefresher = TokenRefresher(authProvider, scope).also { it.start() }
    phase = SessionPhase.SignedIn
  }
}
