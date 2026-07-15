package app.dimo.android.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class NetworkMonitor(context: Context) {
  private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  private val _online = MutableStateFlow(true)
  val online: StateFlow<Boolean> = _online.asStateFlow()
  var onOnline: (() -> Unit)? = null

  private val callback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
      val was = _online.value
      _online.value = true
      if (!was) onOnline?.invoke()
    }

    override fun onLost(network: Network) {
      _online.value = currentlyOnline()
    }

    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
      val was = _online.value
      val now = networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      _online.value = now
      if (!was && now) onOnline?.invoke()
    }
  }

  fun start() {
    _online.value = currentlyOnline()
    val request = NetworkRequest.Builder()
      .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      .build()
    cm.registerNetworkCallback(request, callback)
  }

  fun stop() {
    runCatching { cm.unregisterNetworkCallback(callback) }
  }

  private fun currentlyOnline(): Boolean {
    val network = cm.activeNetwork ?: return false
    val caps = cm.getNetworkCapabilities(network) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
  }
}
