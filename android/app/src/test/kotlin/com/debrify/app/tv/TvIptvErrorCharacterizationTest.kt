package com.debrify.app.tv

import android.net.Uri
import android.view.View
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackException
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlaybackException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvErrorCharacterizationTest : TvPhase17OriginalTest() {
    private fun auth(code: Int)=error(HttpDataSource.InvalidResponseCodeException(code,"status",null,emptyMap(),DataSpec(Uri.parse(original)),byteArrayOf()))
    private fun authSurrender(code: Int) {
        tune();quiet();probe.events.clear();deliver(auth(code));assertTrue(recovery().isSurrendered);assertTrue(tuning().isEmpty())
        assertEquals("Stream refused (expired or blocked) — press play to retry",(reconnectPill()).text.toString())
    }
    @Test fun unauthorizedReplySurrendersInsteadOfRetuning()=authSurrender(401)
    @Test fun forbiddenReplySurrendersInsteadOfRetuning()=authSurrender(403)
    @Test fun missingChannelReplySurrendersInsteadOfRetuning()=authSurrender(404)
    @Test fun wrappedSniffFailureRetriesTheSameUriWithAnHlsMime() {
        tune(url="http://h/no-extension");quiet();probe.mediaItems.clear();deliver(sniff())
        assertEquals("sniff correction dispatches exactly one replacement",1,probe.mediaItems.size)
        assertEquals("application/x-mpegURL",probe.mediaItems.single().localConfiguration!!.mimeType);assertTrue(forced().contains("http://h/no-extension"))
    }
    @Test fun supersededNullPlayerErrorDoesNotPoisonTheNewUrl() {
        tune();quiet();probe.events.clear();probe.error=null;listener().onPlayerError(sniff());advance(0)
        assertTrue(forced().isEmpty());assertTrue(tuning().isEmpty());assertFalse(recovery().isSurrendered)
    }
    @Test fun activeTrialClaimsSniffFailureBeforeTheGenericHlsRetry() {
        begin();quiet();deliver(sniff());assertNull(trial());assertTrue(forced().isEmpty());assertTrue(failed().contains(original));assertEquals(original,field("currentIptvStreamUrl"))
    }
    @Test fun acceptedTwinAuthRevokesPreferenceAndRestoresBeforeSurrender() {
        iptv(channel(original));pref()[original]=twin;set("currentIptvStreamUrl",twin);deliver(auth(403))
        assertFalse(pref().containsKey(original));assertTrue(failed().contains(original));assertEquals(original,field("currentIptvStreamUrl"));assertFalse(recovery().isSurrendered)
    }
    @Test fun behindLiveWindowUsesDefaultPositionPreparePlayInOrder() {
        tune();quiet();probe.events.clear();deliver(error(code=PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW))
        assertEquals(listOf("seek-default","prepare","play"),probe.events)
    }
    @Test fun rendererFormatExplainsMpeg2WhileTheDecoderGetsOneRetry() {
        tune();quiet();probe.events.clear()
        val e=ExoPlaybackException.createForRenderer(IOException("decoder"),"codec",0,Format.Builder().setSampleMimeType("video/mpeg2").build(),C.FORMAT_UNSUPPORTED_TYPE,false,PlaybackException.ERROR_CODE_DECODER_INIT_FAILED)
        deliver(e);advance(0);quiet();assertEquals(1,tuning().size)
        assertEquals("This device has no MPEG-2 video decoder, so this file can't play here. It will play on the phone app.",ShadowToast.getTextOfLatestToast())
        advance(301);deliver(e);assertTrue(recovery().isSurrendered);assertEquals("Stream lost — press play to retry",(reconnectPill()).text.toString())
        assertEquals(View.VISIBLE,(reconnectPill()).visibility)
    }
}
