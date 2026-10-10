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
internal class TvPlaybackStartEffectsCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun playItemDropsOldSourceFeedbackBeforeStartingMedia() {
        call("watchSourceSwitchOutcome",arrayOf(intType),1); val listener=field("sourceSwitchReadyListener")
        assertNotNull(listener); play(); assertNull(field("sourceSwitchReadyListener")); assertNull(field("sourceSwitchTimeoutRunnable")); assertTrue(probe.removed.any { it===listener })
    }

    @Test fun playlistHighlightDirect() {
        val adapter=PlaylistAdapter(model().items,onItemClick={}); set("playlistAdapter",adapter); assertEquals(-1,adapter.getActiveItemPosition()); directItem(); assertTrue(adapter.getActiveItemPosition()>=0)
    }

    @Test fun titleRefreshDirect() {
        (field("titleView") as TextView).text="Outgoing"; directItem(); assertEquals("Film",title())
    }

    @Test fun playlistHighlightPikPak() {
        val adapter=PlaylistAdapter(model().items,onItemClick={}); set("playlistAdapter",adapter); assertEquals(-1,adapter.getActiveItemPosition()); pikpak(); assertTrue(adapter.getActiveItemPosition()>=0)
    }

    @Test fun titleRefreshPikPak() {
        (field("titleView") as TextView).text="Outgoing"; pikpak(); assertEquals("Film",title())
    }

    @Test fun wholeShowHidesUpNextBeforeFetch() {
        wholeShow(ShuffleEpisode(1,2)); set("upNextVisible",true); shuffle(); assertFalse(field("upNextVisible") as Boolean); assertEquals(1,requests("requestEpisodeFetch").size)
    }

    @Test fun manualResolveFailureRestoresBeforeStartupAndKeepsReason() {
        call("beginManualSourceCandidate",arrayOf(intType),1); val snapshot=field("manualSourceSwitchSnapshot"); assertNotNull(snapshot)
        model().items[0]=item().copy(url=""); call("resolveAndPlay",arrayOf(intType,PlaybackItem::class.java),0,item()); replyDirect(null)
        assertNull(field("manualSourceSwitchSnapshot")); assertNull(field("manualSourceSwitchIndex")); assertEquals("https://example.test/a",item().url); assertNull(lastToast())
        assertTrue(org.robolectric.shadows.ShadowLog.getLogs().any { it.msg.contains("event=manual_candidate_reject") && it.msg.contains("reason=initial-resolve") })
    }

    @Test fun startupResolveFailureExhaustsGateBeforeToastAndKeepsReason() {
        val cursor=StartupFailoverCursor(0,1); cursor.beginInitial(2); set("startupFailoverCursor",cursor); set("currentStremioSourceIndex",0)
        payload(p2Item(url="")); call("resolveAndPlay",arrayOf(intType,PlaybackItem::class.java),0,item()); replyDirect(null)
        assertTrue(field("startupSourcesExhausted") as Boolean); assertTrue(activity.isFinishing); assertEquals("No playable source could be started",lastToast())
        assertTrue(org.robolectric.shadows.ShadowLog.getLogs().any { it.msg.contains("reason=initial-resolve") })
    }

    @Test fun sourceMapRefreshesQualityBadge() {
        (field("stremioSourceBadgeText") as TextView).text="old"; call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to listOf(mapOf("name" to "New")))); assertEquals("Sources",(field("stremioSourceBadgeText") as TextView).text.toString())
    }

    @Test fun unifiedMenuRandomChoiceUsesResetAndManualStart() {
        payload(p2Item(),p2Item("Target").copy(index=1,resumePositionMs=55L)); set("continuousShuffleEnabled",true)
        val menu=call("umPlaybackModel",arrayOf(listType,intType),emptyList<UnifiedMenuController.Row>(),2) as UnifiedMenuController.Model
        menu.col3[0].onOk?.invoke(); assertFalse(field("continuousShuffleEnabled") as Boolean); assertEquals(1,field("showShuffleGeneration")); assertEquals(1,field("currentIndex")); assertEquals(0L,field("pendingSeekMs"))
    }

    @Test fun alreadyFinishedFailureDoesNotPostUnavailable() {
        var retries=0; val a=attemptWith(finished=true,unavailable={retries++}); set("pendingShufflePlayback",a); assertEquals(true,call("failShufflePlayback",emptyArray())); pump(); assertEquals(0,retries); assertNull(field("pendingShufflePlayback"))
    }
}
