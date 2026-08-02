package com.debrify.app.recording

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Durable record of every live-recording task, mirroring DownloadTaskStore's
 * idiom (prefs-backed JSON map, synchronized, corrupt entries dropped).
 *
 * Unlike downloads, a live capture can never be RESUMED after process death —
 * the stream kept broadcasting while we were dead, so the gap is unbounded.
 * A persisted `recording` entry with no live worker therefore means "finalize
 * what's on disk": [reconcileDeadEntries] clears the row's IS_PENDING so the
 * partial file becomes user-visible, and flips the entry to `done`. Terminal
 * entries (`done`/`failed`) stay queryable by Dart until forgotten or pruned.
 */
data class RecordingEntry(
	val taskId: String,
	val url: String,
	val headers: HashMap<String, String>,
	val fileName: String,
	val channelName: String,
	val uri: String?,
	val status: String, // "recording" | "done" | "failed"
	val bytes: Long,
	val startedAtMs: Long,
	val endAtMs: Long,
	val errorMessage: String?,
	val updatedAt: Long,
	/** False when the finished row's IS_PENDING could not be cleared — the
	 *  file exists but is invisible. Kept recoverable: [RecordingTaskStore
	 *  .reconcileDeadEntries] retries publication on every pass. */
	val published: Boolean = true,
)

object RecordingTaskStore {
	private const val PREFS = "debrify_recording_service"
	private const val KEY = "tasks_v1"
	private val lock = Any()

	/** Terminal entries older than this are pruned on reconcile. */
	private const val TERMINAL_TTL_MS = 24L * 60 * 60 * 1000

	/** A `recording` entry younger than this is never treated as dead — it may
	 *  be a worker that has persisted but not yet reached the registry insert
	 *  visible to the caller's thread. */
	private const val DEAD_MIN_AGE_MS = 15_000L

	fun get(context: Context, taskId: String): RecordingEntry? = all(context)[taskId]

	fun put(context: Context, entry: RecordingEntry) {
		synchronized(lock) {
			val map = loadJson(context)
			map.put(entry.taskId, toJson(entry))
			save(context, map)
		}
	}

	fun remove(context: Context, taskId: String) {
		synchronized(lock) {
			val map = loadJson(context)
			if (map.has(taskId)) {
				map.remove(taskId)
				save(context, map)
			}
		}
	}

	fun all(context: Context): Map<String, RecordingEntry> {
		synchronized(lock) {
			val map = loadJson(context)
			val out = HashMap<String, RecordingEntry>()
			map.keys().forEach { id ->
				try {
					out[id] = fromJson(id, map.getJSONObject(id))
				} catch (_: Exception) {
					// Corrupt entry: drop rather than poison every query.
				}
			}
			return out
		}
	}

	/**
	 * Settle entries left behind by a dead process, and prune stale terminal
	 * ones. Safe to call from any thread; each call is one pass over the store.
	 *
	 * A dead `recording` entry's row already holds every byte that was synced —
	 * publishing it (IS_PENDING=0) is the whole crash story. A dead entry whose
	 * row has no bytes (or no row at all) has nothing worth keeping: delete the
	 * row, mark failed.
	 */
	fun reconcileDeadEntries(context: Context) {
		val now = System.currentTimeMillis()
		for ((taskId, entry) in all(context)) {
			when (entry.status) {
				"recording" -> {
					if (RecordingRegistry.live.containsKey(taskId)) continue
					if (now - entry.updatedAt < DEAD_MIN_AGE_MS) continue
					val uri = entry.uri?.let { Uri.parse(it) }
					val size = uri?.let { fileSize(context, it) } ?: -1L
					if (uri != null && size > 0L) {
						val published = publishRow(context, uri)
						put(
							context,
							entry.copy(
								status = "done",
								bytes = size,
								published = published,
								updatedAt = now,
							),
						)
					} else {
						uri?.let {
							runCatching { context.contentResolver.delete(it, null, null) }
						}
						put(
							context,
							entry.copy(
								status = "failed",
								errorMessage = "interrupted before any data was saved",
								updatedAt = now,
							),
						)
					}
				}
				"done" -> {
					// A finished capture whose row never got IS_PENDING cleared
					// (provider hiccup at stop time): the bytes exist but the
					// file is invisible. Retry — the provider may be back.
					if (!entry.published) {
						val uri = entry.uri?.let { Uri.parse(it) }
						if (uri != null && publishRow(context, uri)) {
							put(context, entry.copy(published = true, updatedAt = now))
							continue
						}
					}
					if (entry.published && now - entry.updatedAt > TERMINAL_TTL_MS) {
						remove(context, taskId)
					}
				}
				else -> {
					if (now - entry.updatedAt > TERMINAL_TTL_MS) remove(context, taskId)
				}
			}
		}
	}

	fun fileSize(context: Context, uri: Uri): Long {
		return try {
			context.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
				java.io.FileInputStream(pfd.fileDescriptor).use { fis -> fis.channel.size() }
			} ?: -1L
		} catch (_: Exception) { -1L }
	}

	/** Clear IS_PENDING; false when the row could NOT be made visible (update
	 *  threw or matched no rows). Callers persist that so the file stays
	 *  recoverable instead of silently invisible. */
	fun publishRow(context: Context, uri: Uri): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
		val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
		return runCatching {
			context.contentResolver.update(uri, done, null, null)
		}.getOrDefault(0) > 0
	}

	private fun prefs(context: Context) =
		context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

	private fun loadJson(context: Context): JSONObject {
		return try {
			JSONObject(prefs(context).getString(KEY, null) ?: "{}")
		} catch (_: Exception) {
			JSONObject()
		}
	}

	private fun save(context: Context, map: JSONObject) {
		prefs(context).edit().putString(KEY, map.toString()).apply()
	}

	// Absent optionals are OMITTED, never JSONObject.NULL (see DownloadTaskStore
	// for the optString("null") trap this avoids).
	private fun toJson(e: RecordingEntry): JSONObject = JSONObject().apply {
		put("url", e.url)
		put("headers", JSONObject(e.headers as Map<String, Any?>))
		put("fileName", e.fileName)
		put("channelName", e.channelName)
		e.uri?.let { put("uri", it) }
		put("status", e.status)
		put("bytes", e.bytes)
		put("startedAtMs", e.startedAtMs)
		put("endAtMs", e.endAtMs)
		e.errorMessage?.let { put("errorMessage", it) }
		put("updatedAt", e.updatedAt)
		put("published", e.published)
	}

	private fun optNullable(o: JSONObject, key: String): String? =
		o.optString(key, "").takeIf { it.isNotEmpty() && it != "null" }

	private fun fromJson(taskId: String, o: JSONObject): RecordingEntry {
		val headers = HashMap<String, String>()
		o.optJSONObject("headers")?.let { h ->
			h.keys().forEach { k -> headers[k] = h.optString(k, "") }
		}
		return RecordingEntry(
			taskId = taskId,
			url = o.optString("url", ""),
			headers = headers,
			fileName = o.optString("fileName", "recording.ts"),
			channelName = o.optString("channelName", ""),
			uri = optNullable(o, "uri"),
			status = o.optString("status", "failed"),
			bytes = o.optLong("bytes", 0L),
			startedAtMs = o.optLong("startedAtMs", 0L),
			endAtMs = o.optLong("endAtMs", 0L),
			errorMessage = optNullable(o, "errorMessage"),
			updatedAt = o.optLong("updatedAt", 0L),
			published = o.optBoolean("published", true),
		)
	}
}

/**
 * Live in-memory snapshot of RUNNING recordings, readable from outside the
 * service (MainActivity's query, the TV player's Record button) without
 * binding. A task is present here iff a worker thread currently owns it.
 *
 * UI that wants to repaint when recordings start/stop registers a listener;
 * callbacks always arrive on the main thread.
 */
object RecordingRegistry {
	class Live(
		val url: String,
		val channelName: String,
		val fileName: String,
		val startedAtMs: Long,
	) {
		@Volatile var bytes: Long = 0L
	}

	val live = ConcurrentHashMap<String, Live>()

	/**
	 * url → taskId claims for starts the SERVICE has not resolved yet: issued
	 * by MainActivity before startForegroundService, cleared by the service on
	 * every resolution path — worker registered in [live] (the claim's job is
	 * done), start rejected, or capture finished before registration. Between
	 * claim and resolution, a same-url start returns the claimed id instead of
	 * minting one the service would silently deduplicate. No time component:
	 * the claim lives exactly as long as the service is still deciding, so a
	 * slow MediaStore insert can't expire it and a failed capture can't leave
	 * it answering with a dead id. Dies with the process, same as the intent
	 * it shadows.
	 */
	val pendingStarts = ConcurrentHashMap<String, String>()

	/** Clear [url]'s claim iff it belongs to [taskId] — a newer claim for the
	 *  same url must not be removed by an older start's resolution. */
	fun resolvePendingStart(url: String, taskId: String) {
		pendingStarts.remove(url, taskId)
	}

	/**
	 * Atomically: the id already responsible for [url] — live capture or
	 * pending claim — or, if none, register [candidateId] as the new claim and
	 * return null ("proceed, you own the start"). One synchronized operation
	 * across BOTH maps, holding the same monitor as [promoteToLive]: separate
	 * reads could fall into the worker's move-from-pending-to-live gap, see
	 * neither, and mint an id the service then discards as a duplicate.
	 */
	@Synchronized
	fun claimOrExisting(url: String, candidateId: String): String? {
		taskIdForUrl(url)?.let { return it }
		pendingStarts[url]?.let { return it }
		pendingStarts[url] = candidateId
		return null
	}

	/** The worker's registered-now transition: live insert + claim resolution
	 *  as one atomic step (see [claimOrExisting]). */
	@Synchronized
	fun promoteToLive(taskId: String, entry: Live) {
		live[taskId] = entry
		pendingStarts.remove(entry.url, taskId)
	}

	private val listeners = CopyOnWriteArrayList<() -> Unit>()
	private val mainHandler = Handler(Looper.getMainLooper())

	fun addListener(listener: () -> Unit) {
		listeners.addIfAbsent(listener)
	}

	fun removeListener(listener: () -> Unit) {
		listeners.remove(listener)
	}

	/** Post a change to every listener on the main thread. */
	fun notifyChanged() {
		mainHandler.post {
			listeners.forEach { runCatching { it() } }
		}
	}

	/** The live task recording [url], or null. */
	fun taskIdForUrl(url: String): String? =
		live.entries.firstOrNull { it.value.url == url }?.key
}

/**
 * MediaStore rows the TEE recorder (IptvRecordingController) has created but
 * not yet published. Entries are added at row CREATION — not at
 * publish-failure — because the two loss paths are the same invisible pending
 * row: a publish whose IS_PENDING clear failed, and a process that died
 * mid-recording (onDestroy never ran, the controller's in-memory state is
 * gone). [retryAll] sweeps the set at app start: rows with bytes are
 * published as (possibly partial) recordings, empty rows are deleted. Entries
 * leave on successful publication or row deletion. Safe against a live
 * recording: the sweep runs once, at engine setup, before any player exists.
 */
object TeeUnpublishedStore {
	private const val PREFS = "debrify_tee_unpublished"
	private const val KEY = "uris_v1"
	private val lock = Any()

	fun add(context: Context, uri: Uri) {
		synchronized(lock) {
			val prefs = prefs(context)
			val set = HashSet(prefs.getStringSet(KEY, emptySet()) ?: emptySet())
			if (set.add(uri.toString())) {
				prefs.edit().putStringSet(KEY, set).apply()
			}
		}
	}

	fun remove(context: Context, uri: Uri) {
		synchronized(lock) {
			val prefs = prefs(context)
			val set = HashSet(prefs.getStringSet(KEY, emptySet()) ?: emptySet())
			if (set.remove(uri.toString())) {
				prefs.edit().putStringSet(KEY, set).apply()
			}
		}
	}

	/** Retry publication of every stored row; call from app-start housekeeping. */
	fun retryAll(context: Context) {
		val uris: List<String> = synchronized(lock) {
			(prefs(context).getStringSet(KEY, emptySet()) ?: emptySet()).toList()
		}
		for (raw in uris) {
			val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: continue
			val size = RecordingTaskStore.fileSize(context, uri)
			if (size < 0L) {
				// Row gone (user deleted it, system reaped it) — nothing left
				// to recover.
				remove(context, uri)
				continue
			}
			if (size == 0L) {
				// Created but never written (death before the first byte):
				// publishing would surface a junk empty file. Delete instead.
				runCatching { context.contentResolver.delete(uri, null, null) }
				remove(context, uri)
				continue
			}
			if (RecordingTaskStore.publishRow(context, uri)) {
				remove(context, uri)
			}
		}
	}

	private fun prefs(context: Context) =
		context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
