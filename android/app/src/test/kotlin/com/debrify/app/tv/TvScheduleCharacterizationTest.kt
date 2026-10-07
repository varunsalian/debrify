package com.debrify.app.tv

import android.content.Context
import androidx.appcompat.app.AlertDialog
import com.debrify.app.recording.RecordingScheduleStore
import com.debrify.app.security.DeviceSecretCipherPlugin
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowToast

/** AAD-preserving test cipher: schedule authorization/storage remain production code. */
@Implements(value = DeviceSecretCipherPlugin::class, isInAndroidSdk = false)
class TvScheduleCipherShadow {
    companion object {
        var failSeal = false
        @org.robolectric.annotation.Resetter @JvmStatic fun reset() { failSeal = false }
        private val payloads = mutableMapOf<String, Pair<ByteArray, ByteArray>>()
        @Implementation @JvmStatic fun sealForNative(plaintext: ByteArray, aad: ByteArray): String =
            if (failSeal) throw java.io.IOException("fixture seal failure") else
                ("test-envelope-${payloads.size}").also { payloads[it] = plaintext.copyOf() to aad.copyOf() }
        @Implementation @JvmStatic fun openForNative(envelope: String, aad: ByteArray): ByteArray {
            val stored = payloads[envelope] ?: error("unknown test envelope")
            check(stored.second.contentEquals(aad)) { "schedule AAD differs" }
            return stored.first.copyOf()
        }
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], shadows = [TvScheduleCipherShadow::class],
    instrumentedPackages = ["com.debrify.app.security.DeviceSecretCipherPlugin"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvScheduleCharacterizationTest : TvPhase3OriginalTest() {
    private fun publish(profile: String, enabled: Boolean = true, resourceGranted: Boolean = true) {
        val authority = JSONObject().put("revision", 17).put("enabled", enabled)
            .put("features", JSONArray().put("recordings"))
            .put("resources", JSONObject().put("r1", JSONObject().put("revision", 1).put("permissions", if (resourceGranted) 2 else 0))
                .put("r2", JSONObject().put("revision", 12).put("permissions", 2)))
        val root = JSONObject().put("version", 2).put("state", "active").put("profileId", profile)
            .put("publication", 1).put("values", JSONObject().put("recording_engine_enabled", true))
            .put("authorization", JSONObject().put("a", authority).put("b", authority))
        activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().clear()
            .putString("flutter.profiles_runtime_mode_v1", "profileCommitted")
            .putLong("flutter.profiles_native_projection_sequence_v1", 1)
            .putString("flutter.profiles_native_projection_v1", root.toString()).commit()
    }
    private fun sources(resource: String, revision: Long) = set("iptvSources", listOf(
        IptvSourceEntry("source", "Source", false, false, false, connectionResourceId = resource, connectionResourceRevision = revision)))
    private fun dialog(): Pair<AlertDialog, IptvEpgProgram> {
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        val entry = p2Channel().copy(url = "https://example.test/channel.ts", sourceId = "source", httpHeaders = mapOf("X-Test" to "header"))
        val start = System.currentTimeMillis() + 3_600_000L
        val program = IptvEpgProgram("Programme", "description", start, start + 3_600_000L, false)
        call("promptScheduleRecording", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java), entry, program)
        return (ShadowDialog.getLatestDialog() as AlertDialog) to program
    }
    private fun confirm(dialog: AlertDialog) { dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); idle() }

    @Test fun confirmationCapturesTheProfileAtClickAndPersistsTheExecutionPayload() {
        publish("a"); sources("r1", 1)
        val (dialog, program) = dialog()
        assertTrue(RecordingScheduleStore.all(activity).isEmpty())
        publish("b"); confirm(dialog)
        val saved = RecordingScheduleStore.all(activity)
        assertEquals("saved schedule; toast=${ShadowToast.getTextOfLatestToast()}", 1, saved.size)
        val schedule = saved.values.single()
        assertEquals("b", schedule.ownerProfileId); assertEquals(17L, schedule.profileAuthorizationRevision)
        assertEquals(program.startMs, schedule.startMs); assertEquals(program.stopMs, schedule.endMs)
        assertEquals("Programme", schedule.programmeTitle); assertEquals("Cinema", schedule.channelName)
        assertEquals("https://example.test/channel.ts", schedule.url); assertEquals(mapOf("X-Test" to "header"), schedule.headers)
        assertNotNull(schedule.sealedExecutionPayload)
        val stored = activity.getSharedPreferences("debrify_recording_schedules", 0).getString("schedules_v1", "")!!
        assertFalse("committed schedule keeps URL sealed", stored.contains("https://example.test"))
    }

    @Test fun confirmationResolvesTheResourceFromTheLiveSourceTableAtClick() {
        publish("a"); sources("r1", 1)
        val (dialog, _) = dialog(); sources("r2", 12); confirm(dialog)
        val saved = RecordingScheduleStore.all(activity)
        assertEquals("saved schedule; toast=${ShadowToast.getTextOfLatestToast()}", 1, saved.size)
        val schedule = saved.values.single()
        assertEquals("r2", schedule.connectionResourceId); assertEquals(12L, schedule.resourceAuthorizationRevision)
        assertEquals("a", schedule.ownerProfileId)
    }

    @Test fun authorizationRevokedWhileDialogIsOpenIsRejectedBeforePersisting() {
        publish("a"); sources("r1", 1)
        val (dialog, _) = dialog(); publish("a", enabled = false); confirm(dialog)
        assertTrue(RecordingScheduleStore.all(activity).isEmpty())
        assertEquals("Recording is disabled for this profile", ShadowToast.getTextOfLatestToast())
    }

    @Test fun resourceGrantRevokedWhileDialogIsOpenIsRejectedBeforePersisting() {
        publish("a"); sources("r1", 1)
        val (dialog, _) = dialog(); publish("a", resourceGranted = false); confirm(dialog)
        assertTrue(RecordingScheduleStore.all(activity).isEmpty())
        assertEquals("Recording is disabled for this profile", ShadowToast.getTextOfLatestToast())
    }

    @Test fun engineStartResolvesLiveProfileAndConnectionResourceAtInvocation() {
        publish("a"); sources("r1", 1)
        val entry = p2Channel().copy(url = "https://example.test/channel.ts", sourceId = "source")
        set("currentIptvStreamUrl", entry.url); set("iptvChannels", listOf(entry))
        publish("b"); sources("r2", 12); invoke("toggleIptvRecording")
        val intent = org.robolectric.Shadows.shadowOf(activity).nextStartedService
        assertNotNull("authorized engine START", intent)
        val service = com.debrify.app.recording.LiveRecordingService
        assertEquals("b", intent.getStringExtra(service.EXTRA_OWNER_PROFILE_ID))
        assertEquals(17L, intent.getLongExtra(service.EXTRA_PROFILE_AUTH_REVISION, -1))
        assertEquals("r2", intent.getStringExtra(service.EXTRA_CONNECTION_RESOURCE_ID))
        assertEquals(12L, intent.getLongExtra(service.EXTRA_RESOURCE_AUTH_REVISION, -1))
    }
}
