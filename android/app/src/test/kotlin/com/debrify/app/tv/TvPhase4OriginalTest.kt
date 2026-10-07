package com.debrify.app.tv

import android.os.Handler
import android.view.View
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.SubtitleView
import com.debrify.app.subtitle.StremioSubtitle
import com.debrify.app.util.AlignResult
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import com.debrify.app.util.SubtitleSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.After
import org.junit.Assert.*
import java.util.concurrent.TimeUnit

@org.robolectric.annotation.Config(sdk = [28],
    shadows = [TvPhase4AlignerShadow::class, TvPhase4AudioTapShadow::class, TvPhase4CueFetchShadow::class],
    instrumentedPackages = ["com.debrify.app.util.SubtitleAligner", "com.debrify.app.tv.SpeechFeatureTap", "com.debrify.app.util.SubtitleCueCache"])
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase4OriginalTest : TvPhase3OriginalTest() {
    protected val workerErrors = java.util.concurrent.ConcurrentLinkedQueue<Throwable>()
    @org.junit.Before fun boundedAnimationFrames() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
    }
    protected val pending = mutableListOf<TvPhase4Response<*>>()
    protected val cues = listOf(SubtitleCue(0, 2000, "first"), SubtitleCue(1000, 3000, "second"))
    protected val url = "https://phase4.invalid/first.srt"
    protected lateinit var probe: PlayerProbe
    protected lateinit var overlay: SubtitleView
    protected fun setup(created: Boolean = false) {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        if (created) lifecycle.create().start().resume()
        // Observe uncaught worker failures without altering its Main dispatcher
        // or SupervisorJob; assertion failures remain JUnit evidence.
        val originalScope = field("subtitleScope") as CoroutineScope
        set("subtitleScope", CoroutineScope(originalScope.coroutineContext +
            kotlinx.coroutines.CoroutineExceptionHandler { _, error -> workerErrors.add(error) }))
        val root = bindViews()
        overlay = SubtitleView(activity); root.addView(overlay); set("subtitleOverlay", overlay)
        set("subtitleControlsLift", SubtitleControlsLiftController(overlay, 24))
        set("trackSelector", DefaultTrackSelector(activity))
        probe = PlayerProbe(); set("player", probe.player)
        SubtitleSettings.resetSyncOffset()
        SubtitleSettings.setActiveSubtitleIdentityProvider(activity) { invoke("currentSubtitleIdentity") as String? }
        clearCache()
        TvPhase4AudioTapShadow.segments = listOf(com.debrify.app.util.FeatureSegment(0, 1000, 1000, FloatArray(60), FloatArray(60)))
        TvPhase4AudioTapShadow.anchoredMs = 60_000.0; TvPhase4AudioTapShadow.recent = true
        TvPhase4AudioTapShadow.recentWindow = null
        set("speechTap", SpeechFeatureTap({ it() }, { probe.position }))
    }
    @Suppress("UNCHECKED_CAST") protected fun cache() = TvPlayerOriginalAccess.field(SubtitleCueCache, "cache") as MutableMap<String, List<SubtitleCue>>
    private fun clearCache() { cache().clear() }
    protected fun active(source: String = url) {
        cache()[source] = cues; set("activeExternalSubtitleUrl", source)
        set("externalSubtitleActive", true); set("externalSubtitleCues", cues)
    }
    protected fun subtitle(source: String = url, label: String = "English") = StremioSubtitle("id", source, "eng", label, "Addon", "addon")
    protected fun pref(enabled: Boolean) = activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
        .putBoolean("flutter.subtitle_auto_sync_enabled", enabled).commit()
    protected fun jobs() = (field("subtitleScope") as CoroutineScope).coroutineContext[Job]!!.children.toSet()
    protected fun job(previous: Set<Job> = emptySet()) = (jobs() - previous).single()
    protected fun <T> entered(response: TvPhase4Response<T>): TvPhase4Response<T> {
        idle(); assertTrue("worker entered deterministic seam; errors=$workerErrors", response.entered.await(5, TimeUnit.SECONDS))
        assertNotEquals("worker runs off Main", Thread.currentThread(), response.thread)
        return response
    }
    protected fun beginAlign(result: AlignResult = AlignResult.Synced(1200, 1.0, 60),
        failure: Throwable? = null, auto: Boolean = false): Pair<TvPhase4Response<AlignResult>, Job> {
        val previous = jobs()
        val response = TvPhase4Response(result, failure); pending.add(response)
        TvPhase4AlignerShadow.responses.add(response); invoke("runSubtitleAutoSync", auto)
        entered(response); return response to job(previous)
    }
    protected fun beginFetch(source: String = url, parsed: List<SubtitleCue> = cues): Pair<TvPhase4Response<List<SubtitleCue>>, Job> {
        val previous = jobs()
        assertNull("uncached prerequisite", SubtitleCueCache.get(source))
        val response = TvPhase4Response(parsed); pending.add(response)
        TvPhase4CueFetchShadow.responses.add(response); invoke("loadStremioSubtitle", subtitle(source))
        entered(response); return response to job(previous)
    }
    protected fun complete(response: TvPhase4Response<*>, job: Job) {
        response.release.countDown()
        assertTrue("worker returned", response.returned.await(5, TimeUnit.SECONDS))
        settle(job)
    }
    protected fun settle(job: Job) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!job.isCompleted && System.nanoTime() < deadline) { idle(); Thread.yield() }
        assertTrue("production Main continuation settled", job.isCompleted); idle()
    }
    @After fun settlePhase4Workers() {
        pending.forEach { it.release.countDown() }
        pending.filter { it.entered.count == 0L }.forEach { assertTrue(it.returned.await(5, TimeUnit.SECONDS)) }
        val scope = field("subtitleScope") as CoroutineScope
        val children = scope.coroutineContext[Job]!!.children.toList()
        children.forEach { it.cancel(); settle(it) }
        scope.coroutineContext[Job]!!.cancel()
        (field("externalSubtitleHandler") as Handler).removeCallbacksAndMessages(null)
        (field("subtitleSeekHandler") as Handler).removeCallbacksAndMessages(null)
        (field("autoSyncPillRing") as? AutoSyncRingView)?.setPulsing(false)
        (field("linePickerOverlay") as? SubtitleLinePickerController)?.hide()
        (field("syncOverlay") as? SubtitleSyncOverlayController)?.hide()
        (field("trackSelector") as? DefaultTrackSelector)?.release()
        TvPhase4AlignerShadow.responses.clear(); TvPhase4CueFetchShadow.responses.clear()
        SubtitleSettings.clearActiveSubtitleIdentityProvider(activity); clearCache()
    }
    protected fun label() = (field("autoSyncPillLabel") as android.widget.TextView).text.toString()
    protected fun verifyBegin(result: AlignResult = AlignResult.Synced(0, 1.0, 60), failure: Throwable? = null): Pair<TvPhase4Response<AlignResult>, Job> {
        val previous = jobs()
        val response = TvPhase4Response(result, failure); pending.add(response); TvPhase4AlignerShadow.responses.add(response)
        invoke("maybeRunAutoSyncVerify"); entered(response); return response to job(previous)
    }
    @Suppress("UNCHECKED_CAST") protected fun text() =
        (TvPlayerOriginalAccess.field(overlay, "cues") as List<androidx.media3.common.text.Cue>).map { it.text.toString() }
}
