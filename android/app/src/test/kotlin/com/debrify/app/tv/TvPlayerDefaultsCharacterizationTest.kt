package com.debrify.app.tv

import com.debrify.app.profiles.NativePlayerPreferences
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Start before onCreate so the exception-preserved initializer values are observable. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlayerDefaultsCharacterizationTest : TvPhase3OriginalTest() {
    @Before fun preferences() {
        bindViews()
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
    }
    private fun prefs() = activity.getSharedPreferences("FlutterSharedPreferences", 0)
    private fun load(refresh: Boolean = true) {
        if (refresh) set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
        call("loadPlayerDefaults", emptyArray())
    }
    private fun failRead(key: String, values: Map<String, Any>) {
        val json = object : org.json.JSONObject(values) {
            override fun opt(name: String): Any? {
                if (name == key) throw IllegalStateException("phase15 preference read failed")
                return super.opt(name)
            }
        }
        val constructor = NativePlayerPreferences::class.java.getDeclaredConstructor(org.json.JSONObject::class.java)
        constructor.isAccessible = true
        set("playerPreferences", constructor.newInstance(json))
    }
    @Test fun absentPreferencesApplyAllLiteralDefaultsAndConstructDisplayController() {
        assertEquals(1, field("resizeModeIndex")); assertEquals(2, field("playbackSpeedIndex"))
        load()
        assertEquals(0, field("resizeModeIndex")); assertEquals(0, field("nightModeIndex"))
        assertEquals(false, field("systemAudioEffectsEnabled")); assertEquals(TvContentDisplayMatchMode.SYSTEM, field("displayMatchMode"))
        assertNotNull(field("displayModeController")); assertEquals(true, field("skipSegmentsEnabled"))
        assertEquals(TvSkipSegmentClients.AUTO, field("skipSegmentProviderId"))
        assertEquals(2, field("playbackSpeedIndex"))
        val logs = org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer")
        assertTrue(logs.any { it.msg == "Loaded defaults - aspect=0, nightMode=0, audioEffects=false, displayMatch=system, skipSegments=true, skipProvider=auto" })
        assertTrue(logs.any { it.msg == "Player settings handoff: style=OTT subtitles=auto nightMode=0" })
    }
    @Test fun bothNumericPreferenceBoundariesClampToTheActualArrayBounds() {
        for ((input, aspect, night) in listOf(Triple(-1L, 0, 0), Triple(0L, 0, 0), Triple(3L, 3, 3), Triple(7L, 3, 7), Triple(99L, 3, 7))) {
            prefs().edit().putLong("flutter.player_default_aspect_index_tv", input).putLong("flutter.player_night_mode_index", input).commit()
            load(); assertEquals(aspect, field("resizeModeIndex")); assertEquals(night, field("nightModeIndex"))
        }
    }
    @Test fun defaultReadsUseTvAspectKeyAndIgnoreTheMobileAspectKey() {
        prefs().edit().putLong("flutter.player_default_aspect_index", 3).putLong("flutter.player_default_aspect_index_tv", 2).commit()
        load(); assertEquals(2, field("resizeModeIndex"))
    }
    @Test fun storedAudioEffectsAndDisabledManualSkipSettingsAreRead() {
        prefs().edit().putBoolean("flutter.player_system_audio_effects", true).putBoolean("flutter.skip_segments_enabled", false).commit()
        load(); assertEquals(true, field("systemAudioEffectsEnabled")); assertEquals(false, field("skipSegmentsEnabled"))
    }
    @Test fun allStoredDisplayMatchModesSelectTheirOwnControllerMode() {
        TvContentDisplayMatchMode.entries.forEach { mode ->
            prefs().edit().putString("flutter.content_display_match_mode", mode.storageKey).commit()
            load(); assertEquals(mode, field("displayMatchMode"))
            val controller = field("displayModeController")!!
            assertEquals(mode, TvPlayerOriginalAccess.field(controller, "matchMode"))
        }
    }
    @Test fun unknownAndNullDisplayModesFallBackToSystem() {
        prefs().edit().putString("flutter.content_display_match_mode", "unknown-mode").commit()
        load(); assertEquals(TvContentDisplayMatchMode.SYSTEM, field("displayMatchMode"))
        prefs().edit().putString("flutter.content_display_match_mode", null).commit()
        load(); assertEquals(TvContentDisplayMatchMode.SYSTEM, field("displayMatchMode"))
    }
    @Test fun reloadClearsTheOldPreferredDisplayModeAndReplacesItsController() {
        load(); val first = field("displayModeController")
        activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = 97 }
        load()
        assertNotSame(first, field("displayModeController")); assertEquals(0, activity.window.attributes.preferredDisplayModeId)
    }
    @Test fun knownSkipProviderIsPreservedAndUnknownOrMissingFallsBackToAuto() {
        prefs().edit().putString("flutter.skip_segment_provider", TvSkipSegmentClients.SKIP_DB).commit()
        load(); assertEquals(TvSkipSegmentClients.SKIP_DB, field("skipSegmentProviderId"))
        prefs().edit().putString("flutter.skip_segment_provider", "unsupported-provider").commit()
        load(); assertEquals(TvSkipSegmentClients.AUTO, field("skipSegmentProviderId"))
        prefs().edit().remove("flutter.skip_segment_provider").commit()
        load(); assertEquals(TvSkipSegmentClients.AUTO, field("skipSegmentProviderId"))
    }
    @Test fun firstPreferenceReadFailureKeepsTheOriginalFillInitializerAndStopsLaterReads() {
        failRead("player_default_aspect_index_tv", mapOf("player_night_mode_index" to 7, "player_system_audio_effects" to true))
        load(false)
        assertEquals(1, field("resizeModeIndex")); assertEquals(0, field("nightModeIndex")); assertEquals(false, field("systemAudioEffectsEnabled"))
        assertNull(field("displayModeController"))
        val logs = org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer")
        assertTrue(logs.any { it.msg == "Error loading player defaults" && it.throwable is IllegalStateException })
    }
    @Test fun laterReadFailureRetainsAlreadyAppliedAspectAndSkipsRemainingDefaults() {
        failRead("player_night_mode_index", mapOf("player_default_aspect_index_tv" to 3, "player_system_audio_effects" to true))
        load(false)
        assertEquals(3, field("resizeModeIndex")); assertEquals(0, field("nightModeIndex")); assertEquals(false, field("systemAudioEffectsEnabled"))
        assertNull(field("displayModeController"))
    }
    @Test fun loadingPreferencesDoesNotAllocateEffectsOrApplyResizeAndPlaybackSpeed() {
        prefs().edit().putLong("flutter.player_default_aspect_index_tv", 3).putLong("flutter.player_night_mode_index", 7).commit()
        val before = (field("playerView") as androidx.media3.ui.PlayerView).resizeMode
        load()
        assertEquals(3, field("resizeModeIndex")); assertEquals(7, field("nightModeIndex"))
        assertNull(field("loudnessEnhancer")); assertEquals(before, (field("playerView") as androidx.media3.ui.PlayerView).resizeMode)
        assertEquals(2, field("playbackSpeedIndex"))
    }
    @Test fun preferenceLongValuesNarrowToIntBeforeTheArrayBoundsClamp() {
        for ((raw, expectedAspect, expectedNight) in listOf(Triple(Long.MAX_VALUE, 0, 0),
            Triple(Long.MIN_VALUE, 0, 0), Triple(4_294_967_298L, 2, 2))) {
            prefs().edit().putLong("flutter.player_default_aspect_index_tv", raw)
                .putLong("flutter.player_night_mode_index", raw).commit()
            load(); assertEquals(expectedAspect, field("resizeModeIndex")); assertEquals(expectedNight, field("nightModeIndex"))
        }
    }
}
