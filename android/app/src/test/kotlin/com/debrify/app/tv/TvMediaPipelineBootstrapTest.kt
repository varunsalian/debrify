package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Observe the production bootstrap before its receiver registration; keep its factories real. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19ReceiverShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvMediaPipelineBootstrapTest : TvPhase15OriginalTest() {
    private var playerKind: String? = null
    private var factoryKind: String? = null
    override fun bootstrapPayload(): JSONObject {
        TvPhase19ReceiverShadow.resetFixture()
        TvPhase19ReceiverShadow.onMetadataRegister = onMetadataRegister@ {
            val player = field("player")
            playerKind = player?.javaClass?.name
            if (playerKind != "androidx.media3.exoplayer.ExoPlayerImpl") return@onMetadataRegister
            val factory = TvPlayerOriginalAccess.field(player!!, "mediaSourceFactory")!!
            factoryKind = TvPlayerOriginalAccess.field(factory, "dataSourceFactory")!!.javaClass.name
        }
        return super.bootstrapPayload()
    }
    @org.junit.After fun clearBootstrapObserver() { TvPhase19ReceiverShadow.resetFixture() }
    @Test fun vodOnCreateInstallsPipelineBeforeMetadataRegistration() {
        assertEquals("androidx.media3.exoplayer.ExoPlayerImpl", playerKind)
        assertEquals(androidx.media3.datasource.ResolvingDataSource.Factory::class.java.name, factoryKind)
        assertNotNull("fresh audio tap from production bootstrap", field("speechTap"))
        assertNotNull("offset renderer from production bootstrap", field("offsetRenderersFactory"))
        assertNotNull("metadata receiver registered by onCreate", field("metadataUpdateReceiver"))
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19ReceiverShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvMediaPipelineBootstrapTest : TvPhase15LiveOriginalTest() {
    private var playerKind: String? = null
    private var source: Any? = null
    override fun bootstrapPayload(): JSONObject {
        TvPhase19ReceiverShadow.resetFixture()
        TvPhase19ReceiverShadow.onMetadataRegister = onMetadataRegister@ {
            val player = field("player")
            playerKind = player?.javaClass?.name
            if (playerKind != "androidx.media3.exoplayer.ExoPlayerImpl") return@onMetadataRegister
            source = TvPlayerOriginalAccess.field(TvPlayerOriginalAccess.field(player!!, "mediaSourceFactory")!!, "dataSourceFactory")
        }
        return super.bootstrapPayload()
    }
    @org.junit.After fun clearBootstrapObserver() { TvPhase19ReceiverShadow.resetFixture() }
    @Test fun iptvBootstrapInstallsRecordingPipelineBeforeMetadataRegistration() {
        assertEquals("androidx.media3.exoplayer.ExoPlayerImpl", playerKind)
        assertTrue("real IPTV tee built before receiver", source is RecordingDataSource.Factory)
        assertNotNull(field("speechTap")); assertNotNull(field("metadataUpdateReceiver"))
    }
}
