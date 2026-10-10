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
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvShuffleCallbackSupersessionCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun staleBlankFailureCannotFailNewerPendingAttempt() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(); val old=request("requestTorrentStream")
        set("showShuffleGeneration",1); var retries=0; val newer=attemptWith(unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),newer)
        replyDirect(null,old); pump(); assertSame(newer,field("pendingShufflePlayback")); assertEquals(false,attemptField(newer,"finished")); assertEquals(0,retries); assertEquals(0,field("currentIndex"))
    }

    @Test fun resolveAcceptsNonemptyWhitespaceUrl() {
        payload(p2Item(url="")); call("resolveAndPlay",arrayOf(intType,PlaybackItem::class.java),0,item()); replyDirect(mapOf("url" to "   ")); assertEquals("   ",item().url); assertEquals("   ",probe.media.single().localConfiguration!!.uri.toString()); assertNull(lastToast())
    }

    @Test fun shuffleResolveAcceptsNonemptyWhitespaceUrl() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(); replyDirect(mapOf("url" to "   ")); assertEquals(1,field("currentIndex")); assertEquals("   ",item(1).url); assertTrue(probe.media.isEmpty()); assertEquals(2,requests("requestTorrentStream").size)
        replyDirect(mapOf("url" to "https://shuffle.invalid/second-resolution.mp4")); assertEquals("https://shuffle.invalid/second-resolution.mp4",probe.media.single().localConfiguration!!.uri.toString())
    }

    @Test fun manualWholeShowSelectionClearsSleepBeforeOpening() {
        payload(p2Item(season=1,episode=1),p2Item(season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("sleepStopLatched",true); assertTrue(shuffle()); assertFalse(field("sleepStopLatched") as Boolean); assertEquals(1,probe.media.size); assertEquals(1,field("currentIndex"))
    }
}
