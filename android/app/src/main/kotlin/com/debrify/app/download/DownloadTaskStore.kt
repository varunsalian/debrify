package com.debrify.app.download

import android.content.Context
import org.json.JSONObject
import com.debrify.app.security.DeviceSecretCipherPlugin

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
	val ownerProfileId: String = "legacy-admin-v1",
	val connectionResourceId: String? = null,
	val profileAuthorizationRevision: Long = 1L,
	val resourceAuthorizationRevision: Long? = null,
	val sealedExecutionPayload: String? = null,
)

object DownloadTaskStore {
	private const val PREFS = "debrify_download_service"
	private const val KEY = "tasks_v1"
	private val lock = com.debrify.app.profiles.NativeProfileMigrationGate.lock

	fun hasStoredState(context: Context): Boolean =
		!prefs(context).getString(KEY, null).isNullOrBlank()

	fun get(context: Context, taskId: String): TaskEntry? = all(context)[taskId]

	fun put(context: Context, entry: TaskEntry) {
		synchronized(lock) {
			val committed = com.debrify.app.profiles.ProfilePreferenceProjection.isCommitted(context)
			if (committed &&
				!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
					context,
					entry.ownerProfileId,
					entry.profileAuthorizationRevision,
					"downloads",
					entry.connectionResourceId,
					entry.resourceAuthorizationRevision,
					// Entries carry enqueue-time revisions and are re-persisted
					// for the whole download — see the projection's drift note.
					allowRevisionDrift = true,
				)
			) throw SecurityException("Download profile authorization changed")
			val map = loadJson(context)
			val secured = if (!committed) {
				// Profile flags off must retain the pre-profile plaintext format and
				// must not gain an Android Keystore availability dependency.
				entry.copy(sealedExecutionPayload = null)
			} else if (entry.sealedExecutionPayload == null) {
				entry.copy(sealedExecutionPayload = sealExecutionPayload(entry))
			} else entry
			map.put(entry.taskId, toJson(secured))
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
				val source = runCatching { map.getJSONObject(id) }.getOrNull() ?: return@forEach
				out[id] = try {
					fromJson(id, source)
				} catch (_: Exception) {
					// Keep parseable task metadata visible and non-runnable when its
					// sealed execution data cannot be opened. Silent disappearance is
					// indistinguishable from data loss in the downloads UI.
					fromJsonWithoutExecution(id, source)
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

	/** One-time upgrade of pre-profile tasks. Re-sealing is required because
	 * execution AAD binds both owner and authorization revision. */
	fun migrateLegacyAuthority(context: Context, ownerProfileId: String, revision: Long) {
		synchronized(lock) {
			// Migration must be lossless. Normal queries isolate a corrupt row so
			// one bad task cannot break the UI; migration instead parses every row
			// before replacing anything, otherwise that isolation would silently
			// turn corruption into deletion.
			val source = loadJsonStrict(context)
			val entries = ArrayList<Pair<String, TaskEntry>>()
			source.keys().forEach { taskId ->
				entries.add(taskId to fromJson(taskId, source.getJSONObject(taskId)))
			}
			val migrated = JSONObject()
			for ((taskId, entry) in entries) {
				val rebound = entry.copy(
					ownerProfileId = ownerProfileId,
					profileAuthorizationRevision = revision,
					sealedExecutionPayload = null,
				)
				val secured = rebound.copy(sealedExecutionPayload = sealExecutionPayload(rebound))
				migrated.put(taskId, toJson(secured))
			}
			saveDurably(context, migrated)
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

	private fun loadJsonStrict(context: Context): JSONObject =
		JSONObject(prefs(context).getString(KEY, null) ?: "{}")

	private fun save(context: Context, map: JSONObject) {
		prefs(context).edit().putString(KEY, map.toString()).apply()
	}

	private fun saveDurably(context: Context, map: JSONObject) {
		if (!prefs(context).edit().putString(KEY, map.toString()).commit()) {
			throw IllegalStateException("Could not commit migrated download tasks")
		}
	}

	// Absent optionals are OMITTED, never stored as JSONObject.NULL: Android's
	// org.json optString() coerces NULL to the literal string "null", which
	// would round-trip treeUri="null" -> isSaf==true -> saf_grant_lost on every
	// resume of a plain MediaStore download after process death.
	private fun toJson(e: TaskEntry): JSONObject = JSONObject().apply {
		if (e.sealedExecutionPayload == null) {
			put("url", e.url)
			put("headers", JSONObject(e.headers as Map<String, Any?>))
		} else {
			put("sealedExecutionPayload", e.sealedExecutionPayload)
		}
		put("fileName", e.fileName)
		put("subDir", e.subDir)
		put("mimeType", e.mimeType)
		e.uri?.let { put("uri", it) }
		put("destType", e.destType)
		e.treeUri?.let { put("treeUri", it) }
		e.etag?.let { put("etag", it) }
		e.lastModified?.let { put("lastModified", it) }
		put("total", e.total)
		put("status", e.status)
		e.errorMessage?.let { put("errorMessage", it) }
		put("updatedAt", e.updatedAt)
		put("ownerProfileId", e.ownerProfileId)
		e.connectionResourceId?.let { put("connectionResourceId", it) }
		put("profileAuthorizationRevision", e.profileAuthorizationRevision)
		e.resourceAuthorizationRevision?.let { put("resourceAuthorizationRevision", it) }
	}

	// Belt-and-braces against entries written before the omit-nulls rule.
	private fun optNullable(o: JSONObject, key: String): String? =
		o.optString(key, "").takeIf { it.isNotEmpty() && it != "null" }

	private fun fromJson(taskId: String, o: JSONObject): TaskEntry {
		val owner = o.optString("ownerProfileId", "legacy-admin-v1")
		val revision = o.optLong("profileAuthorizationRevision", 1L)
		val sealed = optNullable(o, "sealedExecutionPayload")
		val execution = if (sealed == null) o else JSONObject(
			DeviceSecretCipherPlugin.openForNative(
				sealed,
				executionAad(taskId, owner, revision).toByteArray(Charsets.UTF_8),
			).toString(Charsets.UTF_8),
		)
		val headers = HashMap<String, String>()
		execution.optJSONObject("headers")?.let { h ->
			h.keys().forEach { k -> headers[k] = h.optString(k, "") }
		}
		return TaskEntry(
			taskId = taskId,
			url = execution.optString("url", ""),
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
			ownerProfileId = owner,
			connectionResourceId = optNullable(o, "connectionResourceId"),
			profileAuthorizationRevision = revision,
			resourceAuthorizationRevision = if (o.has("resourceAuthorizationRevision"))
				o.optLong("resourceAuthorizationRevision") else null,
			sealedExecutionPayload = sealed,
		)
	}

	private fun fromJsonWithoutExecution(taskId: String, o: JSONObject): TaskEntry {
		val owner = o.optString("ownerProfileId", "legacy-admin-v1")
		val revision = o.optLong("profileAuthorizationRevision", 1L)
		return TaskEntry(
			taskId = taskId,
			url = "",
			fileName = o.optString("fileName", "download"),
			subDir = o.optString("subDir", "Debrify"),
			mimeType = o.optString("mimeType", "application/octet-stream"),
			headers = hashMapOf(),
			uri = optNullable(o, "uri"),
			destType = o.optString("destType", "mediastore"),
			treeUri = optNullable(o, "treeUri"),
			etag = optNullable(o, "etag"),
			lastModified = optNullable(o, "lastModified"),
			total = o.optLong("total", -1L),
			status = "failed",
			errorMessage = "saved download credentials are unavailable; start again",
			updatedAt = o.optLong("updatedAt", 0L),
			ownerProfileId = owner,
			connectionResourceId = optNullable(o, "connectionResourceId"),
			profileAuthorizationRevision = revision,
			resourceAuthorizationRevision = if (o.has("resourceAuthorizationRevision"))
				o.optLong("resourceAuthorizationRevision") else null,
			sealedExecutionPayload = optNullable(o, "sealedExecutionPayload"),
		)
	}

	private fun sealExecutionPayload(entry: TaskEntry): String =
		DeviceSecretCipherPlugin.sealForNative(
			JSONObject().apply {
				put("url", entry.url)
				put("headers", JSONObject(entry.headers as Map<String, Any?>))
			}.toString().toByteArray(Charsets.UTF_8),
			executionAad(
				entry.taskId,
				entry.ownerProfileId,
				entry.profileAuthorizationRevision,
			).toByteArray(Charsets.UTF_8),
		)

	private fun executionAad(id: String, owner: String, revision: Long) =
		"debrify-android-download-v1|id=$id|owner=$owner|revision=$revision"
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
