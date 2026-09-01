package com.debrify.app.util

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sqrt

/**
 * One contiguous run of audio features captured by the player's PCM tap.
 *
 * [anchorMs] is the MEDIA time of frame 0 — [SpeechFeatureTap] stamps it from
 * the seek target / start position the run began at. A frame's media time is
 * `anchorMs + k * frameSamples * 1000.0 / sampleRate`: the duration is derived
 * from the exact sample count, never from a rounded per-frame constant, because
 * a 0.01 ms rounding error per frame compounds to over half a second across a
 * long watch — more than the sync error this whole feature exists to remove.
 *
 * [band] is per-frame RMS of the speech band (~300–3400 Hz), [broadband] the
 * unfiltered per-frame RMS. Both linear amplitude, not dB. [vad], when
 * present, is a per-frame neural speech probability in [0, 1] (ten-vad) and
 * replaces the energy heuristics as the activity signal for this run.
 */
class FeatureSegment(
    val anchorMs: Long,
    val sampleRate: Int,
    val frameSamples: Int,
    val band: FloatArray,
    val broadband: FloatArray,
    val vad: FloatArray? = null,
) {
    val frameDurationMs: Double get() = frameSamples * 1000.0 / sampleRate
    val durationMs: Double get() = band.size * frameDurationMs
}

/** A subtitle cue reduced to what alignment needs. */
class CueSpan(val startMs: Long, val endMs: Long, val text: String)

/**
 * Every variant carries its evidence, not just its verdict: the TV feedback
 * card shows these numbers so a failing device run diagnoses itself — "0 s
 * heard" is a dead tap, "no confident match, best guess +2.1 s at z 3.1" is a
 * gate a hair too strict, and those need opposite fixes.
 */
sealed class AlignResult {
    /** Confident global offset: display time = file time + [offsetMs]. */
    data class Synced(
        val offsetMs: Long,
        val confidence: Double,
        val analyzedSec: Int,
        val zPeak: Double = 0.0,
        val usableCues: Int = 0,
        /** Best z outside the peak's ±2 s neighbourhood. */
        val runnerUpZ: Double = 0.0,
    ) : AlignResult()

    /**
     * A framerate-scaled hypothesis won decisively over enough media time to
     * trust it: display time = file time × [scale] + [offsetMs]. Applied by
     * the player through the same gates as a plain offset (see
     * [Tuning.DRIFT_MIN_SPAN_MS]).
     */
    data class Drift(
        val scale: Double,
        val offsetMs: Long,
        val confidence: Double = 0.0,
        val analyzedSec: Int = 0,
        val zPeak: Double = 0.0,
    ) : AlignResult()

    /** Enough data, no peak that clears the confidence gate. Nothing applied. */
    data class NoMatch(
        val analyzedSec: Int,
        val usableCues: Int = 0,
        val bestOffsetMs: Long? = null,
        val bestZ: Double = 0.0,
        val bestPsr: Double = 0.0,
        val runnerUpZ: Double = 0.0,
    ) : AlignResult()

    /** Too little anchored audio (or too few usable cues) to even try. */
    data class NotEnoughAudio(
        val analyzedSec: Int,
        val usableCues: Int = 0,
    ) : AlignResult()
}

/**
 * Aligns a subtitle cue timeline to captured audio by cross-correlating the
 * subtitle's speech schedule against a speech-activity signal derived from the
 * player's own decoded PCM (ffsubsync's approach, computed on-device).
 *
 * The design rule inherited from v1's failure: **never guess**. Every path out
 * of here either clears an explicit confidence gate or reports that it
 * couldn't — a wrong sync reads as "the feature is broken", while "couldn't
 * find a match" reads as an honest miss. All thresholds live in [Tuning] with
 * their rationale.
 *
 * Sign convention, pinned by tests: the player displays a cue at
 * `fileTime + offset` (both the offset text renderer and the side-render
 * ticker's `position - offset` lookup reduce to this). Cues authored EARLY by
 * Δ therefore need offset = +Δ, and that is exactly the lag this correlation
 * reports — the result feeds SubtitleSettings.setSyncOffsetMs unchanged.
 */
object SubtitleAligner {

    object Tuning {
        /** Correlation grid. 32 ms ≈ half a syllable — finer buys nothing. */
        const val GRID_MS = 32.0

        /** Search window for the offset, each direction (full tier). */
        const val SEARCH_MS = 90_000.0

        /**
         * Narrow tier: real subtitle offsets are almost always within a few
         * seconds, and a ±15 s window has 6× fewer candidate lags than ±90 s —
         * so the same confidence gate clears honestly with far less audio.
         * This is what turns "watch a minute first" into ~20–30 s.
         */
        const val NARROW_SEARCH_MS = 15_000.0
        const val NARROW_MIN_AUDIO_MS = 20_000.0
        const val NARROW_MIN_CUE_OVERLAP_FRAMES = 300 // ≈10 s of cue speech
        const val NARROW_MIN_CUES = 8 // ~30 s of dialogue; z/PSR gates carry the rest

        /**
         * Narrow-tier gate. PSR is deflated in a short window through no fault
         * of the peak: dialogue is quasi-periodic (~3–4 s bursts), so the true
         * peak's own sidelobes fill most of ±15 s and inflate the background
         * std that PSR divides by — a measured true match scored z 16.6 with
         * PSR only 3.3. So the narrow tier leans on a much taller z bar
         * (null z is ≈ N(0,1); 8 is beyond reach of chance) and keeps PSR as
         * a moderate distinctness check.
         */
        // 2026-09 recalibration: the z statistic is inflated ~3× over a true
        // N(0,1) null by the burst autocorrelation of dialogue (measured on
        // synthetic speech: the best UNRELATED lag reaches z 8–10 with
        // 45–120 s of audio, a true match 16+ from 45 s). 8 was inside the
        // null's reach; 11 is not. PSR 3 stays a moderate distinctness check.
        const val NARROW_MIN_ZPEAK = 11.0
        const val NARROW_MIN_PSR = 3.0

        /** Full tier won't try below this many dialogue cues. */
        const val MIN_CUES = 20

        /** Feature history hard cap (frames are cheap; this is ~64 min). */
        const val MAX_GRID = 120_000

        /** Media positions live in hours, not days: ~100 h covers any real
         *  file or live window, and everything beyond is a clock-domain leak. */
        const val MAX_SANE_ANCHOR_MS = 360_000_000L

        /** Segments roll over at ~10 min; 1 h means the tap misbehaved. */
        const val MAX_SANE_SEGMENT_MS = 3_600_000.0

        /**
         * Minimum anchored audio before an attempt is made at all. Below this
         * the peak statistics are meaningless and every answer is a guess.
         */
        const val MIN_AUDIO_MS = 45_000.0

        /**
         * Minimum cue mass (in grid frames, ≈30 s of subtitle speech) that must
         * overlap valid audio AT a lag for that lag to be scoreable — a lag
         * that slides most cues into unwatched gaps can't be trusted no matter
         * how well the remainder fits.
         */
        const val MIN_CUE_OVERLAP_FRAMES = 940

        /**
         * Confidence gate. The score is a z-like statistic (≈ standard normal
         * under the null), so ZPEAK is "standard deviations of evidence"; PSR
         * additionally demands the peak stand off from the whole lag landscape,
         * which kills the flat-mush correlations film music produces.
         */
        const val MIN_ZPEAK = 4.0
        const val MIN_PSR = 5.0

        /**
         * The winning peak must beat the strongest rival outside its ±2 s
         * neighbourhood by this factor, in every tier. A spurious winner is
         * the maximum of a null landscape, so its runner-up is nearly as
         * tall (measured ≤ 1.35); a true peak stands alone (≥ 1.9 from 45 s
         * of audio, ≥ 3 from 90 s). The sharpest single discriminator measured.
         */
        const val MIN_PEAK_RATIO = 1.4

        /**
         * The activity signal is centred on a ROLLING mean over this window,
         * not the global mean. Film audio is not stationary: a scored or
         * silent stretch sits below the global mean and dialogue above it,
         * so any lag that slides the cue mass out of the quiet region and
         * into the loud one correlates positively no matter how the cues
         * line up — measured as confident peaks at exactly ±13–15 s (the
         * edge of the narrow window) on unrelated and drifting subtitles.
         * Local centring makes every half-minute zero-mean, so only
         * burst-level alignment can score. Long against the 2–4 s dialogue
         * cycle that carries the signal, so a true peak is untouched.
         */
        const val CENTERING_WINDOW_MS = 30_000.0

        /** Peak neighbourhood excluded from the PSR background (±2 s). */
        const val PSR_EXCLUDE_MS = 2_000.0

        /**
         * A scaled (framerate) hypothesis must beat the unscaled one by this
         * factor to claim drift — at equal evidence the simpler explanation
         * (pure offset) wins.
         */
        const val SCALE_PARSIMONY = 1.10

        /**
         * A drift (framerate) verdict is only trusted — and therefore applied
         * — once the watched audio spans at least this much media time.
         * Scaling is anchored at media time 0, so over a short span early in
         * a file the scaled and unscaled hypotheses differ by well under a
         * cue's width and a lucky sidelobe could win the parsimony race.
         * Below this span the ladder simply keeps listening; nothing is
         * applied from a doubtful drift call.
         */
        const val DRIFT_MIN_SPAN_MS = 120_000.0

        /**
         * A lag is only scoreable when its cue mass inside valid audio is at
         * least this fraction of the best mass any lag achieves. The absolute
         * floors bound the worst case for twenty seconds of audio, but with a
         * minute on hand a lag that slides all but ten seconds of cues off
         * the end can still clear them — and ten seconds of bursty dialogue
         * against a bursty activity signal produces spurious peaks well past
         * the z gate (measured: z 11.5 on a drifting file at a −11 s lag
         * nothing supported). Relative to the achievable mass, such edge lags
         * are never candidates.
         */
        const val MIN_OVERLAP_FRACTION = 0.5

        /** Common framerate mismatches; anything else is out of scope. */
        val SCALES = doubleArrayOf(
            1.0,
            25.0 / 23.976, 23.976 / 25.0,
            25.0 / 24.0, 24.0 / 25.0,
            24.0 / 23.976, 23.976 / 24.0,
        )

        // ── Speech scoring (all in nepers, i.e. natural-log energy units) ──
        /** Activity ramp starts this far above the rolling noise floor (~3 dB). */
        const val ACT_MARGIN = 0.35

        /** ...and saturates over this range (~10 dB). */
        const val ACT_RANGE = 1.2

        /** Noise-floor percentile, taken per 5 s chunk and interpolated. */
        const val FLOOR_CHUNK_MS = 5_000.0
        const val FLOOR_PERCENTILE = 0.10

        /**
         * Syllabic-variance weight: speech modulates its energy at 3–8 Hz, so
         * the ~1 s log-energy stddev is high during dialogue and low during
         * sustained score/effects — the exact false positive that sank v1's
         * plain energy detector. Sustained sound is down-weighted, not zeroed:
         * dialogue over music is still dialogue.
         */
        const val VAR_WINDOW_MS = 1_000.0
        const val VAR_LO = 0.15
        const val VAR_RANGE = 0.45
        const val VAR_MIN_WEIGHT = 0.15

        /** Speech-band dominance weight (speech concentrates in 300–3400 Hz). */
        const val DOM_LO = 0.25
        const val DOM_RANGE = 0.5
        const val DOM_MIN_WEIGHT = 0.2

        /**
         * Cue display spans include reading-time padding beyond the spoken
         * words; cap the rasterized span at a speech-duration estimate so the
         * padding doesn't smear the correlation. ~70 ms/char ≈ 14 chars/s.
         */
        const val CUE_MS_PER_CHAR = 70.0
        const val CUE_MIN_MS = 700.0
        const val CUE_MAX_MS = 7_000.0
    }

    /**
     * Narrow-first ladder: try ±15 s with the low-audio thresholds, fall back
     * to the full ±90 s pass. The narrow tier runs offset-only (scale = 1.0):
     * framerate drift is invisible inside 15 s, and the full tier still
     * catches it. When the narrow tier finds nothing and the full tier lacks
     * audio, the full tier's NotEnoughAudio is the honest verdict — a large
     * offset simply cannot be seen yet.
     */
    fun alignTiered(segments: List<FeatureSegment>, cues: List<CueSpan>): AlignResult {
        val narrow = align(
            segments, cues,
            searchMs = Tuning.NARROW_SEARCH_MS,
            minAudioMs = Tuning.NARROW_MIN_AUDIO_MS,
            minCueOverlapFrames = Tuning.NARROW_MIN_CUE_OVERLAP_FRAMES,
            minCues = Tuning.NARROW_MIN_CUES,
            minZPeak = Tuning.NARROW_MIN_ZPEAK,
            minPsr = Tuning.NARROW_MIN_PSR,
            scales = doubleArrayOf(1.0),
        )
        if (narrow is AlignResult.Synced) return narrow
        return align(segments, cues)
    }

    fun align(
        segments: List<FeatureSegment>,
        cues: List<CueSpan>,
        searchMs: Double = Tuning.SEARCH_MS,
        minAudioMs: Double = Tuning.MIN_AUDIO_MS,
        minCueOverlapFrames: Int = Tuning.MIN_CUE_OVERLAP_FRAMES,
        minCues: Int = Tuning.MIN_CUES,
        minZPeak: Double = Tuning.MIN_ZPEAK,
        minPsr: Double = Tuning.MIN_PSR,
        minPeakRatio: Double = Tuning.MIN_PEAK_RATIO,
        scales: DoubleArray = Tuning.SCALES,
    ): AlignResult {
        // Sanity bounds, not just the UNANCHORED sentinel: an anchor from the
        // wrong clock domain (Media3's TIME_UNSET is MIN_VALUE + 1 and passes
        // a plain sentinel check; live windows and corrupt discontinuities
        // have produced day-scale values) would otherwise size the grid below
        // — the 2026-08-25 MiBox OOM was a ~235-day span turned into a 5 GB
        // array. Anything outside a generous media-position range is garbage.
        val usable = segments.filter {
            it.anchorMs in -60_000L..Tuning.MAX_SANE_ANCHOR_MS &&
                it.durationMs.isFinite() &&
                it.durationMs >= 2_000.0 &&
                it.durationMs <= Tuning.MAX_SANE_SEGMENT_MS
        }
        val analyzedSec = (usable.sumOf { it.durationMs } / 1000.0).roundToInt()
        val speechCues = filterCues(cues)
        if (usable.isEmpty() ||
            usable.sumOf { it.durationMs } < minAudioMs ||
            speechCues.size < minCues
        ) {
            return AlignResult.NotEnoughAudio(analyzedSec, speechCues.size)
        }

        // ── Choose the grid window, then rasterize onto it ──
        // When the watched spans cover more media time than the grid budget,
        // keep the most RECENTLY CAPTURED segments that fit together — by
        // capture order, not media timestamps. The newest capture is what the
        // user is listening to right now, so it is the audio their sense of
        // "out of sync" is anchored to; a brief peek near a film's end must
        // never evict a proper watch of its beginning.
        val spanCapMs = (Tuning.MAX_GRID * Tuning.GRID_MS).toLong()
        val picked = ArrayList<FeatureSegment>(usable.size)
        var t0 = Long.MAX_VALUE
        var t1 = Long.MIN_VALUE
        for (s in usable.asReversed()) { // newest captured first
            val lo = min(t0, s.anchorMs)
            val hi = max(t1, s.anchorMs + s.durationMs.roundToLong())
            if (hi - lo > spanCapMs) continue // won't fit beside newer audio
            picked.add(s)
            t0 = lo
            t1 = hi
        }
        val n = ((t1 - t0) / Tuning.GRID_MS).toInt() + 1
        if (n <= 0 || n > Tuning.MAX_GRID + 1) {
            // The span cap above should make this unreachable; it is the last
            // line of defence between a bad timestamp and an allocation that
            // kills the player. Refusing is always safer than trusting.
            return AlignResult.NotEnoughAudio(analyzedSec, speechCues.size)
        }
        val audio = DoubleArray(n)
        val mask = DoubleArray(n)
        // Reversed again so rasterization runs oldest→newest capture: on a
        // rewatched span, the newest capture's features win.
        for (s in picked.asReversed()) {
            val score = speechScore(s)
            val fd = s.frameDurationMs
            for (k in score.indices) {
                val g = ((s.anchorMs - t0 + k * fd) / Tuning.GRID_MS).toInt()
                if (g in 0 until n) {
                    audio[g] = score[k].toDouble()
                    mask[g] = 1.0
                }
            }
        }

        var maskSum = 0.0
        for (g in 0 until n) maskSum += mask[g]
        if (maskSum < minAudioMs / Tuning.GRID_MS) {
            return AlignResult.NotEnoughAudio(analyzedSec, speechCues.size)
        }
        val a0 = centerLocally(audio, mask)
        var varSum = 0.0
        for (g in 0 until n) if (mask[g] > 0) varSum += a0[g] * a0[g]
        val sigma = sqrt(varSum / maskSum)
        if (sigma < 1e-4) return AlignResult.NotEnoughAudio(analyzedSec, speechCues.size) // silence / flat

        // ── FFT setup (audio-side transforms are shared across hypotheses) ──
        val k = (searchMs / Tuning.GRID_MS).toInt() // lag radius in grids
        val m = nextPow2(n + 2 * k + 1)
        val aFft = Fft(m).forwardConj(a0)
        val mFft = Fft(m).forwardConj(mask)

        var best: Peak? = null
        var bestUnscaled: Peak? = null
        for (scale in scales) {
            val cExt = rasterizeCues(speechCues, scale, t0, n, k)
            val cFft = Fft(m).forward(cExt)
            val corrA = Fft(m).inverseProduct(aFft, cFft) // Σ a0[g]·cExt[g+d]
            val corrM = Fft(m).inverseProduct(mFft, cFft) // cue mass in valid audio
            val peak = bestLag(corrA, corrM, sigma, k, minCueOverlapFrames) ?: continue
            if (scale == 1.0) bestUnscaled = peak
            if (best == null || peak.z > best.z) best = peak.copy(scale = scale)
        }
        val chosen = best ?: return AlignResult.NoMatch(analyzedSec, speechCues.size)

        // Parsimony: a scaled hypothesis must decisively beat pure offset.
        val effective = if (chosen.scale != 1.0 &&
            bestUnscaled != null &&
            bestUnscaled.z * Tuning.SCALE_PARSIMONY >= chosen.z
        ) bestUnscaled.copy(scale = 1.0) else chosen

        val offsetMs = (effective.lagGrids * Tuning.GRID_MS).roundToLong()
        val rivalled = effective.runnerUpZ > 0.0 && effective.z < minPeakRatio * effective.runnerUpZ
        if (effective.z < minZPeak || effective.psr < minPsr || rivalled) {
            // The below-gate candidate rides along so the device run reports
            // HOW close it came — the difference between "gate needs a nudge"
            // and "nothing correlates at all" is the whole diagnosis.
            return AlignResult.NoMatch(
                analyzedSec, speechCues.size,
                bestOffsetMs = offsetMs, bestZ = effective.z, bestPsr = effective.psr,
                runnerUpZ = effective.runnerUpZ,
            )
        }
        return if (effective.scale != 1.0) {
            if ((t1 - t0) < Tuning.DRIFT_MIN_SPAN_MS) {
                // Too little media time to trust a framerate call. Never
                // apply a doubtful scale — and never apply the losing
                // unscaled offset to a file that is probably drifting
                // either. Keep listening.
                AlignResult.NotEnoughAudio(analyzedSec, speechCues.size)
            } else {
                AlignResult.Drift(effective.scale, offsetMs, effective.psr, analyzedSec, effective.z)
            }
        } else {
            AlignResult.Synced(
                offsetMs, effective.psr, analyzedSec, effective.z, speechCues.size,
                runnerUpZ = effective.runnerUpZ,
            )
        }
    }

    /**
     * `mask · (audio − rolling masked mean)` over ±[Tuning.CENTERING_WINDOW_MS]/2.
     * Unmasked cells never contribute to a neighbourhood mean and come back
     * as exact zeros.
     */
    internal fun centerLocally(audio: DoubleArray, mask: DoubleArray): DoubleArray {
        val n = audio.size
        val half = max(1, (Tuning.CENTERING_WINDOW_MS / Tuning.GRID_MS / 2).toInt())
        val pm = DoubleArray(n + 1)
        val pa = DoubleArray(n + 1)
        for (i in 0 until n) {
            pm[i + 1] = pm[i] + mask[i]
            pa[i + 1] = pa[i] + audio[i] * mask[i]
        }
        val out = DoubleArray(n)
        for (i in 0 until n) {
            if (mask[i] <= 0.0) continue
            val lo = max(0, i - half)
            val hi = min(n, i + half + 1)
            val cnt = pm[hi] - pm[lo]
            if (cnt <= 0.0) continue
            out[i] = audio[i] - (pa[hi] - pa[lo]) / cnt
        }
        return out
    }

    // ── Speech scoring ──────────────────────────────────────────────────────

    /**
     * Per-frame speech score in [0,1]. A neural VAD probability, when the
     * tap supplies one, IS the score: it already separates dialogue from
     * score, effects and crowd noise far better than the energy heuristics
     * below, which remain the fallback for runs without a detector.
     */
    internal fun speechScore(s: FeatureSegment): FloatArray {
        val vad = s.vad
        if (vad != null && vad.size == s.band.size) {
            return FloatArray(vad.size) { vad[it].coerceIn(0f, 1f) }
        }
        val nF = s.band.size
        val logE = DoubleArray(nF) { ln(s.band[it] + 1e-6) }

        // Rolling noise floor: per-chunk low percentile, linearly interpolated.
        val chunk = max(1, (Tuning.FLOOR_CHUNK_MS / s.frameDurationMs).toInt())
        val chunks = (nF + chunk - 1) / chunk
        val floors = DoubleArray(chunks)
        val scratch = DoubleArray(chunk)
        for (c in 0 until chunks) {
            val from = c * chunk
            val len = min(chunk, nF - from)
            System.arraycopy(logE, from, scratch, 0, len)
            java.util.Arrays.sort(scratch, 0, len)
            floors[c] = scratch[(len * Tuning.FLOOR_PERCENTILE).toInt().coerceAtMost(len - 1)]
        }
        fun floorAt(i: Int): Double {
            if (chunks == 1) return floors[0]
            val pos = (i.toDouble() / chunk) - 0.5
            val lo = pos.toInt().coerceIn(0, chunks - 1)
            val hi = (lo + 1).coerceAtMost(chunks - 1)
            val f = (pos - lo).coerceIn(0.0, 1.0)
            return floors[lo] * (1 - f) + floors[hi] * f
        }

        // ~1s rolling stddev of log-energy via prefix sums (syllabic modulation).
        val w = max(3, (Tuning.VAR_WINDOW_MS / s.frameDurationMs).toInt()) or 1
        val half = w / 2
        val p1 = DoubleArray(nF + 1)
        val p2 = DoubleArray(nF + 1)
        for (i in 0 until nF) {
            p1[i + 1] = p1[i] + logE[i]
            p2[i + 1] = p2[i] + logE[i] * logE[i]
        }

        val out = FloatArray(nF)
        for (i in 0 until nF) {
            val act = ((logE[i] - floorAt(i) - Tuning.ACT_MARGIN) / Tuning.ACT_RANGE)
                .coerceIn(0.0, 1.0)
            val lo = max(0, i - half)
            val hi = min(nF, i + half + 1)
            val cnt = (hi - lo).toDouble()
            val mu = (p1[hi] - p1[lo]) / cnt
            val sd = sqrt(max(0.0, (p2[hi] - p2[lo]) / cnt - mu * mu))
            val varW = ((sd - Tuning.VAR_LO) / Tuning.VAR_RANGE)
                .coerceIn(Tuning.VAR_MIN_WEIGHT.toDouble(), 1.0)
            val dom = s.band[i] / (s.broadband[i] + 1e-6f)
            val domW = ((dom - Tuning.DOM_LO) / Tuning.DOM_RANGE)
                .coerceIn(Tuning.DOM_MIN_WEIGHT.toDouble(), 1.0)
            out[i] = (act * varW * domW).toFloat()
        }
        return out
    }

    // ── Cue preparation ─────────────────────────────────────────────────────

    private val tagRe = Regex("<[^>]{0,32}>|\\{[^}]{0,48}\\}")

    /**
     * Cues that plausibly mark dialogue. SDH sound cues ("[door slams]",
     * "(gunfire)") and music lines (♪…) describe things the speech detector
     * deliberately scores low, so keeping them would poison the correlation
     * exactly where the audio is least speech-like.
     */
    internal fun filterCues(cues: List<CueSpan>): List<CueSpan> = cues.filter { cue ->
        val t = cue.text.replace(tagRe, "").trim()
        if (t.isEmpty()) return@filter false
        if (t.contains('♪') || t.contains('♫')) return@filter false
        val bracketed = (t.startsWith("[") && t.endsWith("]")) ||
            (t.startsWith("(") && t.endsWith(")"))
        !bracketed && cue.endMs > cue.startMs
    }

    /**
     * Cue schedule rasterized onto an extended grid: index j represents grid
     * (j - k) relative to t0, so lags in ±k stay inside the array. Spans are
     * capped at an estimated speech duration (see [Tuning.CUE_MS_PER_CHAR]).
     */
    private fun rasterizeCues(cues: List<CueSpan>, scale: Double, t0: Long, n: Int, k: Int): DoubleArray {
        val ext = DoubleArray(n + 2 * k)
        for (cue in cues) {
            val chars = cue.text.replace(tagRe, "").trim().length
            val cap = (chars * Tuning.CUE_MS_PER_CHAR).coerceIn(Tuning.CUE_MIN_MS, Tuning.CUE_MAX_MS)
            val startMs = cue.startMs * scale
            val endMs = startMs + min((cue.endMs - cue.startMs) * scale, cap)
            var g = ((startMs - t0) / Tuning.GRID_MS).toInt() + k
            val gEnd = ((endMs - t0) / Tuning.GRID_MS).toInt() + k
            while (g <= gEnd) {
                if (g in ext.indices) ext[g] = 1.0
                g++
            }
        }
        return ext
    }

    // ── Peak selection ──────────────────────────────────────────────────────

    internal data class Peak(
        val lagGrids: Double,
        val z: Double,
        val psr: Double,
        val scale: Double = 1.0,
        val runnerUpZ: Double = 0.0,
    )

    /**
     * Z-scores every lag and finds the best one. With cExt indexed at (g - lag
     * + k), correlation index d = k - lag, so lag L lives at corr[k - L].
     *
     * z(L) = A(L) / (σ·√n(L)) — the mean speech activity during cues at lag L,
     * expressed in standard errors. ≈N(0,1) under the null, so the gate reads
     * as "standard deviations of evidence".
     */
    private fun bestLag(
        corrA: DoubleArray,
        corrM: DoubleArray,
        sigma: Double,
        k: Int,
        minCueOverlapFrames: Int,
    ): Peak? {
        val z = DoubleArray(2 * k + 1) { Double.NaN }
        var maxMass = 0.0
        for (i in 0..2 * k) if (corrM[i] > maxMass) maxMass = corrM[i]
        val overlapFloor = max(minCueOverlapFrames.toDouble(), maxMass * Tuning.MIN_OVERLAP_FRACTION)
        var bestIdx = -1
        for (i in 0..2 * k) {
            val nL = corrM[i]
            if (nL < overlapFloor) continue
            z[i] = corrA[i] / (sigma * sqrt(nL))
            if (bestIdx < 0 || z[i] > z[bestIdx]) bestIdx = i
        }
        if (bestIdx < 0) return null

        // Peak-to-sidelobe over the valid lags outside ±PSR_EXCLUDE_MS.
        val excl = (Tuning.PSR_EXCLUDE_MS / Tuning.GRID_MS).toInt()
        var cnt = 0
        var sum = 0.0
        var sumSq = 0.0
        var runnerUp = Double.NEGATIVE_INFINITY
        for (i in 0..2 * k) {
            if (z[i].isNaN() || abs(i - bestIdx) <= excl) continue
            cnt++; sum += z[i]; sumSq += z[i] * z[i]
            if (z[i] > runnerUp) runnerUp = z[i]
        }
        if (cnt < 50) return null // background too small to judge the peak
        val bgMean = sum / cnt
        val bgSd = sqrt(max(1e-12, sumSq / cnt - bgMean * bgMean))
        val psr = (z[bestIdx] - bgMean) / bgSd

        // Parabolic refinement around the peak for sub-grid precision.
        var lag = (k - bestIdx).toDouble()
        if (bestIdx in 1 until 2 * k && !z[bestIdx - 1].isNaN() && !z[bestIdx + 1].isNaN()) {
            val denom = z[bestIdx - 1] - 2 * z[bestIdx] + z[bestIdx + 1]
            if (abs(denom) > 1e-9) {
                val d = 0.5 * (z[bestIdx - 1] - z[bestIdx + 1]) / denom
                if (abs(d) <= 1.0) lag -= d // corr index runs opposite to lag
            }
        }
        return Peak(lag, z[bestIdx], psr, runnerUpZ = if (runnerUp.isFinite()) runnerUp else 0.0)
    }

    // ── Minimal iterative radix-2 FFT ───────────────────────────────────────

    private fun nextPow2(v: Int): Int {
        var p = 1
        while (p < v) p = p shl 1
        return p
    }

    private class Fft(val m: Int) {
        /** FFT of zero-padded x, conjugated (correlation left operand). */
        fun forwardConj(x: DoubleArray): Pair<DoubleArray, DoubleArray> {
            val (re, im) = forward(x)
            for (i in im.indices) im[i] = -im[i]
            return re to im
        }

        fun forward(x: DoubleArray): Pair<DoubleArray, DoubleArray> {
            val re = DoubleArray(m)
            val im = DoubleArray(m)
            System.arraycopy(x, 0, re, 0, min(x.size, m))
            transform(re, im, invert = false)
            return re to im
        }

        /** IFFT(X̄·Y).re — the cross-correlation Σ x[g]·y[g+d] at index d. */
        fun inverseProduct(xConj: Pair<DoubleArray, DoubleArray>, y: Pair<DoubleArray, DoubleArray>): DoubleArray {
            val (xr, xi) = xConj
            val (yr, yi) = y
            val re = DoubleArray(m)
            val im = DoubleArray(m)
            for (i in 0 until m) {
                re[i] = xr[i] * yr[i] - xi[i] * yi[i]
                im[i] = xr[i] * yi[i] + xi[i] * yr[i]
            }
            transform(re, im, invert = true)
            return re
        }

        private fun transform(re: DoubleArray, im: DoubleArray, invert: Boolean) {
            val n = m
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
                j = j or bit
                if (i < j) {
                    val tr = re[i]; re[i] = re[j]; re[j] = tr
                    val ti = im[i]; im[i] = im[j]; im[j] = ti
                }
            }
            var len = 2
            while (len <= n) {
                val ang = 2 * Math.PI / len * (if (invert) 1 else -1)
                val wr = kotlin.math.cos(ang)
                val wi = kotlin.math.sin(ang)
                var i = 0
                while (i < n) {
                    var cwr = 1.0
                    var cwi = 0.0
                    for (p in 0 until len / 2) {
                        val ur = re[i + p]; val ui = im[i + p]
                        val vr = re[i + p + len / 2] * cwr - im[i + p + len / 2] * cwi
                        val vi = re[i + p + len / 2] * cwi + im[i + p + len / 2] * cwr
                        re[i + p] = ur + vr; im[i + p] = ui + vi
                        re[i + p + len / 2] = ur - vr; im[i + p + len / 2] = ui - vi
                        val nwr = cwr * wr - cwi * wi
                        cwi = cwr * wi + cwi * wr
                        cwr = nwr
                    }
                    i += len
                }
                len = len shl 1
            }
            if (invert) {
                for (i in 0 until n) { re[i] /= n; im[i] /= n }
            }
        }
    }
}
