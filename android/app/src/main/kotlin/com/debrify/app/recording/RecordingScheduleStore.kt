package com.debrify.app.recording

import android.content.Context
import org.json.JSONObject
import com.debrify.app.security.DeviceSecretCipherPlugin

/**
 * One-shot scheduled recordings, natively owned so an alarm fire needs no
 * Flutter engine. Each entry snapshots everything the service needs at start
 * time (url + headers taken when the user scheduled — accepted staleness risk
 * on rotating-token panels). Entries are deleted when their alarm fires
 * (success or not), when cancelled, or when registration finds them fully in
 * the past.
 */
data class RecordingSchedule(
	val id: String,
	val channelName: String,
	val url: String,
	val headers: HashMap<String, String>,
	val startMs: Long,
	val endMs: Long,
	val programmeTitle: String,
	val createdAt: Long,
	val ownerProfileId: String = "legacy-admin-v1",
	val connectionResourceId: String? = null,
	val profileAuthorizationRevision: Long = 1L,
	val resourceAuthorizationRevision: Long? = null,
	val sealedExecutionPayload: String? = null,
)

object RecordingScheduleStore {
	private const val PREFS = "debrify_recording_schedules"
	private const val KEY = "schedules_v1"
	private val lock = com.debrify.app.profiles.NativeProfileMigrationGate.lock

	fun hasStoredState(context: Context): Boolean =
		!prefs(context).getString(KEY, null).isNullOrBlank()

	fun get(context: Context, id: String): RecordingSchedule? = all(context)[id]

	fun put(context: Context, schedule: RecordingSchedule) {
		synchronized(lock) {
			val committed = com.debrify.app.profiles.ProfilePreferenceProjection.isCommitted(context)
			if (committed &&
				!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
					context,
					schedule.ownerProfileId,
					schedule.profileAuthorizationRevision,
					"recordings",
					schedule.connectionResourceId,
					schedule.resourceAuthorizationRevision,
				)
			) throw SecurityException("Schedule profile authorization changed")
			val stored = if (!committed) {
				schedule.copy(sealedExecutionPayload = null)
			} else if (schedule.sealedExecutionPayload == null) {
				schedule.copy(
					sealedExecutionPayload = sealExecutionPayload(
						schedule.id,
						schedule.ownerProfileId,
						schedule.profileAuthorizationRevision,
						schedule.url,
						schedule.headers,
					),
				)
			} else schedule
			val map = loadJson(context)
			map.put(schedule.id, toJson(stored))
			save(context, map)
		}
	}

	fun remove(context: Context, id: String) {
		synchronized(lock) {
			val map = loadJson(context)
			if (map.has(id)) {
				map.remove(id)
				save(context, map)
			}
		}
	}

	fun all(context: Context): Map<String, RecordingSchedule> {
		synchronized(lock) {
			val map = loadJson(context)
			val out = HashMap<String, RecordingSchedule>()
			map.keys().forEach { id ->
				val source = runCatching { map.getJSONObject(id) }.getOrNull() ?: return@forEach
				out[id] = try {
					fromJson(context, id, source)
				} catch (_: Exception) {
					fromJsonWithoutExecution(id, source)
				}
			}
			return out
		}
	}

	/** Rebind old schedules to the migrated Admin and remove plaintext
	 * execution data. Resource/profile mutations subsequently invalidate the
	 * captured authorization revision before an alarm can execute. */
	fun migrateLegacyAuthority(context: Context, ownerProfileId: String, revision: Long) {
		synchronized(lock) {
			val source = loadJsonStrict(context)
			val schedules = ArrayList<Pair<String, RecordingSchedule>>()
			source.keys().forEach { scheduleId ->
				schedules.add(
					scheduleId to fromJson(
						context,
						scheduleId,
						source.getJSONObject(scheduleId),
					),
				)
			}
			val migrated = JSONObject()
			for ((scheduleId, schedule) in schedules) {
				val rebound = schedule.copy(
					ownerProfileId = ownerProfileId,
					profileAuthorizationRevision = revision,
					sealedExecutionPayload = null,
				)
				val secured = rebound.copy(
					sealedExecutionPayload = sealExecutionPayload(
						scheduleId,
						ownerProfileId,
						revision,
						rebound.url,
						rebound.headers,
					),
				)
				migrated.put(scheduleId, toJson(secured))
			}
			saveDurably(context, migrated)
		}
	}

	/** An existing schedule for the same channel-url + start time, if any —
	 *  the UI warns instead of silently double-recording one programme. */
	fun findDuplicate(context: Context, url: String, startMs: Long): RecordingSchedule? =
		all(context).values.firstOrNull { it.url == url && it.startMs == startMs }

	/**
	 * Peak number of stored schedules simultaneously active anywhere inside
	 * `[startMs, endMs)`. Half-open windows: a schedule ending exactly when
	 * another starts never overlaps it. The candidate itself is NOT counted —
	 * callers compare `peak + 1 > limit`.
	 */
	fun peakOverlap(context: Context, startMs: Long, endMs: Long): Int {
		val events = ArrayList<Pair<Long, Int>>()
		for (s in all(context).values) {
			val from = maxOf(s.startMs, startMs)
			val to = minOf(s.endMs, endMs)
			if (to <= from) continue
			events.add(from to 1)
			events.add(to to -1)
		}
		// Ends before starts at the same instant.
		events.sortWith(compareBy({ it.first }, { it.second }))
		var current = 0
		var peak = 0
		for ((_, delta) in events) {
			current += delta
			if (current > peak) peak = current
		}
		return peak
	}

	/** Display labels of schedules overlapping `[startMs, endMs)`, for the
	 *  conflict warning. */
	fun overlappingTitles(context: Context, startMs: Long, endMs: Long): List<String> =
		all(context).values
			.filter { it.startMs < endMs && startMs < it.endMs }
			.sortedBy { it.startMs }
			.map { it.programmeTitle.ifEmpty { it.channelName } }
			.distinct()

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
			throw IllegalStateException("Could not commit migrated recording schedules")
		}
	}

	private fun toJson(s: RecordingSchedule): JSONObject = JSONObject().apply {
		put("channelName", s.channelName)
		if (s.sealedExecutionPayload == null) {
			put("url", s.url)
			put("headers", JSONObject(s.headers as Map<String, Any?>))
		} else {
			put("sealedExecutionPayload", s.sealedExecutionPayload)
		}
		put("startMs", s.startMs)
		put("endMs", s.endMs)
		put("programmeTitle", s.programmeTitle)
		put("createdAt", s.createdAt)
		put("ownerProfileId", s.ownerProfileId)
		s.connectionResourceId?.let { put("connectionResourceId", it) }
		put("profileAuthorizationRevision", s.profileAuthorizationRevision)
		s.resourceAuthorizationRevision?.let { put("resourceAuthorizationRevision", it) }
	}

	private fun fromJson(context: Context, id: String, o: JSONObject): RecordingSchedule {
		val owner = o.optString("ownerProfileId", "legacy-admin-v1")
		val revision = o.optLong("profileAuthorizationRevision", 1L)
		val sealed = o.optString("sealedExecutionPayload", "").takeIf { it.isNotEmpty() }
		val execution = if (sealed == null) o else JSONObject(
			DeviceSecretCipherPlugin.openForNative(
				sealed,
				executionAad(id, owner, revision).toByteArray(Charsets.UTF_8),
			).toString(Charsets.UTF_8),
		)
		val headers = HashMap<String, String>()
		execution.optJSONObject("headers")?.let { h ->
			h.keys().forEach { k -> headers[k] = h.optString(k, "") }
		}
		return RecordingSchedule(
			id = id,
			channelName = o.optString("channelName", ""),
			url = execution.optString("url", ""),
			headers = headers,
			startMs = o.optLong("startMs", 0L),
			endMs = o.optLong("endMs", 0L),
			programmeTitle = o.optString("programmeTitle", ""),
			createdAt = o.optLong("createdAt", 0L),
			ownerProfileId = owner,
			connectionResourceId = o.optString("connectionResourceId", "")
				.takeIf { it.isNotEmpty() && it != "null" },
			profileAuthorizationRevision = revision,
			resourceAuthorizationRevision = if (o.has("resourceAuthorizationRevision"))
				o.optLong("resourceAuthorizationRevision") else null,
			sealedExecutionPayload = sealed,
		)
	}

	private fun fromJsonWithoutExecution(id: String, o: JSONObject): RecordingSchedule =
		RecordingSchedule(
			id = id,
			channelName = o.optString("channelName", ""),
			url = "",
			headers = hashMapOf(),
			startMs = o.optLong("startMs", 0L),
			endMs = o.optLong("endMs", 0L),
			programmeTitle = o.optString("programmeTitle", ""),
			createdAt = o.optLong("createdAt", 0L),
			ownerProfileId = o.optString("ownerProfileId", "legacy-admin-v1"),
			connectionResourceId = o.optString("connectionResourceId", "")
				.takeIf { it.isNotEmpty() && it != "null" },
			profileAuthorizationRevision = o.optLong("profileAuthorizationRevision", 1L),
			resourceAuthorizationRevision = if (o.has("resourceAuthorizationRevision"))
				o.optLong("resourceAuthorizationRevision") else null,
			sealedExecutionPayload = o.optString("sealedExecutionPayload", "")
				.takeIf { it.isNotEmpty() },
		)

	fun sealExecutionPayload(
		id: String,
		ownerProfileId: String,
		profileAuthorizationRevision: Long,
		url: String,
		headers: Map<String, String>,
	): String = DeviceSecretCipherPlugin.sealForNative(
		JSONObject().apply {
			put("url", url)
			put("headers", JSONObject(headers as Map<String, Any?>))
		}.toString().toByteArray(Charsets.UTF_8),
		executionAad(id, ownerProfileId, profileAuthorizationRevision)
			.toByteArray(Charsets.UTF_8),
	)

	private fun executionAad(id: String, owner: String, revision: Long) =
		"debrify-android-schedule-v1|id=$id|owner=$owner|revision=$revision"
}
