package com.debrify.app.recording

import android.content.Context
import org.json.JSONObject

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
)

object RecordingScheduleStore {
	private const val PREFS = "debrify_recording_schedules"
	private const val KEY = "schedules_v1"
	private val lock = Any()

	fun get(context: Context, id: String): RecordingSchedule? = all(context)[id]

	fun put(context: Context, schedule: RecordingSchedule) {
		synchronized(lock) {
			val map = loadJson(context)
			map.put(schedule.id, toJson(schedule))
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
				try {
					out[id] = fromJson(id, map.getJSONObject(id))
				} catch (_: Exception) {
					// Corrupt entry: drop rather than poison every query.
				}
			}
			return out
		}
	}

	/** An existing schedule for the same channel-url + start time, if any —
	 *  the UI warns instead of silently double-recording one programme. */
	fun findDuplicate(context: Context, url: String, startMs: Long): RecordingSchedule? =
		all(context).values.firstOrNull { it.url == url && it.startMs == startMs }

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

	private fun toJson(s: RecordingSchedule): JSONObject = JSONObject().apply {
		put("channelName", s.channelName)
		put("url", s.url)
		put("headers", JSONObject(s.headers as Map<String, Any?>))
		put("startMs", s.startMs)
		put("endMs", s.endMs)
		put("programmeTitle", s.programmeTitle)
		put("createdAt", s.createdAt)
	}

	private fun fromJson(id: String, o: JSONObject): RecordingSchedule {
		val headers = HashMap<String, String>()
		o.optJSONObject("headers")?.let { h ->
			h.keys().forEach { k -> headers[k] = h.optString(k, "") }
		}
		return RecordingSchedule(
			id = id,
			channelName = o.optString("channelName", ""),
			url = o.optString("url", ""),
			headers = headers,
			startMs = o.optLong("startMs", 0L),
			endMs = o.optLong("endMs", 0L),
			programmeTitle = o.optString("programmeTitle", ""),
			createdAt = o.optLong("createdAt", 0L),
		)
	}
}
