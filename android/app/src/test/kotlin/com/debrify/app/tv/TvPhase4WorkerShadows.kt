package com.debrify.app.tv

import com.debrify.app.util.AlignResult
import com.debrify.app.util.CueSpan
import com.debrify.app.util.FeatureSegment
import com.debrify.app.util.SubtitleCue
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Scripted workers retain the production Default/IO → Main dispatch and cancellation. */
class TvPhase4Response<T>(val value: T, val failure: Throwable? = null) {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val returned = CountDownLatch(1)
    @Volatile var thread: Thread? = null
    @Volatile var arguments: List<Any?> = emptyList()
    fun answer(vararg args: Any?): T {
        arguments = args.toList(); thread = Thread.currentThread(); entered.countDown()
        try {
            check(release.await(10, TimeUnit.SECONDS)) { "test did not release phase-4 worker" }
            failure?.let { throw it }
            return value
        } finally { returned.countDown() }
    }
}

@Implements(className = "com.debrify.app.util.SubtitleAligner", isInAndroidSdk = false)
class TvPhase4AlignerShadow {
    @Implementation fun alignTiered(segments: List<FeatureSegment>, cues: List<CueSpan>): AlignResult =
        take().answer("tiered", segments, cues)
    @Implementation fun align(segments: List<FeatureSegment>, cues: List<CueSpan>, searchMs: Double,
        minAudioMs: Double, minCueOverlapFrames: Int, minCues: Int, minZPeak: Double,
        minPsr: Double, scales: DoubleArray): AlignResult =
        take().answer("verify", segments, cues, searchMs, minAudioMs, minCueOverlapFrames, minCues, minZPeak, minPsr, scales)
    private fun take() = responses.poll() ?: error("unplanned phase-4 alignment")
    companion object { val responses = LinkedBlockingQueue<TvPhase4Response<AlignResult>>() }
}

@Implements(className = "com.debrify.app.tv.SpeechFeatureTap", isInAndroidSdk = false)
class TvPhase4AudioTapShadow {
    @Implementation fun snapshot(): List<FeatureSegment> = segments
    @Implementation fun anchoredDurationMs(): Double = anchoredMs
    @Implementation fun hasRecentAudio(windowMs: Long): Boolean { recentWindow = windowMs; return recent }
    companion object {
        var segments = listOf(FeatureSegment(0, 1000, 1000, FloatArray(60), FloatArray(60)))
        var anchoredMs = 60_000.0
        var recent = true
        var recentWindow: Long? = null
    }
}

@Implements(className = "com.debrify.app.util.SubtitleCueCache", isInAndroidSdk = false)
class TvPhase4CueFetchShadow {
    @Implementation fun fetch(url: String): List<SubtitleCue> =
        (responses.poll() ?: error("unplanned phase-4 cue fetch: $url")).answer(url)
    companion object { val responses = LinkedBlockingQueue<TvPhase4Response<List<SubtitleCue>>>() }
}
