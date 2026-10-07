package com.debrify.app.tv

import com.debrify.app.util.SubtitleSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase4AlignerShadow::class, TvPhase4AudioTapShadow::class, TvPhase4CueFetchShadow::class],
    instrumentedPackages = ["com.debrify.app.util.SubtitleAligner", "com.debrify.app.tv.SpeechFeatureTap", "com.debrify.app.util.SubtitleCueCache"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPhase4PrerequisiteTest : TvPhase4OriginalTest() {
    @Test fun blockableAlignerUsesRealDefaultMainAndTapAcrossTwentyRuns() {
        setup(); active()
        repeat(20) {
            val (response, job) = beginAlign()
            assertEquals("tiered", response.arguments[0]); assertSame(TvPhase4AudioTapShadow.segments, response.arguments[1])
            assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity)); assertEquals(true, field("autoSyncRunning"))
            complete(response, job)
            assertEquals("Main publishes alignment offset", 1200L, SubtitleSettings.getSyncOffsetMs(activity))
            assertEquals(false, field("autoSyncRunning")); SubtitleSettings.resetSyncOffset()
        }
    }
    @Test fun blockedAlignmentRejectsReplacementSubtitle() {
        setup(); active(); val (response, job) = beginAlign()
        set("activeExternalSubtitleUrl", "https://phase4.invalid/replacement.srt")
        complete(response, job)
        assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity))
        assertNull("superseded alignment cannot publish result", field("autoSyncResultUrl"))
        assertEquals("SUBTITLE CHANGED — TRY AGAIN", (field("autoSyncPillLabel") as android.widget.TextView).text.toString())
    }
    @Test fun destroyCancelsBlockedAlignmentBeforePublication() {
        setup(created = true); active(); val (response, job) = beginAlign()
        lifecycle.pause().stop().destroy()
        assertTrue("destroy cancels borrowed subtitle scope", (field("subtitleScope") as CoroutineScope).coroutineContext[Job]!!.isCancelled)
        complete(response, job)
        assertTrue(job.isCancelled); assertNull(field("autoSyncResultUrl"))
    }
    @Test fun uncachedFetchUsesRealIoMainAndImmediateTickerAcrossTwentyLoads() {
        setup()
        repeat(20) { index ->
            val source = "https://phase4.invalid/$index.srt"; val (response, job) = beginFetch(source)
            assertEquals(listOf(source), response.arguments)
            assertEquals(false, field("externalSubtitleActive")); assertTrue(text().isEmpty())
            complete(response, job)
            assertEquals(true, field("externalSubtitleActive")); assertEquals(source, field("activeExternalSubtitleUrl"))
            assertEquals(listOf("first"), text())
            invoke("stopExternalSubtitleRendering")
        }
    }
    @Test fun failedUncachedFetchKeepsWorkingSubtitleAndRestoresSelection() {
        setup(); active(); set("currentStremioSubtitleIndex", 2); invoke("startExternalSubtitleTicker")
        val source = "https://phase4.invalid/failure.srt"; val (response, job) = beginFetch(source, emptyList())
        set("currentStremioSubtitleIndex", 3); complete(response, job)
        assertEquals(2, field("currentStremioSubtitleIndex")); assertEquals(url, field("activeExternalSubtitleUrl"))
        assertEquals(listOf("first"), text()); assertTrue((field("failedSubtitleUrls") as Set<*>).contains(source))
    }
    @Test fun supersededUncachedFetchCannotReplaceNewerLoad() {
        setup(); val (old, oldJob) = beginFetch(); val source = "https://phase4.invalid/new.srt"
        val (new, newJob) = beginFetch(source); complete(new, newJob); complete(old, oldJob)
        assertEquals("stale token rejects old cues", source, field("activeExternalSubtitleUrl"))
    }
    @Test fun destroyDuringUncachedFetchPreventsMainPublication() {
        setup(created = true); val (response, job) = beginFetch()
        lifecycle.pause().stop().destroy(); complete(response, job)
        assertTrue(job.isCancelled); assertEquals(false, field("externalSubtitleActive"))
        assertNull(field("activeExternalSubtitleUrl")); assertTrue(text().isEmpty())
    }
}
