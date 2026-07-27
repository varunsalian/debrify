package com.debrify.app.download

import android.content.Context
import org.json.JSONObject

/**
 * Durable record of every non-terminal download task, so the service can
 * survive process death: a START/RESUME for a task whose in-memory state is
 * gone reconstructs it from here and continues from the bytes on disk.
 *
 * `downloaded` is deliberately NOT persisted — the destination file's on-disk
 * size is the resume offset's single source of truth, re-read on every
 * (re)start. Entries are written only on state transitions (created,
 * validators captured, paused, failed) and removed on complete/cancel.
 */
data class TaskEntry(
	val taskId: String,
	val url: String,
	val fileName: String,
	val subDir: String,
	val mimeType: String,
	val headers: HashMap<String, String>,
	val uri: String?,
	val destType: String, // "mediastore" | "saf"
	val treeUri: String?,
	val etag: String?,
	val lastModified: String?,
	val total: Long,
	val status: String, // "running" | "paused" | "failed"
	val errorMessage: String?,
	val updatedAt: Long,
)

object DownloadTaskStore {
	private const val PREFS = "debrify_download_service"
	private const val KEY = "tasks_v1"
	private val lock = Any()

	fun get(context: Context, taskId: String): TaskEntry? = all(context)[taskId]

	fun put(context: Context, entry: TaskEntry) {
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

	fun all(context: Context): Map<String, TaskEntry> {
		synchronized(lock) {
			val map = loadJson(context)
			val out = HashMap<String, TaskEntry>()
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

	fun clear(context: Context) {
		synchronized(lock) {
			prefs(context).edit().remove(KEY).apply()
		}
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

	// Absent optionals are OMITTED, never stored as JSONObject.NULL: Android's
	// org.json optString() coerces NULL to the literal string "null", which
	// would round-trip treeUri="null" -> isSaf==true -> saf_grant_lost on every
	// resume of a plain MediaStore download after process death.
	private fun toJson(e: TaskEntry): JSONObject = JSONObject().apply {
		put("url", e.url)
		put("fileName", e.fileName)
		put("subDir", e.subDir)
		put("mimeType", e.mimeType)
		put("headers", JSONObject(e.headers as Map<String, Any?>))
		e.uri?.let { put("uri", it) }
		put("destType", e.destType)
		e.treeUri?.let { put("treeUri", it) }
		e.etag?.let { put("etag", it) }
		e.lastModified?.let { put("lastModified", it) }
		put("total", e.total)
		put("status", e.status)
		e.errorMessage?.let { put("errorMessage", it) }
		put("updatedAt", e.updatedAt)
	}

	// Belt-and-braces against entries written before the omit-nulls rule.
	private fun optNullable(o: JSONObject, key: String): String? =
		o.optString(key, "").takeIf { it.isNotEmpty() && it != "null" }

	private fun fromJson(taskId: String, o: JSONObject): TaskEntry {
		val headers = HashMap<String, String>()
		o.optJSONObject("headers")?.let { h ->
			h.keys().forEach { k -> headers[k] = h.optString(k, "") }
		}
		return TaskEntry(
			taskId = taskId,
			url = o.optString("url", ""),
			fileName = o.optString("fileName", "download"),
			subDir = o.optString("subDir", "Debrify"),
			mimeType = o.optString("mimeType", "application/octet-stream"),
			headers = headers,
			uri = optNullable(o, "uri"),
			destType = o.optString("destType", "mediastore"),
			treeUri = optNullable(o, "treeUri"),
			etag = optNullable(o, "etag"),
			lastModified = optNullable(o, "lastModified"),
			total = o.optLong("total", -1L),
			status = o.optString("status", "paused"),
			errorMessage = optNullable(o, "errorMessage"),
			updatedAt = o.optLong("updatedAt", 0L),
		)
	}
}

/**
 * Live in-memory snapshot of RUNNING tasks, readable from outside the service
 * (MainActivity's `queryDownloadTasks`) without binding. A task is present
 * here iff a worker thread currently owns it.
 */
object DownloadRegistry {
	class Live(
		@Volatile var bytes: Long,
		@Volatile var total: Long,
	)

	val live = java.util.concurrent.ConcurrentHashMap<String, Live>()
}
