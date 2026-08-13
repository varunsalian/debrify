package com.debrify.app.download

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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.TaskStackBuilder
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.channels.FileChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class MediaStoreDownloadService : Service() {
	companion object {
		const val ACTION_START = "com.debrify.app.download.action.START"
		const val ACTION_PAUSE = "com.debrify.app.download.action.PAUSE"
		const val ACTION_RESUME = "com.debrify.app.download.action.RESUME"
		const val ACTION_CANCEL = "com.debrify.app.download.action.CANCEL"

		const val EXTRA_TASK_ID = "extra_task_id"
		const val EXTRA_URL = "extra_url"
		const val EXTRA_FILE_NAME = "extra_file_name"
		const val EXTRA_RELATIVE_SUBDIR = "extra_relative_subdir" // e.g., "Debrify" -> Downloads/Debrify
		const val EXTRA_MIME_TYPE = "extra_mime_type"
		const val EXTRA_HEADERS = "extra_headers" // HashMap<String, String>
		const val EXTRA_TREE_URI = "extra_tree_uri" // SAF custom download folder (null -> MediaStore)
		const val EXTRA_OWNER_PROFILE_ID = "extra_owner_profile_id"
		const val EXTRA_CONNECTION_RESOURCE_ID = "extra_connection_resource_id"
		const val EXTRA_PROFILE_AUTH_REVISION = "extra_profile_auth_revision"
		const val EXTRA_RESOURCE_AUTH_REVISION = "extra_resource_auth_revision"

		private const val NOTIFICATION_CHANNEL_ID = "downloads_channel_v2"
		private const val NOTIFICATION_CHANNEL_NAME = "Downloads"
		private const val SERVICE_NOTIFICATION_ID = 9000
		private const val GROUP_KEY_DOWNLOADS = "com.debrify.app.downloads.GROUP"

		private const val MAX_RETRIES = 3
		private val RETRY_BACKOFF_MS = longArrayOf(2_000, 4_000, 8_000)
		// Fresh bytes that reset the transient-retry counter: a link that keeps
		// making real progress should never exhaust its retries.
		private const val RETRY_PROGRESS_RESET_BYTES = 1L * 1024 * 1024
		private const val STALL_TIMEOUT_MS = 60_000L
		private const val STALL_CHECK_INTERVAL_MS = 10_000L
	}

	private class DownloadState(
		val taskId: String,
		@Volatile var url: String,
		@Volatile var fileName: String,
		val subDir: String,
		val mimeType: String,
		val headers: HashMap<String, String>,
		val treeUri: String? = null,
		val ownerProfileId: String = "legacy-admin-v1",
		val connectionResourceId: String? = null,
		val profileAuthorizationRevision: Long = 1L,
		val resourceAuthorizationRevision: Long? = null,
		var uri: Uri? = null,
		@Volatile var downloaded: Long = 0L,
		@Volatile var total: Long = -1L,
		@Volatile var etag: String? = null,
		@Volatile var lastModified: String? = null,
	) {
		@Volatile var paused: Boolean = false
		@Volatile var canceled: Boolean = false
		@Volatile var connection: HttpURLConnection? = null
		@Volatile var input: InputStream? = null
		// Timestamp of the last byte read, watched by the stall watchdog.
		@Volatile var lastByteAt: Long = 0L
		// Atomic claim so two threads can never both enter the download loop
		// for the same task (START/RESUME race).
		val running: AtomicBoolean = AtomicBoolean(false)
		// Terminal-transition guard: exactly one of complete/failed/canceled may
		// ever be applied to a task, no matter which thread gets there first.
		val finished: AtomicBoolean = AtomicBoolean(false)

		val isSaf: Boolean get() = treeUri != null
	}

	// The single terminal outcome of a task. Pause is NOT terminal — a paused
	// task keeps its (persisted) state and can resume.
	private sealed class Outcome {
		object Complete : Outcome()
		class Failed(
			val message: String,
			val httpCode: Int? = null,
			val retryable: Boolean = false,
		) : Outcome()

		object Canceled : Outcome()
	}

	private class HttpCodeException(val code: Int, url: String) : IOException("HTTP $code for $url")

	private lateinit var notificationManager: NotificationManager
	private val states = ConcurrentHashMap<String, DownloadState>()
	private val mainHandler = Handler(Looper.getMainLooper())
	private var wakeLock: PowerManager.WakeLock? = null
	private var wifiLock: WifiManager.WifiLock? = null
	@Volatile private var watchdogScheduled = false

	override fun onCreate() {
		super.onCreate()
		notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		createNotificationChannel()
	}

	override fun onDestroy() {
		releaseLocks()
		super.onDestroy()
	}

	override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
		// Commands from the app arrive via startForegroundService(); on
		// Android 8+ the app is killed (ForegroundServiceDidNotStartInTimeException)
		// if ANY such path returns without startForeground(). Claim foreground
		// FIRST, unconditionally — no-work paths release it again via stopIfIdle().
		// Commands from notification action buttons arrive via plain
		// PendingIntent.getService with NO foreground obligation, but on
		// Android 12+ startForeground() itself can throw
		// (ForegroundServiceStartNotAllowedException) if the tap exemption has
		// lapsed — in that case just continue handling the command un-promoted.
		try {
			startForeground(SERVICE_NOTIFICATION_ID, buildSummaryNotification())
		} catch (_: Exception) {
			// No obligation exists on the plain-startService path; proceed.
		}
		when (intent?.action) {
			ACTION_START -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: System.currentTimeMillis().toString()
				val url = intent.getStringExtra(EXTRA_URL)
				if (url == null) {
					stopIfIdle()
					return START_NOT_STICKY
				}
				val existing = states[taskId]
				if (existing != null && !existing.finished.get()) {
					// Duplicate START for a live task: never overwrite the state
					// or spawn a second thread over the same destination. A new
					// URL (refreshed debrid link) is still adopted so the next
					// attempt/resume uses it.
					existing.url = url
					if (existing.running.get()) {
						updateSummaryNotification()
					} else {
						// Known but idle (e.g. paused): treat the START as a resume.
						existing.paused = false
						spawnWorker(existing)
						updateSummaryNotification()
					}
					return START_NOT_STICKY
				}
				@Suppress("UNCHECKED_CAST")
				val headers = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String> ?: hashMapOf()

				// Start-or-adopt: if a persisted entry exists (paused/failed
				// task, or the process died mid-download), reconstruct it and
				// continue from the bytes on disk — with the intent's URL, which
				// may be a freshly refreshed link for the same content.
				val persisted = DownloadTaskStore.get(this, taskId)
				val state = if (persisted != null) {
					stateFromEntry(persisted, urlOverride = url, headersOverride = headers.takeIf { it.isNotEmpty() })
				} else {
					DownloadState(
						taskId = taskId,
						url = url,
						fileName = intent.getStringExtra(EXTRA_FILE_NAME) ?: "download",
						subDir = intent.getStringExtra(EXTRA_RELATIVE_SUBDIR) ?: "Debrify",
						mimeType = intent.getStringExtra(EXTRA_MIME_TYPE) ?: "application/octet-stream",
						headers = headers,
						treeUri = intent.getStringExtra(EXTRA_TREE_URI),
						ownerProfileId = intent.getStringExtra(EXTRA_OWNER_PROFILE_ID)
							?: "legacy-admin-v1",
						connectionResourceId = intent.getStringExtra(EXTRA_CONNECTION_RESOURCE_ID),
						profileAuthorizationRevision = intent.getLongExtra(EXTRA_PROFILE_AUTH_REVISION, 1L),
						resourceAuthorizationRevision = if (intent.hasExtra(EXTRA_RESOURCE_AUTH_REVISION))
							intent.getLongExtra(EXTRA_RESOURCE_AUTH_REVISION, 1L) else null,
					)
				}
				states[taskId] = state
				updateSummaryNotification()
				notifyTask(state, "Preparing...", indeterminate = true, completed = false)
				spawnWorker(state)
			}
			ACTION_PAUSE -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID)
				val s = if (taskId != null) states[taskId] else null
				if (s != null && !s.finished.get()) {
					s.paused = true
					// Force the worker out of a blocking connect()/read(). The
					// connection is assigned before connect(), so a pause during
					// the connect phase takes effect immediately too.
					try { s.connection?.disconnect() } catch (_: Exception) {}
					try { s.input?.close() } catch (_: Exception) {}
					if (!s.running.get()) {
						// No worker to unwind (was idle): persist + settle here.
						persistState(s, status = "paused")
						notifyTask(s, "Paused", indeterminate = false, completed = false)
						updateSummaryNotification()
						stopIfNoneRunning()
					} else {
						notifyTask(s, "Paused", indeterminate = false, completed = false)
						updateSummaryNotification()
					}
					ChannelBridge.emit(mapOf(
						"type" to "paused",
						"taskId" to taskId!!,
						"url" to s.url,
						"fileName" to s.fileName,
						"subDir" to s.subDir,
					))
				} else if (s == null && taskId != null) {
					// Unknown in memory but possibly persisted as running from a
					// killed process: settle the stored status and confirm to
					// Dart, or the UI row stays "running" until the next
					// app-restart reconcile.
					DownloadTaskStore.get(this, taskId)?.let { entry ->
						if (entry.status == "running") {
							DownloadTaskStore.put(this, entry.copy(status = "paused", updatedAt = System.currentTimeMillis()))
						}
						ChannelBridge.emit(mapOf(
							"type" to "paused",
							"taskId" to taskId,
							"url" to entry.url,
							"fileName" to entry.fileName,
							"subDir" to entry.subDir,
						))
					}
				}
				// Don't linger as an idle foreground service.
				stopIfIdle()
			}
			ACTION_RESUME -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID)
				val s = if (taskId != null) states[taskId] else null
				if (s == null) {
					// In-memory state is gone (all-paused shutdown, or the
					// process was killed). Reconstruct from the persisted entry
					// and continue from the bytes on disk.
					val entry = if (taskId != null) DownloadTaskStore.get(this, taskId) else null
					if (entry != null) {
						val revived = stateFromEntry(entry, urlOverride = null, headersOverride = null)
						states[taskId!!] = revived
						updateSummaryNotification()
						spawnWorker(revived)
						ChannelBridge.emit(mapOf(
							"type" to "resumed",
							"taskId" to taskId,
							"url" to revived.url,
							"fileName" to revived.fileName,
							"subDir" to revived.subDir,
						))
					} else {
						if (taskId != null) {
							ChannelBridge.emit(mapOf(
								"type" to "error",
								"taskId" to taskId,
								"message" to "download state lost; start the download again",
							))
						}
						stopIfIdle()
					}
				} else if (!s.running.get() && !s.finished.get()) {
					s.paused = false
					spawnWorker(s)
					updateSummaryNotification()
					ChannelBridge.emit(mapOf(
						"type" to "resumed",
						"taskId" to taskId!!,
						"url" to s.url,
						"fileName" to s.fileName,
						"subDir" to s.subDir,
					))
				}
				// s.running: already downloading — foreground is legitimately
				// held; nothing else to do.
			}
			ACTION_CANCEL -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID)
				val s = if (taskId != null) states[taskId] else null
				if (s != null && !s.finished.get()) {
					s.canceled = true
					try { s.connection?.disconnect() } catch (_: Exception) {}
					try { s.input?.close() } catch (_: Exception) {}
					if (!s.running.get()) {
						// No worker thread owns the destination: safe to delete
						// the row and finish inline (paused/idle task).
						finishTask(s, Outcome.Canceled)
					}
					// else: the worker notices `canceled`, closes its file
					// descriptors first, and then deletes the row + finishes.
					// Deleting here would race the still-open output fd.
				} else if (s == null && taskId != null) {
					// Cancel of a task known only from persistence: delete the
					// partial file and the entry, and confirm to Dart.
					DownloadTaskStore.get(this, taskId)?.let { entry ->
						entry.uri?.let { deleteDestination(Uri.parse(it), entry.treeUri != null) }
						DownloadTaskStore.remove(this, taskId)
						notificationManager.cancel(taskNotificationId(taskId))
						ChannelBridge.emit(mapOf(
							"type" to "canceled",
							"taskId" to taskId,
							"url" to entry.url,
							"fileName" to entry.fileName,
							"subDir" to entry.subDir,
						))
					}
				}
				if (states.isEmpty()) {
					stopIfIdle()
				} else {
					updateSummaryNotification()
				}
			}
			else -> stopIfIdle()
		}
		return START_NOT_STICKY
	}

	private fun stateFromEntry(entry: TaskEntry, urlOverride: String?, headersOverride: HashMap<String, String>?): DownloadState {
		return DownloadState(
			taskId = entry.taskId,
			url = urlOverride ?: entry.url,
			fileName = entry.fileName,
			subDir = entry.subDir,
			mimeType = entry.mimeType,
			headers = headersOverride ?: entry.headers,
			treeUri = entry.treeUri,
			ownerProfileId = entry.ownerProfileId,
			connectionResourceId = entry.connectionResourceId,
			profileAuthorizationRevision = entry.profileAuthorizationRevision,
			resourceAuthorizationRevision = entry.resourceAuthorizationRevision,
			uri = entry.uri?.let { Uri.parse(it) },
			total = entry.total,
			etag = entry.etag,
			lastModified = entry.lastModified,
		)
	}

	private fun persistState(state: DownloadState, status: String, errorMessage: String? = null) {
		try {
			DownloadTaskStore.put(this, TaskEntry(
				taskId = state.taskId,
				url = state.url,
				fileName = state.fileName,
				subDir = state.subDir,
				mimeType = state.mimeType,
				headers = state.headers,
				uri = state.uri?.toString(),
				destType = if (state.isSaf) "saf" else "mediastore",
				treeUri = state.treeUri,
				etag = state.etag,
				lastModified = state.lastModified,
				total = state.total,
				status = status,
				errorMessage = errorMessage,
				updatedAt = System.currentTimeMillis(),
				ownerProfileId = state.ownerProfileId,
				connectionResourceId = state.connectionResourceId,
				profileAuthorizationRevision = state.profileAuthorizationRevision,
				resourceAuthorizationRevision = state.resourceAuthorizationRevision,
			))
		} catch (_: Exception) {}
	}

	private fun spawnWorker(state: DownloadState) {
		if (!jobAuthorizationValid(state)) {
			persistState(state, status = "failed", errorMessage = "profile authorization changed")
			states.remove(state.taskId)
			DownloadRegistry.live.remove(state.taskId)
			notifyTask(state, "Download stopped — profile access changed", indeterminate = false, completed = true)
			stopIfIdle()
			return
		}
		Thread {
			try {
				downloadLoop(state)
			} catch (t: Throwable) {
				// Crash net: downloadLoop handles its own errors; anything that
				// escapes still must not leave a zombie state behind.
				finishTask(state, Outcome.Failed(t.message ?: "crash"))
			}
		}.start()
	}

	private fun jobAuthorizationValid(state: DownloadState): Boolean =
		com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
			this,
			state.ownerProfileId,
			state.profileAuthorizationRevision,
			if (state.taskId.startsWith("update-")) "appUpdates" else "downloads",
			state.connectionResourceId,
			state.resourceAuthorizationRevision,
		)

	// The ONLY place a task may reach a terminal state. Clears/deletes the
	// destination as appropriate, updates the persistent store, emits exactly
	// one terminal event, removes the state and releases the foreground claim
	// when nothing is left.
	private fun finishTask(state: DownloadState, outcome: Outcome) {
		if (!state.finished.compareAndSet(false, true)) return
		when (outcome) {
			is Outcome.Complete -> {
				val uri = state.uri
				if (uri != null && !state.isSaf && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
					try {
						val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
						contentResolver.update(uri, done, null, null)
					} catch (_: Exception) {}
				}
				// Retain a bounded terminal hand-off record until Flutter reconciles
				// ownership/artifact ledgers after a background-only completion.
				persistState(state, status = "done")
				notifyTask(state, "Download complete", indeterminate = false, completed = true)
				val reportedTotal = if (state.total > 0L) state.total else state.downloaded
				ChannelBridge.emit(mapOf(
					"type" to "complete",
					"taskId" to state.taskId,
					"url" to state.url,
					"bytes" to state.downloaded,
					"total" to reportedTotal,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"ownerProfileId" to state.ownerProfileId,
					"contentUri" to (uri?.toString() ?: ""),
					"mimeType" to state.mimeType,
				))
				notificationManager.cancel(taskNotificationId(state.taskId))
			}
			is Outcome.Failed -> {
				// Keep the partial bytes and the persisted entry (status=failed)
				// so a later resume/restart can finish the file. Only cancel
				// deletes it. The notification must NOT be ongoing — a failed
				// task may never get another service command to clean it up.
				persistState(state, status = "failed", errorMessage = outcome.message)
				notifyTask(state, "Download failed", indeterminate = false, completed = true)
				ChannelBridge.emit(mapOf(
					"type" to "error",
					"taskId" to state.taskId,
					"url" to state.url,
					"message" to outcome.message,
					"httpCode" to outcome.httpCode,
					"bytes" to state.downloaded,
					"total" to state.total,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"ownerProfileId" to state.ownerProfileId,
				))
			}
			is Outcome.Canceled -> {
				state.uri?.let { deleteDestination(it, state.isSaf) }
				DownloadTaskStore.remove(this, state.taskId)
				ChannelBridge.emit(mapOf(
					"type" to "canceled",
					"taskId" to state.taskId,
					"url" to state.url,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
				))
				notificationManager.cancel(taskNotificationId(state.taskId))
			}
		}
		states.remove(state.taskId)
		DownloadRegistry.live.remove(state.taskId)
		if (states.isEmpty()) {
			stopIfIdle()
		} else {
			updateSummaryNotification()
			stopIfNoneRunning()
		}
	}

	private fun deleteDestination(uri: Uri, isSaf: Boolean) {
		try {
			if (isSaf) {
				DocumentsContract.deleteDocument(contentResolver, uri)
			} else {
				contentResolver.delete(uri, null, null)
			}
		} catch (_: Exception) {}
	}

	// With no tracked downloads there is nothing to be foreground for —
	// release the foreground claim taken at the top of onStartCommand and
	// stop, so the OS timeout can never fire on a no-work command.
	//
	// Both stop paths run their check-then-act on the MAIN handler, where
	// onStartCommand also runs: a worker-thread snapshot of `states` could
	// otherwise race an ACTION_START inserting a brand-new task and clear it
	// (or stop foreground under a live download).
	private fun stopIfIdle() {
		mainHandler.post {
			if (states.isEmpty()) {
				releaseLocks()
				stopForeground(STOP_FOREGROUND_REMOVE)
				notificationManager.cancel(SERVICE_NOTIFICATION_ID)
				stopSelfSafely()
			}
		}
	}

	// Every remaining task is paused: their entries are persisted, their
	// notifications are non-ongoing with working Resume/Cancel actions, and a
	// later RESUME reconstructs from the store — so there is no reason to keep
	// a foreground service (and its permanent notification) alive.
	private fun stopIfNoneRunning() {
		mainHandler.post {
			val values = states.values.toList()
			if (values.isEmpty()) {
				releaseLocks()
				stopForeground(STOP_FOREGROUND_REMOVE)
				notificationManager.cancel(SERVICE_NOTIFICATION_ID)
				stopSelfSafely()
				return@post
			}
			if (values.any { it.running.get() }) return@post
			if (values.all { it.paused && !it.canceled }) {
				values.forEach { persistState(it, status = "paused") }
				states.clear()
				releaseLocks()
				stopForeground(STOP_FOREGROUND_REMOVE)
				notificationManager.cancel(SERVICE_NOTIFICATION_ID)
				stopSelfSafely()
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
						.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "debrify:downloads")
						.apply { setReferenceCounted(false); acquire() }
				} catch (_: Exception) {}
			}
			if (wifiLock == null) {
				try {
					wifiLock = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
						.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "debrify:downloads")
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

	// One lightweight timer for all tasks: a download that has produced no
	// bytes for STALL_TIMEOUT_MS gets its stream closed, which surfaces as a
	// retryable IOException in the worker — reconnect + Range instead of
	// hanging forever (readTimeout is deliberately 0: a hard read timeout
	// kills legitimately slow large downloads).
	private fun scheduleWatchdog() {
		if (watchdogScheduled) return
		watchdogScheduled = true
		mainHandler.postDelayed(object : Runnable {
			override fun run() {
				val now = System.currentTimeMillis()
				var anyRunning = false
				states.values.forEach { s ->
					if (s.running.get() && !s.paused && !s.canceled) {
						anyRunning = true
						if (!jobAuthorizationValid(s)) {
							s.canceled = true
							try { s.input?.close() } catch (_: Exception) {}
							try { s.connection?.disconnect() } catch (_: Exception) {}
							return@forEach
						}
						if (s.lastByteAt > 0 && now - s.lastByteAt > STALL_TIMEOUT_MS) {
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

	// Returns the file's current size, or -1 when it cannot be read (which is
	// different from an empty/vanished file at 0: a 0 restarts the download,
	// while -1 means the destination itself is inaccessible).
	private fun existingSize(uri: Uri): Long {
		return try {
			contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
				FileInputStream(pfd.fileDescriptor).use { fis -> fis.channel.size() }
			} ?: -1L
		} catch (_: Exception) { -1L }
	}

	private fun parseContentRange(header: String?): Triple<Long, Long, Long>? {
		// Example: bytes 100-999/1234
		if (header.isNullOrEmpty()) return null
		return try {
			val parts = header.split(" ")
			if (parts.size < 2) return null
			val rangeAndTotal = parts[1].split("/")
			if (rangeAndTotal.size != 2) return null
			val range = rangeAndTotal[0]
			val totalStr = rangeAndTotal[1]
			val startEnd = range.split("-")
			val start = startEnd[0].toLong()
			val end = startEnd[1].toLong()
			val total = if (totalStr == "*") -1L else totalStr.toLong()
			Triple(start, end, total)
		} catch (_: Exception) { null }
	}

	// Worker entry: claims the task, runs attempts with transient-retry +
	// backoff, then applies exactly one outcome (or settles as paused).
	private fun downloadLoop(state: DownloadState) {
		// Atomic claim: exactly one worker thread per task.
		if (!state.running.compareAndSet(false, true)) return
		updateLocks()
		scheduleWatchdog()
		var outcome: Outcome?
		var attempt = 0
		var bytesAtLastFailure = state.downloaded
		while (true) {
			outcome = runAttempt(state)
			val failed = outcome as? Outcome.Failed
			if (failed != null && failed.retryable && !state.paused && !state.canceled) {
				// Real progress since the last failure resets the budget.
				if (state.downloaded >= bytesAtLastFailure + RETRY_PROGRESS_RESET_BYTES) attempt = 0
				bytesAtLastFailure = state.downloaded
				if (attempt < MAX_RETRIES) {
					val delay = RETRY_BACKOFF_MS[attempt.coerceAtMost(RETRY_BACKOFF_MS.size - 1)]
					attempt++
					notifyTask(state, "Retrying ($attempt/$MAX_RETRIES)...", indeterminate = true, completed = false)
					// Interruptible backoff: pause/cancel must not wait it out.
					val sleepUntil = System.currentTimeMillis() + delay
					while (System.currentTimeMillis() < sleepUntil && !state.paused && !state.canceled) {
						try { Thread.sleep(250) } catch (_: InterruptedException) { break }
					}
					if (state.paused) { outcome = null; break }
					if (state.canceled) { outcome = Outcome.Canceled; break }
					continue
				}
			}
			break
		}
		state.running.set(false)
		updateLocks()
		// A cancel that raced the tail of the last attempt must still win over
		// pause/failure — but never over a genuine completion.
		val finalOutcome = if (state.canceled && outcome !is Outcome.Complete) Outcome.Canceled else outcome
		if (finalOutcome != null) {
			finishTask(state, finalOutcome)
		} else if (!state.finished.get()) {
			// Paused: persist so the task survives service/process death, then
			// let the service exit if nothing else is running.
			DownloadRegistry.live.remove(state.taskId)
			persistState(state, status = "paused")
			notifyTask(state, "Paused", indeterminate = false, completed = false)
			updateSummaryNotification()
			stopIfNoneRunning()
		}
	}

	// One connect+stream attempt. Never throws; returns the outcome, or null
	// when the attempt ended because the task was paused.
	private fun runAttempt(state: DownloadState): Outcome? {
		var uri: Uri? = state.uri
		var connection: HttpURLConnection? = null
		var input: InputStream? = null
		var out: BufferedOutputStream? = null
		var outPfd: ParcelFileDescriptor? = null
		var outChannel: FileChannel? = null
		var outcome: Outcome? = null
		var settled = false
		try {
			if (!jobAuthorizationValid(state)) return Outcome.Canceled
			// Fresh liveness stamp for THIS attempt: with readTimeout=0 the
			// stall watchdog is the only dead-stream detector, so it must also
			// cover the connect/header phase — and a stale stamp from the
			// previous attempt must not let the watchdog kill the reconnect.
			state.lastByteAt = System.currentTimeMillis()
			if (state.canceled) throw InterruptedException("canceled")
			var justCreated = false
			if (uri == null) {
				uri = createDestination(state)
				justCreated = true
				state.uri = uri
				persistState(state, status = "running")
					ChannelBridge.emit(mapOf("type" to "started", "taskId" to state.taskId, "url" to state.url, "fileName" to state.fileName, "subDir" to state.subDir))
			}

			// Always confirm bytes already written on disk — the on-disk size is
			// the resume offset's source of truth. An unreadable EXISTING
			// destination is a hard error (resuming on a stale in-memory offset
			// would write a sparse hole into the file) — but a just-inserted
			// MediaStore pending row may have no backing file until the first
			// write on some OEMs (ColorOS/OxygenOS), so a fresh destination
			// that can't be read yet simply starts at 0.
			val onDisk = existingSize(uri)
			if (onDisk < 0L && !justCreated) {
				val reason = if (state.isSaf && !hasTreeGrant(state.treeUri)) "saf_grant_lost" else "destination missing or unreadable"
				return Outcome.Failed(reason)
			}
			state.downloaded = if (onDisk >= 0L) onDisk else 0L

			val url = URL(state.url)
			connection = (url.openConnection() as HttpURLConnection).apply {
				instanceFollowRedirects = true
				connectTimeout = 60_000
				readTimeout = 0 // stall watchdog handles dead streams
				doInput = true
				state.headers.forEach { (k, v) -> setRequestProperty(k, v) }
				if (state.downloaded > 0L) {
					setRequestProperty("Range", "bytes=${state.downloaded}-")
					// Strong ETag preferred; weak ETags ("W/...") are not valid
					// range validators. Fall back to Last-Modified.
					val validator = state.etag?.takeIf { !it.startsWith("W/") } ?: state.lastModified
					validator?.let { setRequestProperty("If-Range", it) }
				}
			}
			// Assign BEFORE connect() so pause/cancel can disconnect a
			// connection that is still being established.
			state.connection = connection
			if (state.canceled) throw InterruptedException("canceled")
			if (state.paused) return null
			connection.connect()
			if (state.canceled) throw InterruptedException("canceled")
			if (state.paused) return null

			val resp = connection.responseCode
			// Handle resume edge cases before opening output stream
			if (state.downloaded > 0L && resp == HttpURLConnection.HTTP_OK) {
				// Server ignored Range; restart from 0. The unified output-open
				// below truncates the file to `downloaded` (0), discarding the
				// stale partial bytes.
				state.downloaded = 0L
			} else if (state.downloaded > 0L && resp == 416) {
				// 416: our on-disk size is at/past the end; the file is already
				// fully downloaded. Treat as complete.
				settled = true
				return Outcome.Complete
			} else if (resp != HttpURLConnection.HTTP_OK && resp != HttpURLConnection.HTTP_PARTIAL) {
				// Only a full (200) or partial (206) body is a download; 204/205
				// and friends must not be recorded as phantom completions.
				throw HttpCodeException(resp, state.url)
			}

			val resumedByServer = state.downloaded > 0L && resp == HttpURLConnection.HTTP_PARTIAL
			// Parse Content-Range if present to validate start and total
			if (resumedByServer) {
				parseContentRange(connection.getHeaderField("Content-Range"))?.let { (start, _, total) ->
					if (total > 0) state.total = total
					if (start != state.downloaded) {
						when {
							start == 0L -> {
								// Server explicitly restarts from 0; drop the partial.
								state.downloaded = 0L
							}
							start < state.downloaded -> {
								// Server rewinds behind our offset: append from
								// `start`. The output-open truncates to `start`
								// first so no stale tail bytes survive.
								state.downloaded = start
							}
							else -> {
								// Stream begins beyond our bytes — writing it
								// would leave a hole. Not usable.
								throw IllegalStateException("Server returned infeasible range start=$start, have=${state.downloaded}")
							}
						}
					}
				}
			}

			// Compute total length if not set earlier
			if (state.total <= 0L) {
				val reportedLength = connection.contentLengthLong
				state.total = if (resumedByServer && reportedLength >= 0L) state.downloaded + reportedLength else reportedLength.coerceAtLeast(0L)
			}
			// Only update validators if present
			connection.getHeaderField("ETag")?.let { state.etag = it }
			connection.getHeaderField("Last-Modified")?.let { state.lastModified = it }
			persistState(state, status = "running")

			input = BufferedInputStream(connection.inputStream)
			state.input = input

			// Unified output: a single seekable "rw" descriptor for fresh starts
			// and resumes alike. Truncating to `downloaded` handles every case —
			// fresh (0), clean resume (no-op), server rewind (drops stale tail),
			// range-ignored restart (0).
			val pfd = contentResolver.openFileDescriptor(uri, "rw")
				?: throw IOException("Cannot open destination for writing")
			outPfd = pfd
			val fos = FileOutputStream(pfd.fileDescriptor)
			outChannel = fos.channel
			outChannel.truncate(state.downloaded)
			outChannel.position(state.downloaded)
			out = BufferedOutputStream(fos)

			val registryLive = DownloadRegistry.live.getOrPut(state.taskId) {
				DownloadRegistry.Live(state.downloaded, state.total)
			}
			registryLive.bytes = state.downloaded
			registryLive.total = state.total

			val buffer = ByteArray(256 * 1024)
			var bytesRead: Int
			var eof = false
			var lastUpdate = System.currentTimeMillis()
			state.lastByteAt = System.currentTimeMillis()
			notifyTask(state, "Downloading", indeterminate = state.total <= 0, completed = false)
			updateSummaryNotification()
				if (state.downloaded == 0L) {
					ChannelBridge.emit(mapOf(
						"type" to "progress",
						"taskId" to state.taskId,
						"url" to state.url,
					"bytes" to state.downloaded,
					"total" to state.total,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"ownerProfileId" to state.ownerProfileId,
				))
			}

			while (true) {
				if (state.canceled) throw InterruptedException("canceled")
				if (state.paused) break
				bytesRead = input.read(buffer)
				if (bytesRead == -1) { eof = true; break }
				out.write(buffer, 0, bytesRead)
				state.downloaded += bytesRead
				val now = System.currentTimeMillis()
				state.lastByteAt = now
				if (now - lastUpdate > 500) {
					registryLive.bytes = state.downloaded
					registryLive.total = state.total
					notifyTask(state, "Downloading", indeterminate = state.total <= 0, completed = false)
					ChannelBridge.emit(mapOf(
							"type" to "progress",
							"taskId" to state.taskId,
							"url" to state.url,
						"bytes" to state.downloaded,
						"total" to state.total,
						"fileName" to state.fileName,
						"subDir" to state.subDir,
						"ownerProfileId" to state.ownerProfileId,
					))
					lastUpdate = now
				}
			}
			// Make the bytes durable before declaring any state: flush the
			// buffer, then fsync the descriptor so a process kill right after a
			// pause/complete cannot lose the tail.
			out.flush()
			try { pfd.fileDescriptor.sync() } catch (_: Exception) {}

			outcome = if (eof) {
				if (state.total > 0L && state.downloaded != state.total) {
					// Stream ended early (truncated body). Keep the partial for
					// resume/retry, but do NOT report a phantom completion.
					Outcome.Failed("incomplete: got ${state.downloaded} of ${state.total} bytes", retryable = true)
				} else {
					Outcome.Complete
				}
			} else {
				null // paused
			}
			settled = true
		} catch (e: Exception) {
			if (!settled && outcome == null) {
				outcome = when {
					state.canceled -> Outcome.Canceled
					state.paused -> null // pause forced the stream closed; not an error
					e is HttpCodeException -> Outcome.Failed(
						e.message ?: "http error",
						httpCode = e.code,
						// 4xx means the URL itself is dead (expired debrid link,
						// gone file) — retrying the same URL is pointless; Dart
						// refreshes the link instead. 408/429/5xx are transient.
						retryable = e.code == 408 || e.code == 429 || e.code >= 500,
					)
					e is IOException -> Outcome.Failed(e.message ?: "network error", retryable = true)
					else -> Outcome.Failed(e.message ?: "unknown error")
				}
			}
		} finally {
			// Close EVERYTHING before the outcome is applied — cancel deletes
			// the destination and must never race a still-open output fd.
			try { out?.flush() } catch (_: Exception) {}
			try { outPfd?.fileDescriptor?.sync() } catch (_: Exception) {}
			try { out?.close() } catch (_: Exception) {}
			try { outChannel?.close() } catch (_: Exception) {}
			try { outPfd?.close() } catch (_: Exception) {}
			try { input?.close() } catch (_: Exception) {}
			try { connection?.disconnect() } catch (_: Exception) {}
			state.input = null
			state.connection = null
		}
		return outcome
	}

	// ---- Destination creation ------------------------------------------------

	private fun createDestination(state: DownloadState): Uri {
		return if (state.isSaf) createViaSaf(state) else createViaMediaStore(state)
	}

	private fun createViaMediaStore(state: DownloadState): Uri {
		val values = ContentValues().apply {
			put(MediaStore.Downloads.DISPLAY_NAME, state.fileName)
			put(MediaStore.Downloads.MIME_TYPE, state.mimeType)
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				put(MediaStore.Downloads.RELATIVE_PATH, "Download/${state.subDir}")
				put(MediaStore.Downloads.IS_PENDING, 1)
			}
		}
		return contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
			?: throw IOException("no destination")
	}

	private fun hasTreeGrant(treeUri: String?): Boolean {
		if (treeUri == null) return false
		return try {
			contentResolver.persistedUriPermissions.any {
				it.uri.toString() == treeUri && it.isWritePermission
			}
		} catch (_: Exception) { false }
	}

	private fun createViaSaf(state: DownloadState): Uri {
		val treeUriStr = state.treeUri ?: throw IOException("saf destination without tree uri")
		if (!hasTreeGrant(treeUriStr)) throw IOException("saf_grant_lost")
		val tree = Uri.parse(treeUriStr)
		var parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
		// The MediaStore path roots everything under Download/Debrify/...; in a
		// user-chosen folder the "Debrify" wrapper is redundant — they already
		// picked where downloads go. Keep any torrent/subfolder structure.
		val segments = state.subDir.split('/').filter { it.isNotBlank() }
			.let { if (it.firstOrNull() == "Debrify") it.drop(1) else it }
		for (segment in segments) {
			parent = findOrCreateDir(parent, segment)
		}
		val doc = DocumentsContract.createDocument(contentResolver, parent, state.mimeType, state.fileName)
			?: throw IOException("saf_create_failed")
		// SAF de-duplicates names ("file (1).mkv") — reflect the real name.
		queryDisplayName(doc)?.let { actual ->
			if (actual.isNotEmpty() && actual != state.fileName) state.fileName = actual
		}
		return doc
	}

	private fun findOrCreateDir(parent: Uri, name: String): Uri {
		try {
			val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
				parent, DocumentsContract.getDocumentId(parent)
			)
			contentResolver.query(
				childrenUri,
				arrayOf(
					DocumentsContract.Document.COLUMN_DOCUMENT_ID,
					DocumentsContract.Document.COLUMN_DISPLAY_NAME,
					DocumentsContract.Document.COLUMN_MIME_TYPE,
				),
				null, null, null,
			)?.use { c ->
				while (c.moveToNext()) {
					if (c.getString(1) == name && c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
						return DocumentsContract.buildDocumentUriUsingTree(parent, c.getString(0))
					}
				}
			}
		} catch (_: Exception) {
			// fall through to create
		}
		return DocumentsContract.createDocument(
			contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name
		) ?: throw IOException("saf_mkdir_failed: $name")
	}

	private fun queryDisplayName(doc: Uri): String? {
		return try {
			contentResolver.query(
				doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null
			)?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
		} catch (_: Exception) { null }
	}

	// ---- Notifications -------------------------------------------------------

	private fun stopSelfSafely() {
		try { stopSelf() } catch (_: Exception) {}
	}

	private fun createNotificationChannel() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val channel = NotificationChannel(
				NOTIFICATION_CHANNEL_ID,
				NOTIFICATION_CHANNEL_NAME,
				NotificationManager.IMPORTANCE_DEFAULT
			)
			notificationManager.createNotificationChannel(channel)
		}
	}

	private fun fmtBytes(bytes: Long): String {
		val units = arrayOf("B", "KB", "MB", "GB", "TB")
		var b = bytes.toDouble()
		var idx = 0
		while (b >= 1024 && idx < units.size - 1) { b /= 1024; idx++ }
		return String.format("%.1f %s", b, units[idx])
	}

	private fun pendingService(action: String, taskId: String): PendingIntent {
		val i = Intent(this, MediaStoreDownloadService::class.java).apply {
			setAction(action)
			putExtra(EXTRA_TASK_ID, taskId)
		}
		val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
		return PendingIntent.getService(this, (action + taskId).hashCode(), i, flags)
	}

	private fun buildTaskNotification(state: DownloadState, title: String, indeterminate: Boolean, completed: Boolean): Notification {
		val total = state.total
		val downloaded = state.downloaded
		val pct = if (total > 0) ((downloaded * 100) / total).toInt().coerceIn(0, 100) else 0
		val details = if (total > 0) "${fmtBytes(downloaded)} / ${fmtBytes(total)} ($pct%)" else fmtBytes(downloaded)

		val intent = Intent(this, com.debrify.app.MainActivity::class.java)
		val pendingIntent: PendingIntent? = TaskStackBuilder.create(this).run {
			addNextIntentWithParentStack(intent)
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
				getPendingIntent(0, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
			} else {
				getPendingIntent(0, PendingIntent.FLAG_UPDATE_CURRENT)
			}
		}

		val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
			.setContentTitle(state.fileName)
			.setContentText(details)
			.setSubText(title)
			.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
			// Paused tasks must survive the service stopping (all-paused
			// shutdown), so their notifications cannot be ongoing.
			.setOngoing(!completed && !state.paused)
			.setOnlyAlertOnce(true)
			.setContentIntent(pendingIntent)
			.setPriority(NotificationCompat.PRIORITY_LOW)
			.setStyle(NotificationCompat.BigTextStyle().bigText(details).setSummaryText(title))
			.setGroup(GROUP_KEY_DOWNLOADS)

		if (indeterminate) {
			builder.setProgress(0, 0, true)
		} else if (total > 0) {
			builder.setProgress(100, pct, false)
		}

		if (!completed) {
			if (state.paused) {
				builder.addAction(com.debrify.app.R.mipmap.ic_launcher, "Resume", pendingService(ACTION_RESUME, state.taskId))
			} else {
				builder.addAction(com.debrify.app.R.mipmap.ic_launcher, "Pause", pendingService(ACTION_PAUSE, state.taskId))
			}
			builder.addAction(com.debrify.app.R.mipmap.ic_launcher, "Cancel", pendingService(ACTION_CANCEL, state.taskId))
		}

		return builder.build()
	}

	private fun buildSummaryNotification(): Notification {
		val active = states.values.count { !it.canceled }
		val paused = states.values.count { it.paused && !it.canceled }
		val running = active - paused
		val summaryText = when {
			active <= 0 -> "No active downloads"
			paused > 0 && running > 0 -> "$running running, $paused paused"
			paused > 0 -> "$paused paused"
			else -> "$running running"
		}
		return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
			.setContentTitle("Downloads")
			.setContentText(summaryText)
			.setSmallIcon(com.debrify.app.R.mipmap.ic_launcher)
			.setOngoing(true)
			.setOnlyAlertOnce(true)
			.setPriority(NotificationCompat.PRIORITY_LOW)
			.setGroup(GROUP_KEY_DOWNLOADS)
			.setGroupSummary(true)
			.build()
	}

	private fun updateSummaryNotification() {
		notificationManager.notify(SERVICE_NOTIFICATION_ID, buildSummaryNotification())
	}

	private fun notifyTask(state: DownloadState, title: String, indeterminate: Boolean, completed: Boolean) {
		notificationManager.notify(taskNotificationId(state.taskId), buildTaskNotification(state, title, indeterminate, completed))
	}

	private fun taskNotificationId(taskId: String): Int = taskId.hashCode()

	override fun onBind(intent: Intent?): IBinder? = null
}
