package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import com.debrify.app.util.FeatureSegment
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Sits on the player's decoded-PCM path and reduces every 32 ms of audio to
 * two floats (speech-band RMS + broadband RMS) for [SubtitleAligner].
 *
 * This is the whole reason auto-sync v2 can answer in under a second where v1
 * took ages: v1 re-downloaded and re-decoded stream audio on demand — minutes
 * of interleaved video bytes for minutes of audio — while this taps PCM the
 * player has ALREADY decoded for playout, so analysis costs nothing extra and
 * the data is simply there when asked for. The per-sample work is two biquads
 * and two accumulators; it is deliberately allocation-free in steady state
 * because [handleBuffer] runs on ExoPlayer's playback thread.
 *
 * ── Media-time anchoring ──
 * The sink hands us PCM with no timestamps, so each contiguous run (a
 * "segment", opened at every [flush]) must learn the media time of its first
 * sample. Two stamps cooperate, both on the main thread:
 *
 *  * [onSegmentOpened] fires a main-thread poll of `player.currentPosition`.
 *    A flush happens on seek/start, while the player is buffering — position
 *    is frozen at the seek target until playout resumes, so the poll reads the
 *    right anchor even though it runs a few ms later.
 *  * [notifyDiscontinuity] (Player.Listener) re-stamps a young segment whose
 *    anchor disagrees with the reported position — the belt for rapid
 *    double-seeks, where the poll can read the *second* seek's target for the
 *    first seek's (tiny, soon-flushed) segment.
 *
 * Segments that never get a believable anchor are simply never used: the
 * aligner drops unanchored and sub-2s segments, so a bad stamp costs coverage,
 * never correctness.
 *
 * If the audio path is passthrough (bitstream to a receiver) the processor is
 * never fed; [hasRecentAudio] then reports false and the feature declines
 * honestly instead of analyzing nothing.
 */
@UnstableApi
class SpeechFeatureTap(
    /** Runs [action] on the main thread (activity supplies a Handler post). */
    private val mainPost: (action: () -> Unit) -> Unit,
    /** Reads the player's current media position, main thread only. */
    private val positionMs: () -> Long,
) : TeeAudioProcessor.AudioBufferSink {

    val processor = TeeAudioProcessor(this)

    companion object {
        private const val FRAME_MS = 32.0
        private const val UNANCHORED = Long.MIN_VALUE

        /** History cap; beyond it the oldest segment is dropped whole. */
        private const val MAX_TOTAL_FRAMES = 120_000 // ~64 min

        /**
         * A segment closes itself after this many frames (~10 min) and a
         * continuation opens. Without this an uninterrupted film enforced the
         * cap only at the next flush — history grew past it and every array
         * doubling copied minutes of features on ExoPlayer's playback thread.
         * Rollover bounds both: arrays never exceed ten minutes, and the trim
         * runs at every boundary, so total history overshoots the cap by at
         * most one chunk.
         */
        private const val ROLLOVER_FRAMES = 18_750

        /** A discontinuity re-stamps only a segment younger than this. */
        private const val RESTAMP_MAX_MS = 3_000.0
        private const val RESTAMP_DISAGREE_MS = 500L
    }

    private val lock = Any()
    private val closed = ArrayList<Segment>()
    private var current: Segment? = null

    @Volatile
    private var lastBufferUptimeMs = 0L

    /** True when PCM has flowed within [windowMs] — false on passthrough. */
    fun hasRecentAudio(windowMs: Long): Boolean =
        android.os.SystemClock.uptimeMillis() - lastBufferUptimeMs < windowMs

    /** Snapshot for the aligner (background thread safe). */
    fun snapshot(): List<FeatureSegment> = synchronized(lock) {
        (closed.asSequence() + sequenceOfNotNull(current)).map { it.toFeatureSegment() }.toList()
    }

    /**
     * Total anchored audio on hand, without copying anything — the auto-sync
     * ladder polls this every few seconds to decide when an attempt is worth
     * making, so it must stay O(segments), not O(frames).
     */
    fun anchoredDurationMs(): Double = synchronized(lock) {
        (closed.asSequence() + sequenceOfNotNull(current))
            .filter { it.anchorMs != Long.MIN_VALUE }
            .sumOf { it.frameCount * it.frameDurationMs }
    }

    /** Content changed (episode/source/channel) — history is meaningless. */
    fun reset() = synchronized(lock) {
        closed.clear()
        current = null
    }

    /** Player.Listener.onPositionDiscontinuity — main thread. */
    fun notifyDiscontinuity(newPositionMs: Long) = synchronized(lock) {
        val seg = current ?: return
        val ageMs = seg.frameCount * seg.frameDurationMs
        if (seg.anchorMs == UNANCHORED) {
            seg.anchorMs = newPositionMs
        } else if (ageMs < RESTAMP_MAX_MS &&
            kotlin.math.abs(seg.anchorMs - newPositionMs) > RESTAMP_DISAGREE_MS
        ) {
            seg.anchorMs = newPositionMs
        }
    }

    // ── AudioBufferSink (playback thread) ───────────────────────────────────

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        val supported = encoding == C.ENCODING_PCM_16BIT || encoding == C.ENCODING_PCM_FLOAT
        val seg: Segment?
        synchronized(lock) {
            current?.let { if (it.frameCount > 0) closed.add(it) }
            // Null before trimming: trimLocked counts closed + current, and the
            // segment just moved INTO closed — leaving the reference standing
            // would double-count it, and one flush past the half-cap mark
            // would evict the entire history the aligner was waiting for.
            current = null
            trimLocked()
            seg = if (supported && sampleRateHz > 0 && channelCount > 0) {
                Segment(sampleRateHz, channelCount, encoding)
            } else null
            current = seg
        }
        // Anchor poll — see class doc. Position is frozen while buffering.
        if (seg != null) mainPost {
            synchronized(lock) {
                if (seg === current && seg.anchorMs == UNANCHORED) {
                    seg.anchorMs = positionMs()
                }
            }
        }
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        lastBufferUptimeMs = android.os.SystemClock.uptimeMillis()
        val seg = synchronized(lock) { current } ?: return
        seg.consume(buffer)
        if (seg.frameCount >= ROLLOVER_FRAMES) rollover(seg)
    }

    /**
     * Close a full segment mid-playback and continue into a fresh one. The
     * continuation's anchor is DERIVED from the exact sample count — never
     * polled from the player, whose position lags the processing thread by
     * the sink's buffer depth. An unanchored segment continues unanchored.
     */
    private fun rollover(seg: Segment) = synchronized(lock) {
        if (seg !== current) return // raced with a flush; that path handled it
        closed.add(seg)
        current = Segment(seg.sampleRate, seg.channels, seg.encoding).also {
            it.anchorMs = if (seg.anchorMs == UNANCHORED) UNANCHORED
            else seg.anchorMs + (seg.frameCount * seg.frameDurationMs).roundToLong()
        }
        trimLocked()
    }

    private fun trimLocked() {
        var total = closed.sumOf { it.frameCount } + (current?.frameCount ?: 0)
        while (total > MAX_TOTAL_FRAMES && closed.isNotEmpty()) {
            total -= closed.removeAt(0).frameCount
        }
    }

    private fun <T : Any> sequenceOfNotNull(v: T?): Sequence<T> =
        if (v == null) emptySequence() else sequenceOf(v)

    // ── One contiguous PCM run ──────────────────────────────────────────────

    private class Segment(val sampleRate: Int, val channels: Int, val encoding: Int) {
        @Volatile
        var anchorMs: Long = UNANCHORED

        val frameSamples: Int = ((sampleRate * FRAME_MS) / 1000.0).toInt().coerceAtLeast(1)
        val frameDurationMs: Double get() = frameSamples * 1000.0 / sampleRate

        // Speech band ≈ 300–3400 Hz: Butterworth high-pass + low-pass biquads.
        private val hp = Biquad.highPass(300.0, sampleRate)
        private val lp = Biquad.lowPass(3400.0, sampleRate)

        private var band = FloatArray(4096)
        private var broad = FloatArray(4096)
        var frameCount = 0
            private set

        private var accBand = 0.0
        private var accBroad = 0.0
        private var accN = 0

        /**
         * Growable without ArrayList boxing. Synchronized against
         * [toFeatureSegment]: the snapshot copies while the playback thread
         * appends and occasionally swaps in a grown array — one uncontended
         * monitor per 32 ms frame is noise, a torn read of a mid-grow array
         * is not. Per-sample work stays lock-free; only the frame commit locks.
         */
        private fun push(b: Float, r: Float) = synchronized(this) {
            if (frameCount == band.size) {
                band = band.copyOf(band.size * 2)
                broad = broad.copyOf(broad.size * 2)
            }
            band[frameCount] = b
            broad[frameCount] = r
            frameCount++
        }

        fun consume(buffer: ByteBuffer) {
            val buf = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            when (encoding) {
                C.ENCODING_PCM_16BIT -> {
                    val inv = 1f / (32768f * channels)
                    while (buf.remaining() >= 2 * channels) {
                        var sum = 0
                        for (c in 0 until channels) sum += buf.short.toInt()
                        sample(sum * inv)
                    }
                }
                C.ENCODING_PCM_FLOAT -> {
                    val inv = 1f / channels
                    while (buf.remaining() >= 4 * channels) {
                        var sum = 0f
                        for (c in 0 until channels) sum += buf.float
                        sample(sum * inv)
                    }
                }
            }
        }

        private fun sample(mono: Float) {
            val filtered = lp.process(hp.process(mono.toDouble()))
            accBand += filtered * filtered
            accBroad += mono.toDouble() * mono
            accN++
            if (accN >= frameSamples) {
                push(
                    sqrt(accBand / accN).toFloat(),
                    sqrt(accBroad / accN).toFloat(),
                )
                accBand = 0.0
                accBroad = 0.0
                accN = 0
            }
        }

        fun toFeatureSegment(): FeatureSegment = synchronized(this) {
            FeatureSegment(
                anchorMs = anchorMs,
                sampleRate = sampleRate,
                frameSamples = frameSamples,
                band = band.copyOf(frameCount),
                broadband = broad.copyOf(frameCount),
            )
        }
    }

    /** RBJ-cookbook biquad, direct form I, Butterworth Q. */
    private class Biquad(
        private val b0: Double, private val b1: Double, private val b2: Double,
        private val a1: Double, private val a2: Double,
    ) {
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        fun process(x: Double): Double {
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }

        companion object {
            private const val Q = 0.70710678 // Butterworth

            fun lowPass(freq: Double, rate: Int): Biquad {
                val w = 2 * PI * min(freq, rate / 2.5) / rate
                val alpha = sin(w) / (2 * Q)
                val cw = cos(w)
                val a0 = 1 + alpha
                return Biquad(
                    (1 - cw) / 2 / a0, (1 - cw) / a0, (1 - cw) / 2 / a0,
                    -2 * cw / a0, (1 - alpha) / a0,
                )
            }

            fun highPass(freq: Double, rate: Int): Biquad {
                val w = 2 * PI * min(freq, rate / 2.5) / rate
                val alpha = sin(w) / (2 * Q)
                val cw = cos(w)
                val a0 = 1 + alpha
                return Biquad(
                    (1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0,
                    -2 * cw / a0, (1 - alpha) / a0,
                )
            }
        }
    }
}
