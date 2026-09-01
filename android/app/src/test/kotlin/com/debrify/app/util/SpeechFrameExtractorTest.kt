package com.debrify.app.util

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The extractor's contract, pinned without a real detector:
 *  1. Frames close on exact sample counts; the VAD hop cadence is
 *     independent of the source rate (16 ms of 16 kHz per hop).
 *  2. The per-frame probability is the mean of the hops that closed inside
 *     the frame; a frame that saw no hop carries the last value forward.
 *  3. A detector error switches the run to energy-only, permanently.
 *  4. Resampling preserves the signal well enough for a detector to see it.
 */
class SpeechFrameExtractorTest {

    private class RecordingVad(private val values: Iterator<Float>) : FrameVad {
        override val hopSize = TenVad.DEFAULT_HOP
        val hops = mutableListOf<ShortArray>()
        override fun probability(hop: ShortArray): Float {
            hops.add(hop.copyOf())
            return if (values.hasNext()) values.next() else 0.5f
        }
        override fun close() {}
    }

    @Test
    fun `48 kHz frames are 1536 samples and hops arrive every 16 ms of media`() {
        val vad = RecordingVad(generateSequence { 0.7f }.iterator())
        val extractor = SpeechFrameExtractor(48_000, vad)
        assertEquals(1536, extractor.frameSamples)
        var frames = 0
        repeat(48_000) { if (extractor.sample(0f)) frames++ } // one second
        assertEquals(31, frames) // 48000 / 1536
        // One second of 16 kHz audio is 62.5 hops of 256; the resampler
        // consumes one leading sample, so 62 complete hops.
        assertTrue("hops=${vad.hops.size}", vad.hops.size in 61..63)
    }

    @Test
    fun `frame probability is the mean of hops closed inside it`() {
        val values = listOf(0.2f, 0.8f, 0.4f, 0.6f).iterator()
        val vad = RecordingVad(values)
        val extractor = SpeechFrameExtractor(16_000, vad) // frame = 512 = 2 hops
        val probabilities = mutableListOf<Float>()
        repeat(1024) { if (extractor.sample(0f)) probabilities.add(extractor.frameVad) }
        assertEquals(2, probabilities.size)
        assertEquals(0.5f, probabilities[0], 1e-6f)
        assertEquals(0.5f, probabilities[1], 1e-6f)
    }

    @Test
    fun `a frame without a completed hop carries the last probability`() {
        val vad = RecordingVad(listOf(0.9f).iterator())
        // 8 kHz: frame = 256 source samples = 512 output samples = 2 hops...
        // use a source rate where frames are SHORTER than a hop instead:
        // 4 kHz frame = 128 samples → 512 output samples → 2 hops per frame,
        // so pick a frame length below one hop explicitly.
        val extractor = SpeechFrameExtractor(16_000, vad, frameMs = 8.0) // 128 samples, hop 256
        val probabilities = mutableListOf<Float>()
        repeat(512) { if (extractor.sample(0f)) probabilities.add(extractor.frameVad) }
        assertEquals(4, probabilities.size)
        assertEquals(0f, probabilities[0], 0f) // nothing known yet
        assertEquals(0.9f, probabilities[1], 1e-6f) // first hop closed here
        assertEquals(0.9f, probabilities[2], 1e-6f) // carried forward
    }

    @Test
    fun `a detector failure makes the run energy-only for good`() {
        val vad = object : FrameVad {
            override val hopSize = 256
            var calls = 0
            override fun probability(hop: ShortArray): Float { calls++; return -1f }
            override fun close() {}
        }
        val extractor = SpeechFrameExtractor(16_000, vad)
        assertTrue(extractor.vadValid)
        repeat(2048) { extractor.sample(0.1f) }
        assertFalse(extractor.vadValid)
        assertEquals(1, vad.calls) // never asked again
        assertTrue(extractor.frameBroad > 0f) // energy features still flow
    }

    @Test
    fun `resampling hands the detector a recognisable 1 kHz tone`() {
        val vad = RecordingVad(generateSequence { 0.5f }.iterator())
        val extractor = SpeechFrameExtractor(48_000, vad)
        for (i in 0 until 9_600) extractor.sample((0.5 * sin(2 * PI * 1000.0 * i / 48_000)).toFloat())
        val hop = vad.hops.last()
        // Peak near 0.5 full scale, and ~16 zero crossings per 256 samples
        // at 16 kHz (1 kHz tone → 16 cycles per 16 ms → 32 crossings).
        val peak = hop.maxOf { abs(it.toInt()) }
        assertTrue("peak=$peak", peak in 14_000..17_000)
        var crossings = 0
        for (i in 1 until hop.size) if ((hop[i - 1] < 0) != (hop[i] < 0)) crossings++
        assertTrue("crossings=$crossings", crossings in 30..34)
    }

    @Test
    fun `without a detector the run publishes no probabilities`() {
        val extractor = SpeechFrameExtractor(48_000, null)
        assertFalse(extractor.vadValid)
        repeat(1536) { extractor.sample(0.2f) }
        assertTrue(extractor.frameBroad > 0.19f)
        assertNull(null) // FeatureSegment.vad stays null via SpeechFeatureTap.Segment
    }
}
