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
internal class TvPlaybackStateEdgesCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun bufferingFeedbackIsHiddenBeforeMedia() {
        (field("bufferingIndicator") as View).visibility=View.VISIBLE; (field("bufferingIndicator") as View).animate().setDuration(999L); probe.onEvent={ if(it.startsWith("media:")) assertEquals(200L,(field("bufferingIndicator") as View).animate().duration) }; play(); assertEquals(1,probe.media.size)
    }

    @Test fun selectedEpisodeRecomputesPreviousControl() {
        payload(p2Item(season=1,episode=1),p2Item(season=1,episode=2).copy(index=1),type="series"); play(1); assertEquals(View.VISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun mergedPlayerClearsReadinessBeforeSourceInstall() {
        val a=attemptWith(); set("pendingShufflePlayback",a); readiness().onReady(); payload(p2Item().copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4")); probe.onEvent={ if(it=="merged") { assertFalse(readiness().canSelect(true)); assertEquals(true,attemptField(a,"mediaStarted")) } }; directItem(); assertEquals(listOf("merged","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun pikpakClearsPreviousCuesBeforeInstallingMedia() {
        val subtitles=androidx.media3.ui.SubtitleView(activity); set("subtitleOverlay",subtitles); subtitles.setCues(listOf(androidx.media3.common.text.Cue.Builder().setText("Outgoing").build())); probe.onEvent={ if(it.startsWith("media:")) assertTrue(org.robolectric.util.ReflectionHelpers.getField<List<androidx.media3.common.text.Cue>>(subtitles,"cues").isEmpty()) }; pikpak(); assertEquals(1,probe.media.size)
    }

    @Test fun pikpakNullPlayerPreservesOutgoingCues() {
        val subtitles=androidx.media3.ui.SubtitleView(activity); set("subtitleOverlay",subtitles); val cues=listOf(androidx.media3.common.text.Cue.Builder().setText("Outgoing").build()); subtitles.setCues(cues); set("player",null); pikpak(); assertEquals(cues,org.robolectric.util.ReflectionHelpers.getField<List<androidx.media3.common.text.Cue>>(subtitles,"cues"))
    }

    @Test fun pikpakStartCancelsOldRetryIdAndShowsColdStorageLoop() {
        val id=field("pikPakRetryId") as Int; (field("pikPakReactivationIndicator") as View).visibility=View.VISIBLE; set("isPikPakRetrying",true); set("pikPakRetryCount",4); payload(p2Item(provider="PikPak")); pikpak(); assertEquals(id+1,field("pikPakRetryId")); assertFalse(field("isPikPakRetrying") as Boolean); assertEquals(View.GONE,(field("pikPakReactivationIndicator") as View).visibility); assertEquals(0,field("pikPakRetryCount")); assertTrue(logs().any { it.contains("PikPak: Playback attempt 1/") })
    }

    @Test fun mergedFactoriesFollowCrossProtocolRedirects() {
        val initial=call("buildMergedSourceOrNull",arrayOf(PlaybackItem::class.java,androidx.media3.common.MediaItem::class.java),p2Item().copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4"),androidx.media3.common.MediaItem.fromUri("https://muxed.invalid/a.mp4"))!!
         assertRedirect(initial); assertRedirect(merged("https://video.invalid/v.mp4","https://audio.invalid/a.mp4")!!)
    }

    @Test fun trioNotifiesRowsClearsRetryAndFetchesCaptions() {
        val channel=p2Guide().apply { isCurrent=true; isSwitchingChannel=true }; val channels=field("stremioTvChannels") as MutableList<StremioTvGuideChannel>; channels.add(channel)
         val adapter=TvPlayerOriginalAccess.field(field("stremioTvGuideController")!!,"stremioTvChannelAdapter") as? androidx.recyclerview.widget.RecyclerView.Adapter<*>
         set("manualSubtitleImdbId","ttold"); set("subtitleAddonDiscoveryReady",false); set("injectedSubtitles",listOf(com.debrify.app.subtitle.StremioSubtitle("s","https://subtitles.invalid/a.srt","eng","English","Injected","injected"))); val retry=field("pikPakRetryId") as Int
         call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),channel,emptyMap<String,Any>(),"https://tv.invalid/a.mp4","Next",false)
         assertNull(field("manualSubtitleImdbId")); assertEquals(retry+1,field("pikPakRetryId")); assertEquals(1,(field("stremioSubtitles") as List<*>).size); assertFalse(channel.isSwitchingChannel)
    }

    @Test fun sourceTrioRefreshesQualityAfterRetainedSources() {
        (field("stremioSourceBadgeText") as TextView).text="Outgoing"; call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),p2Guide(),emptyMap<String,Any>(),"https://tv.invalid/a.mp4","Next",false); assertEquals("Sources",(field("stremioSourceBadgeText") as TextView).text.toString())
    }

    @Test fun trioUpdatesGuideChannelMetadataBeforeTitle() {
        val channel=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),channel,mapOf("nowPlaying" to mapOf("title" to "New programme","poster" to "new poster"),"contentSeason" to 2,"contentEpisode" to 4),"https://tv.invalid/a.mp4","Next",false); assertEquals("New programme",channel.nowPlayingTitle); assertEquals("new poster",item().artwork); assertEquals(2,item().season); assertEquals(4,item().episode)
    }
    private fun assertRedirect(source: Any) {
        val children=org.robolectric.util.ReflectionHelpers.getField<Array<androidx.media3.exoplayer.source.MediaSource>>(source,"mediaSources")
        val factory=org.robolectric.util.ReflectionHelpers.getField<Any>(children[0],"dataSourceFactory")
        val http=org.robolectric.util.ReflectionHelpers.getField<Any>(factory,"baseDataSourceFactory")
        assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(http,"allowCrossProtocolRedirects"))
    }
}
