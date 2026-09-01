package com.debrify.app.util

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Turns one contiguous run of mono samples into 32 ms feature frames:
 * speech-band RMS, broadband RMS and — when a [FrameVad] is supplied — a
 * neural speech probability. One instance per audio run (segment); it holds
 * every bit of state the run needs (filters, accumulators, the resampler's
 * phase, the VAD hop buffer), so runs never bleed into each other.
 *
 * Pure Kotlin, no Android types: unit-tested with a fake VAD.
 *
 * VAD alignment: the detector wants 16 kHz int16 hops of [FrameVad.hopSize]
 * samples (16 ms). The run is band-limited to 7 kHz and linearly resampled,
 * each completed hop's probability is accumulated, and when a 32 ms feature
 * frame closes it takes the mean of the hops completed since the previous
 * frame (or the last known value when none did). A detector error switches
 * the run to energy-only for good — [vadValid] goes false and the segment
 * publishes no probabilities, so the aligner falls back per segment.
 */
class SpeechFrameExtractor(
    val sampleRate: Int,
    private val vad: FrameVad?,
    frameMs: Double = FRAME_MS,
) {
    companion object {
        const val FRAME_MS = 32.0
    }

    val frameSamples: Int = ((sampleRate * frameMs) / 1000.0).toInt().coerceAtLeast(1)

    // Speech band ≈ 300–3400 Hz: Butterworth high-pass + low-pass biquads.
    private val hp = Biquad.highPass(300.0, sampleRate)
    private val lp = Biquad.lowPass(3400.0, sampleRate)

    // VAD path: anti-alias before decimating to 16 kHz (skipped when the
    // source is not above 16 kHz — nothing to alias).
    private val vadRate = TenVad.SAMPLE_RATE
    private val antiAlias: Biquad? =
        if (vad != null && sampleRate > vadRate) Biquad.lowPass(7_000.0, sampleRate) else null
    private val resampleStep = sampleRate.toDouble() / vadRate
    private var resamplePhase = 0.0
    private var previousSample = 0.0
    private var haveSample = false
    private val hop = ShortArray(vad?.hopSize ?: 1)
    private var hopFill = 0
    private var vadSum = 0.0
    private var vadCount = 0
    private var lastVad = 0f

    var vadValid: Boolean = vad != null
        private set

    private var accBand = 0.0
    private var accBroad = 0.0
    private var accN = 0

    /** Filled when [sample] returns true. */
    var frameBand = 0f
        private set
    var frameBroad = 0f
        private set
    var frameVad = 0f
        private set

    /** Feed one mono sample in [-1, 1]. Returns true when a frame completed. */
    fun sample(mono: Float): Boolean {
        val x = mono.toDouble()
        val filtered = lp.process(hp.process(x))
        accBand += filtered * filtered
        accBroad += x * x
        accN++
        if (vadValid) feedVad(x)
        if (accN < frameSamples) return false
        frameBand = sqrt(accBand / accN).toFloat()
        frameBroad = sqrt(accBroad / accN).toFloat()
        frameVad = if (vadCount > 0) (vadSum / vadCount).toFloat() else lastVad
        accBand = 0.0
        accBroad = 0.0
        accN = 0
        vadSum = 0.0
        vadCount = 0
        return true
    }

    private fun feedVad(x: Double) {
        val detector = vad ?: return
        val y = antiAlias?.process(x) ?: x
        if (!haveSample) {
            previousSample = y
            haveSample = true
            if (resampleStep != 1.0) return
        }
        if (resampleStep == 1.0) {
            pushHop(y, detector)
            previousSample = y
            return
        }
        // Linear interpolation between the previous and current source
        // samples at every output instant that falls in between.
        while (resamplePhase < 1.0) {
            val v = previousSample + (y - previousSample) * resamplePhase
            pushHop(v, detector)
            resamplePhase += resampleStep
        }
        resamplePhase -= 1.0
        previousSample = y
    }

    private fun pushHop(value: Double, detector: FrameVad) {
        val scaled = (value * 32767.0).roundToInt().coerceIn(-32768, 32767)
        hop[hopFill++] = scaled.toShort()
        if (hopFill < hop.size) return
        hopFill = 0
        val p = detector.probability(hop)
        if (p < 0f) {
            vadValid = false
            return
        }
        lastVad = p
        vadSum += p
        vadCount++
    }

    /** RBJ-cookbook biquad, direct form I, Butterworth Q. */
    class Biquad(
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
