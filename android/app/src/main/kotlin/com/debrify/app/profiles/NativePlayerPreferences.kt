package com.debrify.app.profiles

import android.content.Context
import android.content.Intent
import org.json.JSONObject

/** Non-secret defaults frozen for one player route; never an authorization capability. */
class NativePlayerPreferences private constructor(private val values: JSONObject) {
    fun getString(key: String, fallback: String?): String? = values.opt(key) as? String ?: fallback
    fun getLong(key: String, fallback: Long): Long = (values.opt(key) as? Number)?.toLong() ?: fallback
    fun getBoolean(key: String, fallback: Boolean): Boolean = values.opt(key) as? Boolean ?: fallback

    companion object {
        const val EXTRA = "debrify.playerPreferences"
        private val ownerKeys = listOf("profileId", "dataGeneration", "sessionEpoch")
        // Never copy addon JSON, credentials, grants or authorization revisions
        // into an Intent. Those consumers continue using the live projection.
        private val keys = listOf(
            "tv_player_controls_style", "debrify_tv_player_style", "iptv_player_guide_style",
            "player_default_subtitle_language", "player_default_audio_language",
            "subtitle_only_foreign_audio",
            "subtitle_forced_only",
            "player_default_aspect_index_tv", "player_night_mode_index",
            "player_system_audio_effects", "content_display_match_mode",
            "skip_segments_enabled", "skip_segment_provider",
        )

        @JvmStatic
        fun captureForLaunch(context: Context, expectedOwner: Map<*, *>?): String {
            val committed = ProfilePreferenceProjection.isCommitted(context)
            val root = if (committed) ProfilePreferenceProjection.activeSnapshot(context) else null
            if (committed && (root == null || expectedOwner == null ||
                    root.optJSONObject("values") == null ||
                    ownerKeys.any { root.opt(it)?.toString() != expectedOwner[it]?.toString() } ||
                    ProfilePrivacyState.isSensitive(context))) {
                throw IllegalStateException("Player profile settings are not ready")
            }
            if (!committed && expectedOwner != null) {
                throw IllegalStateException("Player profile changed before launch")
            }
            val legacy = if (!committed) context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE,
            ).all else emptyMap<String, Any?>()
            val source = root?.optJSONObject("values")
            val values = JSONObject()
            for (key in keys) {
                val value = if (committed) source?.opt(key) else legacy["flutter.$key"]
                if (value is String || value is Number || value is Boolean) values.put(key, value)
            }
            val snapshot = JSONObject().put("committed", committed).put("values", values)
            if (committed) for (key in ownerKeys) snapshot.put(key, root!!.get(key))
            return snapshot.toString()
        }

        @JvmStatic
        fun fromIntent(context: Context, intent: Intent): NativePlayerPreferences {
            val raw = intent.getStringExtra(EXTRA)
                ?: captureForLaunch(context, null) // legacy callers only
            val snapshot = JSONObject(raw)
            val committed = ProfilePreferenceProjection.isCommitted(context)
            check(snapshot.optBoolean("committed") == committed) { "Player profile changed" }
            if (committed) {
                val root = ProfilePreferenceProjection.activeSnapshot(context)
                check(root != null && !ProfilePrivacyState.isSensitive(context) &&
                    ownerKeys.all { snapshot.opt(it) == root.opt(it) }) {
                    "Player profile changed or locked during launch"
                }
            }
            return NativePlayerPreferences(snapshot.getJSONObject("values"))
        }
    }
}
