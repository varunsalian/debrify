package com.debrify.app.profiles

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class NativePlayerPreferencesTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val prefs get() = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private val owner = mapOf("profileId" to "profile-a", "dataGeneration" to 1, "sessionEpoch" to 1)
    private val custom = JSONObject().put("tv_player_controls_style", "frost")
        .put("debrify_tv_player_style", "cinema")
        .put("player_default_subtitle_language", "off")
        .put("player_night_mode_index", 3)
        .put("subtitle_only_foreign_audio", true)
        .put("subtitle_forced_only", true)

    @Before fun reset() {
        prefs.edit().clear().commit()
        ProfilePrivacyState.update(context, false, false)
    }

    private fun publish(values: JSONObject = custom, identity: Map<String, Any> = owner, sequence: Long = 1) {
        val root = JSONObject(identity).put("version", 2).put("state", "active")
            .put("publication", sequence).put("values", values)
        prefs.edit().putString("flutter.profiles_runtime_mode_v1", "profileCommitted")
            .putLong("flutter.profiles_native_projection_sequence_v1", sequence)
            .putString("flutter.profiles_native_projection_v1", root.toString()).commit()
    }

    private fun launch(): Intent = Intent().putExtra(
        NativePlayerPreferences.EXTRA, NativePlayerPreferences.captureForLaunch(context, owner),
    )

    @Test fun `custom appearance subtitles off and night mode survive repeated handoffs`() {
        repeat(2) {
            publish(sequence = it + 1L)
            val settings = NativePlayerPreferences.fromIntent(context, launch())
            assertEquals("frost", settings.getString("tv_player_controls_style", "ott"))
            assertEquals("cinema", settings.getString("debrify_tv_player_style", "cinema"))
            assertEquals("off", settings.getString("player_default_subtitle_language", null))
            assertEquals(3L, settings.getLong("player_night_mode_index", 0))
            assertTrue(settings.getBoolean("subtitle_only_foreign_audio", false))
            assertTrue(settings.getBoolean("subtitle_forced_only", false))
        }
    }

    @Test fun `unset preferences keep existing defaults`() {
        publish(JSONObject())
        val settings = NativePlayerPreferences.fromIntent(context, launch())
        assertEquals("ott", settings.getString("tv_player_controls_style", "ott"))
        assertNull(settings.getString("player_default_subtitle_language", null))
        assertFalse(settings.getBoolean("subtitle_only_foreign_audio", false))
        assertEquals(0L, settings.getLong("player_night_mode_index", 0))
        assertFalse(settings.getBoolean("player_system_audio_effects", false))
    }

    @Test fun `incomplete publication rejects launch rather than silently reading defaults`() {
        publish()
        val intent = launch()
        prefs.edit().putLong("flutter.profiles_native_projection_sequence_v1", 2).commit()
        // This is the previous failure signature with the same saved values:
        assertEquals("ott", ProfilePreferenceProjection.getString(context, "tv_player_controls_style", "ott"))
        assertNull(ProfilePreferenceProjection.getString(context, "player_default_subtitle_language", null))
        assertEquals(0L, ProfilePreferenceProjection.getLong(context, "player_night_mode_index", 0))
        assertThrows(IllegalStateException::class.java) { launch() }
        assertThrows(IllegalStateException::class.java) { NativePlayerPreferences.fromIntent(context, intent) }
    }

    @Test fun `profile switches generation changes and new sessions reject old handoffs`() {
        for (changed in listOf(
            owner + ("profileId" to "profile-b"), owner + ("dataGeneration" to 2), owner + ("sessionEpoch" to 2),
        )) {
            publish()
            val intent = launch()
            publish(identity = changed)
            assertThrows(IllegalStateException::class.java) { launch() }
            assertThrows(IllegalStateException::class.java) { NativePlayerPreferences.fromIntent(context, intent) }
        }
    }

    @Test fun `locked profile rejects capture and an already prepared handoff`() {
        publish()
        val intent = launch()
        ProfilePrivacyState.update(context, true, false)
        assertThrows(IllegalStateException::class.java) { launch() }
        assertThrows(IllegalStateException::class.java) { NativePlayerPreferences.fromIntent(context, intent) }
    }

    @Test fun `malformed active projection is not mistaken for unset defaults`() {
        publish()
        val key = "flutter.profiles_native_projection_v1"
        val root = JSONObject(prefs.getString(key, null)!!)
        root.remove("values")
        prefs.edit().putString(key, root.toString()).commit()
        assertThrows(IllegalStateException::class.java) { launch() }
    }

    @Test fun `a same-profile refresh cannot mix one launches preference values`() {
        publish()
        val intent = launch()
        publish(JSONObject().put("tv_player_controls_style", "classic")
            .put("player_night_mode_index", 0), sequence = 2)
        val settings = NativePlayerPreferences.fromIntent(context, intent)
        assertEquals("frost", settings.getString("tv_player_controls_style", "ott"))
        assertEquals("off", settings.getString("player_default_subtitle_language", null))
        assertEquals(3L, settings.getLong("player_night_mode_index", 0))
    }

    @Test fun `handoff never copies addon secrets or authorization`() {
        publish(custom.put("stremio_addons_v1", "private-token").put("authorization", "private-grant"))
        val raw = NativePlayerPreferences.captureForLaunch(context, owner)
        assertFalse(raw.contains("private"))
        assertFalse(raw.contains("authorization"))
        assertFalse(raw.contains("stremio_addons"))
    }

    @Test fun `legacy preferences and old numeric types remain supported`() {
        prefs.edit().putString("flutter.tv_player_controls_style", "frost")
            .putString("flutter.player_default_subtitle_language", "off")
            .putInt("flutter.player_night_mode_index", 2).commit()
        val settings = NativePlayerPreferences.fromIntent(context, Intent())
        assertEquals("frost", settings.getString("tv_player_controls_style", "ott"))
        assertEquals("off", settings.getString("player_default_subtitle_language", null))
        assertEquals(2L, settings.getLong("player_night_mode_index", 0))
        publish()
        assertThrows(IllegalStateException::class.java) { NativePlayerPreferences.fromIntent(context, Intent()) }
    }
}
