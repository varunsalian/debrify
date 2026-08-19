package com.debrify.app.profiles

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/** Atomic, read-only native view of the active Flutter profile. */
object ProfilePreferenceProjection {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val MODE_KEY = "flutter.profiles_runtime_mode_v1"
    private const val PROJECTION_KEY = "flutter.profiles_native_projection_v1"
    private const val PROJECTION_SEQUENCE_KEY = "flutter.profiles_native_projection_sequence_v1"

    private fun flutterPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    private fun root(context: Context): JSONObject? {
        val prefs = flutterPrefs(context)
        if (prefs.getString(MODE_KEY, null) != "profileCommitted") return null
        return runCatching {
            val root = JSONObject(prefs.getString(PROJECTION_KEY, null) ?: return null)
            val sequence = prefs.getLong(PROJECTION_SEQUENCE_KEY, -1L)
            if (root.optInt("version") != 2 ||
                root.optString("state") != "active" ||
                root.optLong("publication", -2L) != sequence ||
                sequence < 1L ||
                root.optString("profileId").isBlank()) null
            else root
        }.getOrNull()
    }

    private fun projection(context: Context): JSONObject? = root(context)?.optJSONObject("values")

    private fun committed(context: Context): Boolean =
        flutterPrefs(context).getString(MODE_KEY, null) == "profileCommitted"

    @JvmStatic
    fun isCommitted(context: Context): Boolean = committed(context)

    data class JobContext(
        val profileId: String,
        val dataGeneration: Long,
        val sessionEpoch: Long,
        val authorizationRevision: Long,
    )

    /** Legacy records are deterministically assigned to the migrated Admin. */
    @JvmStatic
    fun activeJobContext(context: Context): JobContext {
        val root = root(context)
        if (root == null) {
            if (committed(context)) return JobContext("projection-unavailable", -1L, -1L, -1L)
            return JobContext("legacy-admin-v1", 1L, 0L, 1L)
        }
        val profileId = root.optString("profileId", "legacy-admin-v1")
        val auth = root.optJSONObject("authorization")?.optJSONObject(profileId)
        return JobContext(
            profileId,
            root.optLong("dataGeneration", 1L),
            root.optLong("sessionEpoch", 0L),
            auth?.optLong("revision", 1L) ?: 1L,
        )
    }

    @JvmStatic
    @JvmOverloads
    fun authorizationValid(
        context: Context,
        profileId: String,
        revision: Long,
        requiredFeature: String,
        allowRevisionDrift: Boolean = false,
    ): Boolean {
        val root = root(context)
            ?: return !committed(context) && profileId == "legacy-admin-v1"
        val auth = root.optJSONObject("authorization")?.optJSONObject(profileId) ?: return false
        if (!auth.optBoolean("enabled", false)) return false
        if (!allowRevisionDrift && auth.optLong("revision", -1L) != revision) return false
        val features = auth.optJSONArray("features") ?: return false
        for (index in 0 until features.length()) {
            if (features.optString(index) == requiredFeature) return true
        }
        return false
    }

    /** Full durable-job authority. A job that names a connection resource is
     * valid only while that grant remains in the atomically published
     * projection.
     *
     * [allowRevisionDrift] is for jobs REPLAYED from durable stores (a queued
     * download's state, a recording schedule fired by an alarm). Every
     * connection-collection save bumps every retained resource's revision AND
     * the owner profile's, so revisions stamped into such a job go stale on
     * any unrelated source edit — strict equality there silently killed every
     * pending job. With drift the stored revisions are provenance only; the
     * live projection gates (profile enabled + feature, resource granted with
     * the required permission) still refuse delete/disable/revoke/feature-off.
     * Known trade-off: a secret rotation is indistinguishable from a
     * collection save here, so rotation alone no longer kills pending jobs.
     * Callers checking values they JUST captured keep the default. */
    @JvmStatic
    @JvmOverloads
    fun jobAuthorizationValid(
        context: Context,
        profileId: String,
        revision: Long,
        requiredFeature: String,
        resourceId: String?,
        resourceRevision: Long?,
        requiredResourcePermission: Int = 2,
        allowRevisionDrift: Boolean = false,
    ): Boolean {
        if (!authorizationValid(context, profileId, revision, requiredFeature, allowRevisionDrift)) return false
        if (resourceId == null) return resourceRevision == null
        if (resourceRevision == null) return false
        val auth = root(context)
            ?.optJSONObject("authorization")
            ?.optJSONObject(profileId)
            ?: return false
        val resources = auth.optJSONObject("resources") ?: return false
        val authority = resources.optJSONObject(resourceId) ?: return false
        if (!allowRevisionDrift && authority.optLong("revision", -1L) != resourceRevision) return false
        return (authority.optInt("permissions", 0) and requiredResourcePermission) == requiredResourcePermission
    }

    @JvmStatic
    fun getBoolean(context: Context, logicalKey: String, fallback: Boolean): Boolean {
        val values = projection(context)
        return if (values != null && values.has(logicalKey)) {
            values.optBoolean(logicalKey, fallback)
        } else if (!committed(context)) {
            try {
                flutterPrefs(context).getBoolean("flutter.$logicalKey", fallback)
            } catch (_: ClassCastException) {
                // A writer stored a different type under this key (the getLong
                // guard below exists for the same reason). A wrong type has no
                // boolean reading — fall back rather than crash the caller.
                fallback
            }
        } else fallback
    }

    @JvmStatic
	fun getLong(context: Context, logicalKey: String, fallback: Long): Long {
        val values = projection(context)
        return if (values != null && values.has(logicalKey)) {
            values.optLong(logicalKey, fallback)
		} else if (!committed(context)) {
			try {
				flutterPrefs(context).getLong("flutter.$logicalKey", fallback)
			} catch (_: ClassCastException) {
				// Very old native writers stored a Java Int while Flutter stores
				// Dart ints as Long. Preserve that setting across the upgrade.
				(flutterPrefs(context).all["flutter.$logicalKey"] as? Number)
					?.toLong() ?: fallback
			}
        } else fallback
    }

    @JvmStatic
    fun getString(context: Context, logicalKey: String, fallback: String?): String? {
        val values = projection(context)
        return if (values != null && values.has(logicalKey) && !values.isNull(logicalKey)) {
            values.opt(logicalKey) as? String ?: fallback
        } else if (!committed(context)) {
            try {
                flutterPrefs(context).getString("flutter.$logicalKey", fallback)
            } catch (_: ClassCastException) {
                // Same as getBoolean/getLong: a mistyped value must degrade to
                // the fallback, not crash whichever native reader asked.
                fallback
            }
        } else fallback
    }

    /** Explicit read for registered device-owned settings. Unlike profile
     * values, these remain available while the active projection is denied. */
    @JvmStatic
    fun getDeviceLong(context: Context, logicalKey: String, fallback: Long): Long {
        val prefs = flutterPrefs(context)
        return try {
            prefs.getLong("flutter.$logicalKey", fallback)
        } catch (_: ClassCastException) {
            (prefs.all["flutter.$logicalKey"] as? Number)?.toLong() ?: fallback
        }
    }

    /** Native-only settings use one file per opaque profile ID. */
    @JvmStatic
    fun scopedPreferences(context: Context, legacyName: String): SharedPreferences {
        val prefs = flutterPrefs(context)
        val root = root(context)
        val profileId = if (prefs.getString(MODE_KEY, null) == "profileCommitted") {
            root?.optString("profileId")?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,96}")) }
        } else null
        val name = if (profileId == null && !committed(context)) {
            legacyName
        } else {
            "$legacyName.profile.${profileId ?: "projection-unavailable"}"
        }
        return context.getSharedPreferences(name, Context.MODE_PRIVATE)
    }
}
