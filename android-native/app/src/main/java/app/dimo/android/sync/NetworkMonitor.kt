package app.dimo.android.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest

/**
 * `ConnectivityManager` port of `ios-native/Dimo/Sync/NetworkMonitor.swift`.
 *
 * Only the reconnect edge matters: the coordinator asks for a sync when the
 * device comes back online.
 */
class NetworkMonitor(context: Context) : SyncCoordinator.NetworkMonitorLike {
  private val manager =
    context.applicationContext.getSystemService(ConnectivityManager::class.java)

  @Volatile
  override var isOnline: Boolean = true
    private set

  private var callback: ConnectivityManager.NetworkCallback? = null

  override fun start(onReconnect: () -> Unit) {
    isOnline = currentlyOnline()
    val cb = object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) {
        val wasOffline = !isOnline
        isOnline = true
        if (wasOffline) onReconnect()
      }

      override fun onLost(network: Network) {
        isOnline = currentlyOnline()
      }

      override fun onCapabilitiesChanged(
        network: Network,
        networkCapabilities: NetworkCapabilities,
      ) {
        val validated =
          networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val wasOffline = !isOnline
        isOnline = validated
        if (validated && wasOffline) onReconnect()
      }
    }
    callback = cb
    val request = NetworkRequest.Builder()
      .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      .build()
    runCatching { manager?.registerNetworkCallback(request, cb) }
  }

  override fun stop() {
    val cb = callback ?: return
    runCatching { manager?.unregisterNetworkCallback(cb) }
    callback = null
  }

  private fun currentlyOnline(): Boolean {
    val network = manager?.activeNetwork ?: return false
    val capabilities = manager.getNetworkCapabilities(network) ?: return false
    return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
  }
}
