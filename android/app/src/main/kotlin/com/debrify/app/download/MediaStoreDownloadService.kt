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
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.TaskStackBuilder
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.channels.FileChannel
import java.util.concurrent.ConcurrentHashMap

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

		private const val NOTIFICATION_CHANNEL_ID = "downloads_channel_v2"
		private const val NOTIFICATION_CHANNEL_NAME = "Downloads"
		private const val SERVICE_NOTIFICATION_ID = 9000
		private const val GROUP_KEY_DOWNLOADS = "com.debrify.app.downloads.GROUP"
	}

	private data class DownloadState(
		val taskId: String,
		val url: String,
		val fileName: String,
		val subDir: String,
		val mimeType: String,
		val headers: HashMap<String, String>,
		var uri: Uri? = null,
		@Volatile var downloaded: Long = 0L,
		@Volatile var total: Long = -1L,
		@Volatile var etag: String? = null,
		@Volatile var lastModified: String? = null,
		@Volatile var paused: Boolean = false,
		@Volatile var canceled: Boolean = false,
		@Volatile var connection: HttpURLConnection? = null,
		@Volatile var input: InputStream? = null,
		@Volatile var running: Boolean = false,
	)

	private lateinit var notificationManager: NotificationManager
	private val states = ConcurrentHashMap<String, DownloadState>()

	override fun onCreate() {
		super.onCreate()
		notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		createNotificationChannel()
	}

	override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
		when (intent?.action) {
			ACTION_START -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: System.currentTimeMillis().toString()
				val url = intent.getStringExtra(EXTRA_URL) ?: return START_NOT_STICKY
				val fileName = intent.getStringExtra(EXTRA_FILE_NAME) ?: "download"
				val subDir = intent.getStringExtra(EXTRA_RELATIVE_SUBDIR) ?: "Debrify"
				val mimeType = intent.getStringExtra(EXTRA_MIME_TYPE) ?: "application/octet-stream"
				@Suppress("UNCHECKED_CAST")
				val headers = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String> ?: hashMapOf()

				val state = DownloadState(taskId, url, fileName, subDir, mimeType, headers)
				states[taskId] = state
				if (states.size == 1) {
					startForeground(SERVICE_NOTIFICATION_ID, buildSummaryNotification())
				} else {
					updateSummaryNotification()
				}
				notifyTask(state, "Preparing...", indeterminate = true, completed = false)
				Thread { try { startOrResume(state, fresh = true) } catch (t: Throwable) { try { notifyTask(state, "Error", indeterminate = true, completed = false) } catch (_: Exception) {}; ChannelBridge.emit(mapOf("type" to "error", "taskId" to state.taskId, "message" to (t.message ?: "crash"))) } }.start()
			}
			ACTION_PAUSE -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
				states[taskId]?.let { s ->
					s.paused = true
					try { s.connection?.disconnect() } catch (_: Exception) {}
					try { s.input?.close() } catch (_: Exception) {}
					notifyTask(s, "Paused", indeterminate = false, completed = false)
					updateSummaryNotification()
					ChannelBridge.emit(mapOf(
						"type" to "paused",
						"taskId" to taskId,
						"fileName" to s.fileName,
						"subDir" to s.subDir,
					))
				}
			}
			ACTION_RESUME -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
				states[taskId]?.let { s ->
					if (s.running) return START_NOT_STICKY
					s.paused = false
					Thread { try { startOrResume(s, fresh = false) } catch (t: Throwable) { try { notifyTask(s, "Error", indeterminate = true, completed = false) } catch (_: Exception) {}; ChannelBridge.emit(mapOf("type" to "error", "taskId" to s.taskId, "message" to (t.message ?: "crash"))) } }.start()
					updateSummaryNotification()
					ChannelBridge.emit(mapOf(
						"type" to "resumed",
						"taskId" to taskId,
						"fileName" to s.fileName,
						"subDir" to s.subDir,
					))
				}
			}
			ACTION_CANCEL -> {
				val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
				states[taskId]?.let { s ->
					s.canceled = true
					try { s.connection?.disconnect() } catch (_: Exception) {}
					try { s.input?.close() } catch (_: Exception) {}
					s.uri?.let { try { contentResolver.delete(it, null, null) } catch (_: Exception) {} }
					ChannelBridge.emit(mapOf(
						"type" to "canceled",
						"taskId" to taskId,
						"fileName" to s.fileName,
						"subDir" to s.subDir,
					))
					states.remove(taskId)
					notificationManager.cancel(taskNotificationId(taskId))
				}
				if (states.isEmpty()) {
					stopForeground(STOP_FOREGROUND_REMOVE)
					notificationManager.cancel(SERVICE_NOTIFICATION_ID)
					stopSelfSafely()
				} else {
					updateSummaryNotification()
				}
			}
		}
		return START_NOT_STICKY
	}

	private fun existingSize(uri: Uri): Long {
		return try {
			val pfd = contentResolver.openFileDescriptor(uri, "r")
			val fis = FileInputStream(pfd!!.fileDescriptor)
			val ch = fis.channel
			val size = ch.size()
			ch.close()
			fis.close()
			pfd.close()
			size
		} catch (e: Exception) { 0L }
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

	private fun startOrResume(state: DownloadState, fresh: Boolean) {
		if (state.running) return
		state.running = true
		var uri: Uri? = state.uri
		var connection: HttpURLConnection? = null
		var input: InputStream? = null
		var out: BufferedOutputStream? = null
		var outPfd: ParcelFileDescriptor? = null
		var outChannel: FileChannel? = null
		try {
			if (uri == null) {
				val values = ContentValues().apply {
					put(MediaStore.Downloads.DISPLAY_NAME, state.fileName)
					put(MediaStore.Downloads.MIME_TYPE, state.mimeType)
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
						put(MediaStore.Downloads.RELATIVE_PATH, "Download/${state.subDir}")
						put(MediaStore.Downloads.IS_PENDING, 1)
					}
				}
				uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
				if (uri == null) {
					notifyTask(state, "Failed to create destination", indeterminate = true, completed = false)
					ChannelBridge.emit(mapOf("type" to "error", "taskId" to state.taskId, "message" to "no destination"))
					stopSelfSafely(); return
				}
				state.uri = uri
				ChannelBridge.emit(mapOf("type" to "started", "taskId" to state.taskId, "fileName" to state.fileName, "subDir" to state.subDir))
			}

			// Always confirm bytes already written on disk
			uri?.let { confirmed ->
				val onDisk = existingSize(confirmed)
				if (onDisk > 0L) state.downloaded = onDisk
			}

			val url = URL(state.url)
			connection = (url.openConnection() as HttpURLConnection).apply {
				instanceFollowRedirects = true
				connectTimeout = 15000
				readTimeout = 15000
				doInput = true
				state.headers.forEach { (k, v) -> setRequestProperty(k, v) }
				if (state.downloaded > 0L) {
					setRequestProperty("Range", "bytes=${state.downloaded}-")
					state.etag?.let { setRequestProperty("If-Range", it) }
				}
			}
			connection.connect()
			state.connection = connection

			val resp = connection.responseCode
			// Handle resume edge cases before opening output stream
			if (state.downloaded > 0L && resp == HttpURLConnection.HTTP_OK) {
				// Server ignored Range; restart from 0 by truncating existing file
				state.downloaded = 0L
				if (uri != null) {
					try {
						val pfd = contentResolver.openFileDescriptor(uri!!, "rw")
						val fos = FileOutputStream(pfd!!.fileDescriptor)
						val channel: FileChannel = fos.channel
						channel.truncate(0)
						channel.position(0)
						fos.close()
						pfd.close()
					} catch (_: Exception) {}
				}
			} else if (state.downloaded > 0L && resp == 416) {
				// 416: already fully downloaded on server side; treat as complete
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
					val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
					contentResolver.update(uri!!, done, null, null)
				}
				notifyTask(state, "Download complete", indeterminate = false, completed = true)
				ChannelBridge.emit(mapOf(
					"type" to "complete",
					"taskId" to state.taskId,
					"bytes" to state.total,
					"total" to state.total,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"url" to state.url,
				))
				states.remove(state.taskId)
				notificationManager.cancel(taskNotificationId(state.taskId))
				if (states.isEmpty()) {
					stopForeground(STOP_FOREGROUND_REMOVE)
					notificationManager.cancel(SERVICE_NOTIFICATION_ID)
					stopSelfSafely()
				} else {
					updateSummaryNotification()
				}
				return
			} else if (resp !in 200..206) {
				throw IllegalStateException("HTTP $resp for $url")
			}

			val resumedByServer = state.downloaded > 0L && resp == HttpURLConnection.HTTP_PARTIAL
			// Parse Content-Range if present to validate start and total
			if (resumedByServer) {
				parseContentRange(connection.getHeaderField("Content-Range"))?.let { (start, end, total) ->
					if (total > 0) state.total = total
					if (start != state.downloaded) {
						if (start == 0L) {
							// Server starts from 0; restart full
							state.downloaded = 0L
							if (uri != null) {
								try {
									val pfd = contentResolver.openFileDescriptor(uri!!, "rw")
									val fos = FileOutputStream(pfd!!.fileDescriptor)
									val ch = fos.channel
									ch.truncate(0)
									ch.position(0)
									fos.close(); pfd.close()
								} catch (_: Exception) {}
							}
						} else {
							// Adjust to server-provided offset
							state.downloaded = start
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

			input = BufferedInputStream(connection.inputStream)
			state.input = input
			out = if (state.downloaded > 0L) {
				val pfd = contentResolver.openFileDescriptor(uri!!, "rw")
				outPfd = pfd
				val fos = FileOutputStream(pfd!!.fileDescriptor)
				val channel: FileChannel = fos.channel
				outChannel = channel
				channel.position(state.downloaded)
				BufferedOutputStream(fos)
			} else {
				// start from 0, ensure overwrite
				BufferedOutputStream(contentResolver.openOutputStream(uri!!, "w") ?: throw IllegalStateException("No output stream"))
			}

			val buffer = ByteArray(256 * 1024)
			var bytesRead: Int
			var lastUpdate = System.currentTimeMillis()
			notifyTask(state, "Downloading", indeterminate = state.total <= 0, completed = false)
			updateSummaryNotification()
			if (state.downloaded == 0L) {
				ChannelBridge.emit(mapOf(
					"type" to "progress",
					"taskId" to state.taskId,
					"bytes" to state.downloaded,
					"total" to state.total,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"url" to state.url,
				))
			}

			while (true) {
				if (state.canceled) throw InterruptedException("canceled")
				if (state.paused) break
				bytesRead = input.read(buffer)
				if (bytesRead == -1) break
				out.write(buffer, 0, bytesRead)
				state.downloaded += bytesRead
				val now = System.currentTimeMillis()
				if (now - lastUpdate > 500) {
					notifyTask(state, "Downloading", indeterminate = state.total <= 0, completed = false)
					ChannelBridge.emit(mapOf(
						"type" to "progress",
						"taskId" to state.taskId,
						"bytes" to state.downloaded,
						"total" to state.total,
						"fileName" to state.fileName,
						"subDir" to state.subDir,
						"url" to state.url,
					))
					lastUpdate = now
				}
			}
			out.flush()

			if (!state.paused) {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
					val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
					contentResolver.update(uri!!, done, null, null)
				}
				notifyTask(state, "Download complete", indeterminate = false, completed = true)
				ChannelBridge.emit(mapOf(
					"type" to "complete",
					"taskId" to state.taskId,
					"bytes" to state.total,
					"total" to state.total,
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"url" to state.url,
				))
				states.remove(state.taskId)
				notificationManager.cancel(taskNotificationId(state.taskId))
				if (states.isEmpty()) {
					stopForeground(STOP_FOREGROUND_REMOVE)
					notificationManager.cancel(SERVICE_NOTIFICATION_ID)
					stopSelfSafely()
				} else {
					updateSummaryNotification()
				}
			} else {
				notifyTask(state, "Paused", indeterminate = false, completed = false)
				updateSummaryNotification()
			}
		} catch (e: Exception) {
			if (state.paused) {
				notifyTask(state, "Paused", indeterminate = false, completed = false)
			} else if (!state.canceled) {
				notifyTask(state, "Download failed", indeterminate = true, completed = false)
				ChannelBridge.emit(mapOf(
					"type" to "error",
					"taskId" to state.taskId,
					"message" to (e.message ?: "unknown error"),
					"fileName" to state.fileName,
					"subDir" to state.subDir,
					"url" to state.url,
				))
			}
		} finally {
			try { out?.close() } catch (_: Exception) {}
			try { outChannel?.close() } catch (_: Exception) {}
			try { outPfd?.close() } catch (_: Exception) {}
			try { input?.close() } catch (_: Exception) {}
			try { connection?.disconnect() } catch (_: Exception) {}
			state.running = false
		}
	}

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
			.setOngoing(!completed)
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