package com.debrify.app.recording

import android.content.Context
import com.debrify.app.profiles.ProfilePreferenceProjection
import org.json.JSONObject

/**
 * The device-wide "where and how long" recording settings Dart writes as the
 * JSON string `recording_output_v1` (see RecordingOutputSettings in
 * lib/features/recordings/models). Missing or malformed values fall back to
 * the behaviour before the setting existed: the default folder, no start pad
 * and a two-minute end pad.
 */
data class RecordingOutputPrefs(
	val treeUri: String?,
	val startPadMs: Long,
	val endPadMs: Long,
) {
	companion object {
		const val KEY = "recording_output_v1"
		private const val MAX_PAD_MINUTES = 15L
		private const val DEFAULT_END_PAD_MINUTES = 2L

		fun read(context: Context): RecordingOutputPrefs =
			parse(ProfilePreferenceProjection.getDeviceString(context, KEY))

		/** Pure parsing, separate from storage so it can be unit tested. */
		fun parse(raw: String?): RecordingOutputPrefs {
			val json = try {
				if (raw.isNullOrBlank()) null else JSONObject(raw)
			} catch (_: Exception) {
				null
			}
			val tree = json?.optString("treeUri")?.trim()?.takeIf { it.isNotEmpty() }
			return RecordingOutputPrefs(
				treeUri = tree,
				startPadMs = minutes(json, "startPadMinutes", 0L),
				endPadMs = minutes(json, "endPadMinutes", DEFAULT_END_PAD_MINUTES),
			)
		}

		private fun minutes(json: JSONObject?, name: String, fallback: Long): Long {
			val value = if (json != null && json.has(name) && !json.isNull(name)) {
				json.optLong(name, fallback)
			} else {
				fallback
			}
			return value.coerceIn(0L, MAX_PAD_MINUTES) * 60_000L
		}
	}
}
