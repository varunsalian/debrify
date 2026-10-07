package com.debrify.app.tv

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.annotation.Resetter
import org.robolectric.shadows.ShadowContextImpl
import org.robolectric.shadows.ShadowToast

/** A platform permission revoked between two real ContextCompat reads. */
@Implements(className = "android.app.ContextImpl")
class TvRecordingPermissionSequenceShadow : ShadowContextImpl() {
    companion object {
        var legacyReads = 0
        @Resetter @JvmStatic fun resetFixture() { legacyReads = 0 }
    }
    @Implementation override fun checkPermission(permission: String, pid: Int, uid: Int): Int {
        if (permission == Manifest.permission.WRITE_EXTERNAL_STORAGE) {
            return if (legacyReads++ == 0) PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED
        }
        return super.checkPermission(permission, pid, uid)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvRecordingPermissionSequenceShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvRecordingBoundaryMessagesCharacterizationTest : TvPhase3OriginalTest() {
    private fun setup() {
        TvRecordingPermissionSequenceShadow.legacyReads = 0
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear()
            .putBoolean("flutter.recording_engine_enabled", true).commit()
        set("currentIptvStreamUrl", "https://example.test/channel.ts")
    }
    private fun toast(text: String) {
        assertEquals(text, ShadowToast.getTextOfLatestToast())
        assertEquals(Toast.LENGTH_SHORT, ShadowToast.getLatestToast().duration)
    }
    private fun prompt() {
        val p = IptvEpgProgram("Programme", null, System.currentTimeMillis() + 3_600_000,
            System.currentTimeMillis() + 7_200_000, false)
        call("promptScheduleRecording", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java),
            p2Channel().copy(url = "https://example.test/channel.ts"), p)
    }
    @Test fun permissionRevokedBetweenChecksUsesTheEngineUnavailableMessage() {
        setup(); invoke("toggleIptvRecording")
        assertEquals(2, TvRecordingPermissionSequenceShadow.legacyReads)
        toast("Recording isn't available on this device")
    }
    @Test fun permissionRevokedBetweenChecksUsesTheScheduleUnavailableMessage() {
        setup(); prompt()
        assertEquals(2, TvRecordingPermissionSequenceShadow.legacyReads)
        toast("Scheduled recording isn't available")
    }
    @Test @Config(sdk = [29]) fun forcedHlsChangeBetweenEligibilityReadsUsesTheUnrecordableMessage() {
        setup()
        // The first lookup observes a progressive URL; after it returns, the
        // live forced-HLS set changes before the confirmation's second lookup.
        val forced = object : LinkedHashSet<String>() {
            var reads = 0
            override fun contains(element: String): Boolean {
                val found = super.contains(element)
                if (++reads == 1) add(element)
                return found
            }
        }
        set("iptvHlsForcedUrls", forced); prompt()
        assertEquals(2, forced.reads)
        toast("This channel can't be recorded")
    }
}
