package com.debrify.app.tv

import android.net.ConnectivityManager
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowConnectivityManager

/** The same Robolectric network registration with an optional ROM-style failure. */
@Implements(ConnectivityManager::class)
internal class TvPhase19ConnectivityShadow : ShadowConnectivityManager() {
    @Implementation override fun registerDefaultNetworkCallback(callback: ConnectivityManager.NetworkCallback) {
        observed?.invoke(callback)
        if (fail) throw IllegalStateException("p19 ROM callback limit")
        super.registerDefaultNetworkCallback(callback)
    }
    companion object {
        var fail = false
        var observed: ((ConnectivityManager.NetworkCallback) -> Unit)? = null
        @JvmStatic @Resetter fun clear() { fail = false; observed = null }
    }
}
