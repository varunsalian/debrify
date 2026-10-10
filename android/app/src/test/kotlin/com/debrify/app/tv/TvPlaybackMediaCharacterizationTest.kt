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
internal class TvPlaybackMediaCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun pikpakRouteProviderCase() {
        payload(p2Item(url="https://example.test/a",provider="pIkPaK")); start(); assertEquals(false,probe.events.contains("playWhenReady:true")); assertEquals(1,probe.media.size)
    }

    @Test fun pikpakRouteUrlSubstring() {
        payload(p2Item(url="https://mypikpak.com/a",provider=null)); start(); assertEquals(false,probe.events.contains("playWhenReady:true")); assertEquals(1,probe.media.size)
    }

    @Test fun pikpakRouteUrlCase() {
        payload(p2Item(url="https://MYPIKPAK.COM/a",provider=null)); start(); assertEquals(true,probe.events.contains("playWhenReady:true")); assertEquals(1,probe.media.size)
    }

    @Test fun pikpakRouteOrdinary() {
        payload(p2Item(url="https://example.test/a",provider="Other")); start(); assertEquals(true,probe.events.contains("playWhenReady:true")); assertEquals(1,probe.media.size)
    }

    @Test fun descriptionDirectItem() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description="Item description")),0,null)); directItem()
         assertEquals("Item description",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionPikPakItem() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description="Item description")),0,null)); pikpak()
         assertEquals("Item description",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionDirectSubtitle() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description=null)),0,null)); directItem()
         assertEquals("Payload subtitle",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionPikPakSubtitle() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description=null)),0,null)); pikpak()
         assertEquals("Payload subtitle",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionDirectTitle() {
        set("payload",PlaybackPayload("Payload title",null,"single",mutableListOf(p2Item().copy(description=null)),0,null)); directItem()
         assertEquals("Payload title",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionPikPakTitle() {
        set("payload",PlaybackPayload("Payload title",null,"single",mutableListOf(p2Item().copy(description=null)),0,null)); pikpak()
         assertEquals("Payload title",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionDirectEmptyItem() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description="")),0,null)); directItem()
         assertEquals("",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun descriptionPikPakEmptyItem() {
        set("payload",PlaybackPayload("Payload title","Payload subtitle","single",mutableListOf(p2Item().copy(description="")),0,null)); pikpak()
         assertEquals("",probe.media.single().mediaMetadata.description.toString()); assertEquals("Film",probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun mediaReadinessAndAttemptBeforePlayerDirect() {
        val a=attemptWith(); set("pendingShufflePlayback",a); readiness().onReady(); probe.onEvent={ if (it.startsWith("media:")) { assertFalse(readiness().canSelect(true)); assertEquals(true,attemptField(a,"mediaStarted")) } }
         directItem(); assertEquals(1,probe.media.size)
    }

    @Test fun mediaResetsSubtitleDirect() {
        set("manualSubtitleImdbId","tt99"); set("userManuallySelectedSubtitle",true); directItem(); assertNull(field("manualSubtitleImdbId"))
    }

    @Test fun mediaRestartsProgressTickerDirect() {
        val h=field("progressHandler") as android.os.Handler; val r=field("progressRunnable") as Runnable; h.removeCallbacks(r)
         directItem(); assertTrue(TvPlaylistUiQueue.pending(h,r))
    }

    @Test fun mediaFetchesAddonSubtitleDirect() {
        payload(p2Item(season=2,episode=3),type="series",imdb="tt12"); set("subtitleAddonDiscoveryReady",false); directItem()
         assertTrue("production fetch discovers subtitle availability for newly installed item",field("subtitleAddonDiscoveryReady") as Boolean)
    }

    @Test fun mediaReadinessAndAttemptBeforePlayerPikPak() {
        val a=attemptWith(); set("pendingShufflePlayback",a); readiness().onReady(); probe.onEvent={ if (it.startsWith("media:")) { assertFalse(readiness().canSelect(true)); assertEquals(true,attemptField(a,"mediaStarted")) } }
         pikpak(); assertEquals(1,probe.media.size)
    }

    @Test fun mediaResetsSubtitlePikPak() {
        set("manualSubtitleImdbId","tt99"); set("userManuallySelectedSubtitle",true); pikpak(); assertNull(field("manualSubtitleImdbId"))
    }

    @Test fun mediaRestartsProgressTickerPikPak() {
        val h=field("progressHandler") as android.os.Handler; val r=field("progressRunnable") as Runnable; h.removeCallbacks(r)
         pikpak(); assertTrue(TvPlaylistUiQueue.pending(h,r))
    }

    @Test fun mediaFetchesAddonSubtitlePikPak() {
        payload(p2Item(season=2,episode=3),type="series",imdb="tt12"); set("subtitleAddonDiscoveryReady",false); pikpak()
         assertTrue("production fetch discovers subtitle availability for newly installed item",field("subtitleAddonDiscoveryReady") as Boolean)
    }

    @Test fun directInstallsExplicitMimeAndPlayOrder() {
        payload(p2Item(season=2,episode=3).copy(mimeType="video/mp4")); directItem(); assertEquals("Film",probe.media.single().mediaMetadata.title.toString()); assertEquals("video/mp4",probe.media.single().localConfiguration!!.mimeType); assertEquals("S02E03",probe.media.single().mediaMetadata.artist.toString()); assertEquals(listOf("media:https://example.test/a","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun pikpakKeepsMimeUnsetAndNeverMergesOrSetsPlayIntent() {
        payload(p2Item(provider="PikPak").copy(mimeType="video/mp4",hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4")); pikpak(); assertNull(probe.media.single().localConfiguration!!.mimeType); assertEquals(listOf("media:https://example.test/a","prepare","play"),probe.events); assertEquals(1,field("pikPakRetryId")); assertEquals(0,field("pikPakRetryCount")); assertFalse(field("isPikPakRetrying") as Boolean)
    }

    @Test fun pikpakNullPlayerCancelsRetryBeforeLeavingCues() {
        set("player",null); set("isPikPakRetrying",true); set("pikPakRetryCount",4); val id=field("pikPakRetryId") as Int; pikpak(); assertEquals(id+1,field("pikPakRetryId")); assertEquals(0,field("pikPakRetryCount")); assertFalse(field("isPikPakRetrying") as Boolean); assertTrue(probe.media.isEmpty())
    }

    @Test fun mergeMissinghdVideoUrlNull() {
        val v=p2Item().copy(hdVideoUrl=null,audioUrl="https://audio.invalid/a.mp4")
         payload(v); directItem(); assertEquals(1,probe.media.size); assertFalse(probe.events.contains("merged"))
    }

    @Test fun mergeMissinghdVideoUrlEmpty() {
        val v=p2Item().copy(hdVideoUrl="",audioUrl="https://audio.invalid/a.mp4")
         payload(v); directItem(); assertEquals(1,probe.media.size); assertFalse(probe.events.contains("merged"))
    }

    @Test fun mergeMissingaudioUrlNull() {
        val v=p2Item().copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl=null)
         payload(v); directItem(); assertEquals(1,probe.media.size); assertFalse(probe.events.contains("merged"))
    }

    @Test fun mergeMissingaudioUrlEmpty() {
        val v=p2Item().copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="")
         payload(v); directItem(); assertEquals(1,probe.media.size); assertFalse(probe.events.contains("merged"))
    }

    @Test fun mergeChildUrisMetadataAndToleranceFlags() {
        val incoming=p2Item("Merged",season=2,episode=3).copy(hdVideoUrl="https://video.invalid/v.mp4",audioUrl="https://audio.invalid/a.mp4",mimeType="video/mp4",description="Merged description")
         val source=call("buildMergedSourceOrNull",arrayOf(PlaybackItem::class.java,androidx.media3.common.MediaItem::class.java),incoming,androidx.media3.common.MediaItem.Builder().setUri(incoming.url).setMimeType(incoming.mimeType).setMediaMetadata(androidx.media3.common.MediaMetadata.Builder().setTitle(incoming.title).build()).build())!!
         val children=org.robolectric.util.ReflectionHelpers.getField<Array<androidx.media3.exoplayer.source.MediaSource>>(source,"mediaSources")
         assertEquals(listOf(incoming.hdVideoUrl,incoming.audioUrl),children.map { it.mediaItem.localConfiguration!!.uri.toString() }); assertEquals("Merged",children[0].mediaItem.mediaMetadata.title.toString()); assertEquals("video/mp4",children[0].mediaItem.localConfiguration!!.mimeType)
         assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(source,"adjustPeriodTimeOffsets")); assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(source,"clipDurations"))
    }

    @Test fun switchMergeKeepsOrderedUrisAndClipFlags() {
        val source=merged("https://video.invalid/v.mp4","https://audio.invalid/a.mp4")!!
         val children=org.robolectric.util.ReflectionHelpers.getField<Array<androidx.media3.exoplayer.source.MediaSource>>(source,"mediaSources")
         assertEquals(listOf("https://video.invalid/v.mp4","https://audio.invalid/a.mp4"),children.map { it.mediaItem.localConfiguration!!.uri.toString() }); assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(source,"adjustPeriodTimeOffsets")); assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(source,"clipDurations"))
    }
}
