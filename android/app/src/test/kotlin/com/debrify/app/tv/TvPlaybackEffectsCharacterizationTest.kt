package com.debrify.app.tv

import android.media.audiofx.AudioEffect
import android.os.Handler
import android.view.View
import androidx.media3.common.Player
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackEffectsCharacterizationTest : TvPhase15OriginalTest() {
    private fun observed(): TvPhase15Effects.Effect {
        assertEquals("one effect allocated", 1, TvPhase15Effects.effects.size)
        return TvPhase15Effects.effects.single()
    }
    private fun broadcasts() = shadowOf(activity).broadcastIntents.filter {
        it.action == AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION || it.action == AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION
    }
    private fun resetEffects() { releaseEffect(); TvPhase15Effects.reset() }
    private fun listener() = field("playbackListener") as Player.Listener
    private fun track() {
        val time = AnalyticsListener.EventTime(0, androidx.media3.common.Timeline.EMPTY, 0, null, 0,
            androidx.media3.common.Timeline.EMPTY, 0, null, 0, 0)
        (field("decoderAnalyticsListener") as AnalyticsListener).onAudioTrackInitialized(time,
            AudioSink.AudioTrackConfig(2, 48_000, 12, false, false, 4096))
    }
    @Test fun disabledSystemEffectsDoNotReadOrAnnounceAPlayerSession() {
        set("systemAudioEffectsEnabled", false); sync(88)
        assertTrue(broadcasts().isEmpty())
    }
    @Test fun systemEffectsUseTheExplicitCallbackSessionBeforeThePlayerValue() {
        set("systemAudioEffectsEnabled", true); sync(88)
        val intent = broadcasts().single()
        assertEquals(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION, intent.action)
        assertEquals(88, intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1))
        assertEquals(activity.packageName, intent.getStringExtra(AudioEffect.EXTRA_PACKAGE_NAME))
        assertEquals(AudioEffect.CONTENT_TYPE_MUSIC, intent.getIntExtra(AudioEffect.EXTRA_CONTENT_TYPE, -1))
    }
    @Test fun systemEffectsDefaultDispatcherReadsCurrentPlayerSessionPerCall() {
        set("systemAudioEffectsEnabled", true)
        defaultCall("syncAudioEffectSession", arrayOf(boxedIntType), 1, null)
        session = 52
        defaultCall("syncAudioEffectSession", arrayOf(boxedIntType), 1, null)
        assertEquals(listOf(51, 51, 52), broadcasts().map { it.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1) })
        assertEquals(listOf(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION, AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION, AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION), broadcasts().map { it.action })
    }
    @Test fun zeroSessionDoesNotAnnounceOrCloseAnAlreadyOpenEffectSession() {
        set("systemAudioEffectsEnabled", true); sync(88); sync(0)
        assertEquals(1, broadcasts().size)
        assertEquals(88, TvPlayerOriginalAccess.field(com.debrify.app.audio.AudioEffectSession, "openSessionId"))
    }
    @Test fun nullPlayerAndZeroPlayerSessionDoNotAllocateEffects() {
        set("nightModeIndex", 3); session = 0; initialize()
        assertNull(effect()); assertTrue(TvPhase15Effects.events.isEmpty())
        set("player", null); initialize()
        assertNull(effect()); assertTrue(TvPhase15Effects.events.isEmpty())
        set("systemAudioEffectsEnabled", true); sync()
        assertTrue(broadcasts().isEmpty())
    }
    @Test fun invalidSessionLeavesThePreviouslyOwnedEnhancerUntouched() {
        set("nightModeIndex", 1); initialize(); val first = observed()
        session = 0; initialize()
        assertSame(first.instance, effect()); assertFalse(first.released)
        assertEquals(listOf("create:51", "enabled:true", "gain:500"), TvPhase15Effects.events)
    }
    @Test fun initializationReleasesTheOldEffectBeforeCreatingTheReplacement() {
        set("nightModeIndex", 1); initialize(); val first = observed()
        session = 52; initialize()
        assertTrue(first.released); assertEquals(2, TvPhase15Effects.effects.size)
        assertSame(TvPhase15Effects.effects[1].instance, effect())
        assertEquals(listOf("create:51", "enabled:true", "gain:500", "release", "create:52", "enabled:true", "gain:500"), TvPhase15Effects.events)
    }
    @Test fun offInitializationCreatesADisabledEffectWithoutSettingGain() {
        set("nightModeIndex", 0); initialize()
        val value = observed(); assertFalse(value.enabled); assertTrue(value.gains.isEmpty())
        assertEquals(listOf("create:51", "enabled:false"), TvPhase15Effects.events)
    }
    @Test fun everyNightModeGainLabelAndToastIsPinned() {
        val labels = listOf("Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby")
        val gains = listOf(0, 500, 1000, 1500, 2000, 2500, 3000, 5000)
        labels.indices.forEach { index ->
            resetEffects(); routing().update(index > 0, false); night(index)
            assertEquals(index, field("nightModeIndex")); assertEquals(labels[index], button("nightModeButton").text.toString())
            assertEquals("Night Mode: ${labels[index]}", toast())
            if (index == 0) assertTrue(TvPhase15Effects.effects.isEmpty())
            else { val effect = observed(); assertTrue(effect.enabled); assertEquals(listOf(gains[index], gains[index]), effect.gains) }
        }
    }
    @Test fun switchingNightModeOffDisablesAnEffectWhenSystemEffectsKeepPcmActive() {
        set("systemAudioEffectsEnabled", true); set("nightModeIndex", 1); routing().update(true, true); initialize()
        val value = observed(); night(0)
        assertSame(value.instance, effect()); assertFalse(value.enabled); assertFalse(value.released)
        assertTrue(routing().requiresPcm); assertEquals(listOf(500), value.gains)
    }
    @Test fun changingNightGainOnAnExistingRouteDoesNotReplaceOrRestartThePlayer() {
        routing().update(true, false); set("nightModeIndex", 1); initialize(); val value = observed()
        mediaCount = 1; night(3)
        assertSame(value.instance, effect()); assertFalse(value.released); assertEquals(listOf(500, 1500), value.gains)
        assertTrue(probe.events.isEmpty())
    }
    @Test fun routeChangingNightModeReleasesAndRepreparesBeforeReadyCreatesAnEffect() {
        initialize(); val old = observed(); mediaCount = 1; probe.state = Player.STATE_READY
        night(1)
        assertTrue(old.released); assertNull(effect()); assertEquals(listOf("stop", "speed:1.0", "prepare"), probe.events)
        probe.state = Player.STATE_READY; listener().onPlaybackStateChanged(Player.STATE_READY)
        assertEquals(2, TvPhase15Effects.effects.size); assertEquals(listOf(500), TvPhase15Effects.effects.last().gains)
    }
    @Test fun routeChangingNightModeWithoutMediaInitializesImmediately() {
        mediaCount = 0; night(1)
        assertTrue(routing().requiresPcm); assertEquals(listOf("speed:1.0"), probe.events)
        assertEquals(listOf(500, 500), observed().gains)
    }
    @Test fun readyOnlyCreatesNightEffectWhenEnabledAndAbsent() {
        set("nightModeIndex", 0); listener().onPlaybackStateChanged(Player.STATE_READY)
        assertTrue(TvPhase15Effects.effects.isEmpty())
        set("nightModeIndex", 1); listener().onPlaybackStateChanged(Player.STATE_READY)
        val first = observed(); listener().onPlaybackStateChanged(Player.STATE_READY)
        assertSame(first.instance, effect()); assertEquals(1, TvPhase15Effects.effects.size)
    }
    @Test fun decoderAudioTrackInitReattachesEffectsEvenWhenTheSessionIdIsUnchanged() {
        set("nightModeIndex", 1); initialize(); val first = observed()
        set("systemAudioEffectsEnabled", true); track()
        assertTrue(first.released); assertEquals(2, TvPhase15Effects.effects.size)
        assertSame(TvPhase15Effects.effects.last().instance, effect())
        assertEquals(1, broadcasts().size); assertEquals(51, broadcasts().single().getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1))
    }
    @Test fun decoderAudioTrackInitAnnouncesSystemEffectsWhileNightModeIsOff() {
        set("nightModeIndex", 0); set("systemAudioEffectsEnabled", true); track()
        assertTrue(TvPhase15Effects.effects.isEmpty())
        assertEquals(1, broadcasts().size); assertEquals(51, broadcasts().single().getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1))
    }
    @Test fun sessionCallbackUsesItsIdForAnnouncementButThePlayerForEnhancer() {
        set("nightModeIndex", 1); set("systemAudioEffectsEnabled", true)
        listener().onAudioSessionIdChanged(88)
        assertEquals(88, broadcasts().single().getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1))
        assertEquals(51, observed().session)
    }
    @Test fun zeroSessionCallbackDoesNotReleaseExistingNightEffect() {
        set("nightModeIndex", 1); initialize(); val value = observed()
        listener().onAudioSessionIdChanged(0)
        assertSame(value.instance, effect()); assertFalse(value.released)
    }
    @Test fun sessionCallbackReleasesAndReinitializesOnlyWhenNightModeIsOn() {
        set("nightModeIndex", 0); initialize(); val value = observed()
        listener().onAudioSessionIdChanged(88)
        assertSame(value.instance, effect()); assertFalse(value.released)
        set("nightModeIndex", 1); listener().onAudioSessionIdChanged(88)
        assertTrue(value.released); assertEquals(2, TvPhase15Effects.effects.size)
    }
    @Test fun repeatTransitionRetainsNightEffectButOtherTransitionsReleaseIt() {
        set("nightModeIndex", 1); initialize(); val value = observed()
        listener().onMediaItemTransition(null, Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT)
        assertSame(value.instance, effect()); assertFalse(value.released)
        listener().onMediaItemTransition(null, Player.MEDIA_ITEM_TRANSITION_REASON_AUTO)
        assertNull(effect()); assertTrue(value.released)
    }
    @Test fun pauseAndStopRetainNightEffectUntilDestroy() {
        set("nightModeIndex", 1); initialize(); val value = observed()
        lifecycle.pause().stop()
        assertSame(value.instance, effect()); assertFalse(value.released)
        destroyNow(); assertNull(effect()); assertTrue(value.released)
    }
    @Test fun nightLabelRefreshUpdatesTheActuallyFocusedCaption() {
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE; layout()
        assertTrue(button("nightModeButton").requestFocus()); set("ottSkinInstalled", true)
        val label = android.widget.TextView(activity); set("ottCaptionLabel", label)
        night(4)
        assertEquals("Higher", label.text.toString()); assertSame(button("nightModeButton"), field("ottCaptionOwner"))
        assertEquals("Higher", button("nightModeButton").text.toString())
    }
}
