package com.debrify.app.tv

import android.Manifest
import android.content.Context
import android.content.Intent
import androidx.appcompat.widget.AppCompatButton
import com.debrify.app.recording.LiveRecordingService
import com.debrify.app.recording.RecordingRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvRecordingCharacterizationTest : TvPhase3OriginalTest() {
    private fun prefs() = activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private fun engine(on: Boolean) = prefs().edit().putBoolean("flutter.recording_engine_enabled", on).commit()
    private fun channel(url: String = "https://example.test/live/u/p/3.m3u8"): IptvChannelEntry =
        p2Channel().copy(name = "TV / Cinema", url = url).also {
            set("currentIptvStreamUrl", url); set("iptvChannels", listOf(it))
            set("currentIptvHttpHeaders", mapOf("X-Test" to "header"))
        }
    @After fun clearRegistry() { RecordingRegistry.live.clear(); RecordingRegistry.pendingStarts.clear() }

    @Test fun enginePreferenceIsReadOnFirstAccessAndThenFrozenWhileTeeRemainsLazy() {
        val enabled = field("recordingEngineEnabled\$delegate") as Lazy<*>
        val tee = field("iptvRecordingController\$delegate") as Lazy<*>
        assertFalse(enabled.isInitialized()); assertFalse(tee.isInitialized())
        engine(false); assertEquals(false, invoke("getRecordingEngineEnabled"))
        engine(true); assertEquals(false, invoke("getRecordingEngineEnabled"))
        assertFalse(tee.isInitialized())
        invoke("updateRecordButtonState"); assertFalse("no view means no tee access", tee.isInitialized())
        set("iptvRecordButton", AppCompatButton(activity)); channel("https://example.test/live.ts")
        invoke("updateRecordButtonState"); assertTrue(tee.isInitialized())
        set("currentIptvStreamUrl", "https://example.test/true.m3u8")
        assertEquals(false, invoke("canRecordCurrentIptv"))
    }

    @Test @Config(sdk = [28]) fun sdk28OffersEnginePermissionPathButNeverOffersTheUnsupportedTee() {
        channel("https://example.test/live.ts")
        shadowOf(activity).denyPermissions(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        assertEquals(true, invoke("canRecordCurrentIptv"))
        invoke("toggleIptvRecording")
        val request = shadowOf(activity).lastRequestedPermission
        assertArrayEquals(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), request.requestedPermissions)
        assertEquals(field("legacyStoragePermissionRequestCode"), request.requestCode)
        assertNull(shadowOf(activity).nextStartedService)
        assertEquals("Allow storage access, then press Record again", ShadowToast.getTextOfLatestToast())
        shadowOf(activity).grantPermissions(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        invoke("toggleIptvRecording"); assertNotNull("grant permits the next start", shadowOf(activity).nextStartedService)
        // Use a fresh original activity, so its first lazy read sees tee mode.
        engine(false)
        val other = org.robolectric.Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()
        TvPlayerOriginalAccess.set(other, "currentIptvStreamUrl", "https://example.test/live.ts")
        assertEquals(false, TvPlayerOriginalAccess.callTyped(other, "canRecordCurrentIptv", emptyArray()))
        (TvPlayerOriginalAccess.field(other, "skipSegmentScope") as kotlinx.coroutines.CoroutineScope).coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }

    @Test fun sdk29EngineStartsWithTwinHeadersNameOwnerAndDurationThenStopsExistingTask() {
        val entry = channel(); invoke("toggleIptvRecording")
        val intent = shadowOf(activity).nextStartedService
        assertNotNull("engine START intent", intent)
        assertEquals(LiveRecordingService.ACTION_START, intent.action)
        assertEquals("https://example.test/live/u/p/3.ts", intent.getStringExtra(LiveRecordingService.EXTRA_URL))
        assertEquals(entry.name, intent.getStringExtra(LiveRecordingService.EXTRA_CHANNEL_NAME))
        assertEquals(mapOf("X-Test" to "header"), intent.getSerializableExtra(LiveRecordingService.EXTRA_HEADERS))
        assertTrue(intent.getStringExtra(LiveRecordingService.EXTRA_FILE_NAME)!!.matches(Regex("TV_Cinema_\\d{8}_\\d{6}\\.ts")))
        assertEquals(LiveRecordingService.MAX_DURATION_DEFAULT_MS, intent.getLongExtra(LiveRecordingService.EXTRA_MAX_DURATION_MS, -1))
        assertEquals("legacy-admin-v1", intent.getStringExtra(LiveRecordingService.EXTRA_OWNER_PROFILE_ID))
        assertNull("SDK 29 does not request notification permission", shadowOf(activity).lastRequestedPermission)
        RecordingRegistry.live["task"] = RecordingRegistry.Live("https://example.test/live/u/p/3.ts", "TV", "f", 0)
        invoke("toggleIptvRecording")
        val stop = shadowOf(activity).nextStartedService
        assertEquals(LiveRecordingService.ACTION_STOP, stop.action)
        assertEquals("task", stop.getStringExtra(LiveRecordingService.EXTRA_TASK_ID))
    }

    @Test fun recordButtonBindsLateAndTracksAvailableDisabledAndActiveEngineStates() {
        invoke("updateRecordButtonState")
        val button = AppCompatButton(activity); set("iptvRecordButton", button)
        channel("https://example.test/plain.ts"); invoke("updateRecordButtonState")
        assertEquals("Record", button.text.toString()); assertTrue(button.isEnabled); assertTrue(button.isFocusable); assertEquals(1f, button.alpha)
        channel("https://example.test/true.m3u8"); invoke("updateRecordButtonState")
        assertFalse(button.isEnabled); assertFalse(button.isFocusable); assertEquals(0.4f, button.alpha)
        RecordingRegistry.live["task"] = RecordingRegistry.Live("https://example.test/true.m3u8", "TV", "f", 0)
        invoke("updateRecordButtonState")
        assertEquals("Stop", button.text.toString()); assertTrue(button.isEnabled); assertTrue(button.isFocusable); assertEquals(1f, button.alpha)
    }

    @Test fun streamEligibilityKeepsForcedHlsAndNonHttpOutOfTeeAndChecksSchedulingExtensions() {
        channel("https://example.test/no-extension")
        assertEquals("https://example.test/no-extension", invoke("engineRecordableUrl", "https://example.test/no-extension"))
        set("iptvHlsForcedUrls", mutableSetOf("https://example.test/no-extension"))
        assertNull(invoke("engineRecordableUrl", "https://example.test/no-extension"))
        for (url in listOf("rtmp://example.test/live.ts", "https://example.test/playlist.m3u8")) assertNull(invoke("engineRecordableUrl", url))
        for (ext in listOf("ts", "mts", "m2ts")) assertEquals(true, invoke("isSchedulableStreamUrl", "https://example.test/a.$ext?x=1#frag"))
        assertEquals(false, invoke("isSchedulableStreamUrl", "https://example.test/no-extension"))
        assertEquals(true, invoke("isSchedulableStreamUrl", "https://example.test/live/u/p/3.m3u8"))
    }

    @Test fun fullEngineCapacityBlocksStartAndReadsTheLimitAgainForTheNextAttempt() {
        channel("https://example.test/plain.ts")
        RecordingRegistry.live["other"] = RecordingRegistry.Live("https://other.test/a.ts", "other", "f", 0)
        prefs().edit().putLong("flutter.recording_max_concurrent", 1).commit()
        invoke("toggleIptvRecording"); assertNull(shadowOf(activity).nextStartedService)
        assertTrue(ShadowToast.getTextOfLatestToast().toString().contains("Recording limit reached (1 at a time)"))
        prefs().edit().putLong("flutter.recording_max_concurrent", 2).commit()
        invoke("toggleIptvRecording"); assertNotNull(shadowOf(activity).nextStartedService)
    }

    @Test @Config(sdk = [33]) fun notificationPermissionIsAskedOnceAndRecordingContinuesWithoutIt() {
        channel("https://example.test/plain.ts"); shadowOf(activity).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        invoke("toggleIptvRecording")
        assertNotNull(shadowOf(activity).nextStartedService)
        val permission = shadowOf(activity).lastRequestedPermission
        assertArrayEquals(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permission.requestedPermissions)
        assertEquals(field("notificationPermissionRequestCode"), permission.requestCode)
        assertTrue(activity.getSharedPreferences("debrify_permissions", 0).getBoolean("notification_permission_asked", false))
        invoke("maybeAskNotificationPermission"); assertSame(permission, shadowOf(activity).lastRequestedPermission)
    }

    @Test fun queuedRegistryNotificationUsesMembershipWhenDeliveredAndAddIsIdempotent() {
        val calls = mutableListOf<String>(); val first = { calls.add("first"); Unit }; val second = { calls.add("second"); Unit }
        try {
            RecordingRegistry.addListener(first); RecordingRegistry.addListener(first)
            RecordingRegistry.notifyChanged(); RecordingRegistry.removeListener(first); RecordingRegistry.addListener(second)
            assertTrue(calls.isEmpty()); idle(); assertEquals(listOf("second"), calls)
            calls.clear(); RecordingRegistry.addListener(second); RecordingRegistry.notifyChanged(); idle()
            assertEquals(listOf("second"), calls)
        } finally { RecordingRegistry.removeListener(first); RecordingRegistry.removeListener(second) }
    }
}
