package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase18DataSourceFactoryFailure::class])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackMergeFallbackCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun initialMergeFactoryFailureUsesMuxedFallback() {
        payload(p2Item("Muxed fallback").copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4"))
        try { directItem() } catch (failure: Exception) { fail("merge construction failure must fall back: $failure") }
        assertEquals(listOf("media:https://example.test/a","prepare","playWhenReady:true","play"),probe.events); assertEquals("Muxed fallback",probe.media.single().mediaMetadata.title.toString()); assertTrue(logs().any { it.contains("merge build failed, using muxed fallback") })
    }

    @Test fun qualitySwitchFactoryFailureReturnsNullForSingleUrlFallback() {
        var result:Any?="unset"
        try { result=merged("https://video.invalid/v.mp4","https://audio.invalid/a.mp4") } catch (failure: Exception) { fail("quality merge construction failure must return fallback: $failure") }
        assertNull(result); assertTrue(logs().any { it.contains("switch merge build failed, using single url") })
    }
}

/** Scoped constructor failure; playback still executes the real original fallback. */
@org.robolectric.annotation.Implements(androidx.media3.datasource.DefaultDataSource.Factory::class, isInAndroidSdk = false)
internal class TvPhase18DataSourceFactoryFailure {
    @org.robolectric.annotation.Implementation
    fun __constructor__(context: android.content.Context, upstream: androidx.media3.datasource.DataSource.Factory) {
        throw IllegalStateException("phase18 bounded merge-factory failure")
    }
}
