package com.debrify.app.tv

import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.audio.NativeAudioRouting
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase15LoudnessShadow::class, TvPhase15AudioEffectShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvLoudnessPrerequisiteTest : TvPhase3OriginalTest() {
    @Before fun prepareEffect() {
        TvPhase15Effects.reset()
        bindViews()
        val delegate = TvPhase5PlayerProbe().player
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, args ->
            if (method.name == "getAudioSessionId") 51 else method.invoke(delegate, *(args ?: emptyArray()))
        } as ExoPlayer
        assertEquals("player session probe", 51, player.audioSessionId)
        set("player", player)
        set("nightModeIndex", 1)
        (field("nativeAudioRouting") as NativeAudioRouting).update(true, false)
    }
    private fun initialize() {
        try { call("initializeLoudnessEnhancer", emptyArray()) }
        catch (failure: Exception) { fail("Initialization must catch effect failures: $failure") }
    }
    private fun release() {
        try { call("releaseLoudnessEnhancer", emptyArray()) }
        catch (failure: Exception) { fail("Release must catch effect failures: $failure") }
    }
    private fun logged(message: String) {
        val logs = org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer")
        assertFalse("failure is logged: $message", logs.isEmpty()); val log = logs.last()
        assertEquals(message, log.msg); assertNotNull(log.throwable)
    }
    private fun apply() = call("applyNightMode", arrayOf(intType), 1)
    private fun propagate(text: String, action: () -> Unit) {
        try { action(); fail("$text must propagate outside initialization catch") }
        catch (expected: IllegalStateException) { assertEquals("phase15 $text failure", expected.message) }
    }
    @After fun cleanEffects() { TvPhase15Effects.failRelease = false; release() }

    @Test fun creationEnableGainAndReleaseAreObservable() {
        initialize()
        val effect = TvPhase15Effects.effects.single()
        assertSame(effect.instance, field("loudnessEnhancer"))
        assertEquals(51, effect.session); assertTrue(effect.enabled); assertEquals(listOf(500), effect.gains)
        assertEquals(listOf("create:51", "enabled:true", "gain:500"), TvPhase15Effects.events)
        release(); assertTrue(effect.released); assertNull(field("loudnessEnhancer"))
        assertEquals("release", TvPhase15Effects.events.last())
    }
    @Test fun constructorFailureIsCaughtAndClearsReference() {
        TvPhase15Effects.failConstructor = true
        initialize()
        assertNull(field("loudnessEnhancer")); assertTrue(TvPhase15Effects.effects.isEmpty())
        assertEquals(listOf("create:51"), TvPhase15Effects.events); logged("Failed to initialize LoudnessEnhancer")
    }
    @Test fun initializationEnableFailureClearsWithoutReleasingAllocatedEffect() {
        TvPhase15Effects.failEnableAt = 1; initialize()
        assertNull(field("loudnessEnhancer")); assertFalse(TvPhase15Effects.effects.single().released)
        assertEquals(listOf("create:51", "enabled:true"), TvPhase15Effects.events); logged("Failed to initialize LoudnessEnhancer")
    }
    @Test fun initializationGainFailureClearsWithoutReleasingAllocatedEffect() {
        TvPhase15Effects.failGainAt = 1; initialize()
        assertNull(field("loudnessEnhancer")); assertFalse(TvPhase15Effects.effects.single().released)
        assertEquals(listOf("create:51", "enabled:true", "gain:500"), TvPhase15Effects.events); logged("Failed to initialize LoudnessEnhancer")
    }
    @Test fun releaseFailureIsCaughtAndStillClearsReference() {
        initialize(); TvPhase15Effects.failRelease = true; release()
        assertNull(field("loudnessEnhancer")); assertFalse(TvPhase15Effects.effects.single().released)
        assertEquals("release", TvPhase15Effects.events.last()); logged("Error releasing LoudnessEnhancer")
    }
    @Test fun applyEnableFailurePropagatesWithEffectStillOwned() {
        initialize(); TvPhase15Effects.failEnableAt = 2
        propagate("enable") { apply() }
        assertSame(TvPhase15Effects.effects.single().instance, field("loudnessEnhancer"))
        assertEquals(listOf(500), TvPhase15Effects.effects.single().gains)
    }
    @Test fun applySecondGainFailurePropagatesAfterSuccessfulInitialization() {
        TvPhase15Effects.failGainAt = 2
        propagate("gain") { apply() }
        assertSame(TvPhase15Effects.effects.single().instance, field("loudnessEnhancer"))
        assertEquals(listOf(500), TvPhase15Effects.effects.single().gains)
        assertEquals(listOf("create:51", "enabled:true", "gain:500", "enabled:true", "gain:500"), TvPhase15Effects.events)
    }
}
