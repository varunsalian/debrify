package com.debrify.app.tv

/** Configuration is independent of whether this particular source matched.
 * A null badge list is unresolved and must remain retryable. */
data class TvSourceBadgeResult(
    val configured: Boolean,
    val badges: List<Map<*, *>>?,
) {
    companion object {
        fun parse(raw: Any?): TvSourceBadgeResult? {
            val map = raw as? Map<*, *> ?: return null
            val configured = map["configured"] as? Boolean ?: return null
            val badges = map["badges"]
            if (badges != null && (badges !is List<*> || badges.any { it !is Map<*, *> })) return null
            return TvSourceBadgeResult(configured, (badges as? List<*>)?.filterIsInstance<Map<*, *>>())
        }
    }
}
