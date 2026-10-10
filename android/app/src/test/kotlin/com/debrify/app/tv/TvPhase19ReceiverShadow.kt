package com.debrify.app.tv

import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowContextImpl

/** Observe the platform boundary, then preserve broadcast delivery and registration. */
@Implements(className = "android.app.ContextImpl")
internal class TvPhase19ReceiverShadow : ShadowContextImpl() {
    @Implementation override fun registerReceiver(receiver: BroadcastReceiver?, filter: IntentFilter): Intent? {
        registrations.add(Registration(receiver, filter, 0))
        if (filter.hasAction("com.debrify.app.tv.UPDATE_EPISODE_METADATA")) onMetadataRegister?.invoke()
        return super.registerReceiver(receiver, filter)
    }
    @Implementation override fun registerReceiver(receiver: BroadcastReceiver?, filter: IntentFilter, flags: Int): Intent? {
        registrations.add(Registration(receiver, filter, flags))
        if (filter.hasAction("com.debrify.app.tv.UPDATE_EPISODE_METADATA")) onMetadataRegister?.invoke()
        return super.registerReceiver(receiver, filter, flags)
    }
    @Implementation override fun unregisterReceiver(receiver: BroadcastReceiver) {
        unregister?.invoke(receiver)
        super.unregisterReceiver(receiver)
        if (failUnregister) throw IllegalArgumentException("p19 unregister failure after removal")
    }
    data class Registration(val receiver: BroadcastReceiver?, val filter: IntentFilter, val flags: Int)
    companion object {
        val registrations = mutableListOf<Registration>()
        var unregister: ((BroadcastReceiver) -> Unit)? = null
        var failUnregister = false
        var onMetadataRegister: (() -> Unit)? = null
        @JvmStatic @Resetter fun resetFixture() { registrations.clear(); unregister = null; failUnregister = false; onMetadataRegister = null }
    }
}
