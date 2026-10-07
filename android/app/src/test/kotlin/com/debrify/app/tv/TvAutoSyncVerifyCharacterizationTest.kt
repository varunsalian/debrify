package com.debrify.app.tv

import com.debrify.app.util.AlignResult
import com.debrify.app.util.FeatureSegment
import com.debrify.app.util.CueSpan
import com.debrify.app.util.SubtitleAligner
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvAutoSyncVerifyCharacterizationTest : TvPhase4OriginalTest() {
    private fun ready() { setup(); active(); probe.position = 400_000; SubtitleSettings.setSyncOffsetMs(activity, 1000); set("autoSyncAppliedOffsetMs", 1000L) }
    @Test fun verifyCentersCuesAndNarrowArgumentsThenEscalatesAfterTwoConfidentMisses() {
        ready()
        repeat(3) { index ->
            val (response, job) = verifyBegin(AlignResult.NoMatch(60))
            @Suppress("UNCHECKED_CAST") val centered = response.arguments[2] as List<CueSpan>
            assertEquals(listOf(1000L, 2000L), centered.map { it.startMs }); assertEquals(listOf(3000L, 4000L), centered.map { it.endMs })
            assertEquals(if (index < 2) 10_000.0 else SubtitleAligner.Tuning.SEARCH_MS, response.arguments[3])
            assertEquals(if (index < 2) 25_000.0 else SubtitleAligner.Tuning.MIN_AUDIO_MS, response.arguments[4])
            assertEquals(if (index < 2) SubtitleAligner.Tuning.NARROW_MIN_CUE_OVERLAP_FRAMES else SubtitleAligner.Tuning.MIN_CUE_OVERLAP_FRAMES, response.arguments[5])
            assertEquals(if (index < 2) SubtitleAligner.Tuning.NARROW_MIN_CUES else SubtitleAligner.Tuning.MIN_CUES, response.arguments[6])
            assertEquals(if (index < 2) SubtitleAligner.Tuning.NARROW_MIN_ZPEAK else SubtitleAligner.Tuning.MIN_ZPEAK, response.arguments[7])
            assertEquals(if (index < 2) SubtitleAligner.Tuning.NARROW_MIN_PSR else SubtitleAligner.Tuning.MIN_PSR, response.arguments[8])
            assertArrayEquals(if (index < 2) doubleArrayOf(1.0) else SubtitleAligner.Tuning.SCALES, response.arguments[9] as DoubleArray, 0.0)
            complete(response, job); assertEquals(index + 1, field("autoSyncVerifyMisses"))
        }
    }
    @Test fun verifyFiltersUnanchoredOldAndFutureAudioWithInclusiveWindowBoundaries() {
        ready()
        fun segment(anchor: Long, seconds: Int = 10) = FeatureSegment(anchor, 1000, 1000, FloatArray(seconds), FloatArray(seconds))
        val keep = listOf(segment(30_000), segment(410_000), segment(200_000))
        TvPhase4AudioTapShadow.segments = listOf(segment(Long.MIN_VALUE), segment(29_999), segment(410_001)) + keep
        val (response, job) = verifyBegin(); assertEquals(keep, response.arguments[1]); complete(response, job)
    }
    @Test fun verifyRequiresThirtySecondsAndPlayingExternalSubtitleWithAppliedOffset() {
        ready(); TvPhase4AudioTapShadow.segments = listOf(FeatureSegment(100_000, 1000, 1, FloatArray(29_999), FloatArray(29_999)))
        invoke("maybeRunAutoSyncVerify"); assertTrue(jobs().isEmpty())
        TvPhase4AudioTapShadow.segments = listOf(FeatureSegment(100_000, 1000, 1, FloatArray(30_000), FloatArray(30_000)))
        probe.playing = false; invoke("maybeRunAutoSyncVerify"); assertTrue(jobs().isEmpty()); probe.playing = true
        val (response, job) = verifyBegin(); complete(response, job)
        set("externalSubtitleActive", false); invoke("maybeRunAutoSyncVerify"); assertTrue(jobs().isEmpty())
        set("externalSubtitleActive", true); set("autoSyncRunning", true); invoke("maybeRunAutoSyncVerify"); assertTrue(jobs().isEmpty())
    }
    @Test fun fourHundredMillisecondResidualIsConfirmedAndLargerEitherSignIsApplied() {
        ready()
        for (residual in listOf(400L, -400L, 401L, -401L)) {
            set("autoSyncVerifyMisses", 2); val applied = field("autoSyncAppliedOffsetMs") as Long
            val (response, job) = verifyBegin(AlignResult.Synced(residual, 1.0, 60)); complete(response, job)
            val expected = if (kotlin.math.abs(residual) > 400) applied + residual else applied
            assertEquals("residual=$residual", expected, field("autoSyncAppliedOffsetMs")); assertEquals(expected, SubtitleSettings.getSyncOffsetMs(activity))
            assertEquals(0, field("autoSyncVerifyMisses"))
        }
        assertEquals("↻  RE-SYNCED", label()); assertEquals(url, field("autoSyncResultUrl"))
    }
    @Test fun userOffsetChangeCancelsVerifyPermanentlyAndResetsMisses() {
        ready(); pref(true); invoke("scheduleAutoSyncVerify"); set("autoSyncVerifyMisses", 2)
        SubtitleSettings.setSyncOffsetMs(activity, 999); invoke("maybeRunAutoSyncVerify")
        assertNull(field("autoSyncVerifyTick")); assertEquals(0, field("autoSyncVerifyMisses")); assertTrue(jobs().isEmpty())
    }
    @Test fun pendingVerifyRejectsReplacementUrlAndChangedAppliedOffset() {
        ready(); val (first, firstJob) = verifyBegin(AlignResult.Synced(1000, 1.0, 60))
        set("activeExternalSubtitleUrl", "replacement"); complete(first, firstJob)
        assertEquals(1000L, field("autoSyncAppliedOffsetMs")); assertNull(field("autoSyncResultUrl"))
        set("activeExternalSubtitleUrl", url); val (second, secondJob) = verifyBegin(AlignResult.Synced(1000, 1.0, 60))
        set("autoSyncAppliedOffsetMs", 500L); complete(second, secondJob)
        assertEquals(500L, field("autoSyncAppliedOffsetMs")); assertNull(field("autoSyncResultUrl"))
    }
    @Test fun verifyExceptionCountsAsMissButErrorEscapesAndFinallyClearsRunning() {
        ready(); val (first, firstJob) = verifyBegin(failure = IllegalStateException("scripted")); complete(first, firstJob)
        assertEquals(1, field("autoSyncVerifyMisses")); assertTrue(workerErrors.isEmpty())
        val error = OutOfMemoryError("scripted verify OOM"); val (second, secondJob) = verifyBegin(failure = error); complete(second, secondJob)
        assertEquals(1, workerErrors.size); assertEquals(OutOfMemoryError::class.java, workerErrors.single().javaClass)
        assertEquals("scripted verify OOM", workerErrors.single().message); assertEquals(1, field("autoSyncVerifyMisses"))
        assertEquals(false, field("autoSyncRunning"))
    }
    @Test fun driftOrInsufficientAudioDoNotEscalateOnSilence() {
        ready(); set("autoSyncVerifyMisses", 1)
        for (result in listOf(AlignResult.Drift(1.04, 0), AlignResult.NotEnoughAudio(20))) {
            val (response, job) = verifyBegin(result); complete(response, job)
            assertEquals(1, field("autoSyncVerifyMisses")); assertEquals(1000L, field("autoSyncAppliedOffsetMs"))
        }
    }
}
