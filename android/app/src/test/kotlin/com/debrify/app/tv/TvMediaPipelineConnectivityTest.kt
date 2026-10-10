package com.debrify.app.tv

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19ConnectivityShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvMediaPipelineConnectivityTest : TvPhase19PipelineTest() {
    @org.junit.Before fun resetNetworkObserver() { TvPhase19ConnectivityShadow.clear() }
    private fun recoveryLazy() = TvPlayerOriginalAccess.field(field("iptvTuneController")!!, "iptvLiveRecovery\$delegate") as Lazy<*>
    private fun offline() = read(recoveryLazy().value!!, "offline") as Boolean
    @Test fun initialOfflineAndWorkerCallbacksUseQueuedLiveRecovery() {
        assertFalse(recoveryLazy().isInitialized())
        TvPhase19ConnectivityShadow.observed = { assertFalse("registration precedes first recovery access", recoveryLazy().isInitialized()) }
        buildPipeline(true)
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        assertNotNull("registered callback is retained for teardown", field("iptvNetworkCallback"))
        val callback = field("iptvNetworkCallback") as ConnectivityManager.NetworkCallback
        assertTrue("registered exact activity callback", shadowOf(cm).networkCallbacks.contains(callback))
        assertTrue("cold-start disconnected truth", offline())
        worker { callback.onAvailable(org.robolectric.shadows.ShadowNetwork.newInstance(19)) }; assertTrue("available waits for Main", offline()); idle(); assertFalse(offline())
        worker { callback.onLost(org.robolectric.shadows.ShadowNetwork.newInstance(19)) }; assertFalse("lost waits for Main", offline()); idle(); assertTrue(offline())
    }
    @Test fun registrationFailureDoesNotStoreCallbackOrTouchLazyRecovery() {
        TvPhase19ConnectivityShadow.fail = true
        buildPipeline(true)
        assertNull(field("iptvNetworkCallback")); assertFalse(recoveryLazy().isInitialized())
        assertTrue("registration failure diagnostic", org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any { it.msg.contains("network callback:") })
    }
    @Test fun nonIptvDoesNotRegisterOrInitializeRecovery() {
        var registrations = 0; TvPhase19ConnectivityShadow.observed = { registrations++ }
        buildPipeline()
        assertEquals(0, registrations); assertNull(field("iptvNetworkCallback")); assertFalse(recoveryLazy().isInitialized())
    }
    @Test fun preNBoxesKeepTheTimedLadderWithoutRegistration() {
        var registrations = 0; TvPhase19ConnectivityShadow.observed = { registrations++ }
        // minSdk 24 resource APK cannot load on SDK 23; exercise the branch on the installed SDK 28 runtime.
        org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", 23)
        try {
            buildPipeline(true)
            assertEquals(0, registrations); assertNull(field("iptvNetworkCallback")); assertFalse(recoveryLazy().isInitialized())
        } finally { org.robolectric.util.ReflectionHelpers.setStaticField(android.os.Build.VERSION::class.java, "SDK_INT", 28) }
    }
    @Test fun connectedColdStartIsOnline() {
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        shadowOf(cm).setActiveNetworkInfo(org.robolectric.shadows.ShadowNetworkInfo.newInstance(android.net.NetworkInfo.DetailedState.CONNECTED, ConnectivityManager.TYPE_WIFI, 0, true, true))
        buildPipeline(true); assertFalse("cold start active network is online", offline())
    }
}
