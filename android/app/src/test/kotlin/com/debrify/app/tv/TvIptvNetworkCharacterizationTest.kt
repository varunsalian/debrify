package com.debrify.app.tv

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvNetworkCharacterizationTest : TvPhase17OriginalTest() {
    private fun worker(action: () -> Unit) {
        val executor=Executors.newSingleThreadExecutor()
        try { executor.submit { assertNotEquals(android.os.Looper.getMainLooper().thread,Thread.currentThread());action() }.get(5,TimeUnit.SECONDS) }
        finally { executor.shutdownNow();assertTrue(executor.awaitTermination(5,TimeUnit.SECONDS)) }
    }
    private fun callback(): ConnectivityManager.NetworkCallback {
        val cb=field("iptvNetworkCallback") as ConnectivityManager.NetworkCallback
        val cm=activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        assertTrue("bootstrap registers its real callback",shadowOf(cm).networkCallbacks.contains(cb));return cb
    }
    @Test fun offlineBootstrapParksEndedUntilWorkerAvailableHopsToMain() {
        bootstrap();val machine=recovery();assertTrue(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        assertTrue(machine.onEnded());advance(0);assertTrue(tuning().isEmpty());assertEquals("ended",TvPlayerOriginalAccess.field(machine,"deferredSource"))
        worker { callback().onAvailable(org.robolectric.shadows.ShadowNetwork.newInstance(1)) };assertTrue(tuning().isEmpty());assertTrue(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        advance(0);quiet();assertEquals(1,tuning().size);assertFalse(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any { it.msg.contains("ended+online") })
    }
    @Test fun lostCallbackAlsoHopsAndDestroyOnlyUnregistersAlreadyQueuedDelivery() {
        bootstrap();val cb=callback();val machine=recovery();machine.setOffline(false)
        worker { cb.onLost(org.robolectric.shadows.ShadowNetwork.newInstance(1)) };assertFalse(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        advance(0);assertTrue(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        worker { cb.onAvailable(org.robolectric.shadows.ShadowNetwork.newInstance(1)) };lifecycle.destroy();booted=false
        val cm=activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        assertFalse(shadowOf(cm).networkCallbacks.contains(cb));assertTrue(TvPlayerOriginalAccess.field(machine,"offline") as Boolean)
        advance(0);assertFalse(TvPlayerOriginalAccess.field(machine,"offline") as Boolean);assertTrue(tuning().isEmpty())
    }
}
