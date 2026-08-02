package com.debrify.app.recording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.TaskStackBuilder
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The recording ENGINE: captures a live stream over its OWN HTTP connection
 * into a MediaStore file, independent of any player. Zaps, source switches,
 * Home, player teardown and app death do not touch it — a recording ends only
 * on user stop, its duration cap, storage failure, or a stream that stays dead
 * through the reconnect budget.
 *
 * Structure is deliberately a sibling of MediaStoreDownloadService (foreground
 * claim first, AtomicBoolean claim/finish guards, main-handler stop paths,
 * shared stall watchdog, wake/wifi locks) rather than an extension of it — the
 * download service is shipping and hardened, and recording must not be able to
 * regress it. What differs from a download:
 *
 *  - No Range/resume. Live streams don't rewind; a reconnect after a drop just
 *    keeps appending, and the TS container tolerates the discontinuity.
 *  - No EOF-means-done. EOF from a live server is a drop like any other; the
 *    recording ends by STOP or the duration cap, and a stream that stays dead
 *    for [MAX_CONSECUTIVE_RECONNECTS] attempts finalizes as a partial.
 *  - Process death is finalize-not-resume: RecordingTaskStore.reconcileDeadEntries
 *    publishes whatever was synced to the row. A dead live capture can never be
 *    resumed — the gap is unbounded.
 *
 * API 29+ only (MediaStore.Downloads destination); callers gate.
 */
class LiveRecordingService : Service() {
	companion object {
		const val ACTION_START = "com.debrify.app.recording.action.START"
		const val ACTION_STOP = "com.debrify.app.recording.action.STOP"
		const val ACTION_STOP_ALL = "com.debrify.app.recording.action.STOP_ALL"

		const val EXTRA_TASK_ID = "extra_task_id"
		const val EXTRA_URL = "extra_url"
		const val EXTRA_FILE_NAME = "extra_file_name"
		const val EXTRA_CHANNEL_NAME = "extra_channel_name"
		const val EXTRA_HEADERS = "extra_headers" // HashMap<String, String>
		const val EXTRA_MAX_DURATION_MS = "extra_max_duration_ms"
		const val EXTRA_FROM_SCHEDULE = "extra_from_schedule"

		const val RELATIVE_PATH = "Download/Debrify/Recordings"
		const val MIME_TYPE = "video/mp2t"

		/** Concurrent live captures. Cheap TV boxes have real IO/bandwidth
		 *  limits, and every capture is a full extra connection. */
		const val MAX_CONCURRENT = 2

		/** Safety ceiling per recording — also keeps a single capture inside
		 *  Android 15's rolling dataSync foreground budget. */
		const val MAX_DURATION_DEFAULT_MS = 6L * 60 * 60 * 1000

		const val NOTIFICATION_CHANNEL_ID = "recordings_channel_v1"
		private const val NOTIFICATION_CHANNEL_NAME = "Recordings"

		/** Also used by the alarm receiver, which may post before the service
		 *  has ever run in this process. */
		fun ensureNotificationChannel(context: Context) {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
					as NotificationManager
				manager.createNotificationChannel(
					NotificationChannel(
						NOTIFICATION_CHANNEL_ID,
						NOTIFICATION_CHANNEL_NAME,
						NotificationManager.IMPORTANCE_LOW,
					)
				)
			}
		}
		private const val SERVICE_NOTIFICATION_ID = 9100
		private const val GROUP_KEY_RECORDINGS = "com.debrify.app.recordings.GROUP"

		private const val MIN_FREE_BYTES = 200L * 1024 * 1024

		/** Sent when the channel declares no User-Agent of its own. Providers
		 *  routinely block default library UAs (the app's mpv path learned
		 *  this the hard way — Lavf was rejected outright); mirror Dart's
		 *  kIptvDefaultUserAgent so the engine looks like the player. */
		private const val DEFAULT_USER_AGENT =
			"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
				"(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
		private const val STALL_TIMEOUT_MS = 60_000L
		private const val STALL_CHECK_INTERVAL_MS = 10_000L
		private const val MAX_CONSECUTIVE_RECONNECTS = 3
		private const val RECONNECT_BACKOFF_MS = 2_000L
		private const val NOTIFY_THROTTLE_MS = 2_000L

		/** Q+ always (MediaStore destination); pre-Q with the legacy storage
		 *  grant writes a plain file into public Download/ instead. */
		fun isSupported(context: Context): Boolean =
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
				legacyStorageGranted(context)

		/** Pre-Q only: whether WRITE_EXTERNAL_STORAGE is granted (install-time
		 *  on API 21-22, runtime on 23-28). */
		fun legacyStorageGranted(context: Context): Boolean {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return false
			return androidx.core.content.ContextCompat.checkSelfPermission(
				context,
				android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
			) == android.content.pm.PackageManager.PERMISSION_GRANTED
		}

		/** Pre-Q device that could record once the user grants storage. */
		fun needsLegacyPermission(context: Context): Boolean =
			Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
				!legacyStorageGranted(context)

		/** The legacy destination directory (public Downloads). */
		fun legacyRecordingsDir(): java.io.File = java.io.File(
			@Suppress("DEPRECATION")
			Environment.getExternalStoragePublicDirectory(
				Environment.DIRECTORY_DOWNLOADS,
			),
			"Debrify/Recordings",
		)

		/** Build a START intent; shared by MainActivity, the TV player and the
		 *  alarm receiver so the extras can never drift apart. */
		fun buildStartIntent(
			context: Context,
			taskId: String,
			url: String,
			fileName: String,
			channelName: String,
			headers: HashMap<String, String>,
			maxDurationMs: Long,
			fromSchedule: Boolean = false,
		): Intent = Intent(context, LiveRecordingService::class.java).apply {
			action = ACTION_START
			putExtra(EXTRA_TASK_ID, taskId)
			putExtra(EXTRA_URL, url)
			putExtra(EXTRA_FILE_NAME, fileName)
			putExtra(EXTRA_CHANNEL_NAME, channelName)
			putExtra(EXTRA_HEADERS, headers)
			putExtra(EXTRA_MAX_DURATION_MS, maxDurationMs)
			putExtra(EXTRA_FROM_SCHEDULE, fromSchedule)
		}
	}

	private class RecordingState(
		val taskId: String,
		val url: String,
		val fileName: String,
		val channelName: String,
		val headers: HashMap<String, String>,
		val startedAtMs: Long,
		val endAtMs: Long,
	) {
		var uri: Uri? = null
		@Volatile var bytes: Long = 0L
		@Volatile var stopRequested: Boolean = false
		@Volatile var connection: HttpURLConnection? = null
		@Volatile var input: InputStream? = null
		@Volatile var lastByteAt: Long = 0L
		val running = AtomicBoolean(false)
		val finished = AtomicBoolean(false)

		val timeUp: Boolean get() = System.currentTimeMillis() >= endAtMs
	}

	/** The single terminal outcome of a capture. */
	private sealed class Outcome {
		/** Bytes were saved; [note] annotates non-user endings ("6h limit"). */
		class Done(val note: String? = null) : Outcome()
		class Failed(val message: String) : Outcome()
	}

	private lateinit var notificationManager: NotificationManager
	private val states = ConcurrentHashMap<String, RecordingState>()
	private val mainHandler = Handler(Looper.getMainLooper())
	private var wakeLock: PowerManager.WakeLock? = null
	private var wifiLock: WifiManager.WifiLock? = null
	@Volatile private var watchdogScheduled = false

	override fun onCreate() {
		super.onCreate()
		notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		createNotificationChannel()
		// Entries from a previous process: publish their bytes before any new
		// task is inserted (onCreate always precedes onStartCommand).
		Thread { runCatching { RecordingTaskStore.reconcileDeadEntries(this) } }.start()
	}

	override fun onDestroy() {
		releaseLocks()
		super.onDestroy()
	}

	/**
	 * Android 15 (target 35): the app-wide dataSync foreground budget (~6h per
	 * rolling day, SHARED with the download service) can expire mid-capture.
	 * The system then calls this and kills the process after a short grace if
	 * the service doesn't stop — so finalize everything NOW: stopping the
	 * captures flushes + publishes their files within milliseconds, and the
	 * delayed stop below is the backstop in case a worker is wedged.
	 */
	override fun onTimeout(startId: Int, fgsType: Int) {
		states.values.forEach { requestStop(it) }
		mainHandler.postDelayed({
			releaseLocks()
			try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
			try { stopSelf() } catch (_: Exception) {}
		}, 3_000)
	}

	override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
		// Foreground FIRST, unconditionally — see MediaStoreDownloadService for
		// the Android 8+/12+ rationale. No-work paths release via stopIfIdle().
		try {
			startForeground(SERVICE_NOTIFICATION_ID, buildSummaryNotification())
		} catch (_: Exception) {
			// Plain-startService paths (notification actions) carry no
			// foreground obligation; continue un-promoted.
		}
		when (intent?.action) {
			ACTION_START -> handleStart(intent)
			ACTION_STOP -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID)
				val s = if (taskId != null) states[taskId] else null
				if (s != null) requestStop(s)
				stopIfIdle()
			}
			ACTION_STOP_ALL -> {
				states.values.forEach { requestStop(it) }
				stopIfIdle()
			}
			else -> stopIfIdle()
		}
		return START_NOT_STICKY
	}

	private fun handleStart(intent: Intent) {
		val url = intent.getStringExtra(EXTRA_URL)
		val taskId = intent.getStringExtra(EXTRA_TASK_ID)
			?: System.currentTimeMillis().toString()
		if (url.isNullOrEmpty() || !isSupported(this)) {
			stopIfIdle()
			return
		}
		if (!url.startsWith("http://", ignoreCase = true) &&
			!url.startsWith("https://", ignoreCase = true)
		) {
			// The engine is a plain HTTP client; callers gate, this is the
			// backstop for anything that slips through (e.g. an old schedule).
			RecordingRegistry.resolvePendingStart(url, taskId)
			postEventNotification(
				id = ("scheme-$taskId").hashCode(),
				title = "Recording not started",
				text = "This stream type can't be recorded in the background",
			)
			stopIfIdle()
			return
		}
		val existing = states[taskId]
		if (existing != null && !existing.finished.get()) {
			// Duplicate START (double-delivered alarm, double-tap): one task per
			// id, never two workers over one destination.
			updateSummaryNotification()
			return
		}
		if (states.values.any { it.url == url && !it.finished.get() }) {
			// Same URL under a DIFFERENT id (rapid double-tap racing the
			// registry, or a schedule firing for a channel already recording):
			// one capture per stream, never two connections to one channel.
			// This taskId lost — its claim must not keep answering for the url.
			RecordingRegistry.resolvePendingStart(url, taskId)
			updateSummaryNotification()
			return
		}
		val fromSchedule = intent.getBooleanExtra(EXTRA_FROM_SCHEDULE, false)
		if (states.values.count { !it.finished.get() } >= MAX_CONCURRENT) {
			// The manual path pre-checks in MainActivity, so this is mostly the
			// scheduled path racing live recordings — and with no UI in sight, a
			// notification is the only honest channel.
			RecordingRegistry.resolvePendingStart(url, taskId)
			postEventNotification(
				id = ("limit-$taskId").hashCode(),
				title = if (fromSchedule) "Scheduled recording skipped" else "Recording not started",
				text = "Recording limit reached ($MAX_CONCURRENT at a time)",
			)
			stopIfIdle()
			return
		}
		@Suppress("UNCHECKED_CAST")
		val headers = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String>
			?: hashMapOf()
		val now = System.currentTimeMillis()
		val maxDuration = intent.getLongExtra(EXTRA_MAX_DURATION_MS, MAX_DURATION_DEFAULT_MS)
			.coerceIn(1_000L, MAX_DURATION_DEFAULT_MS)
		val state = RecordingState(
			taskId = taskId,
			url = url,
			fileName = intent.getStringExtra(EXTRA_FILE_NAME) ?: "recording.ts",
			channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Live channel",
			headers = headers,
			startedAtMs = now,
			endAtMs = now + maxDuration,
		)
		states[taskId] = state
		updateSummaryNotification()
		notifyTask(state, "Starting…", completed = false)
		Thread {
			try {
				recordLoop(state)
			} catch (t: Throwable) {
				// Crash net: nothing may leave a zombie state behind.
				finishTask(state, Outcome.Failed(t.message ?: "crash"))
			}
		}.start()
	}

	/** Ask a capture to end and force its blocked read out NOW. */
	private fun requestStop(state: RecordingState) {
		state.stopRequested = true
		try { state.connection?.disconnect() } catch (_: Exception) {}
		try { state.input?.close() } catch (_: Exception) {}
	}

	// ---- Capture ------------------------------------------------------------

	private fun recordLoop(state: RecordingState) {
		if (!state.running.compareAndSet(false, true)) return
		updateLocks()
		scheduleWatchdog()
		val outcome = runCapture(state)
		state.running.set(false)
		updateLocks()
		finishTask(state, outcome)
	}

	/**
	 * The whole life of one capture: create the destination once, then connect
	 * → copy → reconnect until stopped, timed out, or the stream stays dead.
	 * Never throws.
	 */
	private fun runCapture(state: RecordingState): Outcome {
		if (freeSpaceBytes() in 0 until MIN_FREE_BYTES) {
			return Outcome.Failed("not enough free storage")
		}

		val uri: Uri
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			try {
				val values = ContentValues().apply {
					put(MediaStore.Downloads.DISPLAY_NAME, state.fileName)
					put(MediaStore.Downloads.MIME_TYPE, MIME_TYPE)
					put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
					put(MediaStore.Downloads.IS_PENDING, 1)
				}
				uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
					?: return Outcome.Failed("could not create destination")
			} catch (e: Exception) {
				return Outcome.Failed(e.message ?: "could not create destination")
			}
		} else {
			// Legacy (API 21-28): a plain file in public Download/. No pending
			// rows, no publish step — a file that exists is already visible,
			// which also collapses the crash-reconcile story to a media scan.
			try {
				val dir = legacyRecordingsDir()
				if (!dir.exists() && !dir.mkdirs()) {
					return Outcome.Failed("could not create recordings folder")
				}
				var file = java.io.File(dir, state.fileName)
				if (file.exists()) {
					// Same collision rule as everywhere else: an existing file
					// means "in use" — step aside with a suffix.
					val base = state.fileName.removeSuffix(".ts")
					var n = 2
					while (file.exists() && n < 100) {
						file = java.io.File(dir, "${base}_$n.ts")
						n++
					}
				}
				uri = Uri.fromFile(file)
			} catch (e: Exception) {
				return Outcome.Failed(e.message ?: "could not create destination")
			}
		}
		state.uri = uri

		// Registry BEFORE the persisted `recording` entry: reconcile treats
		// store-without-registry as dead, so this order (plus the store's
		// minimum dead age) keeps a starting task out of its reach.
		val live = RecordingRegistry.Live(
			url = state.url,
			channelName = state.channelName,
			fileName = state.fileName,
			startedAtMs = state.startedAtMs,
		)
		// Atomic move from pending claim to live entry — a lookup in
		// MainActivity can never see this url in NEITHER map. (Failures
		// BEFORE this point resolve the claim in finishTask.)
		RecordingRegistry.promoteToLive(state.taskId, live)
		RecordingRegistry.notifyChanged()
		persist(state, status = "recording")

		var outPfd: ParcelFileDescriptor? = null
		var outFd: java.io.FileDescriptor? = null
		var out: BufferedOutputStream? = null
		var endedNote: String? = null
		var storageFailed = false
		try {
			if (uri.scheme == "file") {
				val fos = FileOutputStream(java.io.File(uri.path!!))
				outFd = fos.fd
				out = BufferedOutputStream(fos)
			} else {
				val pfd = contentResolver.openFileDescriptor(uri, "rw")
					?: return Outcome.Failed("could not open destination")
				outPfd = pfd
				outFd = pfd.fileDescriptor
				out = BufferedOutputStream(FileOutputStream(pfd.fileDescriptor))
			}

			val buffer = ByteArray(256 * 1024)
			var consecutiveDeadConnects = 0
			var bytesAtLastDrop = 0L
			notifyTask(state, "Recording", completed = false)

			capture@ while (!state.stopRequested && !state.timeUp) {
				var connection: HttpURLConnection? = null
				var input: InputStream? = null
				var gotBytesThisAttempt = false
				try {
					// Fresh liveness stamp per attempt so the watchdog covers the
					// connect phase without killing the reconnect for the
					// previous attempt's silence.
					state.lastByteAt = System.currentTimeMillis()
					connection = (URL(state.url).openConnection() as HttpURLConnection).apply {
						instanceFollowRedirects = true
						connectTimeout = 30_000
						readTimeout = 0 // stall watchdog owns dead-stream detection
						doInput = true
						state.headers.forEach { (k, v) -> setRequestProperty(k, v) }
						if (state.headers.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
							setRequestProperty("User-Agent", DEFAULT_USER_AGENT)
						}
					}
					state.connection = connection
					if (state.stopRequested) break@capture
					connection.connect()
					val resp = connection.responseCode
					if (resp != HttpURLConnection.HTTP_OK) {
						throw IOException("HTTP $resp for live stream")
					}
					input = BufferedInputStream(connection.inputStream)
					state.input = input

					while (!state.stopRequested && !state.timeUp) {
						val n = input.read(buffer)
						if (n == -1) break
						if (n > 0) {
							// First bytes of the whole capture: if the server is
							// handing us an HLS PLAYLIST (extensionless URL that
							// lied), recording it would loop-append manifest text
							// into a ".ts" and report it saved. Fail instead.
							if (state.bytes == 0L && n >= 7 &&
								buffer[0] == '#'.code.toByte() &&
								String(buffer, 0, 7) == "#EXTM3U"
							) {
								endedNote = "stream is a playlist (HLS), not recordable"
								break@capture
							}
							try {
								out.write(buffer, 0, n)
							} catch (e: IOException) {
								// The WRITE side failing (disk full, row revoked)
								// is terminal — no reconnect can fix storage.
								storageFailed = true
								endedNote = "storage full"
								break@capture
							}
							state.bytes += n
							live.bytes = state.bytes
							gotBytesThisAttempt = true
							val now = System.currentTimeMillis()
							state.lastByteAt = now
							maybeNotifyProgress(state, now)
						}
					}
					// Clean EOF from a live server = a drop like any other; fall
					// through to the reconnect accounting below.
				} catch (e: Exception) {
					if (state.stopRequested || state.timeUp) break@capture
					// Read/connect failure: fall through to reconnect accounting.
				} finally {
					try { input?.close() } catch (_: Exception) {}
					try { connection?.disconnect() } catch (_: Exception) {}
					state.input = null
					state.connection = null
				}
				if (state.stopRequested || state.timeUp) break@capture

				// Reconnect budget: only CONSECUTIVE dead attempts count. Any
				// attempt that produced bytes proves the stream lives.
				if (gotBytesThisAttempt || state.bytes > bytesAtLastDrop) {
					consecutiveDeadConnects = 0
				} else {
					consecutiveDeadConnects++
					if (consecutiveDeadConnects >= MAX_CONSECUTIVE_RECONNECTS) {
						endedNote = "stream ended"
						break@capture
					}
				}
				bytesAtLastDrop = state.bytes
				notifyTask(state, "Reconnecting…", completed = false)
				val sleepUntil = System.currentTimeMillis() + RECONNECT_BACKOFF_MS
				while (System.currentTimeMillis() < sleepUntil &&
					!state.stopRequested && !state.timeUp
				) {
					try { Thread.sleep(200) } catch (_: InterruptedException) { break }
				}
			}
		} finally {
			// Bytes must be durable before ANY terminal state is applied.
			try { out?.flush() } catch (_: Exception) {}
			try { outFd?.sync() } catch (_: Exception) {}
			try { out?.close() } catch (_: Exception) {}
			try { outPfd?.close() } catch (_: Exception) {}
		}

		if (state.timeUp && endedNote == null && !state.stopRequested) {
			endedNote = "time limit reached"
		}
		if (storageFailed && state.bytes == 0L) {
			return Outcome.Failed("could not write to storage")
		}
		return if (state.bytes > 0L) {
			Outcome.Done(endedNote)
		} else {
			Outcome.Failed(endedNote ?: "no data received")
		}
	}

	// The ONLY place a capture reaches a terminal state.
	private fun finishTask(state: RecordingState, outcome: Outcome) {
		if (!state.finished.compareAndSet(false, true)) return
		val uri = state.uri
		when (outcome) {
			is Outcome.Done -> {
				// Publication can FAIL (provider hiccup, ejected volume). The
				// bytes exist only in this row, so never claim a save that
				// didn't happen: persist published=false and let the store's
				// reconcile retry it on every later pass.
				val published = uri != null && RecordingTaskStore.publishRow(this, uri)
				persist(state, status = "done", published = published)
				val sizeText = fmtBytes(state.bytes)
				val suffix = outcome.note?.let { " ($it)" } ?: ""
				notifyTask(
					state,
					if (published) {
						"Saved to Downloads/Debrify/Recordings · $sizeText$suffix"
					} else {
						"Recording finished ($sizeText) but couldn't be added to " +
							"Downloads yet — will retry"
					},
					completed = true,
				)
			}
			is Outcome.Failed -> {
				// A failed capture holds nothing worth keeping: a 0-byte (or
				// never-created) destination. Delete the pending row / file.
				uri?.let { RecordingTaskStore.deleteDestination(this, it) }
				persist(state, status = "failed", errorMessage = outcome.message)
				notifyTask(state, "Recording failed: ${outcome.message}", completed = true)
			}
		}
		states.remove(state.taskId)
		notifyThrottle.remove(state.taskId)
		RecordingRegistry.live.remove(state.taskId)
		// Covers captures that failed BEFORE the worker reached its registry
		// insert (preflight, destination creation) — their claim must not keep
		// answering with a dead id.
		RecordingRegistry.resolvePendingStart(state.url, state.taskId)
		RecordingRegistry.notifyChanged()
		if (states.isEmpty()) {
			stopIfIdle()
		} else {
			updateSummaryNotification()
		}
	}

	private fun persist(
		state: RecordingState,
		status: String,
		errorMessage: String? = null,
		published: Boolean = true,
	) {
		try {
			RecordingTaskStore.put(this, RecordingEntry(
				taskId = state.taskId,
				url = state.url,
				headers = state.headers,
				fileName = state.fileName,
				channelName = state.channelName,
				uri = state.uri?.toString(),
				status = status,
				bytes = state.bytes,
				startedAtMs = state.startedAtMs,
				endAtMs = state.endAtMs,
				errorMessage = errorMessage,
				updatedAt = System.currentTimeMillis(),
				published = published,
			))
		} catch (_: Exception) {}
	}

	// ---- Idle / locks / watchdog -------------------------------------------

	// Check-then-act on the MAIN handler, where onStartCommand also runs — a
	// worker-thread snapshot could race a brand-new START (see the download
	// service's identical comment).
	private fun stopIfIdle() {
		mainHandler.post {
			if (states.isEmpty()) {
				releaseLocks()
				stopForeground(STOP_FOREGROUND_REMOVE)
				notificationManager.cancel(SERVICE_NOTIFICATION_ID)
				try { stopSelf() } catch (_: Exception) {}
			}
		}
	}

	@Synchronized
	private fun updateLocks() {
		val anyRunning = states.values.any { it.running.get() }
		if (anyRunning) {
			if (wakeLock == null) {
				try {
					wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
						.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "debrify:recordings")
						.apply { setReferenceCounted(false); acquire() }
				} catch (_: Exception) {}
			}
			if (wifiLock == null) {
				try {
					wifiLock = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
						.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "debrify:recordings")
						.apply { setReferenceCounted(false); acquire() }
				} catch (_: Exception) {}
			}
		} else {
			releaseLocks()
		}
	}

	@Synchronized
	private fun releaseLocks() {
		try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
		try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
		wakeLock = null
		wifiLock = null
	}

	/** One timer for all captures: a stream silent past STALL_TIMEOUT_MS gets
	 *  its input closed (surfaces as a reconnect), and a capture past its end
	 *  time gets forced out of a blocked read. */
	private fun scheduleWatchdog() {
		if (watchdogScheduled) return
		watchdogScheduled = true
		mainHandler.postDelayed(object : Runnable {
			override fun run() {
				val now = System.currentTimeMillis()
				var anyRunning = false
				states.values.forEach { s ->
					if (s.running.get() && !s.stopRequested) {
						anyRunning = true
						val stalled = s.lastByteAt > 0 && now - s.lastByteAt > STALL_TIMEOUT_MS
						if (stalled || s.timeUp) {
							try { s.input?.close() } catch (_: Exception) {}
							try { s.connection?.disconnect() } catch (_: Exception) {}
						}
					}
				}
				if (anyRunning) {
					mainHandler.postDelayed(this, STALL_CHECK_INTERVAL_MS)
				} else {
					watchdogScheduled = false
				}
			}
		}, STALL_CHECK_INTERVAL_MS)
	}

	private fun freeSpaceBytes(): Long = try {
		@Suppress("DEPRECATION")
		val stat = StatFs(Environment.getExternalStorageDirectory().path)
		stat.availableBytes
	} catch (_: Exception) { -1L }

	// ---- Notifications ------------------------------------------------------

	private fun createNotificationChannel() {
		ensureNotificationChannel(this)
	}

	private fun maybeNotifyProgress(state: RecordingState, now: Long) {
		// lastNotifyAt piggybacks on the volatile via a per-state slot in the
		// notification throttle map to avoid hammering NotificationManager.
		val last = notifyThrottle[state.taskId] ?: 0L
		if (now - last < NOTIFY_THROTTLE_MS) return
		notifyThrottle[state.taskId] = now
		notifyTask(state, "Recording", completed = false)
	}
	private val notifyThrottle = ConcurrentHashMap<String, Long>()

	private fun fmtBytes(bytes: Long): String {
		val units = arrayOf("B", "KB", "MB", "GB", "TB")
		var b = bytes.toDouble()
		var idx = 0
		while (b >= 1024 && idx < units.size - 1) { b /= 1024; idx++ }
		return String.format("%.1f %s", b, units[idx])
	}

	private fun fmtElapsed(state: RecordingState): String {
		val secs = ((System.currentTimeMillis() - state.startedAtMs) / 1000).coerceAtLeast(0)
		val h = secs / 3600
		val m = (secs % 3600) / 60
		val s = secs % 60
		return if (h > 0) String.format("%d:%02d:%02d", h, m, s)
		else String.format("%d:%02d", m, s)
	}

	private fun pendingService(action: String, taskId: String): PendingIntent {
		val i = Intent(this, LiveRecordingService::class.java).apply {
			setAction(action)
			putExtra(EXTRA_TASK_ID, taskId)
		}
		val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
		return PendingIntent.getService(this, (action + taskId).hashCode(), i, flags)
	}

	private fun contentTapIntent(): PendingIntent? {
		val intent = Intent(this, com.debrify.app.MainActivity::class.java)
		return TaskStackBuilder.create(this).run {
			addNextIntentWithParentStack(intent)
			getPendingIntent(0, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
		}
	}

	private fun buildTaskNotification(
		state: RecordingState,
		title: String,
		completed: Boolean,
	): Notification {
		val details = if (completed) title
		else "● REC ${fmtElapsed(state)} · ${fmtBytes(state.bytes)}"
		val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
			.setContentTitle(state.channelName)
			.setContentText(details)
			.setSubText(if (completed) null else title)
			.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
			.setOngoing(!completed)
			.setOnlyAlertOnce(true)
			.setContentIntent(contentTapIntent())
			.setPriority(NotificationCompat.PRIORITY_LOW)
			.setGroup(GROUP_KEY_RECORDINGS)
		if (!completed) {
			builder.addAction(
				com.debrify.app.R.mipmap.ic_launcher,
				"Stop",
				pendingService(ACTION_STOP, state.taskId),
			)
		}
		return builder.build()
	}

	private fun buildSummaryNotification(): Notification {
		val recording = states.values.count { !it.finished.get() }
		val text = when {
			recording <= 0 -> "No active recordings"
			recording == 1 -> "1 recording"
			else -> "$recording recording"
		}
		return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
			.setContentTitle("Recordings")
			.setContentText(text)
			.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
			.setOngoing(true)
			.setOnlyAlertOnce(true)
			.setPriority(NotificationCompat.PRIORITY_LOW)
			.setGroup(GROUP_KEY_RECORDINGS)
			.setGroupSummary(true)
			.build()
	}

	private fun updateSummaryNotification() {
		notificationManager.notify(SERVICE_NOTIFICATION_ID, buildSummaryNotification())
	}

	private fun notifyTask(state: RecordingState, title: String, completed: Boolean) {
		notificationManager.notify(
			taskNotificationId(state.taskId),
			buildTaskNotification(state, title, completed),
		)
	}

	/** Standalone event notification (limit hit, schedule failure). */
	private fun postEventNotification(id: Int, title: String, text: String) {
		notificationManager.notify(
			id,
			NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
				.setContentTitle(title)
				.setContentText(text)
				.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
				.setOnlyAlertOnce(true)
				.setPriority(NotificationCompat.PRIORITY_DEFAULT)
				.setGroup(GROUP_KEY_RECORDINGS)
				.build(),
		)
	}

	private fun taskNotificationId(taskId: String): Int = ("rec-$taskId").hashCode()

	override fun onBind(intent: Intent?): IBinder? = null
}
