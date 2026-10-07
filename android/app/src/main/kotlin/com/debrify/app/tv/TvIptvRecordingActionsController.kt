package com.debrify.app.tv

import android.content.Intent
import android.content.Context
import android.os.Build
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.ContextCompat
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import com.debrify.app.recording.LiveRecordingService
import com.debrify.app.recording.RecordingRegistry
import com.debrify.app.recording.RecordingSchedule
import com.debrify.app.recording.RecordingScheduleStore
import com.debrify.app.recording.RecordingAlarmReceiver

@OptIn(UnstableApi::class)
internal class TvIptvRecordingActionsController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val currentIptvStreamUrl: String?
        val iptvHlsForcedUrls: Set<String>
        val iptvChannels: List<IptvChannelEntry>
        val currentIptvIndex: Int
        val iptvSources: List<IptvSourceEntry>
        val iptvSourceId: String?
        val currentIptvHttpHeaders: Map<String, String>
        val iptvRecordingController: IptvRecordingController
        val iptvRecordButton: AppCompatButton?
        val legacyStoragePermissionRequestCode: Int
    }

    // ── IPTV recording ──────────────────────────────────────────────────────

    /**
     * Engine vs tee. ON (default): Record starts a [LiveRecordingService]
     * capture over its own connection — it survives zaps, Home, and player
     * teardown, and stops only from the button, the notification, or its
     * duration cap. OFF: the original in-player tee ([IptvRecordingController])
     * with its record-what-you-watch, stops-with-the-player semantics.
     * Dart owns the setting; fixed per activity launch (like the player
     * defaults loaded in onCreate).
     */
    val recordingEngineEnabled: Boolean by lazy {
        com.debrify.app.profiles.ProfilePreferenceProjection.getBoolean(
            activity,
            "recording_engine_enabled",
            true,
        )
    }

    /** Repaints the Record button whenever an engine capture starts or ends —
     *  including from the notification's Stop, which the activity never sees. */
    val recordingRegistryListener: () -> Unit = {
        if (!activity.isDestroyed && !activity.isFinishing) updateRecordButtonState()
    }

    fun isCurrentIptvSegmented(): Boolean {
        val url = host.currentIptvStreamUrl ?: return true
        return host.iptvHlsForcedUrls.contains(url) || isSegmentedStreamUrl(url)
    }

    /** The URL the ENGINE would capture for [url], or null when it can't:
     *  the URL itself when progressive, its Xtream `.ts` twin when that
     *  rescues an `.m3u8` channel, nothing for true segmented streams or
     *  non-HTTP transports (rtmp/rtsp/udp/... — the engine is a plain HTTP
     *  client and would fail every attempt after reporting a start). */
    private fun engineRecordableUrl(url: String): String? {
        if (!url.startsWith("http://", ignoreCase = true) &&
            !url.startsWith("https://", ignoreCase = true)
        ) {
            return null
        }
        if (!host.iptvHlsForcedUrls.contains(url) && !isSegmentedStreamUrl(url)) return url
        return xtreamTsTwin(url)
    }

    /**
     * Stricter gate for SCHEDULING: only URLs affirmatively known to be
     * progressive TS. At alarm time nobody is watching, so there is no player
     * probe to catch an extensionless HLS URL — which the raw engine would
     * "record" as looping playlist text. Explicit `.ts` and Xtream live URLs
     * (extensionless default IS TS) qualify.
     */
    private fun isSchedulableStreamUrl(url: String): Boolean {
        val recordable = engineRecordableUrl(url) ?: return false
        val path = recordable.substringBefore('?').substringBefore('#').lowercase()
        if (path.endsWith(".ts") || path.endsWith(".mts") || path.endsWith(".m2ts")) return true
        return Regex("^https?://[^/]+/(?:live/)?[^/]+/[^/]+/\\d+(?:\\.ts)?$")
            .matches(path)
    }

    /** The live engine capture for the CURRENT channel, if any — matched on
     *  the playing URL or its recordable twin. */
    fun engineTaskIdForCurrentChannel(): String? {
        val url = host.currentIptvStreamUrl ?: return null
        RecordingRegistry.taskIdForUrl(url)?.let { return it }
        return engineRecordableUrl(url)?.let { RecordingRegistry.taskIdForUrl(it) }
    }

    private fun recordingResourceFor(entry: IptvChannelEntry?): IptvSourceEntry? {
        val sourceId = entry?.sourceId ?: host.iptvSourceId
        return host.iptvSources.firstOrNull { it.id == sourceId }
    }

    /** Record is offered only when the stream AND the OS can support it.
     *  Pre-Q needs-permission counts as offered: the button is how the user
     *  triggers the storage grant in the first place. */
    private fun canRecordCurrentIptv(): Boolean {
        if (recordingEngineEnabled) {
            if (!LiveRecordingService.isSupported(activity) &&
                !LiveRecordingService.needsLegacyPermission(activity)
            ) {
                return false
            }
            val url = host.currentIptvStreamUrl ?: return false
            return engineRecordableUrl(url) != null
        }
        return IptvRecordingController.isSupported && !isCurrentIptvSegmented()
    }

    /** Reflect record availability + active state on the button. */
    fun updateRecordButtonState() {
        val button = host.iptvRecordButton ?: return
        val engineActive = recordingEngineEnabled && engineTaskIdForCurrentChannel() != null
        if (engineActive || host.iptvRecordingController.isActive) {
            button.text = "Stop"
            button.isEnabled = true
            button.isFocusable = true
            button.alpha = 1f
        } else {
            val recordable = canRecordCurrentIptv()
            button.text = "Record"
            button.isEnabled = recordable
            // A disabled button can still trap D-pad focus; drop it from the
            // focus order so segmented channels skip past it cleanly.
            button.isFocusable = recordable
            button.alpha = if (recordable) 1f else 0.4f
        }
    }

    fun toggleIptvRecording() {
        if (recordingEngineEnabled) {
            toggleEngineRecording()
            return
        }
        if (host.iptvRecordingController.isActive) {
            val result = host.iptvRecordingController.stop()
            updateRecordButtonState()
            Toast.makeText(
                activity,
                if (result.published) {
                    "Recording saved to Downloads/Debrify/Recordings"
                } else {
                    "Recording stopped, but couldn't be added to Downloads"
                },
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!IptvRecordingController.isSupported) {
            Toast.makeText(activity, "Recording needs Android 10 or newer", Toast.LENGTH_SHORT).show()
            return
        }
        if (isCurrentIptvSegmented()) {
            Toast.makeText(activity, "Recording isn't supported for this stream", Toast.LENGTH_SHORT).show()
            return
        }
        val url = host.currentIptvStreamUrl
        if (url.isNullOrEmpty()) return
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        val fileName = "${sanitizeRecordingName(entry?.name ?: "recording")}_${recordingTimestamp()}.ts"
        if (host.iptvRecordingController.start(url, fileName, "video/mp2t")) {
            updateRecordButtonState()
            Toast.makeText(activity, "Recording started", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(activity, "Couldn't start recording", Toast.LENGTH_SHORT).show()
        }
    }

    /** Android 13+ notification permission, asked contextually on the first
     *  record/schedule — same asked-once pref the phone activity uses, so
     *  the user is asked at most once app-wide. Non-blocking: recording
     *  proceeds while the dialog is up (it works without the grant; only
     *  the notifications go silent). */
    private fun maybeAskNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
            activity,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) return
        val prefs = activity.getSharedPreferences("debrify_permissions", Context.MODE_PRIVATE)
        if (prefs.getBoolean("notification_permission_asked", false)) return
        prefs.edit().putBoolean("notification_permission_asked", true).apply()
        androidx.core.app.ActivityCompat.requestPermissions(
            activity,
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun toggleEngineRecording() {
        engineTaskIdForCurrentChannel()?.let { taskId ->
            // Finalization is async in the service; its "Saved" notification is
            // the confirmation. The registry listener repaints the button.
            try {
                activity.startService(
                    Intent(activity, LiveRecordingService::class.java).apply {
                        action = LiveRecordingService.ACTION_STOP
                        putExtra(LiveRecordingService.EXTRA_TASK_ID, taskId)
                    },
                )
                Toast.makeText(activity, "Recording stopped — saving…", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(activity, "Couldn't stop recording", Toast.LENGTH_SHORT).show()
            }
            return
        }
        if (LiveRecordingService.needsLegacyPermission(activity)) {
            // Pre-Q: the grant IS the enable switch. Ask, tell the user to
            // press Record again once allowed; onRequestPermissionsResult
            // repaints the button.
            androidx.core.app.ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                host.legacyStoragePermissionRequestCode,
            )
            Toast.makeText(
                activity,
                "Allow storage access, then press Record again",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!LiveRecordingService.isSupported(activity)) {
            Toast.makeText(activity, "Recording isn't available on this device", Toast.LENGTH_SHORT).show()
            return
        }
        val url = host.currentIptvStreamUrl
        if (url.isNullOrEmpty()) return
        val recordUrl = engineRecordableUrl(url)
        if (recordUrl == null) {
            Toast.makeText(activity, "Recording isn't supported for this stream", Toast.LENGTH_SHORT).show()
            return
        }
        val recordingLimit = LiveRecordingService.maxConcurrent(activity)
        if (RecordingRegistry.live.size >= recordingLimit) {
            Toast.makeText(
                activity,
                "Recording limit reached ($recordingLimit at a time) — " +
                    "stop one, or raise the limit in IPTV settings",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        maybeAskNotificationPermission()
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        val resource = recordingResourceFor(entry)
        val owner = com.debrify.app.profiles.ProfilePreferenceProjection
            .activeJobContext(activity)
        // Drift-tolerant: the channel's resource revision rode in with the
        // launch payload and a sources edit since then bumped every revision.
        // The live grant/feature checks still refuse real revocation.
        if (!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
                activity, owner.profileId, owner.authorizationRevision, "recordings",
                resource?.connectionResourceId, resource?.connectionResourceRevision,
                allowRevisionDrift = true,
            )
        ) {
            Toast.makeText(activity, "Recording is disabled for this profile", Toast.LENGTH_SHORT).show()
            return
        }
        val fileName = "${sanitizeRecordingName(entry?.name ?: "recording")}_${recordingTimestamp()}.ts"
        try {
            ContextCompat.startForegroundService(
                activity,
                LiveRecordingService.buildStartIntent(
                    context = activity,
                    taskId = "rec-${System.currentTimeMillis()}",
                    url = recordUrl,
                    fileName = fileName,
                    channelName = entry?.name ?: "Live channel",
                    headers = HashMap(host.currentIptvHttpHeaders),
                    maxDurationMs = LiveRecordingService.MAX_DURATION_DEFAULT_MS,
                    ownerProfileId = owner.profileId,
                    connectionResourceId = resource?.connectionResourceId,
                    profileAuthorizationRevision = owner.authorizationRevision,
                    resourceAuthorizationRevision = resource?.connectionResourceRevision,
                ),
            )
            Toast.makeText(
                activity,
                "Recording in background — keeps going if you zap or leave",
                Toast.LENGTH_LONG,
            ).show()
        } catch (e: Exception) {
            Toast.makeText(activity, "Couldn't start recording", Toast.LENGTH_SHORT).show()
        }
    }

    /** Confirm-and-schedule for a FUTURE programme picked in the EPG guide.
     *  Everything stays native: the schedule store and alarms need no Dart. */
    fun promptScheduleRecording(entry: IptvChannelEntry, program: IptvEpgProgram) {
        if (!recordingEngineEnabled) {
            Toast.makeText(activity, "Scheduled recording isn't available", Toast.LENGTH_SHORT).show()
            return
        }
        if (LiveRecordingService.needsLegacyPermission(activity)) {
            androidx.core.app.ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                host.legacyStoragePermissionRequestCode,
            )
            Toast.makeText(
                activity,
                "Allow storage access, then pick the programme again",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!LiveRecordingService.isSupported(activity)) {
            Toast.makeText(activity, "Scheduled recording isn't available", Toast.LENGTH_SHORT).show()
            return
        }
        if (!RecordingAlarmReceiver.exactAlarmsGranted(activity)) {
            // An inexact fire couldn't legally start the recording service from
            // the background — refuse rather than schedule something doomed.
            Toast.makeText(
                activity,
                "Allow \"Alarms & reminders\" for Debrify in system settings to schedule recordings",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!isSchedulableStreamUrl(entry.url)) {
            Toast.makeText(activity, "This channel can't be scheduled", Toast.LENGTH_SHORT).show()
            return
        }
        val recordUrl = engineRecordableUrl(entry.url)
        if (recordUrl == null) {
            Toast.makeText(activity, "This channel can't be recorded", Toast.LENGTH_SHORT).show()
            return
        }
        if (RecordingScheduleStore.findDuplicate(activity, recordUrl, program.startMs) != null) {
            Toast.makeText(activity, "Already scheduled", Toast.LENGTH_SHORT).show()
            return
        }
        val timeFormat = android.text.format.DateFormat.getTimeFormat(activity)
        val range = "${timeFormat.format(java.util.Date(program.startMs))} – " +
            timeFormat.format(java.util.Date(program.stopMs))
        // Capacity check folded into the confirm dialog: Android's runtime
        // rule is fire-time skip, so scheduling anyway is honest — but the
        // user must hear about the conflict NOW, while they can still fix it.
        val limit = LiveRecordingService.maxConcurrent(activity)
        val peak = RecordingScheduleStore.peakOverlap(activity, program.startMs, program.stopMs)
        val conflictNote = if (peak + 1 > limit) {
            val names = RecordingScheduleStore
                .overlappingTitles(activity, program.startMs, program.stopMs)
                .take(3)
                .joinToString(" · ")
            "\n\nConflicts with $names — only $limit can record at once, so " +
                "this may be skipped. Raise the limit in IPTV settings, or " +
                "cancel another recording."
        } else {
            ""
        }
        androidx.appcompat.app.AlertDialog.Builder(activity)
            .setTitle(if (conflictNote.isEmpty()) "Record programme" else "Recording conflict")
            .setMessage("${program.title}\n${entry.name} · $range$conflictNote")
            .setPositiveButton("Record") { _, _ ->
                maybeAskNotificationPermission()
                val owner = com.debrify.app.profiles.ProfilePreferenceProjection
                    .activeJobContext(activity)
                val resource = recordingResourceFor(entry)
                // Drift-tolerant: the payload's resource revision predates any
                // sources edit made since launch — see the projection's note.
                if (!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
                        activity, owner.profileId, owner.authorizationRevision, "recordings",
                        resource?.connectionResourceId, resource?.connectionResourceRevision,
                        allowRevisionDrift = true,
                    )
                ) {
                    Toast.makeText(activity, "Recording is disabled for this profile", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                val scheduleId = "sched-${System.currentTimeMillis()}"
				try {
				RecordingScheduleStore.put(
					activity,
                    RecordingSchedule(
                        id = scheduleId,
                        channelName = entry.name,
                        url = recordUrl,
                        headers = HashMap(entry.httpHeaders),
                        startMs = program.startMs,
                        endMs = program.stopMs,
                        programmeTitle = program.title,
                        createdAt = System.currentTimeMillis(),
                        ownerProfileId = owner.profileId,
                        connectionResourceId = resource?.connectionResourceId,
                        profileAuthorizationRevision = owner.authorizationRevision,
                        resourceAuthorizationRevision = resource?.connectionResourceRevision,
						sealedExecutionPayload = null,
					),
				)
				RecordingAlarmReceiver.registerAll(activity)
				Toast.makeText(activity, "Recording scheduled", Toast.LENGTH_SHORT).show()
				} catch (_: Exception) {
					Toast.makeText(activity, "Could not save the recording schedule", Toast.LENGTH_SHORT).show()
				}
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /** Finalize any active recording (channel change / exit). Safe when idle.
     *  Silent on success — the user didn't ask for this stop — but a failed
     *  publish is worth saying out loud, since the file is invisible. */
    fun finalizeIptvRecordingIfActive() {
        if (!host.iptvRecordingController.isActive) return
        val result = host.iptvRecordingController.stop()
        updateRecordButtonState()
        if (result.wasRecording && !result.published && !activity.isFinishing) {
            Toast.makeText(
                activity,
                "Recording stopped, but couldn't be added to Downloads",
                Toast.LENGTH_LONG,
            ).show()
        }
    }
    private val notificationPermissionRequestCode = 7403
}
