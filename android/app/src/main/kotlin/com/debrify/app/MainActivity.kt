package com.debrify.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognizerIntent
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.util.DisplayMetrics
import android.util.Rational
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.core.view.WindowCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterJNI
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import org.json.JSONObject
import org.json.JSONArray

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.debrify.app/downloader"
	private val EVENTS = "com.debrify.app/downloader_events"

	// ── SAF download-folder picker ──────────────────────────────────────────
	private val REQUEST_PICK_DOWNLOAD_DIR = 51423
	private var pendingDirPickResult: MethodChannel.Result? = null

	// ── TV voice dictation (in-app SpeechRecognizer) ────────────────────────
	// Deliberately NOT the ACTION_RECOGNIZE_SPEECH activity: that hands the
	// screen to a system voice UI, which pauses us (trailer/playback lifecycle)
	// and drops a foreign text box over the Debrify keyboard. We bind the
	// recognition SERVICE instead and stream its events to Dart, so the whole
	// listening state is drawn inside our own keyboard panel.
	private val VOICE_CHANNEL = "debrify/tv_voice"
	private val VOICE_EVENTS = "debrify/tv_voice_events"
	private val PLAYER_DIAGNOSTICS_CHANNEL = "debrify/player_diagnostics"
	// SecretVault key derivation. ANDROID_ID is per-device (scoped to our
	// signing key + user since Android 8, stable across OTAs) — unlike the
	// build/model fields device_info_plus exposes, which every unit of the
	// same model shares and which therefore bind nothing.
	private val DEVICE_ID_CHANNEL = "debrify/device"
	private val recordAudioPermissionRequestCode = 7404
	private var pendingVoicePermissionResult: MethodChannel.Result? = null
	private var speechRecognizer: android.speech.SpeechRecognizer? = null
	private var voiceEvents: EventChannel.EventSink? = null

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (requestCode == REQUEST_PICK_DOWNLOAD_DIR) {
			val pending = pendingDirPickResult
			pendingDirPickResult = null
			if (pending != null) {
				val treeUri = data?.data
				if (resultCode == RESULT_OK && treeUri != null) {
					try {
						contentResolver.takePersistableUriPermission(
							treeUri,
							Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
						)
						val name = androidx.documentfile.provider.DocumentFile
							.fromTreeUri(this, treeUri)?.name ?: treeUri.lastPathSegment ?: "Custom folder"
						pending.success(mapOf("treeUri" to treeUri.toString(), "displayName" to name))
					} catch (e: Exception) {
						pending.error("pick_failed", e.message, null)
					}
				} else {
					// User backed out of the picker.
					pending.success(null)
				}
			}
			return
		}
		super.onActivityResult(requestCode, resultCode, data)
	}
    private val ANDROID_TV_CHANNEL = "com.debrify.app/android_tv_player"
    private val REMOTE_CONTROL_CHANNEL = "com.debrify.app/remote_control"
    private val PIP_CHANNEL = "com.debrify.app/pip"

    // ── Picture-in-Picture (phone media_kit player) ─────────────────────────
    // PiP shrinks THIS activity into a floating window; the media_kit Flutter
    // texture keeps rendering as long as the activity/engine survives. Armed by
    // the Dart player screen while it's on top (see onUserLeaveHint). Phone
    // only — TV has its own native player and never uses phone-style PiP.
    private val PIP_ACTION = "com.debrify.app.PIP_ACTION"
    private var pipChannel: MethodChannel? = null
    private var pipAutoEnterArmed = false
    private var pipAspectW = 0
    private var pipAspectH = 0
    private var pipIsPlaying = false
    private var pipHasNext = false
    private var pipReceiverRegistered = false

    /** Receives taps on the PiP window's action buttons and forwards them to
     *  the Dart player over [pipChannel]. Registered lazily on first PiP entry
     *  (see registerPipReceiver), unregistered in onDestroy. */
    private val pipActionReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != PIP_ACTION) return
            val action = intent.getStringExtra("pipAction") ?: return
            try {
                pipChannel?.invokeMethod("onPipAction", action)
            } catch (e: Exception) {
                android.util.Log.e("DebrifyPiP", "action dispatch failed: ${e.message}")
            }
        }
    }

    // Inline ExoPlayer for the ambient trailer backdrop on TV.
    private var tvTrailerPlayer: com.debrify.app.tv.TvTrailerTexturePlayer? = null

    /** The player MethodChannel THIS instance registered into the static
     *  registry — cleanup compares against it so a stale instance's teardown
     *  can't clobber a newer engine's live channel. */
    private var registeredTvPlayerChannel: MethodChannel? = null

    // Full-window layer UNDER the FlutterView hosting the trailer underlay
    // SurfaceView(s). See trailerUnderlayContainer().
    private var trailerUnderlayContainer: FrameLayout? = null

    /** True on Android TV, computed once. UI_MODE_TYPE_TELEVISION alone misses
     *  some Google TV / Chromecast / Fire builds that report a non-TV UI mode,
     *  dropping them onto the system IME and its broken DPAD typing
     *  (flutter#177360); FEATURE_LEANBACK is present ONLY on TV devices, so it's
     *  a safe widener. The two probes are independent — a throw in the UI-mode
     *  cast must not skip the Leanback fallback (the whole point of widening). */
    private val televisionDetected: Boolean by lazy {
        val uiIsTv = try {
            (getSystemService(UI_MODE_SERVICE) as? UiModeManager)?.currentModeType ==
                Configuration.UI_MODE_TYPE_TELEVISION
        } catch (e: Exception) {
            false
        }
        val leanback = try {
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        } catch (e: Exception) {
            false
        }
        uiIsTv || leanback
    }

    private fun isTelevision(): Boolean = televisionDetected

    /**
     * Copy [path] into the MediaStore (`Download/<subDir>`) so it becomes
     * user-visible, then delete the source. Mirrors
     * MediaStoreDownloadService.createViaMediaStore. Used to publish an IPTV
     * recording that libmpv wrote to app-private storage. Runs on a worker
     * thread; returns the content URI string or null on failure.
     *
     * Pre-Q there is no MediaStore.Downloads class and the app holds no
     * WRITE_EXTERNAL_STORAGE, so publishing is impossible: return null and let
     * the caller keep the recording at its app-private path (touching the
     * class would throw NoClassDefFoundError — an Error, uncatchable by the
     * catch below, on this worker thread it would take the process down).
     */
    private fun saveRecordingToMediaStore(
        path: String,
        fileName: String,
        subDir: String,
        mimeType: String,
    ): String? {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) return null
        val source = java.io.File(path)
        if (!source.exists()) return null
        // Held outside the try so EVERY unsuccessful exit — including a throw
        // from openOutputStream/copyTo (disk full, storage revoked) — can drop
        // the pending row instead of leaking it, invisible, forever.
        var created: android.net.Uri? = null
        return try {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, mimeType)
                put(android.provider.MediaStore.Downloads.RELATIVE_PATH, "Download/$subDir")
                put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: return null
            created = uri
            val wrote = resolver.openOutputStream(uri)?.use { out ->
                java.io.FileInputStream(source).use { input -> input.copyTo(out) }
                true
            } ?: false
            if (!wrote) {
                runCatching { resolver.delete(uri, null, null) }
                return null
            }
            val done = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
            }
            val published = runCatching {
                resolver.update(uri, done, null, null)
            }.getOrDefault(0) > 0
            if (!published) {
                // The copy landed but can't be made visible (volume ejected,
                // provider refused). Reporting success here would be a lie that
                // costs the user the recording: an invisible pending row, and
                // the source deleted below. Drop the row and fail — the caller
                // keeps the file at its app-private path.
                runCatching { resolver.delete(uri, null, null) }
                created = null
                return null
            }
            created = null
            runCatching { source.delete() }
            uri.toString()
        } catch (e: Exception) {
            created?.let { runCatching { contentResolver.delete(it, null, null) } }
            null
        }
    }

    /** The MethodChannel result awaiting the legacy-storage permission dialog
     *  (pre-Q recording destination). One at a time; resolved in
     *  [onRequestPermissionsResult]. */
    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private val legacyStoragePermissionRequestCode = 7401

    /** Android 13+ notification permission, asked CONTEXTUALLY on the first
     *  record/schedule (recording runs without it — but progress, "Saved",
     *  and "schedule skipped" notifications go silent). Asked exactly once:
     *  a decline is remembered and never nagged again. */
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private val notificationPermissionRequestCode = 7403

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            legacyStoragePermissionRequestCode -> {
                pendingStoragePermissionResult?.success(granted)
                pendingStoragePermissionResult = null
            }
            notificationPermissionRequestCode -> {
                pendingNotificationPermissionResult?.success(granted)
                pendingNotificationPermissionResult = null
            }
            recordAudioPermissionRequestCode -> {
                // (see below for the capture engine these two feed)
                // Unlike notifications, this one is asked EVERY time the mic
                // key is pressed without the grant: it's a deliberate,
                // user-initiated action and the feature simply cannot run
                // without it. Android itself stops showing the dialog once the
                // user has permanently declined, and the deny path just leaves
                // the keyboard as it was.
                pendingVoicePermissionResult?.success(granted)
                pendingVoicePermissionResult = null
            }
        }
    }

    // ── Voice capture engine ────────────────────────────────────────────────

    /** Last level frame sent to Dart. [android.speech.RecognitionListener.onRmsChanged]
     *  fires far faster than a TV can usefully animate, and every frame is a
     *  platform-channel hop plus a Flutter rebuild — throttled to ~10/s. */
    private var lastVoiceLevelAt = 0L

    /** Emits one voice event to Dart. Main thread only — every recognition
     *  callback already arrives there. */
    private fun emitVoice(type: String, data: Map<String, Any?> = emptyMap()) {
        val sink = voiceEvents ?: return
        val payload = HashMap<String, Any?>(data)
        payload["type"] = type
        runCatching { sink.success(payload) }
    }

    /** Tears the session down. Safe to call at any time, including when
     *  nothing is listening. */
    private fun destroyVoiceCapture() {
        val recognizer = speechRecognizer
        speechRecognizer = null
        if (recognizer != null) {
            runCatching { recognizer.cancel() }
            runCatching { recognizer.destroy() }
        }
    }

    /** Destroy AFTER the current callback returns — destroying a recognizer
     *  from inside its own listener is how you get a half-torn-down service. */
    private fun destroyVoiceCaptureDeferred() {
        android.os.Handler(android.os.Looper.getMainLooper()).post { destroyVoiceCapture() }
    }

    /** One recognizer per dictation, destroyed when it ends. Holding a single
     *  instance across sessions is the classic route to a permanently
     *  ERROR_RECOGNIZER_BUSY mic on Google's implementation. */
    private fun startVoiceCapture(locale: String?) {
        destroyVoiceCapture()
        lastVoiceLevelAt = 0L
        val recognizer = runCatching {
            android.speech.SpeechRecognizer.createSpeechRecognizer(this)
        }.getOrNull()
        if (recognizer == null) {
            emitVoice("error", mapOf("code" to -1, "message" to "no recognizer"))
            return
        }
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(object : android.speech.RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = emitVoice("ready")
            override fun onBeginningOfSpeech() = emitVoice("speech")

            override fun onRmsChanged(rmsdB: Float) {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - lastVoiceLevelAt < 100) return
                lastVoiceLevelAt = now
                emitVoice("level", mapOf("db" to rmsdB.toDouble()))
            }

            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() = emitVoice("processing")

            override fun onError(error: Int) {
                emitVoice("error", mapOf("code" to error))
                destroyVoiceCaptureDeferred()
            }

            override fun onResults(results: Bundle?) {
                val text = results
                    ?.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                emitVoice("result", mapOf("text" to text))
                destroyVoiceCaptureDeferred()
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults
                    ?.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) emitVoice("partial", mapOf("text" to text))
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            // Some OEM recognition services reject a session without it.
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (!locale.isNullOrBlank()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            }
            // People pause mid-title ("the… mandalorian"), so give them a beat
            // more than the default before the engine calls it done. Advisory:
            // several engines ignore these outright.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                1500L,
            )
        }
        runCatching { recognizer.startListening(intent) }.onFailure {
            emitVoice("error", mapOf("code" to -1, "message" to it.message))
            destroyVoiceCapture()
        }
    }

    // ── Pending-recording registry ──────────────────────────────────────────
    // Durability for IPTV recording publication without a foreground service:
    // Dart registers a recording's temp path the moment libmpv starts writing
    // it, and the entry is forgotten only after a SUCCESSFUL publish. If the
    // process dies mid-recording, mid-copy (Home-press publish on a plain
    // thread), or the MediaStore publish fails outright, the temp file is
    // still on disk and the entry still in prefs — the sweep on next launch
    // publishes it then. A pending row leaked by a killed copy is reaped by
    // MediaStore itself (~week); the bytes are what must survive, and they do.

    private val pendingRecordingLock = Any()

    private fun pendingRecordingPrefs() =
        getSharedPreferences("debrify_pending_recordings", MODE_PRIVATE)

    /** Entry format: path|fileName|subDir|mimeType. Safe: sanitized recording
     *  filenames and app-storage paths never contain '|'. */
    private fun rememberPendingRecording(
        path: String,
        fileName: String,
        subDir: String,
        mimeType: String,
    ) {
        synchronized(pendingRecordingLock) {
            val prefs = pendingRecordingPrefs()
            val entries = HashSet(prefs.getStringSet("entries", emptySet()) ?: emptySet())
            entries.add(listOf(path, fileName, subDir, mimeType).joinToString("|"))
            prefs.edit().putStringSet("entries", entries).apply()
        }
    }

    private fun forgetPendingRecording(path: String) {
        synchronized(pendingRecordingLock) {
            val prefs = pendingRecordingPrefs()
            val entries = HashSet(prefs.getStringSet("entries", emptySet()) ?: emptySet())
            if (entries.removeAll { it == path || it.startsWith("$path|") }) {
                prefs.edit().putStringSet("entries", entries).apply()
            }
        }
    }

    /** Publish every registered recording that never made it to Downloads.
     *  Runs once per process at engine setup. The snapshot is taken
     *  SYNCHRONOUSLY, before configureFlutterEngine installs the method
     *  channel — so an entry a LIVE tee recording registers moments later can
     *  never enter it. (Snapshotting inside the worker thread would race that
     *  registration, and the sweep both copies mid-write AND deletes the
     *  source it copied — destroying the active recording.) Entries in the
     *  snapshot are by definition from a previous process, whose writer is
     *  dead. */
    private fun retryPendingRecordingPublishes() {
        if (pendingRecordingRetryRan) return
        pendingRecordingRetryRan = true
        val entries: List<String> = synchronized(pendingRecordingLock) {
            (pendingRecordingPrefs().getStringSet("entries", emptySet()) ?: emptySet()).toList()
        }
        if (entries.isEmpty()) return
        Thread {
            for (entry in entries) {
                val parts = entry.split("|")
                if (parts.size != 4) {
                    // Unparseable — drop it rather than retry forever.
                    synchronized(pendingRecordingLock) {
                        val prefs = pendingRecordingPrefs()
                        val set = HashSet(prefs.getStringSet("entries", emptySet()) ?: emptySet())
                        if (set.remove(entry)) prefs.edit().putStringSet("entries", set).apply()
                    }
                    continue
                }
                val (path, fileName, subDir, mimeType) = parts
                if (!java.io.File(path).exists()) {
                    // Source gone (published elsewhere, or a cancelled stub) —
                    // nothing left to recover.
                    forgetPendingRecording(path)
                    continue
                }
                val uri = saveRecordingToMediaStore(path, fileName, subDir, mimeType)
                if (uri != null) forgetPendingRecording(path)
                // On failure the entry stays for the launch after this one.
            }
        }.start()
    }

    /** Finished recordings for the hub's Library zone: the recording store's
     *  `done` entries (which carry channel name + duration) merged with a scan
     *  of the on-disk destination — MediaStore on Q+ (a no-permission query
     *  only ever returns OUR rows), a plain dir listing pre-Q (only when the
     *  legacy grant is held). Scan-only files (tee recordings, entries the old
     *  TTL pruned) surface with metadata read off the file itself. Call from a
     *  worker thread — reconcile + scan are IO. */
    private fun buildRecordingsLibrary(): List<Map<String, Any?>> {
        com.debrify.app.recording.RecordingTaskStore
            .reconcileDeadEntries(this, forceFileCheck = true)
        val entries = com.debrify.app.recording.RecordingTaskStore.all(this)
        val out = ArrayList<Map<String, Any?>>()

        // Every uri any entry owns — including LIVE captures, whose growing
        // file must not be double-listed by the scans below.
        val coveredIds = HashSet<Long>()
        val coveredPaths = HashSet<String>()
        for (entry in entries.values) {
            val raw = entry.uri ?: continue
            val uri = android.net.Uri.parse(raw)
            if (uri.scheme == "file") {
                uri.path?.let { coveredPaths.add(it) }
            } else {
                runCatching { android.content.ContentUris.parseId(uri) }
                    .getOrNull()?.let { coveredIds.add(it) }
            }
        }

        for ((taskId, entry) in entries) {
            if (entry.status != "done") continue
            val raw = entry.uri ?: continue
            // Duration = finish (the final store write, which normal engine
            // finishes stamp and publish retries preserve) minus start. A
            // crash-finalized entry's updatedAt is reconcile time, not the
            // capture's end — those carry an errorMessage marker and report
            // no duration rather than a wild number.
            val durationMs =
                if (entry.errorMessage == null) entry.updatedAt - entry.startedAtMs
                else -1L
            out.add(
                mapOf(
                    "taskId" to taskId,
                    "uri" to raw,
                    "name" to entry.fileName,
                    "channelName" to entry.channelName.takeIf { it.isNotEmpty() },
                    "bytes" to entry.bytes,
                    "recordedAtMs" to entry.startedAtMs,
                    "durationMs" to durationMs.takeIf {
                        it in 1_000L..(12L * 60 * 60 * 1000)
                    },
                    // Crash-finalized (the OS killed the capture; reconcile
                    // salvaged the partial) — the hub's battery-optimization
                    // nudge keys off this. The WHEN is updatedAt (finalize
                    // time), not the start: a dismissal must only silence
                    // interruptions that had already happened.
                    "interrupted" to (entry.errorMessage != null),
                    "interruptedAtMs" to
                        if (entry.errorMessage != null) entry.updatedAt else null,
                ),
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val projection = arrayOf(
                android.provider.MediaStore.Downloads._ID,
                android.provider.MediaStore.Downloads.DISPLAY_NAME,
                android.provider.MediaStore.Downloads.SIZE,
                android.provider.MediaStore.Downloads.DATE_MODIFIED,
            )
            runCatching {
                contentResolver.query(
                    android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    projection,
                    "${android.provider.MediaStore.Downloads.RELATIVE_PATH} LIKE ?",
                    arrayOf(
                        "${com.debrify.app.recording.LiveRecordingService.RELATIVE_PATH}%",
                    ),
                    null,
                )?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow(
                        android.provider.MediaStore.Downloads._ID,
                    )
                    val nameCol = cursor.getColumnIndexOrThrow(
                        android.provider.MediaStore.Downloads.DISPLAY_NAME,
                    )
                    val sizeCol = cursor.getColumnIndexOrThrow(
                        android.provider.MediaStore.Downloads.SIZE,
                    )
                    val dateCol = cursor.getColumnIndexOrThrow(
                        android.provider.MediaStore.Downloads.DATE_MODIFIED,
                    )
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(idCol)
                        if (id in coveredIds) continue
                        val uri = android.content.ContentUris.withAppendedId(
                            android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            id,
                        )
                        out.add(
                            mapOf(
                                "taskId" to null,
                                "uri" to uri.toString(),
                                "name" to (cursor.getString(nameCol) ?: "recording.ts"),
                                "channelName" to null,
                                "bytes" to cursor.getLong(sizeCol),
                                // DATE_MODIFIED is in SECONDS.
                                "recordedAtMs" to cursor.getLong(dateCol) * 1000L,
                                "durationMs" to null,
                            ),
                        )
                    }
                }
            }
        } else if (
            com.debrify.app.recording.LiveRecordingService.legacyStorageGranted(this)
        ) {
            val dir = com.debrify.app.recording.LiveRecordingService.legacyRecordingsDir()
            val files = runCatching { dir.listFiles() }.getOrNull() ?: emptyArray()
            for (file in files) {
                if (!file.isFile || file.absolutePath in coveredPaths) continue
                val ext = file.extension.lowercase()
                if (ext !in setOf("ts", "mts", "m2ts", "mkv", "mp4")) continue
                out.add(
                    mapOf(
                        "taskId" to null,
                        "uri" to android.net.Uri.fromFile(file).toString(),
                        "name" to file.name,
                        "channelName" to null,
                        "bytes" to file.length(),
                        "recordedAtMs" to file.lastModified(),
                        "durationMs" to null,
                    ),
                )
            }
        }
        return out
    }

    /** The Dart-owned setting (Settings → Home Page → Native Trailer Surface),
     *  read from the shared_preferences plugin's store. Must be checked here
     *  too: the transparency mode is fixed at activity creation, so flipping
     *  the toggle takes effect on the next app start. */
    private fun trailerUnderlayEnabled(): Boolean =
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.tv_trailer_underlay_enabled", true)

    /** Whether this device's GPU can AFFORD the underlay's permanently
     *  translucent Flutter surface. A translucent full-screen surface can never
     *  be marked opaque, so SurfaceFlinger alpha-blends two full-1080p layers
     *  on every frame the app draws — measured on a Mi Box (Mali-450, GLES 2.0)
     *  that standing tax janks the whole app, spinners included, trailer or no
     *  trailer. GLES 3.0+ devices have the fill-rate headroom; ES2-class
     *  boxes compensate with low-res rendering (computeRenderScale), which
     *  the onCreate interlock requires before granting them the translucent
     *  surface. */
    private fun underlaySurfaceAffordable(): Boolean = try {
        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        am.deviceConfigurationInfo.reqGlEsVersion >= 0x30000
    } catch (e: Exception) {
        false
    }

    /** The EFFECTIVE underlay decision for this activity's whole life — user
     *  toggle AND device capability — made once in [onCreate] BEFORE the
     *  FlutterView exists, and persisted for the Dart side (see onCreate). */
    private var trailerUnderlayEffective = false

    // ── Low-res render scale (weak-GPU TVs) ─────────────────────────────────
    // GLES2-class boxes (Mi Box: Mali-450) are FILL-RATE bound: rendering the
    // Flutter UI at full 1080p is what makes the whole app feel heavy, no
    // matter how lean the widget tree is (verified on-device: the same build
    // at 720p feels near native). The games technique: give the Flutter
    // surface a FIXED ~720p buffer (the hardware scaler upscales for free)
    // and scale the viewport metrics by the same factor so the LOGICAL layout
    // is pixel-for-pixel identical — every frame just costs ~2.25x fewer
    // pixels. Scoped to this activity's Flutter surface only: video playback
    // (movies in the native player activity, trailer underlays) renders on
    // its own decoder-sized surfaces and stays full resolution.

    /** <1.0 when low-res rendering is active (e.g. 720/1080 = 0.667). */
    private var renderScale = 1.0f

    // ── TV screen size (UI zoom-out) ────────────────────────────────────────
    // A 1080p panel at density 320 hands Flutter a 960x540 logical canvas, so
    // every screen — all written in logical px — is drawn 2x and reads as
    // "zoomed in" across a big TV. Dividing ONLY the reported devicePixelRatio
    // grows that canvas (0.8 -> 1200x675) while the window, the surface buffer
    // and the physical metrics stay exactly as they were: the same layouts get
    // more room and draw proportionally smaller, with no widget changes. It
    // composes with [renderScale] (which scales the physical side instead) and,
    // unlike that one, keeps pointer mapping consistent — Flutter divides
    // pointer physical px by this same dpr.

    /** The TV UI size factor ("Screen Size" in TV Mode settings): <1.0 on
     *  Android TV by DEFAULT — see [DEFAULT_UI_SCALE_PERCENT] — and always
     *  exactly 1.0 on every non-TV device. */
    private var uiScale = 1.0f

    private fun computeUiScale() {
        uiScale = 1.0f
        if (!isTelevision()) return
        // Dart writes this with SharedPreferences.setInt, which lands as a
        // Long. Any other type (or none) means "never set" → the default.
        val percent = try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getLong("flutter.tv_ui_scale_percent", DEFAULT_UI_SCALE_PERCENT)
                .toInt()
        } catch (e: Exception) {
            DEFAULT_UI_SCALE_PERCENT.toInt()
        }
        // Anything outside 70..100 falls back to the default rather than being
        // clamped: a stray 0 (or a value from a future build) must never be
        // able to silently shrink the UI to the smallest thing allowed. 70 is
        // the floor because TV text stops being legible from a couch below it.
        val effective = if (percent in 70..100) {
            percent
        } else {
            DEFAULT_UI_SCALE_PERCENT.toInt()
        }
        uiScale = effective / 100f
    }

    private fun computeRenderScale(gpuCapable: Boolean) {
        renderScale = 1.0f
        val auto = isTelevision() && !gpuCapable
        // Pref = future Settings escape hatch ("sharper picture vs faster
        // navigation"); absent → the automatic weak-GPU decision.
        val enabled = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.tv_low_res_render", auto)
        if (!enabled) return
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(dm)
        // Already ~720p-class (or unknown) → nothing to win, don't downscale.
        if (dm.heightPixels <= 736 || dm.widthPixels <= 0) return
        renderScale = 720f / dm.heightPixels
    }

    /** Rewrites the viewport metrics Flutter receives so the engine lays out
     *  and rasters at the scaled size while logical geometry is unchanged:
     *  physical w/h/insets × [scale], devicePixelRatio × [dprScale]. MUST
     *  round exactly like [applyFixedSurfaceSize] — the engine discards frames
     *  whose size doesn't match the surface buffer.
     *
     *  The two factors are separate on purpose:
     *   - low-res rendering passes the SAME value for both (physical and dpr
     *     move together → identical logical layout, fewer rastered pixels);
     *   - the TV screen-size setting folds an extra `uiScale` into [dprScale]
     *     only (dpr shrinks, physical doesn't → a LARGER logical canvas, so
     *     the UI draws smaller). Both compose in one engine.
     *
     *  Known limitations (accepted; TV is DPAD-driven): pointer coordinates
     *  and accessibility-node bounds are NOT rescaled by the physical [scale],
     *  so an air-mouse remote or TalkBack under low-res rendering would see
     *  ~2/3-offset hit targets. The `flutter.tv_low_res_render=false` pref is
     *  the escape hatch. (The screen-size factor is exempt: it never touches
     *  the physical side, and Flutter converts pointers with the same dpr it
     *  is given here.) */
    private class ScaledFlutterJNI(
        private val scale: Float,
        private val dprScale: Float,
    ) : FlutterJNI() {
        private fun s(v: Int): Int = Math.round(v * scale)

        override fun setViewportMetrics(
            devicePixelRatio: Float,
            physicalWidth: Int,
            physicalHeight: Int,
            physicalPaddingTop: Int,
            physicalPaddingRight: Int,
            physicalPaddingBottom: Int,
            physicalPaddingLeft: Int,
            physicalViewInsetTop: Int,
            physicalViewInsetRight: Int,
            physicalViewInsetBottom: Int,
            physicalViewInsetLeft: Int,
            systemGestureInsetTop: Int,
            systemGestureInsetRight: Int,
            systemGestureInsetBottom: Int,
            systemGestureInsetLeft: Int,
            physicalTouchSlop: Int,
            displayFeaturesBounds: IntArray,
            displayFeaturesType: IntArray,
            displayFeaturesState: IntArray,
            // Added by the engine in Flutter 3.44. Same physical-pixel space
            // as the width/height/insets above, so they scale with them —
            // leaving them raw would hand the engine constraints and corner
            // radii from the unscaled surface. Their defaults are 0 (not an
            // unbounded sentinel), so scaling is safe arithmetic.
            minWidth: Int,
            maxWidth: Int,
            minHeight: Int,
            maxHeight: Int,
            physicalDisplayCornerRadiusTopLeft: Int,
            physicalDisplayCornerRadiusTopRight: Int,
            physicalDisplayCornerRadiusBottomRight: Int,
            physicalDisplayCornerRadiusBottomLeft: Int,
        ) {
            super.setViewportMetrics(
                devicePixelRatio * dprScale,
                s(physicalWidth),
                s(physicalHeight),
                s(physicalPaddingTop),
                s(physicalPaddingRight),
                s(physicalPaddingBottom),
                s(physicalPaddingLeft),
                s(physicalViewInsetTop),
                s(physicalViewInsetRight),
                s(physicalViewInsetBottom),
                s(physicalViewInsetLeft),
                s(systemGestureInsetTop),
                s(systemGestureInsetRight),
                s(systemGestureInsetBottom),
                s(systemGestureInsetLeft),
                s(physicalTouchSlop),
                IntArray(displayFeaturesBounds.size) { i -> s(displayFeaturesBounds[i]) },
                displayFeaturesType,
                displayFeaturesState,
                s(minWidth),
                s(maxWidth),
                s(minHeight),
                s(maxHeight),
                s(physicalDisplayCornerRadiusTopLeft),
                s(physicalDisplayCornerRadiusTopRight),
                s(physicalDisplayCornerRadiusBottomRight),
                s(physicalDisplayCornerRadiusBottomLeft),
            )
        }
    }

    /** Low-res rendering and/or a non-default TV screen size build the engine
     *  around [ScaledFlutterJNI]; default path (null) lets FlutterActivity
     *  create its own stock engine. */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        if (renderScale >= 0.999f && uiScale >= 0.999f) return null
        return FlutterEngine(
            context,
            FlutterInjector.instance().flutterLoader(),
            ScaledFlutterJNI(renderScale, renderScale * uiScale),
            /* dartVmArgs = */ null,
            /* automaticallyRegisterPlugins = */ true,
        )
    }

    /** Our provided engine must die with the activity like a stock one would —
     *  otherwise every recreation would leak a running Dart isolate. */
    override fun shouldDestroyEngineWithHost(): Boolean = true

    /** Pins the Flutter SurfaceView's buffer to the scaled size, keyed off the
     *  FlutterView's OWN layout size with the SAME rounding as the metrics
     *  rewrite, so buffer and viewport can never disagree. */
    private fun applyFixedSurfaceSize() {
        if (renderScale >= 0.999f) return
        val flutterView = findViewById<ViewGroup>(FLUTTER_VIEW_ID) ?: return
        var surfaceView: SurfaceView? = null
        for (i in 0 until flutterView.childCount) {
            (flutterView.getChildAt(i) as? SurfaceView)?.let { surfaceView = it }
        }
        val sv = surfaceView ?: return
        val scale = renderScale
        fun apply() {
            val w = flutterView.width
            val h = flutterView.height
            if (w > 0 && h > 0) {
                sv.holder.setFixedSize(Math.round(w * scale), Math.round(h * scale))
            }
        }
        apply()
        flutterView.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, orr, ob ->
            if (r - l != orr - ol || b - t != ob - ot) apply()
        }
    }

    /**
     * TV: make the Flutter surface translucent so the ambient trailer can play
     * on a native SurfaceView *behind* it (its own hardware overlay plane —
     * Flutter never composites the video frames; see TvTrailerTexturePlayer's
     * underlay mode). This keeps the fast SurfaceView render path — RenderMode
     * stays `surface` because the background mode is untouched — the Flutter
     * surface just gets a TRANSLUCENT format and sits Z-above the window. The
     * window, launch theme and every non-TV platform are unchanged, and the app
     * paints opaque UI everywhere except the trailer hole, so nothing else is
     * visibly different. Weak GPUs get this too, but ONLY while low-res
     * rendering offsets the blend tax — see the interlock in [onCreate].
     */
    override fun getTransparencyMode(): TransparencyMode =
        if (trailerUnderlayEffective) TransparencyMode.transparent
        else super.getTransparencyMode()

    /** Lazily creates the underlay container at content-view index 0 (below the
     *  FlutterView). Called from the platform thread on first underlay create. */
    private fun trailerUnderlayContainer(): FrameLayout? {
        trailerUnderlayContainer?.let { return it }
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return null
        val container = FrameLayout(this)
        content.addView(
            container,
            0,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        trailerUnderlayContainer = container
        return container
    }

    companion object {
        /** TV screen size applied when the user has never picked one. 80 (not
         *  100) because at native density the app lays out on a 960x540 canvas
         *  and reads visibly larger than the TV apps it sits next to; 100 is
         *  the opt-in "put it back" choice. MUST stay in step with
         *  StorageService.kTvUiScaleDefault, which drives the Settings row. */
        // MUST stay in step with StorageService.kTvUiScaleDefault.
        private const val DEFAULT_UI_SCALE_PERCENT = 90L

        /** Once per PROCESS, not per activity: recreation must not re-run the
         *  pending-recording retry sweep alongside a live one. */
        @JvmStatic
        @Volatile
        private var pendingRecordingRetryRan = false

        @JvmStatic
        private var androidTvPlayerChannel: MethodChannel? = null

        @JvmStatic
        fun getAndroidTvPlayerChannel(): MethodChannel? = androidTvPlayerChannel

        @JvmStatic
        fun setAndroidTvPlayerChannel(channel: MethodChannel?) {
            androidTvPlayerChannel = channel
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Decide the surface mode BEFORE super.onCreate builds the FlutterView
        // (which consults getTransparencyMode exactly once), and persist the
        // EFFECTIVE decision where Dart's launch snapshot reads it — both
        // sides must agree, or the Dart underlay hole would punch through an
        // opaque surface as a black rectangle. commit() (not apply) so the
        // value is on disk before the Dart isolate starts reading prefs.
        val gpuCapable = underlaySurfaceAffordable()
        // Must run before super.onCreate (provideFlutterEngine, called from
        // within it, reads renderScale) AND before the underlay decision
        // below, which depends on the outcome.
        computeRenderScale(gpuCapable)
        // Same timing requirement: provideFlutterEngine (called from within
        // super.onCreate) reads uiScale, so the pref must be resolved first.
        // Nothing downstream depends on it, so a change only lands on the next
        // cold start — the Settings row says so.
        computeUiScale()
        // Underlay trailers are back ON for weak GPUs too: with low-res
        // rendering the Flutter raster cost sits well under the pre-redesign
        // level that co-existed happily with the underlay's full-screen blend
        // tax — the charm-era playback architecture, at a UI cost the GPU can
        // afford. The parenthesised clause is the safety interlock: a weak
        // GPU gets the translucent surface ONLY while low-res rendering is
        // actually paying for it — if a future Settings row turns low-res
        // off (`tv_low_res_render=false`), the underlay drops with it rather
        // than recreating the measured full-1080p-plus-blend jank.
        trailerUnderlayEffective = isTelevision() && trailerUnderlayEnabled() &&
            (gpuCapable || renderScale < 0.999f)
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .putBoolean(
                "flutter.tv_trailer_underlay_effective",
                trailerUnderlayEffective,
            )
            // Surfaced for a future Settings row ("performance rendering").
            .putBoolean("flutter.tv_low_res_render_active", renderScale < 0.999f)
            .commit()
        super.onCreate(savedInstanceState)
        applyFixedSurfaceSize()
        // Enable edge-to-edge display to properly handle system navigation bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun onResume() {
        super.onResume()
        ActivityTracker.currentActivity = this
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        // The trailer player's ExoPlayer listeners keep emitting onto this
        // engine's messenger after detach; invokeMethod on a detached engine
        // throws an UNCAUGHT RuntimeException on the main thread (process
        // death). releaseAll() marks the player detached (emits become no-ops)
        // and tears every instance down. Instance-scoped (unlike the static
        // player channel below), so a stale activity's cleanup can't clobber a
        // newer instance's player. onDestroy's call is then a no-op.
        tvTrailerPlayer?.releaseAll()
        tvTrailerPlayer = null
        // The static player channel targets this engine's messenger. Once the
        // engine detaches, invokeMethod on it goes into the void and its
        // Result callback never fires — the native TV player's EPG bridge
        // then hangs on every ask (with playback itself unaffected, so it
        // presents as "EPG missing everywhere"). Null it so callers fail
        // fast; a recreated MainActivity re-registers a live channel.
        //
        // ONLY when the registry still holds the channel THIS instance
        // registered: Android doesn't order an old activity's teardown
        // before a new instance's configureFlutterEngine, so a stale
        // instance's cleanup must never clobber the fresh channel a newer
        // engine just installed.
        if (getAndroidTvPlayerChannel() === registeredTvPlayerChannel) {
            setAndroidTvPlayerChannel(null)
        }
        registeredTvPlayerChannel = null
    }

    override fun onDestroy() {
        tvTrailerPlayer?.releaseAll()
        tvTrailerPlayer = null
        // A live recognizer holds the microphone; never let one outlive the
        // activity that opened it.
        destroyVoiceCapture()
        // Safety net for the phone player: the Dart screen closes its own
        // session in dispose(), but an activity torn down without that (task
        // swipe, recreation) would otherwise leave effect apps attached to a
        // session that no longer plays. No-op if nothing is open.
        com.debrify.app.audio.AudioEffectSession.closeCurrent(this)
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipActionReceiver)
            } catch (e: Exception) {
                // Already unregistered / never fully registered — ignore.
            }
            pipReceiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onPause() {
        super.onPause()
        if (ActivityTracker.currentActivity == this) {
            ActivityTracker.currentActivity = null
        }
        // Backgrounded mid-dictation: Android cuts a background app off the
        // microphone anyway, so end the session cleanly and tell Dart, rather
        // than leaving the keyboard listening to a mic it no longer has.
        if (speechRecognizer != null) {
            destroyVoiceCapture()
            emitVoice("aborted")
        }
    }

    /** Auto-enter PiP when the user leaves the app (Home / Recents) while the
     *  Dart player screen has armed it. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipAutoEnterArmed) return
        // Don't re-enter if the window is already in PiP.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            isInPictureInPictureMode
        ) {
            return
        }
        enterPipInternal(pipAspectW, pipAspectH)
    }

    /** Tell the Dart side so it can collapse chrome in the tiny window. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        try {
            pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "notify failed: ${e.message}")
        }
    }

    private fun pipSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isTelevision()) return false
        return packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )
    }

    private fun enterPipInternal(aspectW: Int, aspectH: Int): Boolean {
        // Inline SDK guard (not just pipSupported()) so the NewApi lint's flow
        // analysis can see it before the API-26 calls below.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!pipSupported()) return false
        return try {
            registerPipReceiver()
            enterPictureInPictureMode(buildPipParams(aspectW, aspectH))
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "enterPip failed: ${e.message}")
            false
        }
    }

    private fun registerPipReceiver() {
        if (pipReceiverRegistered) return
        val filter = android.content.IntentFilter(PIP_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipActionReceiver, filter)
        }
        pipReceiverRegistered = true
    }

    /** Push updated action buttons (play/pause icon, Next) to a PiP window
     *  that's already open — no-op otherwise. */
    private fun updatePipParamsIfActive() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!isInPictureInPictureMode) return
        try {
            setPictureInPictureParams(buildPipParams(pipAspectW, pipAspectH))
        } catch (e: Exception) {
            android.util.Log.e("DebrifyPiP", "updateParams failed: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipParams(aspectW: Int, aspectH: Int): PictureInPictureParams {
        // Android rejects aspect ratios outside [1/2.39, 2.39] with
        // IllegalArgumentException — clamp ultrawide/portrait sources to just
        // INSIDE those bounds (0.42 / 2.39; note 1/2.39 ≈ 0.41841, so a 0.4184
        // clamp target would itself still be rejected).
        var w = if (aspectW > 0) aspectW else 16
        var h = if (aspectH > 0) aspectH else 9
        val ratio = w.toDouble() / h.toDouble()
        if (ratio > 2.39) {
            w = 239; h = 100
        } else if (ratio < 0.42) {
            w = 42; h = 100
        }
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(w, h))
            .setActions(buildPipActions())
            .build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPipActions(): ArrayList<android.app.RemoteAction> {
        val actions = ArrayList<android.app.RemoteAction>()
        val icon = if (pipIsPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val title = if (pipIsPlaying) "Pause" else "Play"
        actions.add(makePipAction(icon, title, "playpause", 1))
        if (pipHasNext) {
            actions.add(
                makePipAction(android.R.drawable.ic_media_next, "Next", "next", 2),
            )
        }
        return actions
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun makePipAction(
        iconRes: Int,
        title: String,
        action: String,
        requestCode: Int,
    ): android.app.RemoteAction {
        val intent = Intent(PIP_ACTION).apply {
            setPackage(packageName)
            putExtra("pipAction", action)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        val pi = PendingIntent.getBroadcast(this, requestCode, intent, flags)
        val icon = android.graphics.drawable.Icon.createWithResource(this, iconRes)
        return android.app.RemoteAction(icon, title, title, pi)
    }

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			PLAYER_DIAGNOSTICS_CHANNEL,
		).setMethodCallHandler { call, result ->
			if (call.method != "logDecoder") {
				result.notImplemented()
				return@setMethodCallHandler
			}
			val message = call.argument<String>("message")
				?.replace('\n', ' ')
				?.replace('\r', ' ')
				?.take(2_048)
			if (message.isNullOrBlank()) {
				result.error("bad_args", "message is required", null)
				return@setMethodCallHandler
			}
			android.util.Log.i("DEBRIFY_PLAYER_DECODER", message)
			result.success(null)
		}
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			DEVICE_ID_CHANNEL,
		).setMethodCallHandler { call, result ->
			if (call.method == "id") {
				result.success(
					Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
				)
			} else {
				result.notImplemented()
			}
		}
		// Lets system audio-effect apps (Wavelet, OEM equalizers) attach to the
		// phone player's audio session — see AudioEffectSession.
		com.debrify.app.audio.AudioEffectSession.register(flutterEngine, this)
		// Recordings a previous process never managed to publish (killed
		// mid-copy, failed MediaStore update, died while recording).
		retryPendingRecordingPublishes()
		// Recording engine housekeeping, off the main thread: finalize captures
		// a dead process left mid-write, and re-arm schedule alarms — the only
		// revival path after a force-stop (no alarms, no boot broadcast reach a
		// force-stopped app until the user opens it again).
		Thread {
			runCatching {
				com.debrify.app.recording.RecordingTaskStore.reconcileDeadEntries(this)
			}
			runCatching {
				// Tee recordings whose IS_PENDING clear failed in a dead
				// activity (often during its own onDestroy) — the only retry
				// path that survives the controller's in-memory list.
				com.debrify.app.recording.TeeUnpublishedStore.retryAll(this)
			}
			runCatching {
				com.debrify.app.recording.RecordingAlarmReceiver.registerAll(this)
			}
		}.start()
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"startMediaStoreDownload" -> {
					val url = call.argument<String>("url")
					val fileName = call.argument<String>("fileName") ?: "download"
					val subDir = call.argument<String>("subDir") ?: "Debrify"
					val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
					val markAsUpdate = call.argument<Boolean>("markAsUpdate") ?: false
					val treeUri = call.argument<String>("treeUri")
					@Suppress("UNCHECKED_CAST")
					val headers = call.argument<HashMap<String, String>>("headers") ?: hashMapOf()

					if (url.isNullOrEmpty()) {
						result.error("bad_args", "url is required", null)
						return@setMethodCallHandler
					}

					// Dart mints and passes the taskId so record id == native
					// task id end-to-end (start-or-adopt on the service side
					// resumes a persisted task under the same id with a
					// refreshed URL). Fallback for callers that don't.
					val baseId = System.currentTimeMillis().toString()
					val taskId = call.argument<String>("taskId")
						?: (if (markAsUpdate) "update-$baseId" else baseId)
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_START
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_URL, url)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_FILE_NAME, fileName)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_RELATIVE_SUBDIR, subDir)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_MIME_TYPE, mimeType)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_HEADERS, headers)
						if (!treeUri.isNullOrEmpty()) {
							putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TREE_URI, treeUri)
						}
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(taskId)
					} catch (e: Exception) {
						// Android 12+ forbids foreground-service starts from the
						// background (ForegroundServiceStartNotAllowedException).
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"engineRecordingSupport" -> {
					// Three-state, unlike the tee's Q+-only canPublishRecordings:
					// pre-Q devices must SHOW the affordances so the first press
					// can request the legacy storage grant — a plain false would
					// hide the feature with no path to ever enable it.
					result.success(
						when {
							com.debrify.app.recording.LiveRecordingService
								.isSupported(this) -> "supported"
							com.debrify.app.recording.LiveRecordingService
								.needsLegacyPermission(this) -> "needs_permission"
							else -> "unsupported"
						},
					)
				}
				"requestLegacyStoragePermission" -> {
					if (!com.debrify.app.recording.LiveRecordingService
							.needsLegacyPermission(this)
					) {
						result.success(
							com.debrify.app.recording.LiveRecordingService
								.isSupported(this),
						)
						return@setMethodCallHandler
					}
					if (pendingStoragePermissionResult != null) {
						result.error("in_flight", "request already showing", null)
						return@setMethodCallHandler
					}
					pendingStoragePermissionResult = result
					androidx.core.app.ActivityCompat.requestPermissions(
						this,
						arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
						legacyStoragePermissionRequestCode,
					)
				}
				"canPublishRecordings" -> {
					// MediaStore.Downloads is API 29+, and the app ships no
					// WRITE_EXTERNAL_STORAGE, so below Q a finished recording
					// could never leave app-private storage. Dart hides the
					// record control rather than write a file the user can't
					// reach.
					result.success(
						android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q
					)
				}
				"saveFileToMediaStore" -> {
						val path = call.argument<String>("path")
						val fileName = call.argument<String>("fileName") ?: "recording.ts"
						val subDir = call.argument<String>("subDir") ?: "Debrify/Recordings"
						val mimeType = call.argument<String>("mimeType") ?: "video/mp2t"
						if (path.isNullOrEmpty()) {
							result.error("bad_args", "path is required", null)
							return@setMethodCallHandler
						}
						// Copy off the main thread (recordings can be large); post
						// the MethodChannel result back on the main thread. Only
						// SUCCESS clears the registry entry — a failed or killed
						// copy leaves it for the next-launch retry sweep.
						Thread {
							val savedUri = saveRecordingToMediaStore(path, fileName, subDir, mimeType)
							if (savedUri != null) forgetPendingRecording(path)
							runOnUiThread {
								if (savedUri != null) result.success(savedUri)
								else result.error("save_failed", "could not save file", null)
							}
						}.start()
					}
					"registerPendingRecording" -> {
						// Called when libmpv STARTS writing a recording, so the
						// file survives any later death of the process: the
						// next-launch sweep publishes whatever is on disk.
						val path = call.argument<String>("path")
						val fileName = call.argument<String>("fileName") ?: "recording.ts"
						val subDir = call.argument<String>("subDir") ?: "Debrify/Recordings"
						val mimeType = call.argument<String>("mimeType") ?: "video/mp2t"
						if (path.isNullOrEmpty()) {
							result.error("bad_args", "path is required", null)
							return@setMethodCallHandler
						}
						rememberPendingRecording(path, fileName, subDir, mimeType)
						result.success(true)
					}
					// ── Recording engine (LiveRecordingService) ─────────────
					"startLiveRecording" -> {
						val url = call.argument<String>("url")
						val fileName = call.argument<String>("fileName") ?: "recording.ts"
						val channelName = call.argument<String>("channelName") ?: "Live channel"
						val maxDurationMs = call.argument<Number>("maxDurationMs")?.toLong()
							?: com.debrify.app.recording.LiveRecordingService.MAX_DURATION_DEFAULT_MS
						@Suppress("UNCHECKED_CAST")
						val headers = call.argument<HashMap<String, String>>("headers") ?: hashMapOf()
						if (url.isNullOrEmpty()) {
							result.error("bad_args", "url is required", null)
							return@setMethodCallHandler
						}
						if (!com.debrify.app.recording.LiveRecordingService.isSupported(this)) {
							result.error("engine_unsupported", "requires Android 10+", null)
							return@setMethodCallHandler
						}
						val recordingLimit =
							com.debrify.app.recording.LiveRecordingService.maxConcurrent(this)
						if (com.debrify.app.recording.RecordingRegistry.live.size >=
							recordingLimit
						) {
							result.error(
								"recording_limit_reached",
								"limit is $recordingLimit",
								null,
							)
							return@setMethodCallHandler
						}
						// ONE atomic claim-or-existing across the live registry
						// AND the pending claims: separate reads could straddle
						// the worker's pending→live move, see the url in neither
						// map, and mint an id the service then discards as a
						// duplicate. The claim placed here is cleared by the
						// service on every resolution path (registered /
						// rejected / failed) — no timers involved.
						val taskId = "rec-${System.currentTimeMillis()}"
						val existingId = com.debrify.app.recording.RecordingRegistry
							.claimOrExisting(url, taskId)
						if (existingId != null) {
							// Same channel already being captured (or mid-start):
							// hand back the responsible task instead of opening a
							// second identical connection.
							result.success(existingId)
							return@setMethodCallHandler
						}
						val intent = com.debrify.app.recording.LiveRecordingService.buildStartIntent(
							context = this,
							taskId = taskId,
							url = url,
							fileName = fileName,
							channelName = channelName,
							headers = headers,
							maxDurationMs = maxDurationMs,
						)
						try {
							androidx.core.content.ContextCompat.startForegroundService(this, intent)
							result.success(taskId)
						} catch (e: Exception) {
							// The service never saw the intent; nothing will
							// resolve the claim — take it back ourselves.
							com.debrify.app.recording.RecordingRegistry
								.resolvePendingStart(url, taskId)
							result.error("fgs_not_allowed", e.message, null)
						}
					}
					"stopLiveRecording" -> {
						val taskId = call.argument<String>("taskId")
						if (taskId.isNullOrEmpty()) {
							result.error("bad_args", "taskId required", null)
							return@setMethodCallHandler
						}
						val intent = Intent(this, com.debrify.app.recording.LiveRecordingService::class.java).apply {
							action = com.debrify.app.recording.LiveRecordingService.ACTION_STOP
							putExtra(com.debrify.app.recording.LiveRecordingService.EXTRA_TASK_ID, taskId)
						}
						// The service is necessarily foreground while a capture
						// runs, so a plain startService reaches it from anywhere.
						try {
							startService(intent)
							result.success(true)
						} catch (e: Exception) {
							result.error("stop_failed", e.message, null)
						}
					}
					"stopAllLiveRecordings" -> {
						val intent = Intent(this, com.debrify.app.recording.LiveRecordingService::class.java).apply {
							action = com.debrify.app.recording.LiveRecordingService.ACTION_STOP_ALL
						}
						try {
							startService(intent)
							result.success(true)
						} catch (e: Exception) {
							result.error("stop_failed", e.message, null)
						}
					}
					"queryLiveRecordings" -> {
						// Reconcile first so a process death shows up as a
						// finalized recording, never a phantom "recording" row.
						Thread {
							val list = try {
								com.debrify.app.recording.RecordingTaskStore.reconcileDeadEntries(this)
								com.debrify.app.recording.RecordingTaskStore.all(this).values.map { e ->
									val live = com.debrify.app.recording.RecordingRegistry.live[e.taskId]
									mapOf(
										"taskId" to e.taskId,
										"status" to if (live != null) "recording" else e.status,
										"url" to e.url,
										"fileName" to e.fileName,
										"channelName" to e.channelName,
										"bytes" to (live?.bytes ?: e.bytes),
										"startedAtMs" to e.startedAtMs,
										"uri" to e.uri,
										"errorMessage" to e.errorMessage,
										"updatedAt" to e.updatedAt,
									)
								}
							} catch (e: Exception) {
								null
							}
							runOnUiThread {
								if (list != null) result.success(list)
								else result.error("query_failed", "recordings query failed", null)
							}
						}.start()
					}
					"forgetLiveRecording" -> {
						val taskId = call.argument<String>("taskId")
						if (taskId.isNullOrEmpty()) {
							result.error("bad_args", "taskId required", null)
							return@setMethodCallHandler
						}
						com.debrify.app.recording.RecordingTaskStore.remove(this, taskId)
						result.success(true)
					}
					"queryRecordingsLibrary" -> {
						// Finished recordings for the Recordings hub. The store's
						// `done` entries are the index (channel name + duration),
						// merged with a MediaStore scan of our own rows under the
						// recordings path — the scan is what surfaces tee-recorded
						// files and recordings whose entries the old 24h TTL
						// already pruned. Worker thread: reconcile + scan are IO.
						Thread {
							val list = try { buildRecordingsLibrary() } catch (e: Exception) { null }
							runOnUiThread {
								if (list != null) result.success(list)
								else result.error("query_failed", "library query failed", null)
							}
						}.start()
					}
					"deleteRecordingFile" -> {
						val uriString = call.argument<String>("uri")
						if (uriString.isNullOrEmpty()) {
							result.error("bad_args", "uri required", null)
							return@setMethodCallHandler
						}
						// A live capture's destination must be stopped, not
						// deleted out from under the worker's file descriptor.
						val liveEntry = com.debrify.app.recording.RecordingTaskStore
							.all(this).values.firstOrNull {
								it.uri == uriString &&
									it.status == "recording" &&
									com.debrify.app.recording.RecordingRegistry.live
										.containsKey(it.taskId)
							}
						if (liveEntry != null) {
							result.error("recording_live", "stop the recording first", null)
							return@setMethodCallHandler
						}
						Thread {
							val ok = try {
								val uri = android.net.Uri.parse(uriString)
								com.debrify.app.recording.RecordingTaskStore
									.deleteDestination(this, uri)
								for ((taskId, entry) in
									com.debrify.app.recording.RecordingTaskStore.all(this)
								) {
									if (entry.uri == uriString) {
										com.debrify.app.recording.RecordingTaskStore
											.remove(this, taskId)
									}
								}
								com.debrify.app.recording.TeeUnpublishedStore.remove(this, uri)
								true
							} catch (e: Exception) { false }
							runOnUiThread { result.success(ok) }
						}.start()
					}
					// ── Scheduled recordings ────────────────────────────────
					"scheduleRecording" -> {
						val url = call.argument<String>("url")
						val channelName = call.argument<String>("channelName") ?: "Live channel"
						val programmeTitle = call.argument<String>("programmeTitle") ?: ""
						val startMs = call.argument<Number>("startMs")?.toLong()
						val endMs = call.argument<Number>("endMs")?.toLong()
						val force = call.argument<Boolean>("force") ?: false
						@Suppress("UNCHECKED_CAST")
						val headers = call.argument<HashMap<String, String>>("headers") ?: hashMapOf()
						if (url.isNullOrEmpty() || startMs == null || endMs == null) {
							result.error("bad_args", "url/startMs/endMs required", null)
							return@setMethodCallHandler
						}
						if (!com.debrify.app.recording.LiveRecordingService.isSupported(this)) {
							result.error("engine_unsupported", "requires Android 10+", null)
							return@setMethodCallHandler
						}
						if (url.startsWith("stremio-tv://")) {
							result.error("unsupported_channel", "Stremio channels can't be scheduled", null)
							return@setMethodCallHandler
						}
						// Without the exact-alarm grant the fire would arrive as an
						// INEXACT broadcast, which carries no foreground-service
						// start exemption — the recording could not reliably start
						// at all. Refuse honestly instead of promising "a bit
						// late"; the UI links straight to the grant.
						if (!com.debrify.app.recording.RecordingAlarmReceiver.exactAlarmsGranted(this)) {
							result.error(
								"exact_alarms_required",
								"allow exact alarms in system settings",
								null,
							)
							return@setMethodCallHandler
						}
						val now = System.currentTimeMillis()
						if (endMs <= now + 60_000L || endMs <= startMs) {
							result.error("bad_time", "programme is over or times invalid", null)
							return@setMethodCallHandler
						}
						val dup = com.debrify.app.recording.RecordingScheduleStore
							.findDuplicate(this, url, startMs)
						if (dup != null && !force) {
							result.error("duplicate", "already scheduled", null)
							return@setMethodCallHandler
						}
						val id = "sched-${System.currentTimeMillis()}"
						com.debrify.app.recording.RecordingScheduleStore.put(
							this,
							com.debrify.app.recording.RecordingSchedule(
								id = id,
								channelName = channelName,
								url = url,
								headers = headers,
								startMs = startMs,
								endMs = endMs,
								programmeTitle = programmeTitle,
								createdAt = now,
							),
						)
						com.debrify.app.recording.RecordingAlarmReceiver.registerAll(this)
						result.success(mapOf(
							"id" to id,
							"exact" to com.debrify.app.recording.RecordingAlarmReceiver
								.exactAlarmsGranted(this),
						))
					}
					"cancelScheduledRecording" -> {
						val id = call.argument<String>("id")
						if (id.isNullOrEmpty()) {
							result.error("bad_args", "id required", null)
							return@setMethodCallHandler
						}
						com.debrify.app.recording.RecordingScheduleStore.remove(this, id)
						com.debrify.app.recording.RecordingAlarmReceiver.cancelAlarm(this, id)
						result.success(true)
					}
					"listScheduledRecordings" -> {
						val list = com.debrify.app.recording.RecordingScheduleStore.all(this)
							.values
							.sortedBy { it.startMs }
							.map { s ->
								mapOf(
									"id" to s.id,
									"channelName" to s.channelName,
									"url" to s.url,
									"programmeTitle" to s.programmeTitle,
									"startMs" to s.startMs,
									"endMs" to s.endMs,
								)
							}
						result.success(list)
					}
					"exactAlarmState" -> {
						result.success(
							com.debrify.app.recording.RecordingAlarmReceiver.exactAlarmsGranted(this),
						)
					}
					"openExactAlarmSettings" -> {
						if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
							try {
								startActivity(
									Intent(
										android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
										android.net.Uri.parse("package:$packageName"),
									),
								)
								result.success(true)
							} catch (e: Exception) {
								result.success(false)
							}
						} else {
							result.success(false)
						}
					}
					"queryDownloadTasks" -> {
					// Native truth for Dart reconciliation: the persisted store
					// merged with the live in-memory registry. A stored
					// "running" with no live worker means the process died
					// mid-download — report it as paused (bytes are on disk).
					try {
						val entries = com.debrify.app.download.DownloadTaskStore.all(this)
						val list = entries.values.map { e ->
							val live = com.debrify.app.download.DownloadRegistry.live[e.taskId]
							val bytes = live?.bytes ?: (e.uri?.let { u ->
								try {
									contentResolver.openFileDescriptor(Uri.parse(u), "r")?.use { pfd ->
										java.io.FileInputStream(pfd.fileDescriptor).use { fis -> fis.channel.size() }
									} ?: 0L
								} catch (_: Exception) { 0L }
							} ?: 0L)
							val status = if (live != null) "running"
								else if (e.status == "running") "paused" else e.status
							mapOf(
								"taskId" to e.taskId,
								"status" to status,
								"bytes" to bytes,
								"total" to (live?.total ?: e.total),
								"uri" to e.uri,
								"destType" to e.destType,
								"fileName" to e.fileName,
								"subDir" to e.subDir,
								"url" to e.url,
								"errorMessage" to e.errorMessage,
								"updatedAt" to e.updatedAt,
							)
						}
						result.success(list)
					} catch (e: Exception) {
						result.error("query_failed", e.message, null)
					}
				}
				"forgetDownloadTask" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					try {
						com.debrify.app.download.DownloadTaskStore.remove(this, taskId)
						com.debrify.app.download.DownloadRegistry.live.remove(taskId)
						result.success(true)
					} catch (e: Exception) {
						result.error("forget_failed", e.message, null)
					}
				}
				"pickDownloadDirectory" -> {
					if (pendingDirPickResult != null) {
						result.error("busy", "picker already open", null)
						return@setMethodCallHandler
					}
					try {
						pendingDirPickResult = result
						val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
							addFlags(
								Intent.FLAG_GRANT_READ_URI_PERMISSION or
									Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
									Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
							)
						}
						startActivityForResult(intent, REQUEST_PICK_DOWNLOAD_DIR)
					} catch (e: Exception) {
						pendingDirPickResult = null
						result.error("pick_failed", e.message, null)
					}
				}
				"releaseDownloadDirectory" -> {
					val treeUri = call.argument<String>("treeUri")
					if (treeUri.isNullOrEmpty()) { result.error("bad_args", "treeUri required", null); return@setMethodCallHandler }
					try {
						contentResolver.releasePersistableUriPermission(
							Uri.parse(treeUri),
							Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
						)
						result.success(true)
					} catch (_: Exception) {
						// Grant already gone — releasing is best-effort.
						result.success(false)
					}
				}
				"validateDownloadDirectory" -> {
					val treeUri = call.argument<String>("treeUri")
					if (treeUri.isNullOrEmpty()) { result.error("bad_args", "treeUri required", null); return@setMethodCallHandler }
					try {
						val uri = Uri.parse(treeUri)
						val held = contentResolver.persistedUriPermissions.any {
							it.uri == uri && it.isWritePermission
						}
						val canWrite = held && (androidx.documentfile.provider.DocumentFile.fromTreeUri(this, uri)?.canWrite() == true)
						result.success(canWrite)
					} catch (_: Exception) {
						result.success(false)
					}
				}
				"pause" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_PAUSE
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"resume" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_RESUME
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"cancel" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_CANCEL
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					try {
						androidx.core.content.ContextCompat.startForegroundService(this, intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("fgs_not_allowed", e.message, null)
					}
				}
				"openContentUri" -> {
					val uriStr = call.argument<String>("uri")
					val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
					if (uriStr.isNullOrEmpty()) {
						result.error("bad_args", "uri required", null)
						return@setMethodCallHandler
					}
					try {
						val u = Uri.parse(uriStr)
						val view = Intent(Intent.ACTION_VIEW).apply {
							setDataAndType(u, mime)
							addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(view)
						result.success(true)
					} catch (e: ActivityNotFoundException) {
						try {
							val downloads = Intent("android.intent.action.VIEW_DOWNLOADS")
							downloads.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(downloads)
							result.success(false)
						} catch (e2: Exception) {
							result.error("open_failed", e2.message, null)
						}
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
				}
				"ensureNotificationPermission" -> {
					// True = notifications will show. Ask at most once ever;
					// recording proceeds either way, so a decline is final
					// unless the user flips it in system settings.
					if (android.os.Build.VERSION.SDK_INT < 33) {
						result.success(true)
						return@setMethodCallHandler
					}
					val grantedNow = androidx.core.content.ContextCompat.checkSelfPermission(
						this,
						android.Manifest.permission.POST_NOTIFICATIONS,
					) == android.content.pm.PackageManager.PERMISSION_GRANTED
					if (grantedNow) {
						result.success(true)
						return@setMethodCallHandler
					}
					val prefs = getSharedPreferences("debrify_permissions", MODE_PRIVATE)
					if (prefs.getBoolean("notification_permission_asked", false)) {
						result.success(false)
						return@setMethodCallHandler
					}
					if (pendingNotificationPermissionResult != null) {
						result.success(false)
						return@setMethodCallHandler
					}
					prefs.edit().putBoolean("notification_permission_asked", true).apply()
					pendingNotificationPermissionResult = result
					androidx.core.app.ActivityCompat.requestPermissions(
						this,
						arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
						notificationPermissionRequestCode,
					)
				}
				"isIgnoringBatteryOptimizations" -> {
					// Doze (and this API) arrived in M — below that there is
					// nothing to be exempt from, so "exempt" is the truth.
					if (android.os.Build.VERSION.SDK_INT < 23) {
						result.success(true)
						return@setMethodCallHandler
					}
					val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
					result.success(pm.isIgnoringBatteryOptimizations(packageName))
				}
				"openBatteryOptimizationSettings" -> {
					try {
						val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
				}
				"requestIgnoreBatteryOptimizationForApp" -> {
					if (android.os.Build.VERSION.SDK_INT < 23) {
						result.success(false)
						return@setMethodCallHandler
					}
					try {
						val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
							data = Uri.parse("package:" + packageName)
						}
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("request_failed", e.message, null)
					}
				}
				"isTelevision" -> {
					// Single source of truth — includes the Leanback fallback so a
					// device that reports a non-TV UI mode still gets the Debrify
					// keyboard instead of the broken system IME (flutter#177360).
					result.success(isTelevision())
				}
				"getDeviceName" -> {
					try {
						// Try to get the user-set device name first (Bluetooth name)
						val bluetoothName = Settings.Global.getString(contentResolver, "device_name")
						if (!bluetoothName.isNullOrBlank()) {
							result.success(bluetoothName)
							return@setMethodCallHandler
						}
						// Fall back to manufacturer + model
						val manufacturer = Build.MANUFACTURER?.replaceFirstChar { it.uppercase() } ?: ""
						val model = Build.MODEL ?: ""
						val deviceName = if (manufacturer.isNotEmpty() && model.isNotEmpty() && !model.startsWith(manufacturer, ignoreCase = true)) {
							"$manufacturer $model"
						} else if (model.isNotEmpty()) {
							model
						} else {
							"Android TV"
						}
						result.success(deviceName)
					} catch (e: Exception) {
						result.success("Android TV")
					}
				}
			else -> result.notImplemented()
			}
		}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(object: EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				com.debrify.app.download.ChannelBridge.setSink(events)
			}

			override fun onCancel(arguments: Any?) {
				com.debrify.app.download.ChannelBridge.setSink(null)
			}
		})

        val tvChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANDROID_TV_CHANNEL
        )
        registeredTvPlayerChannel = tvChannel
        setAndroidTvPlayerChannel(tvChannel)
        tvChannel.setMethodCallHandler { call, result ->
            android.util.Log.d("DebrifyTV", "MainActivity: Method channel received: ${call.method}")
            when (call.method) {
                "launchTorboxPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorboxPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "torbox")
                }
                "launchRealDebridPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchRealDebridPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "real_debrid")
                }
                "launchTorrentPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorrentPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing torrent payload", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTorrentPlayback(args, result)
                }
                "updateEpisodeMetadata" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling updateEpisodeMetadata")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing metadata updates", null)
                        return@setMethodCallHandler
                    }
                    handleUpdateEpisodeMetadata(args, result)
                }
                else -> {
                    android.util.Log.w("DebrifyTV", "MainActivity: Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        // Inline ExoPlayer texture surface for the ambient trailer backdrop —
        // TV only (the Dart side only selects the Exo engine on Android TV, so
        // there's no reason to stand up the native player + channel elsewhere).
        // Release any prior instance first in case configureFlutterEngine runs
        // again on a reused engine without an intervening onDestroy.
        tvTrailerPlayer?.releaseAll()
        tvTrailerPlayer = null
        if (isTelevision()) {
            tvTrailerPlayer = com.debrify.app.tv.TvTrailerTexturePlayer(
                this,
                flutterEngine.renderer,
                flutterEngine.dartExecutor.binaryMessenger,
                { trailerUnderlayContainer() },
                uiScale,
            )
        }

        // Remote control channel for injecting key events and text
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMOTE_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "injectKeyEvent" -> {
                    val keyCode = call.argument<Int>("keyCode")
                    if (keyCode == null) {
                        result.error("bad_args", "keyCode is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // Get the currently active activity (could be MainActivity or a video player)
                        val targetActivity = ActivityTracker.currentActivity
                        if (targetActivity == null) {
                            android.util.Log.w("RemoteControl", "No active activity to receive key event")
                            result.error("no_activity", "No active activity", null)
                            return@setMethodCallHandler
                        }
                        // Dispatch key down event
                        val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                        targetActivity.dispatchKeyEvent(downEvent)
                        // Dispatch key up event
                        val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
                        targetActivity.dispatchKeyEvent(upEvent)
                        android.util.Log.d("RemoteControl", "Injected key event $keyCode to ${targetActivity.javaClass.simpleName}")
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("RemoteControl", "Failed to inject key event: ${e.message}")
                        result.error("inject_failed", e.message, null)
                    }
                }
                "injectText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val clear = call.argument<Boolean>("clear") ?: false
                    try {
                        val targetActivity = ActivityTracker.currentActivity
                        if (targetActivity == null) {
                            android.util.Log.w("RemoteControl", "No active activity to receive text")
                            result.error("no_activity", "No active activity", null)
                            return@setMethodCallHandler
                        }

                        if (clear) {
                            // Select all and delete to clear the field
                            // Send Ctrl+A to select all
                            val metaState = KeyEvent.META_CTRL_ON
                            val downA = KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A, 0, metaState)
                            val upA = KeyEvent(0, 0, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_A, 0, metaState)
                            targetActivity.dispatchKeyEvent(downA)
                            targetActivity.dispatchKeyEvent(upA)
                            // Then send delete
                            val downDel = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL)
                            val upDel = KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL)
                            targetActivity.dispatchKeyEvent(downDel)
                            targetActivity.dispatchKeyEvent(upDel)
                            android.util.Log.d("RemoteControl", "Cleared text field")
                        } else if (text.isNotEmpty()) {
                            // Use KeyCharacterMap to dispatch key events for each character
                            // This is the most reliable way to inject text into Flutter TextFields
                            // as it uses the same mechanism as physical keyboards
                            val keyCharMap = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD)
                            for (char in text) {
                                val events = keyCharMap.getEvents(charArrayOf(char))
                                if (events != null) {
                                    for (event in events) {
                                        targetActivity.dispatchKeyEvent(event)
                                    }
                                } else {
                                    android.util.Log.w("RemoteControl", "No key events for char: $char")
                                }
                            }
                            android.util.Log.d("RemoteControl", "Injected text via key events: $text")
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("RemoteControl", "Failed to inject text: ${e.message}")
                        result.error("inject_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // TV voice dictation — in-app capture. Events (partials, levels, the
        // final transcript, errors) go up the companion EventChannel; this
        // channel only carries commands.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    voiceEvents = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Ask the platform, don't try/catch a start: plenty of
                    // cheap AOSP boxes (and Fire TV) ship no recognition
                    // service at all, and the keyboard hides its mic key when
                    // this is false. NB the manifest needs a <queries> entry
                    // for android.speech.RecognitionService or this lies on
                    // API 30+ even when a recognizer is installed.
                    "isAvailable" -> {
                        result.success(
                            runCatching {
                                android.speech.SpeechRecognizer.isRecognitionAvailable(this)
                            }.getOrDefault(false)
                        )
                    }
                    // True once the mic is ours to use. Asked contextually, on
                    // the press — never at app start.
                    "ensurePermission" -> {
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.RECORD_AUDIO,
                        ) == PackageManager.PERMISSION_GRANTED
                        if (granted) {
                            result.success(true)
                        } else if (pendingVoicePermissionResult != null) {
                            result.success(false)
                        } else {
                            pendingVoicePermissionResult = result
                            androidx.core.app.ActivityCompat.requestPermissions(
                                this,
                                arrayOf(android.Manifest.permission.RECORD_AUDIO),
                                recordAudioPermissionRequestCode,
                            )
                        }
                    }
                    "start" -> {
                        startVoiceCapture(call.argument<String>("locale"))
                        result.success(true)
                    }
                    // Stop = "I'm done talking, transcribe what you have"; the
                    // final result still arrives on the event channel.
                    "stop" -> {
                        runCatching { speechRecognizer?.stopListening() }
                        result.success(true)
                    }
                    // Cancel = throw it away, no result event follows.
                    "cancel" -> {
                        destroyVoiceCapture()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Picture-in-Picture channel — driven by the phone media_kit player.
        val pipCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel = pipCh
        pipCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(pipSupported())
                "enterPip" -> {
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    result.success(enterPipInternal(aw, ah))
                }
                "setAutoEnter" -> {
                    pipAutoEnterArmed = call.argument<Boolean>("enabled") ?: false
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    pipIsPlaying = call.argument<Boolean>("isPlaying") ?: pipIsPlaying
                    pipHasNext = call.argument<Boolean>("hasNext") ?: pipHasNext
                    val aw = call.argument<Int>("aspectWidth") ?: 0
                    val ah = call.argument<Int>("aspectHeight") ?: 0
                    if (aw > 0 && ah > 0) {
                        pipAspectW = aw
                        pipAspectH = ah
                    }
                    updatePipParamsIfActive()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
	}

    private fun handleLaunchTvPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
        provider: String
    ) {
        android.util.Log.d("DebrifyTV", "MainActivity: handleLaunchTvPlayback() called with provider=$provider")
        
        val initialUrl = (args["initialUrl"] as? String)?.trim()
        android.util.Log.d("DebrifyTV", "MainActivity: initialUrl=${initialUrl?.take(50)}...")
        
        if (initialUrl.isNullOrEmpty()) {
            android.util.Log.e("DebrifyTV", "MainActivity: initialUrl is null or empty")
            result.error("bad_args", "initialUrl is required", null)
            return
        }
        
        val initialTitleRaw = (args["initialTitle"] as? String)?.trim()
        val initialTitle = if (initialTitleRaw.isNullOrEmpty()) "Debrify TV" else initialTitleRaw
        android.util.Log.d("DebrifyTV", "MainActivity: title=$initialTitle")

        @Suppress("UNCHECKED_CAST")
        val config = args["config"] as? Map<String, Any?>
        android.util.Log.d("DebrifyTV", "MainActivity: config=$config")

        android.util.Log.d("DebrifyTV", "MainActivity: Creating intent for TorboxTvPlayerActivity")
        val intent = Intent().apply {
            setClassName(this@MainActivity, "com.debrify.app.tv.TorboxTvPlayerActivity")
            putExtra("initialUrl", initialUrl)
            putExtra("initialTitle", initialTitle)
            putExtra("provider", provider)
            putExtra("channelName", (args["channelName"] as? String)?.trim())
            putExtra("currentChannelId", (args["currentChannelId"] as? String)?.trim())
            (args["currentChannelNumber"] as? Number)?.toInt()?.let { number ->
                putExtra("currentChannelNumber", number)
            }

            @Suppress("UNCHECKED_CAST")
            val channelsRaw = args["channels"] as? List<Map<String, Any?>>
            if (!channelsRaw.isNullOrEmpty()) {
                android.util.Log.d(
                    "DebrifyTV",
                    "MainActivity: Preparing ${channelsRaw.size} channel directory entries",
                )
                val channelBundles = ArrayList<Bundle>(channelsRaw.size)
                channelsRaw.forEach { entry ->
                    val bundle = Bundle()
                    (entry["id"] as? String)?.trim()?.let { bundle.putString("id", it) }
                    (entry["name"] as? String)?.trim()?.let { bundle.putString("name", it) }
                    (entry["channelNumber"] as? Number)?.toInt()
                        ?.let { bundle.putInt("channelNumber", it) }
                    (entry["isCurrent"] as? Boolean)?.let { bundle.putBoolean("isCurrent", it) }
                    channelBundles.add(bundle)
                }
                if (channelBundles.isNotEmpty()) {
                    putParcelableArrayListExtra("channelDirectory", channelBundles)
                }
            }

            // For Torbox: magnets are required. For Real-Debrid: magnets are optional
            @Suppress("UNCHECKED_CAST")
            val magnetsRaw = args["magnets"] as? List<Map<String, Any?>>
            if (magnetsRaw != null && magnetsRaw.isNotEmpty()) {
                android.util.Log.d("DebrifyTV", "MainActivity: Processing ${magnetsRaw.size} magnets")
                val magnetBundles = ArrayList<Bundle>()
                magnetsRaw.forEach { entry ->
                    val magnet = (entry["magnet"] as? String)?.trim()
                    if (!magnet.isNullOrEmpty()) {
                        val bundle = Bundle()
                        bundle.putString("magnet", magnet)
                        bundle.putString("hash", (entry["hash"] as? String)?.trim() ?: "")
                        bundle.putString("name", (entry["name"] as? String)?.trim() ?: "")
                        (entry["sizeBytes"] as? Number)?.let { bundle.putLong("sizeBytes", it.toLong()) }
                        (entry["seeders"] as? Number)?.let { bundle.putInt("seeders", it.toInt()) }
                        magnetBundles.add(bundle)
                    }
                }
                if (magnetBundles.isNotEmpty()) {
                    android.util.Log.d("DebrifyTV", "MainActivity: Added ${magnetBundles.size} magnet bundles")
                    putParcelableArrayListExtra("magnetList", magnetBundles)
                }
            } else {
                android.util.Log.d("DebrifyTV", "MainActivity: No magnets provided (OK for Real-Debrid)")
            }
            
            putExtra("startFromRandom", config?.get("startFromRandom") as? Boolean ?: false)
            putExtra("randomStartMaxPercent", (config?.get("randomStartMaxPercent") as? Number)?.toInt() ?: 40)
            putExtra("startAtPercent", (config?.get("startAtPercent") as? Number)?.toDouble() ?: 0.0)
            putExtra("hideSeekbar", config?.get("hideSeekbar") as? Boolean ?: false)
            putExtra("hideOptions", config?.get("hideOptions") as? Boolean ?: false)
            putExtra("showVideoTitle", config?.get("showVideoTitle") as? Boolean ?: true)
            putExtra("showChannelName", config?.get("showChannelName") as? Boolean ?: false)

            // Custom font from Flutter settings
            (args["customFontPath"] as? String)?.trim()?.let { fontPath ->
                putExtra("customFontPath", fontPath)
                (args["customFontName"] as? String)?.trim()?.let { fontName ->
                    putExtra("customFontName", fontName)
                }
                android.util.Log.d("DebrifyTV", "MainActivity: Passing custom font: $fontPath")
            }
        }

        try {
            android.util.Log.d("DebrifyTV", "MainActivity: Starting TorboxTvPlayerActivity")
            startActivity(intent)
            android.util.Log.d("DebrifyTV", "MainActivity: ✅ Activity started successfully")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: ❌ Failed to start activity: ${e.message}")
            e.printStackTrace()
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleUpdateEpisodeMetadata(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        android.util.Log.d("TVMazeUpdate", "MainActivity: handleUpdateEpisodeMetadata CALLED")
        @Suppress("UNCHECKED_CAST")
        val updates = args["updates"] as? List<Map<String, Any?>> ?: emptyList()
        val imdbId = args["imdbId"] as? String

        if (updates.isEmpty() && imdbId.isNullOrEmpty()) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: updates is empty and no imdbId")
            result.error("bad_args", "updates or imdbId is required", null)
            return
        }
        android.util.Log.d("TVMazeUpdate", "MainActivity: received ${updates.size} updates, imdbId=$imdbId")

        try {
            // Broadcast intent to the active player activity
            val intent = Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA").apply {
                setPackage(packageName)
                val updatesJson = listToJson(updates).toString()
                android.util.Log.d("TVMazeUpdate", "MainActivity: updatesJson length=${updatesJson.length}")
                putExtra("metadataUpdates", updatesJson)
                // Include discovered IMDB ID for Stremio subtitle fetching
                if (!imdbId.isNullOrEmpty()) {
                    putExtra("imdbId", imdbId)
                    android.util.Log.d("TVMazeUpdate", "MainActivity: Including imdbId=$imdbId")
                }
            }
            sendBroadcast(intent)
            android.util.Log.d("TVMazeUpdate", "MainActivity: Broadcast SENT with ${updates.size} updates, imdbId=$imdbId")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: Failed to send metadata update: ${e.message}", e)
            result.error("update_failed", e.message, null)
        }
    }

    private fun handleLaunchTorrentPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        val payload = args["payload"]
        if (payload !is Map<*, *>) {
            result.error("bad_args", "payload is required", null)
            return
        }

        try {
            val payloadJson = mapToJson(payload).toString()

            // Write payload to temp file to avoid Android's Intent size limit (~1MB)
            // This allows playlists with 500+ items without TransactionTooLargeException
            val tempFile = java.io.File(cacheDir, "torrent_payload_${System.currentTimeMillis()}.json")
            tempFile.writeText(payloadJson)
            android.util.Log.d("DebrifyTV", "MainActivity: Wrote payload to temp file: ${tempFile.absolutePath} (${payloadJson.length} bytes)")

            val intent = Intent().apply {
                setClassName(
                    this@MainActivity,
                    "com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
                )
                putExtra("payloadPath", tempFile.absolutePath)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: Failed to launch torrent playback", e)
            result.error("launch_failed", e.message, null)
        }
    }

    private fun mapToJson(map: Map<*, *>): org.json.JSONObject {
        val json = org.json.JSONObject()
        for ((key, value) in map) {
            if (key == null) continue
            json.put(key.toString(), valueToJson(value))
        }
        return json
    }

    private fun listToJson(list: List<*>): org.json.JSONArray {
        val array = org.json.JSONArray()
        for (value in list) {
            array.put(valueToJson(value))
        }
        return array
    }

    private fun valueToJson(value: Any?): Any? {
        return when (value) {
            null -> org.json.JSONObject.NULL
            is Map<*, *> -> mapToJson(value)
            is List<*> -> listToJson(value)
            is Number, is Boolean, is String -> value
            else -> value.toString()
        }
    }
}
