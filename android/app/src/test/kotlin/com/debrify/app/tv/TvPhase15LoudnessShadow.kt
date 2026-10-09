package com.debrify.app.tv

import android.media.audiofx.AudioEffect
import android.media.audiofx.LoudnessEnhancer
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.RealObject
import org.robolectric.shadows.ShadowAudioEffect

/** A device-free observation seam: it preserves the original catch boundaries. */
internal object TvPhase15Effects {
    data class Effect(val instance: LoudnessEnhancer, val session: Int,
        var enabled: Boolean = false, val gains: MutableList<Int> = mutableListOf(),
        var released: Boolean = false)
    val effects = mutableListOf<Effect>()
    val events = mutableListOf<String>()
    var failConstructor = false
    var failEnableAt = 0
    var failGainAt = 0
    var failRelease = false
    var enableCalls = 0
    var gainCalls = 0
    var onRelease: (() -> Unit)? = null
    fun reset() {
        effects.clear(); events.clear()
        failConstructor = false; failEnableAt = 0; failGainAt = 0; failRelease = false
        enableCalls = 0; gainCalls = 0; onRelease = null
    }
    fun effect(instance: LoudnessEnhancer) = effects.single { it.instance === instance }
}

@Implements(LoudnessEnhancer::class)
internal class TvPhase15LoudnessShadow : TvPhase15AudioEffectShadow() {
    @RealObject private lateinit var real: LoudnessEnhancer
    @Implementation fun __constructor__(session: Int) {
        TvPhase15Effects.events.add("create:$session")
        check(!TvPhase15Effects.failConstructor) { "phase15 constructor failure" }
        TvPhase15Effects.effects.add(TvPhase15Effects.Effect(real, session))
    }
    @Implementation fun setTargetGain(gain: Int) {
        TvPhase15Effects.events.add("gain:$gain")
        TvPhase15Effects.gainCalls++
        check(TvPhase15Effects.gainCalls != TvPhase15Effects.failGainAt) { "phase15 gain failure" }
        TvPhase15Effects.effect(real).gains.add(gain)
    }
}

@Implements(AudioEffect::class)
internal open class TvPhase15AudioEffectShadow : ShadowAudioEffect() {
    @RealObject private lateinit var real: AudioEffect
    @Implementation fun setEnabled(enabled: Boolean): Int {
        val effect = real as LoudnessEnhancer
        TvPhase15Effects.events.add("enabled:$enabled")
        TvPhase15Effects.enableCalls++
        check(TvPhase15Effects.enableCalls != TvPhase15Effects.failEnableAt) { "phase15 enable failure" }
        TvPhase15Effects.effect(effect).enabled = enabled
        return AudioEffect.SUCCESS
    }
    @Implementation fun release() {
        TvPhase15Effects.onRelease?.invoke()
        TvPhase15Effects.events.add("release")
        check(!TvPhase15Effects.failRelease) { "phase15 release failure" }
        TvPhase15Effects.effect(real as LoudnessEnhancer).released = true
    }
}
