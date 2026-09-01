package com.debrify.app.util

import kotlin.math.abs
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The aligner's contract, pinned by synthetic audio:
 *
 *  1. Cues authored EARLY by Δ recover offset ≈ +Δ (the sign the player's
 *     "display = file time + offset" convention needs — get this wrong and
 *     auto-sync doubles the error instead of fixing it).
 *  2. The confidence gate refuses to answer when the cues don't describe the
 *     audio, when there's too little audio, or when the timing drifts.
 *  3. Seek gaps, film music and SDH noise don't break 1 or 2.
 *
 * Audio is synthesized at the FEATURE level (band/broadband RMS frames):
 * "speech" = strong band energy modulated at syllable rate; "music" = strong
 * but sustained energy spread across the band; "silence" = low noise. That is
 * exactly the signal shape the DSP hands the aligner, so these tests exercise
 * scoring, rasterization, correlation, and gating — everything except the
 * biquads and the anchor stamps, which only a device can prove.
 */
class SubtitleAlignerTest {

    private val frameMs = 32.0

    /** Speech on/off timeline → one FeatureSegment starting at [anchorMs]. */
    private fun segment(
        anchorMs: Long,
        durationMs: Int,
        speech: List<LongRange>,
        music: List<LongRange> = emptyList(),
        seed: Int = 7,
    ): FeatureSegment {
        val rate = 48_000
        val frameSamples = ((rate * frameMs) / 1000.0).toInt() // 1536
        val n = (durationMs / frameMs).toInt()
        val band = FloatArray(n)
        val broad = FloatArray(n)
        val rnd = Random(seed)
        for (i in 0 until n) {
            val t = anchorMs + (i * frameMs).toLong()
            val inSpeech = speech.any { t in it }
            val inMusic = music.any { t in it }
            // Noise floor.
            var b = 0.002f + rnd.nextFloat() * 0.001f
            var r = 0.004f + rnd.nextFloat() * 0.002f
            if (inMusic) {
                // Loud but SUSTAINED (low frame-to-frame variance) and broad:
                // the classic false positive for an energy detector.
                b += 0.05f + rnd.nextFloat() * 0.004f
                r += 0.18f
            }
            if (inSpeech) {
                // Loud AND syllabically modulated, concentrated in the band.
                val syllable = if ((i / 6) % 2 == 0) 1.0f else 0.25f
                b += 0.12f * syllable + rnd.nextFloat() * 0.01f
                r += 0.13f * syllable
            }
            band[i] = b
            broad[i] = r
        }
        return FeatureSegment(anchorMs, rate, frameSamples, band, broad)
    }

    /** Plausible dialogue pattern: bursts 600–2400 ms, gaps 400–2600 ms. */
    private fun speechPattern(fromMs: Long, toMs: Long, seed: Int = 3): List<LongRange> {
        val rnd = Random(seed)
        val out = mutableListOf<LongRange>()
        var t = fromMs + 500
        while (t < toMs - 1000) {
            val len = 600 + rnd.nextLong(1800)
            out.add(t..(t + len))
            t += len + 400 + rnd.nextLong(2200)
        }
        return out
    }

    private fun cuesFor(speech: List<LongRange>, offsetEarlierMs: Long, seed: Int = 11): List<CueSpan> {
        val rnd = Random(seed)
        return speech.map { s ->
            val jitter = rnd.nextLong(-80, 81)
            CueSpan(
                startMs = s.first - offsetEarlierMs + jitter,
                endMs = s.last - offsetEarlierMs + jitter + 250, // display padding
                text = "Dialogue line with a plausible length here",
            )
        }
    }

    // ── 1. Recovery + sign ──────────────────────────────────────────────────

    @Test
    fun `recovers a 3s-early subtitle as +3000ms`() {
        val speech = speechPattern(0, 8 * 60_000)
        val seg = segment(0, 8 * 60_000, speech)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(speech, offsetEarlierMs = 3_000))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        val offset = (result as AlignResult.Synced).offsetMs
        assertTrue("offset $offset should be ≈ +3000", abs(offset - 3_000) <= 150)
    }

    @Test
    fun `recovers a late subtitle as a negative offset`() {
        val speech = speechPattern(0, 8 * 60_000)
        val seg = segment(0, 8 * 60_000, speech)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(speech, offsetEarlierMs = -12_000))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        val offset = (result as AlignResult.Synced).offsetMs
        assertTrue("offset $offset should be ≈ -12000", abs(offset + 12_000) <= 150)
    }

    @Test
    fun `already-synced subtitles come back near zero`() {
        val speech = speechPattern(0, 6 * 60_000)
        val seg = segment(0, 6 * 60_000, speech)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(speech, offsetEarlierMs = 0))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs) <= 150)
    }

    // ── 2. The gate ─────────────────────────────────────────────────────────

    @Test
    fun `unrelated cues are refused, not guessed`() {
        val speech = speechPattern(0, 8 * 60_000, seed = 3)
        val unrelated = speechPattern(0, 8 * 60_000, seed = 99) // different film, same style
        val seg = segment(0, 8 * 60_000, speech)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(unrelated, 0))
        assertTrue("expected NoMatch, got $result", result is AlignResult.NoMatch)
    }

    @Test
    fun `too little audio is declined before any attempt`() {
        val speech = speechPattern(0, 20_000)
        val seg = segment(0, 20_000, speech)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(speech, 2_000))
        assertTrue("expected NotEnoughAudio, got $result", result is AlignResult.NotEnoughAudio)
    }

    @Test
    fun `unanchored segments are invisible`() {
        val speech = speechPattern(0, 8 * 60_000)
        val good = segment(0, 8 * 60_000, speech)
        val unanchored = FeatureSegment(
            Long.MIN_VALUE, good.sampleRate, good.frameSamples,
            FloatArray(10_000) { 0.5f }, FloatArray(10_000) { 0.5f },
        )
        val result = SubtitleAligner.align(listOf(good, unanchored), cuesFor(speech, 1_500))
        assertTrue(result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs - 1_500) <= 150)
    }

    @Test
    fun `framerate drift is reported as drift, never as a confident offset`() {
        val speech = speechPattern(0, 10 * 60_000)
        val seg = segment(0, 10 * 60_000, speech)
        // Cues authored against 25fps timing for 23.976fps audio: every cue
        // time compressed by 23.976/25 — a pure offset CANNOT fix this.
        val scale = 23.976 / 25.0
        val drifted = speech.map { s ->
            CueSpan((s.first * scale).toLong(), (s.last * scale).toLong() + 250, "A plausible dialogue line")
        }
        when (val result = SubtitleAligner.align(listOf(seg), drifted)) {
            is AlignResult.Drift -> assertEquals(25.0 / 23.976, result.scale, 1e-6)
            is AlignResult.NoMatch -> Unit // acceptable: refused rather than wrong
            else -> throw AssertionError("drifted subs must never yield $result")
        }
    }

    // ── 3. Robustness ───────────────────────────────────────────────────────

    @Test
    fun `survives seek gaps in the watched audio`() {
        val speech = speechPattern(0, 20 * 60_000)
        val segA = segment(0, 3 * 60_000, speech)               // watched 0–3 min
        val segB = segment(9 * 60_000, 4 * 60_000, speech)      // seeked, watched 9–13 min
        val result = SubtitleAligner.align(listOf(segA, segB), cuesFor(speech, offsetEarlierMs = -4_000))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs + 4_000) <= 150)
    }

    @Test
    fun `film music under and between dialogue does not break recovery`() {
        val speech = speechPattern(0, 8 * 60_000)
        val music = listOf(0L..90_000L, 200_000L..300_000L, 380_000L..470_000L)
        val seg = segment(0, 8 * 60_000, speech, music = music)
        val result = SubtitleAligner.align(listOf(seg), cuesFor(speech, offsetEarlierMs = 2_000))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs - 2_000) <= 150)
    }

    @Test
    fun `SDH sound cues are filtered out before alignment`() {
        val kept = SubtitleAligner.filterCues(
            listOf(
                CueSpan(0, 1000, "[door slams]"),
                CueSpan(0, 1000, "(distant gunfire)"),
                CueSpan(0, 1000, "♪ ominous music ♪"),
                CueSpan(0, 1000, "<i>[thunder]</i>"),
                CueSpan(0, 1000, ""),
                CueSpan(0, 1000, "Actual spoken dialogue."),
                CueSpan(0, 1000, "<i>Whispered but real.</i>"),
            )
        )
        assertEquals(2, kept.size)
        assertTrue(kept.all { !it.text.contains('[') })
    }

    @Test
    fun `a subtitle file of only sound cues is declined`() {
        val speech = speechPattern(0, 5 * 60_000)
        val seg = segment(0, 5 * 60_000, speech)
        val sdh = speech.map { CueSpan(it.first, it.last, "[music]") }
        val result = SubtitleAligner.align(listOf(seg), sdh)
        assertTrue("expected NotEnoughAudio, got $result", result is AlignResult.NotEnoughAudio)
    }

    @Test
    fun `a peek at the film's end never evicts the audio being watched now`() {
        // Captured FIRST: a one-minute sample near the three-hour mark.
        // Captured SECOND (what's playing now): six minutes from the start.
        // The two spans can't share one grid window — the window must follow
        // capture recency, not the larger media timestamp, or the current
        // watch is discarded and auto-sync starves.
        val speech = speechPattern(0, 200 * 60_000)
        val peek = segment(178 * 60_000L, 60_000, speech)
        val watch = segment(0, 6 * 60_000, speech)
        val result = SubtitleAligner.align(listOf(peek, watch), cuesFor(speech, offsetEarlierMs = 2_500))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs - 2_500) <= 150)
    }

    // ── The tiered ladder (fast first sync without losing the gate) ────────

    @Test
    fun `narrow tier syncs a typical offset from ~45s of audio`() {
        // The whole point of the ladder: a few-seconds offset must not cost
        // the user minutes of watching. ±15s window, low-audio thresholds —
        // and a scored opening, the DC-shift trap the gate must survive.
        for (seed in intArrayOf(3, 5)) {
            val speech = speechPattern(0, 45_000, seed = seed)
            val seg = segment(0, 45_000, speech, music = listOf(0L..15_000L), seed = seed + 100)
            val result = SubtitleAligner.alignTiered(listOf(seg), cuesFor(speech, offsetEarlierMs = 2_000))
            assertTrue("seed $seed: expected Synced, got $result", result is AlignResult.Synced)
            assertTrue(abs((result as AlignResult.Synced).offsetMs - 2_000) <= 300)
        }
    }

    @Test
    fun `unrelated cues are refused at every rung, scored audio included`() {
        // A loud sustained score over the first third plus wrong-film cues,
        // at every ladder rung: never a confident verdict. (The old z ≥ 8
        // narrow gate let these through at z 8–10.)
        for (seconds in intArrayOf(30, 45, 60, 90, 120, 180)) {
            for (seed in intArrayOf(3, 5)) {
                val speech = speechPattern(0, seconds * 1_000L, seed = seed)
                val unrelated = speechPattern(0, seconds * 1_000L, seed = seed + 40)
                val seg = segment(
                    0, seconds * 1_000, speech,
                    music = listOf(0L..(seconds * 1_000L / 3)), seed = seed + 100,
                )
                val result = SubtitleAligner.alignTiered(listOf(seg), cuesFor(unrelated, 0))
                assertTrue("${seconds}s seed $seed: expected refusal, got $result", result !is AlignResult.Synced)
                assertTrue(result !is AlignResult.Drift)
            }
        }
    }

    @Test
    fun `a drifting file never gets a far-off plain offset from a short span`() {
        val scale = 23.976 / 25.0
        for (seconds in intArrayOf(45, 60, 90)) {
            for (seed in intArrayOf(3, 5)) {
                val speech = speechPattern(0, seconds * 1_000L, seed = seed)
                val drifted = speech.map { s ->
                    CueSpan((s.first * scale).toLong() + 1_500, (s.last * scale).toLong() + 1_750, "A plausible dialogue line")
                }
                val seg = segment(
                    0, seconds * 1_000, speech,
                    music = listOf(0L..(seconds * 1_000L / 3)), seed = seed + 100,
                )
                val result = SubtitleAligner.alignTiered(listOf(seg), drifted)
                assertTrue("${seconds}s seed $seed: $result", result !is AlignResult.Drift)
                if (result is AlignResult.Synced) {
                    assertTrue("${seconds}s seed $seed: far-off offset $result", abs(result.offsetMs) < 1_000)
                }
            }
        }
    }

    @Test
    fun `framerate drift is corrected once enough of the file was heard`() {
        // display = file × (25/23.976) − 1.56 s; three minutes is past the
        // trust span, so the verdict is a Drift carrying that transform.
        val speech = speechPattern(0, 3 * 60_000)
        val scale = 23.976 / 25.0
        val drifted = speech.map { s ->
            CueSpan((s.first * scale).toLong() + 1_500, (s.last * scale).toLong() + 1_750, "A plausible dialogue line")
        }
        val result = SubtitleAligner.align(listOf(segment(0, 3 * 60_000, speech)), drifted)
        assertTrue("expected Drift, got $result", result is AlignResult.Drift)
        val drift = result as AlignResult.Drift
        assertEquals(25.0 / 23.976, drift.scale, 0.002)
        assertTrue("offset ${drift.offsetMs} should be ≈ −1564", abs(drift.offsetMs + 1_564) <= 500)
    }

    @Test
    fun `local centring zeroes masked-out cells and removes a regional mean`() {
        val audio = DoubleArray(2_000) { if (it < 1_000) 0.2 else 0.8 }
        val mask = DoubleArray(2_000) { if (it == 1_500) 0.0 else 1.0 }
        val centered = SubtitleAligner.centerLocally(audio, mask)
        assertEquals(0.0, centered[1_500], 0.0)
        assertEquals(0.0, centered[300], 1e-9)
        assertEquals(0.0, centered[1_800], 1e-9)
        assertTrue(centered.all { abs(it) < 0.31 })
    }

    @Test
    fun `narrow tier still refuses unrelated cues`() {
        // The relaxed narrow gate must not become a false-positive machine:
        // wrong-film cues over the same 30s must be refused, not guessed.
        val speech = speechPattern(0, 30_000, seed = 3)
        val unrelated = speechPattern(0, 30_000, seed = 99)
        val seg = segment(0, 30_000, speech)
        val result = SubtitleAligner.alignTiered(listOf(seg), cuesFor(unrelated, 0))
        assertTrue("expected refusal, got $result", result !is AlignResult.Synced)
    }

    @Test
    fun `narrow tier never guesses an offset beyond its window`() {
        // True offset +40s, only 30s of audio: the narrow window cannot see
        // the real peak and must NOT invent one; the full tier lacks audio.
        // "Keep watching" is the only honest verdict.
        val speech = speechPattern(0, 30_000 + 45_000)
        val seg = segment(0, 30_000, speech)
        val result = SubtitleAligner.alignTiered(listOf(seg), cuesFor(speech, offsetEarlierMs = 40_000))
        assertTrue("expected NotEnoughAudio, got $result", result is AlignResult.NotEnoughAudio)
    }

    @Test
    fun `a large offset resolves through the full tier once audio allows`() {
        val speech = speechPattern(0, 8 * 60_000)
        val seg = segment(0, 4 * 60_000, speech)
        val result = SubtitleAligner.alignTiered(listOf(seg), cuesFor(speech, offsetEarlierMs = 40_000))
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        assertTrue(abs((result as AlignResult.Synced).offsetMs - 40_000) <= 150)
    }

    // ── Verify-mode composition (piecewise sync via centered re-checks) ────
    // Verify passes pre-shift the cues by the APPLIED offset, so a correct
    // sync correlates at lag 0 and any peak is the residual to add on top.

    @Test
    fun `a centered verify finds a small residual within its narrow window`() {
        val speech = speechPattern(0, 4 * 60_000)
        val seg = segment(0, 4 * 60_000, speech)
        val truth = 3_500L
        val applied = 2_000L
        val centered = cuesFor(speech, offsetEarlierMs = truth).map {
            CueSpan(it.startMs + applied, it.endMs + applied, it.text)
        }
        val result = SubtitleAligner.align(
            listOf(seg), centered,
            searchMs = 10_000.0,
            minAudioMs = 25_000.0,
            minCueOverlapFrames = SubtitleAligner.Tuning.NARROW_MIN_CUE_OVERLAP_FRAMES,
            minCues = SubtitleAligner.Tuning.NARROW_MIN_CUES,
            minZPeak = SubtitleAligner.Tuning.NARROW_MIN_ZPEAK,
            minPsr = SubtitleAligner.Tuning.NARROW_MIN_PSR,
            scales = doubleArrayOf(1.0),
        )
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        val residual = (result as AlignResult.Synced).offsetMs
        assertTrue("residual $residual should be ≈ +1500", abs(residual - 1_500) <= 150)
    }

    @Test
    fun `an escalated verify catches a mid-file timing break`() {
        // Ad-break shape: subs correct at +2s for the first half, +14s after.
        // The verify runs over the RECENT window (second half only), centered
        // at the applied +2s — a +12s residual, beyond the narrow window,
        // recovered by the escalated full-width pass.
        val speech = speechPattern(0, 12 * 60_000)
        val recent = segment(6 * 60_000L, 6 * 60_000, speech)
        val applied = 2_000L
        val cues = speech.map { span ->
            val off = if (span.first < 6 * 60_000) 2_000L else 14_000L
            CueSpan(span.first - off, span.last - off + 250, "A plausible dialogue line")
        }
        val centered = cues.map { CueSpan(it.startMs + applied, it.endMs + applied, it.text) }
        val result = SubtitleAligner.align(listOf(recent), centered)
        assertTrue("expected Synced, got $result", result is AlignResult.Synced)
        val residual = (result as AlignResult.Synced).offsetMs
        assertTrue(
            "residual $residual should be ≈ +12000 (new offset = +14s)",
            abs(residual - 12_000) <= 150,
        )
    }

    // ── Frame timing exactness (the drift-by-rounding trap) ────────────────

    @Test
    fun `frame duration derives from sample counts, not a rounded constant`() {
        // 44.1kHz: 32ms → 1411 samples → 31.995ms true duration. Using a flat
        // 32ms would drift ~0.9s over an hour — worse than the errors this
        // feature corrects. The segment must expose the exact value.
        val seg = FeatureSegment(0, 44_100, 1411, FloatArray(0), FloatArray(0))
        assertEquals(1411 * 1000.0 / 44_100, seg.frameDurationMs, 1e-9)
        assertTrue(abs(seg.frameDurationMs - 32.0) > 1e-4)
    }
}
