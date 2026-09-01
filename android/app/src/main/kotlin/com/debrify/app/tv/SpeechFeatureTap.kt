package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import com.debrify.app.util.FeatureSegment
import com.debrify.app.util.FrameVad
import com.debrify.app.util.SpeechFrameExtractor
import com.debrify.app.util.TenVad
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.roundToLong

/**
 * Sits on the player's decoded-PCM path and reduces every 32 ms of audio to
 * a few floats (speech-band RMS, broadband RMS and — when the ten-vad
 * library loads — a neural speech probability) for [SubtitleAligner].
 *
 * This is the whole reason auto-sync v2 can answer in under a second where v1
 * took ages: v1 re-downloaded and re-decoded stream audio on demand — minutes
 * of interleaved video bytes for minutes of audio — while this taps PCM the
 * player has ALREADY decoded for playout, so analysis costs nothing extra and
 * the data is simply there when asked for.
 *
 * ── Threading ──
 * [handleBuffer] runs on ExoPlayer's playback thread and does only the
 * cheapest possible thing: downmix to mono into a pooled float array and hand
 * it to the feature worker. Filters, resampling and the VAD run on that
 * worker; it processes chunks in arrival order, so a segment's frames are
 * always appended in sample order. The VAD costs ~6% of one core on the
 * weakest supported box; if the worker ever falls behind by more than
 * [MAX_QUEUED_CHUNKS] the overflowing chunk is dropped and its segment marked
 * unanchored (invisible to the aligner) rather than letting the queue grow.
 *
 * ── Media-time anchoring ──
 * The sink hands us PCM with no timestamps, so each contiguous run (a
 * "segment", opened at every [flush]) must learn the media time of its first
 * sample. Two stamps cooperate, both on the main thread:
 *
 *  * [flush] fires a main-thread poll of `player.currentPosition`. A flush
 *    happens on seek/start, while the player is buffering — position is
 *    frozen at the seek target until playout resumes, so the poll reads the
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
    /** Detector factory; the default loads ten-vad and yields null without it. */
    vadFactory: () -> FrameVad? = { TenVad.create() },
) : TeeAudioProcessor.AudioBufferSink {

    val processor = TeeAudioProcessor(this)

    companion object {
        private const val UNANCHORED = Long.MIN_VALUE

        /** History cap; beyond it the oldest segment is dropped whole. */
        private const val MAX_TOTAL_FRAMES = 120_000 // ~64 min

        /**
         * A segment closes itself after this many frames (~10 min) and a
         * continuation opens. Without this an uninterrupted film enforced the
         * cap only at the next flush — history grew past it and every array
         * doubling copied minutes of features. Rollover bounds both: arrays
         * never exceed ten minutes, and the trim runs at every boundary, so
         * total history overshoots the cap by at most one chunk.
         */
        private const val ROLLOVER_FRAMES = 18_750

        /** A discontinuity re-stamps only a segment younger than this. */
        private const val RESTAMP_MAX_MS = 3_000.0
        private const val RESTAMP_DISAGREE_MS = 500L

        /** Worker backlog bound (~5 s of 20 ms buffers). */
        private const val MAX_QUEUED_CHUNKS = 256
        private const val POOL_CHUNKS = 64
        private const val CHUNK_CAPACITY = 8_192
    }

    private val lock = Any()
    private val closed = ArrayList<Segment>()
    private var current: Segment? = null

    private val vad: FrameVad? = vadFactory()

    /** "ten-vad 1.0.0" or the load failure, for the AutoSync log line. */
    val detectorDescription: String
        get() = if (vad != null) TenVad.availability else "energy features (${TenVad.availability})"

    @Volatile
    private var lastBufferUptimeMs = 0L

    @Volatile
    private var released = false

    private class Chunk(val segment: Segment?, val samples: FloatArray, val count: Int)

    private val poison = Chunk(null, FloatArray(0), 0)
    private val queue = LinkedBlockingQueue<Chunk>()
    private val pool = ArrayBlockingQueue<FloatArray>(POOL_CHUNKS)
    private var droppedChunks = 0

    private val worker = Thread({ workerLoop() }, "autosync-features").apply {
        isDaemon = true
        priority = Thread.NORM_PRIORITY - 1
        start()
    }

    /** True when PCM has flowed within [windowMs] — false on passthrough. */
    fun hasRecentAudio(windowMs: Long): Boolean =
        android.os.SystemClock.uptimeMillis() - lastBufferUptimeMs < windowMs

    /** Snapshot for the aligner (background thread safe). */
    fun snapshot(): List<FeatureSegment> = synchronized(lock) {
        (closed.asSequence() + sequenceOfNotNull(current)).map { it.toFeatureSegment() }.toList()
    }

    /**
     * Total anchored audio on hand, without copying anything — the auto-sync
     * ladder polls this every couple of seconds to decide when an attempt is
     * worth making, so it must stay O(segments), not O(frames).
     */
    fun anchoredDurationMs(): Double = synchronized(lock) {
        (closed.asSequence() + sequenceOfNotNull(current))
            .filter { it.anchorMs != UNANCHORED }
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
        if (seg.broken) return // made invisible on purpose; never re-stamped
        val ageMs = seg.frameCount * seg.frameDurationMs
        if (seg.anchorMs == UNANCHORED) {
            seg.anchorMs = newPositionMs
        } else if (ageMs < RESTAMP_MAX_MS &&
            kotlin.math.abs(seg.anchorMs - newPositionMs) > RESTAMP_DISAGREE_MS
        ) {
            seg.anchorMs = newPositionMs
        }
    }

    /**
     * Stop the worker and free the detector. The player that fed this tap is
     * being released; a fresh tap is built with the next player.
     */
    fun release() {
        if (released) return
        released = true
        queue.offer(poison)
    }

    // ── AudioBufferSink (playback thread) ───────────────────────────────────

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        val supported = encoding == C.ENCODING_PCM_16BIT || encoding == C.ENCODING_PCM_FLOAT
        val seg: Segment?
        synchronized(lock) {
            current?.let { if (it.frameCount > 0 || it.pending) closed.add(it) }
            // Null before trimming: trimLocked counts closed + current, and the
            // segment just moved INTO closed — leaving the reference standing
            // would double-count it, and one flush past the half-cap mark
            // would evict the entire history the aligner was waiting for.
            current = null
            trimLocked()
            seg = if (supported && sampleRateHz > 0 && channelCount > 0) {
                Segment(sampleRateHz, channelCount, encoding, vad)
            } else null
            current = seg
        }
        // Anchor poll — see class doc. Position is frozen while buffering.
        if (seg != null) mainPost {
            synchronized(lock) {
                if (seg === current && !seg.broken && seg.anchorMs == UNANCHORED) {
                    seg.anchorMs = positionMs()
                }
            }
        }
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        lastBufferUptimeMs = android.os.SystemClock.uptimeMillis()
        if (released) return
        val seg = synchronized(lock) { current } ?: return
        val buf = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val channels = seg.channels
        while (buf.hasRemaining()) {
            val array = pool.poll() ?: FloatArray(CHUNK_CAPACITY)
            var n = 0
            when (seg.encoding) {
                C.ENCODING_PCM_16BIT -> {
                    val inv = 1f / (32768f * channels)
                    while (n < array.size && buf.remaining() >= 2 * channels) {
                        var sum = 0
                        for (c in 0 until channels) sum += buf.short.toInt()
                        array[n++] = sum * inv
                    }
                }
                C.ENCODING_PCM_FLOAT -> {
                    val inv = 1f / channels
                    while (n < array.size && buf.remaining() >= 4 * channels) {
                        var sum = 0f
                        for (c in 0 until channels) sum += buf.float
                        array[n++] = sum * inv
                    }
                }
                else -> return
            }
            if (n == 0) {
                pool.offer(array)
                return // trailing partial sample: nothing more to read
            }
            if (queue.size >= MAX_QUEUED_CHUNKS) {
                // The worker is hopelessly behind (thermal throttle, a stalled
                // VAD). Dropping samples would silently time-warp this run's
                // frame grid, so the run is made invisible instead.
                pool.offer(array)
                markBroken(seg)
                droppedChunks++
                if (droppedChunks == 1) {
                    android.util.Log.w("AutoSync", "feature worker backlog — dropping audio, segment unanchored")
                }
                return
            }
            seg.pending = true
            queue.offer(Chunk(seg, array, n))
        }
    }

    // ── Feature worker ──────────────────────────────────────────────────────

    private fun workerLoop() {
        try {
            while (true) {
                val chunk = queue.take()
                if (chunk === poison) break
                try {
                    processChunk(chunk)
                } catch (e: Throwable) {
                    // Feature extraction must never take the player down. A
                    // broken run is made invisible; playback is untouched.
                    android.util.Log.e("AutoSync", "feature worker failed", e)
                    chunk.segment?.let { markBroken(it) }
                }
                pool.offer(chunk.samples)
            }
        } finally {
            vad?.close()
            queue.clear()
        }
    }

    private fun processChunk(chunk: Chunk) {
        var seg = chunk.segment ?: return
        // A rollover may already have redirected this run to a continuation.
        while (true) seg = seg.successor ?: break
        val samples = chunk.samples
        for (i in 0 until chunk.count) {
            if (seg.sample(samples[i]) && seg.frameCount >= ROLLOVER_FRAMES) {
                seg = rollover(seg)
            }
        }
        seg.pending = false
    }

    /**
     * Close a full segment mid-run and continue into a fresh one. The
     * continuation's anchor is DERIVED from the exact sample count — never
     * polled from the player, whose position lags the processing thread by
     * the sink's buffer depth. An unanchored segment continues unanchored.
     */
    private fun rollover(seg: Segment): Segment = synchronized(lock) {
        val next = Segment(seg.sampleRate, seg.channels, seg.encoding, vad).also {
            it.broken = seg.broken
            it.anchorMs = if (seg.anchorMs == UNANCHORED) UNANCHORED
            else seg.anchorMs + (seg.frameCount * seg.frameDurationMs).roundToLong()
        }
        seg.successor = next
        when {
            seg === current -> { closed.add(seg); current = next }
            else -> {
                // Already flushed into history: keep order by inserting the
                // continuation right after its parent. If the parent was
                // trimmed away, the continuation is history too.
                val index = closed.indexOf(seg)
                if (index >= 0) closed.add(index + 1, next) else next.anchorMs = UNANCHORED
            }
        }
        trimLocked()
        next
    }

    /**
     * A run whose frame grid can no longer be trusted (dropped audio, a
     * worker failure) is made permanently invisible: it and every
     * continuation it rolled into — the samples in question may have landed
     * anywhere down that chain — lose their anchor, and nothing (not the
     * flush poll, not a discontinuity) may ever stamp one back.
     */
    private fun markBroken(seg: Segment) = synchronized(lock) {
        var s: Segment? = seg
        while (s != null) {
            s.broken = true
            s.anchorMs = UNANCHORED
            s = s.successor
        }
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

    private class Segment(val sampleRate: Int, val channels: Int, val encoding: Int, vad: FrameVad?) {
        @Volatile
        var anchorMs: Long = UNANCHORED

        /** Set by the playback thread when chunks are queued, cleared by the worker. */
        @Volatile
        var pending = false

        /** Continuation opened by a rollover; queued chunks follow it. */
        @Volatile
        var successor: Segment? = null

        /** Frame grid no longer trustworthy; stays unanchored forever. */
        @Volatile
        var broken = false

        private val extractor = SpeechFrameExtractor(sampleRate, vad)
        val frameSamples: Int get() = extractor.frameSamples
        val frameDurationMs: Double get() = frameSamples * 1000.0 / sampleRate

        private var band = FloatArray(4096)
        private var broad = FloatArray(4096)
        private var vadProb = FloatArray(4096)

        @Volatile
        var frameCount = 0
            private set

        /** Worker thread only. Returns true when a frame was committed. */
        fun sample(mono: Float): Boolean {
            if (!extractor.sample(mono)) return false
            push(extractor.frameBand, extractor.frameBroad, extractor.frameVad)
            return true
        }

        /**
         * Growable without ArrayList boxing. Synchronized against
         * [toFeatureSegment]: the snapshot copies while the worker appends and
         * occasionally swaps in a grown array — one uncontended monitor per
         * 32 ms frame is noise, a torn read of a mid-grow array is not.
         */
        private fun push(b: Float, r: Float, v: Float) = synchronized(this) {
            if (frameCount == band.size) {
                band = band.copyOf(band.size * 2)
                broad = broad.copyOf(broad.size * 2)
                vadProb = vadProb.copyOf(vadProb.size * 2)
            }
            band[frameCount] = b
            broad[frameCount] = r
            vadProb[frameCount] = v
            frameCount++
        }

        fun toFeatureSegment(): FeatureSegment = synchronized(this) {
            FeatureSegment(
                anchorMs = anchorMs,
                sampleRate = sampleRate,
                frameSamples = frameSamples,
                band = band.copyOf(frameCount),
                broadband = broad.copyOf(frameCount),
                vad = if (extractor.vadValid) vadProb.copyOf(frameCount) else null,
            )
        }
    }
}
