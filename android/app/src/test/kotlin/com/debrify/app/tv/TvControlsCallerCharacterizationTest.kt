package com.debrify.app.tv

import android.view.View
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsCallerCharacterizationTest : TvPhase16OriginalTest() {
    override val skin = TvControlsSkin.OTT
    @Test fun metadataWritesTrimmedShowNameAndRefreshesTheDockWithoutRevealingTopTitle() {
        val item = p2Item("Episode", season = 2, episode = 7)
        set("payload", PlaybackPayload("release.mkv", null, "series", mutableListOf(item), 0, null)); set("currentIndex", 0)
        set("ottShowName", "Old"); runOriginal("updateTitle", item)
        call("handleMetadataUpdate", arrayOf(stringType, stringType, stringType, stringType), null, null, null, "  New Show  ")
        assertEquals("New Show", field("ottShowName")); assertEquals("New Show — Episode", tv("ottIdentityTitle").text.toString())
        assertEquals(View.GONE, v("titleContainer").visibility)
    }
    @Test fun endedPlaybackShowsTheNextItemThenHidesAndPlaysItAtFifteenHundredMs() {
        val first = p2Item("First"); val second = p2Item("Second").copy(index = 1, id = "second")
        val model = PlaybackPayload("Collection", null, "collection", mutableListOf(first, second), 0, null)
        set("payload", model); set("currentIndex", 0); set("maxStableDurationMs", 100_000L); set("lastRealPositionMs", 100_000L)
        set("isIptvMode", false); set("isAutoAdvancing", false)
        (field("playbackListener") as Player.Listener).onPlaybackStateChanged(Player.STATE_ENDED)
        assertEquals("Second", tv("nextText").text.toString()); assertEquals(View.VISIBLE, v("nextOverlay").visibility)
        step(1499); assertEquals(0, field("currentIndex")); step(1)
        assertEquals(1, field("currentIndex")); assertEquals("Second", tv("titleView").text.toString()); step(161)
        assertEquals(View.GONE, v("nextOverlay").visibility)
    }
    @Test fun stremioGuideHostUsesTheOriginalResolvingAndLoadingOverlay() {
        val guide = field("stremioTvGuideController")!!; val host = TvPlayerOriginalAccess.field(guide, "host") as TvStremioTvGuideController.Host
        host.fadeInNextOverlay(); assertEquals(View.VISIBLE, v("nextOverlay").visibility)
        host.hideNextOverlay(); step(161); assertEquals(View.GONE, v("nextOverlay").visibility)
        showDock(); assertTrue(field("controlsMenuVisible") as Boolean)
        host.hideControlsMenu(); assertFalse(field("controlsMenuVisible") as Boolean)
    }
    @Test fun noDurationClassicFallbackAndDefaultConfirmGuardsDoNotSeek() {
        probe.duration = 0; set("ottSkinInstalled", false)
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource(0, "Source", "hash", null, streamType = "torrent", sizeBytes = 1, seeders = 0, source = null, quality = "1080p"))
        showDock(); step(301); v("stremioSourceBadge").visibility = View.VISIBLE; enterScrub(); assertTrue(v("stremioSourceBadge").hasFocus())
        sources.clear(); enterScrub(); assertTrue(v("pauseButton").hasFocus()); assertFalse(field("cinemaSeekMode") as Boolean)
        set("cinemaSeekMode", true); set("seekbarVisible", true); set("player", null); probe.events.clear()
        runOriginal("confirmCinemaSeek"); runOriginal("confirmSeekPosition"); assertTrue(probe.events.isEmpty())
        assertTrue(field("cinemaSeekMode") as Boolean); assertTrue(field("seekbarVisible") as Boolean)
        originalPlayer(); set("cinemaSeekMode", false); set("seekbarVisible", false)
    }
    @Test fun workerMetadataStoresShowNameBeforeItsQueuedIdentityPublication() {
        val item = p2Item("Episode", season = 2, episode = 7)
        set("payload", PlaybackPayload("release", null, "series", mutableListOf(item), 0, null)); set("ottShowName", "Old")
        runOriginal("updateTitle", item); val failures = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val worker = Thread { try { call("handleMetadataUpdate", arrayOf(stringType, stringType, stringType, stringType), null, null, null, " New ") } catch (error: Throwable) { failures.set(error) } }
        worker.start(); worker.join(5000); assertFalse(worker.isAlive); assertNull(failures.get())
        assertEquals("New", field("ottShowName")); assertEquals("Old — Episode", tv("ottIdentityTitle").text.toString())
        step(0); assertEquals("New — Episode", tv("ottIdentityTitle").text.toString())
    }
    @Test fun stremioPayloadReplacementClearsThePreviousShowName() {
        set("ottShowName", "Previous Show")
        call("replacePayloadWithStremioTvItem", arrayOf(StremioTvGuideChannel::class.java, mapType, stringType, stringType), p2Guide(), emptyMap<String, Any>(), "Film", "https://phase16.invalid/film")
        assertNull(field("ottShowName")); assertEquals("Film", (field("payload") as PlaybackPayload).items.single().title)
    }
    @Test fun directPlayItemAndPikPakRetryBothRefreshTitleThroughTheirActualCallers() {
        val item = p2Item("Direct title").copy(mimeType = "video/mp4")
        set("payload", PlaybackPayload("Film", null, "single", mutableListOf(item), 0, null))
        defaultCall("playItem", arrayOf(intType, boolType, boolType, TvPlayerOriginalAccess.type("AndroidTvTorrentPlayerActivity\$ShufflePlaybackAttempt")), 14, 0, false, false, null); assertEquals("Direct title", tv("titleView").text.toString())
        runOriginal("playPikPakVideoWithRetry", item.copy(title = "PikPak title"))
        assertEquals("PikPak title", tv("titleView").text.toString()); assertEquals(View.GONE, v("titleContainer").visibility)
    }

    @Test fun absentIdentityTitleReturnsWithoutPublishingMetadataOrChangingTheCache() {
        val original = field("ottIdentityTitle"); set("ottIdentityTitle", null)
        tv("ottIdentitySubtitle").text = "unchanged"; set("dockTagsCacheKey", "unchanged")
        val result = runCatching { runOriginal("updateOttIdentity") }
        assertTrue(result.isSuccess); assertEquals("unchanged", tv("ottIdentitySubtitle").text.toString()); assertEquals("unchanged", field("dockTagsCacheKey"))
        set("ottIdentityTitle", original)
    }

}
