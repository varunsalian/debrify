package com.debrify.app.tv

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import com.debrify.app.recording.RecordingRegistry
import com.debrify.app.recording.RecordingSchedule
import com.debrify.app.recording.RecordingScheduleStore
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowContextImpl
import org.robolectric.shadows.ShadowContentResolver
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowToast
import java.io.File

/** OS service failure only; production action, authorization and payload stay real. */
@Implements(className = "android.app.ContextImpl")
class TvRecordingServiceFailureShadow : ShadowContextImpl() {
    companion object {
        var fail = false
        @Resetter @JvmStatic fun resetFixture() { fail = false }
    }
    @Implementation override fun startService(intent: Intent): ComponentName? {
        if (fail) throw SecurityException("fixture service failure")
        return super.startService(intent)
    }
    @Implementation override fun startForegroundService(intent: Intent): ComponentName? {
        if (fail) throw SecurityException("fixture foreground service failure")
        return super.startForegroundService(intent)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], shadows = [TvRecordingServiceFailureShadow::class, TvScheduleCipherShadow::class],
    instrumentedPackages = ["com.debrify.app.security.DeviceSecretCipherPlugin"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvRecordingMessagesCharacterizationTest : TvPhase3OriginalTest() {
    private fun toast(text: String, duration: Int = Toast.LENGTH_SHORT) {
        assertEquals(text, ShadowToast.getTextOfLatestToast())
        assertEquals(duration, ShadowToast.getLatestToast().duration)
    }
    private fun setup(engine: Boolean = true) {
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear()
            .putBoolean("flutter.recording_engine_enabled", engine).commit()
        set("currentIptvStreamUrl", "https://example.test/channel.ts")
        set("iptvChannels", listOf(p2Channel()))
    }
    private fun provider() = TvRecordingMediaStoreProvider().also {
        it.file = File(activity.cacheDir, "messages-tee.ts")
        it.attachInfo(activity, android.content.pm.ProviderInfo().apply { authority = "media" })
        ShadowContentResolver.registerProviderInternal("media", it)
    }
    private fun entry(url: String = "https://example.test/channel.ts") = p2Channel().copy(url = url)
    private fun program() = IptvEpgProgram("Programme", "Description", System.currentTimeMillis() + 3_600_000,
        System.currentTimeMillis() + 7_200_000, false)
    private fun prompt(e: IptvChannelEntry = entry(), p: IptvEpgProgram = program()) =
        call("promptScheduleRecording", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java), e, p)
    private fun confirm() {
        (ShadowDialog.getLatestDialog() as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick(); idle()
    }
    @After fun clear() {
        RecordingRegistry.live.clear(); RecordingRegistry.pendingStarts.clear()
        TvScheduleCipherShadow.failSeal = false; TvRecordingServiceFailureShadow.fail = false
    }

    @Test fun teeStartStopAndFailedPublicationKeepExactMessages() {
        setup(false); val provider = provider(); invoke("toggleIptvRecording")
        toast("Recording started"); invoke("toggleIptvRecording")
        toast("Recording saved to Downloads/Debrify/Recordings", Toast.LENGTH_LONG)
        invoke("toggleIptvRecording"); provider.failPublish = true; invoke("toggleIptvRecording")
        toast("Recording stopped, but couldn't be added to Downloads", Toast.LENGTH_LONG)
    }
    @Test fun teeInsertFailureAndSegmentedStreamKeepExactMessages() {
        setup(false); provider().failInsert = true; invoke("toggleIptvRecording")
        toast("Couldn't start recording")
        set("currentIptvStreamUrl", "https://example.test/true.m3u8"); invoke("toggleIptvRecording")
        toast("Recording isn't supported for this stream")
    }
    @Test @Config(sdk = [28]) fun unsupportedTeeKeepsItsPlatformMessage() {
        setup(false); invoke("toggleIptvRecording"); toast("Recording needs Android 10 or newer")
    }
    @Test fun finalizeReportsPublicationFailureButIsSilentWhenFinishing() {
        setup(false); val provider = provider(); invoke("toggleIptvRecording"); provider.failPublish = true
        invoke("finalizeIptvRecordingIfActive")
        toast("Recording stopped, but couldn't be added to Downloads", Toast.LENGTH_LONG)
        provider.failPublish = false; invoke("toggleIptvRecording"); toast("Recording started")
        provider.failPublish = true; activity.finish(); invoke("finalizeIptvRecordingIfActive")
        toast("Recording started")
    }
    @Test fun engineStartStopAndBothServiceFailuresKeepExactMessages() {
        setup(); invoke("toggleIptvRecording")
        toast("Recording in background — keeps going if you zap or leave", Toast.LENGTH_LONG)
        RecordingRegistry.live["task"] = RecordingRegistry.Live("https://example.test/channel.ts", "TV", "f", 0)
        invoke("toggleIptvRecording"); toast("Recording stopped — saving…")
        TvRecordingServiceFailureShadow.fail = true; invoke("toggleIptvRecording"); toast("Couldn't stop recording")
        RecordingRegistry.live.clear(); invoke("toggleIptvRecording"); toast("Couldn't start recording")
    }
    @Test fun engineFallbackNameAndRevokedProfileMessageRemainExact() {
        setup(); set("iptvChannels", emptyList<IptvChannelEntry>()); invoke("toggleIptvRecording")
        val intent = shadowOf(activity).nextStartedService
        assertEquals("Live channel", intent.getStringExtra(com.debrify.app.recording.LiveRecordingService.EXTRA_CHANNEL_NAME))
        assertTrue(intent.getStringExtra(com.debrify.app.recording.LiveRecordingService.EXTRA_FILE_NAME)!!.startsWith("recording_"))
        val root = JSONObject().put("version", 2).put("state", "active").put("profileId", "a").put("publication", 1)
            .put("values", JSONObject()).put("authorization", JSONObject().put("a", JSONObject().put("revision", 1)
                .put("enabled", false).put("features", JSONArray().put("recordings"))))
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.profiles_runtime_mode_v1", "profileCommitted").putLong("flutter.profiles_native_projection_sequence_v1", 1)
            .putString("flutter.profiles_native_projection_v1", root.toString()).commit()
        invoke("toggleIptvRecording"); toast("Recording is disabled for this profile")
    }
    @Test fun engineUnsupportedStreamAndCapacityMessageRemainExact() {
        setup(); set("currentIptvStreamUrl", "rtmp://example.test/live"); invoke("toggleIptvRecording")
        toast("Recording isn't supported for this stream")
        set("currentIptvStreamUrl", "https://example.test/channel.ts")
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putLong("flutter.recording_max_concurrent", 1).commit()
        RecordingRegistry.live["other"] = RecordingRegistry.Live("https://other.test/live.ts", "Other", "f", 0)
        invoke("toggleIptvRecording")
        toast("Recording limit reached (1 at a time) — stop one, or raise the limit in IPTV settings", Toast.LENGTH_LONG)
    }
    @Test @Config(sdk = [28]) fun engineAndSchedulePermissionMessagesRemainExact() {
        setup(); shadowOf(activity).denyPermissions(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        invoke("toggleIptvRecording"); toast("Allow storage access, then press Record again", Toast.LENGTH_LONG)
        prompt(); toast("Allow storage access, then pick the programme again", Toast.LENGTH_LONG)
    }
    @Test fun disabledSchedulingAndNonProgressiveSchedulingKeepExactMessages() {
        setup(false); prompt(); toast("Scheduled recording isn't available")
        val other = org.robolectric.Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()
        try {
            activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putBoolean("flutter.recording_engine_enabled", true).commit()
            TvPlayerOriginalAccess.callTyped(other, "promptScheduleRecording", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java),
                entry("https://example.test/no-extension"), program())
            toast("This channel can't be scheduled")
        } finally {
            (TvPlayerOriginalAccess.field(other, "skipSegmentScope") as kotlinx.coroutines.CoroutineScope).coroutineContext[kotlinx.coroutines.Job]?.cancel()
        }
    }
    @Test @Config(sdk = [33]) fun exactAlarmPermissionMessageRemainsExact() {
        setup(); org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(false)
        prompt(); toast("Allow \"Alarms & reminders\" for Debrify in system settings to schedule recordings", Toast.LENGTH_LONG)
    }
    private fun stored(p: IptvEpgProgram, name: String, url: String = "https://other.test/live.ts") {
        RecordingScheduleStore.put(activity, RecordingSchedule(name, "Other", url, hashMapOf(), p.startMs, p.stopMs, name, 0))
    }
    @Test fun scheduleDuplicateConflictDialogAndSuccessKeepAllVisibleText() {
        setup(); val p = program(); stored(p, "First"); stored(p, "Second", "https://other.test/second.ts")
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putLong("flutter.recording_max_concurrent", 1).commit()
        prompt(p = p); val dialog = ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Recording conflict", dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        val format = android.text.format.DateFormat.getTimeFormat(activity)
        val range = "${format.format(java.util.Date(p.startMs))} – ${format.format(java.util.Date(p.stopMs))}"
        assertEquals("Programme\nCinema · $range\n\nConflicts with Second · First — only 1 can record at once, so " +
            "this may be skipped. Raise the limit in IPTV settings, or cancel another recording.",
            dialog.findViewById<TextView>(android.R.id.message)!!.text.toString())
        assertEquals("Record", dialog.getButton(AlertDialog.BUTTON_POSITIVE).text.toString())
        assertEquals("Cancel", dialog.getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        confirm(); toast("Recording scheduled"); prompt(p = p); toast("Already scheduled")
    }
    @Test fun plainScheduleDialogAndStorageFailureKeepExactVisibleText() {
        setup(); val p = program(); prompt(p = p); val dialog = ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Record programme", dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        val authority = JSONObject().put("revision", 1).put("enabled", true).put("features", JSONArray().put("recordings"))
        val root = JSONObject().put("version", 2).put("state", "active").put("profileId", "a").put("publication", 1)
            .put("values", JSONObject().put("recording_engine_enabled", true)).put("authorization", JSONObject().put("a", authority))
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.profiles_runtime_mode_v1", "profileCommitted").putLong("flutter.profiles_native_projection_sequence_v1", 1)
            .putString("flutter.profiles_native_projection_v1", root.toString()).commit()
        TvScheduleCipherShadow.failSeal = true; confirm(); toast("Could not save the recording schedule")
    }
}
