package com.debrify.app.profiles

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity
import com.debrify.app.tv.TorboxTvPlayerActivity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NativePlayerSettingsConsumptionTest {
    private fun intent(custom: Boolean, onlyForeign: Boolean = false): Intent {
        val context = RuntimeEnvironment.getApplication()
        val owner = mapOf("profileId" to "probe", "dataGeneration" to 1, "sessionEpoch" to 1)
        val values = if (custom) JSONObject()
            .put("tv_player_controls_style", "frost")
            .put("debrify_tv_player_style", "network")
            .put("player_default_subtitle_language", "off")
            .put("player_night_mode_index", 3) else JSONObject()
        if (onlyForeign) values.put("subtitle_only_foreign_audio", true)
            .put("player_default_audio_language", "en")
            .put("player_default_subtitle_language", "en")
        val root = JSONObject(owner).put("version", 2).put("state", "active")
            .put("publication", 1).put("values", values)
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear()
            .putString("flutter.profiles_runtime_mode_v1", "profileCommitted")
            .putLong("flutter.profiles_native_projection_sequence_v1", 1)
            .putString("flutter.profiles_native_projection_v1", root.toString()).commit()
        ProfilePrivacyState.update(context, false, false)
        return Intent().putExtra(NativePlayerPreferences.EXTRA, NativePlayerPreferences.captureForLaunch(context, owner))
            .putExtra("initialUrl", "file:///nonexistent-settings-fixture.mp4")
            .putExtra("initialTitle", "Settings test")
            .putExtra("provider", "torbox")
            .putExtra("payload", """{"contentType":"movie","items":[{"id":"probe","index":0,"title":"Settings test","url":"file:///nonexistent-settings-fixture.mp4"}]}""")
    }

    private fun field(activity: Activity, name: String): Any? = activity.javaClass.getDeclaredField(name)
        .apply { isAccessible = true }.get(activity)

    private fun assertDefaults(activity: Activity, custom: Boolean) {
        assertFalse(activity.isFinishing)
        assertEquals(if (custom) 3 else 0, field(activity, "nightModeIndex"))
        val selector = field(activity, "trackSelector") as DefaultTrackSelector
        assertEquals(custom, selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun channelPlayerWaitsForAudioAndRespectsManualSubtitlesUntilNextItem() {
        val lifecycle = Robolectric.buildActivity(TorboxTvPlayerActivity::class.java,
            intent(custom = false, onlyForeign = true)).create()
        try {
            val activity = lifecycle.get()
            val selector = field(activity, "trackSelector") as DefaultTrackSelector
            assertTrue(selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
            val optionType = Class.forName("com.debrify.app.tv.TorboxTvPlayerActivity\$TrackOption")
            val group = Tracks.Group(TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.TEXT_VTT)
                .setLanguage("en").build()), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))
            val option = optionType.getDeclaredConstructor(Tracks.Group::class.java, Int::class.javaPrimitiveType, String::class.java)
                .apply { isAccessible = true }.newInstance(group, 0, "English")
            activity.javaClass.getDeclaredMethod("applySubtitleTrack", optionType)
                .apply { isAccessible = true }.invoke(activity, option)
            activity.javaClass.getDeclaredMethod("ensureDefaultSubtitleSelected")
                .apply { isAccessible = true }.invoke(activity)
            assertFalse(selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
            activity.javaClass.getDeclaredMethod("resetSubtitleState")
                .apply { isAccessible = true }.invoke(activity)
            assertTrue(selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        } finally { lifecycle.destroy() }
    }

    @Test fun moviePlayerConsumesDefaultsAndCustomSettings() {
        for (custom in listOf(false, true)) {
            val lifecycle = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java, intent(custom)).create()
            try {
                assertDefaults(lifecycle.get(), custom)
                val style = lifecycle.get().javaClass.getDeclaredMethod("getControlsSkin")
                    .apply { isAccessible = true }.invoke(lifecycle.get())?.toString()
                assertEquals(if (custom) "FROST" else "OTT", style)
            } finally { lifecycle.destroy() }
        }
    }

    @Test fun debrifyTvPlayerConsumesDefaultsAndCustomSettings() {
        for (custom in listOf(false, true)) {
            val lifecycle = Robolectric.buildActivity(TorboxTvPlayerActivity::class.java, intent(custom)).create()
            try {
                assertDefaults(lifecycle.get(), custom)
                assertEquals(if (custom) "NETWORK" else "CINEMA", field(lifecycle.get(), "playerStyle").toString())
                if (custom) {
                    val optionType = Class.forName("com.debrify.app.tv.TorboxTvPlayerActivity\$TrackOption")
                    val group = Tracks.Group(TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.TEXT_VTT)
                        .setLanguage("en").build()), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))
                    val option = optionType.getDeclaredConstructor(Tracks.Group::class.java, Int::class.javaPrimitiveType, String::class.java)
                        .apply { isAccessible = true }.newInstance(group, 0, "English")
                    val choose = lifecycle.get().javaClass.getDeclaredMethod("applySubtitleTrack", optionType)
                        .apply { isAccessible = true }
                    choose.invoke(lifecycle.get(), option)
                    val selector = field(lifecycle.get(), "trackSelector") as DefaultTrackSelector
                    assertFalse(selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
                    choose.invoke(lifecycle.get(), null)
                    assertTrue(selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
                }
            } finally { lifecycle.destroy() }
        }
    }
}
