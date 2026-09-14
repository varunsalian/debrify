package com.debrify.app.tv

/**
 * Process-lifetime proof that a new Flutter host is the return target of the
 * native player, rather than a cold app launch.
 *
 * Deliberately never persisted: a process restart must land on the normal
 * profile gate. A pending handoff is one-shot and short-lived so it cannot
 * become a general profile-unlock token.
 */
internal class PlaybackReturnLedger(
    private val nowMs: () -> Long,
    private val ttlMs: Long = 120_000L,
) {
    private data class Session(
        val id: Int,
        val profileId: String,
        val dataGeneration: Int,
        val pendingSinceMs: Long?,
    )

    private var session: Session? = null

    @Synchronized
    fun begin(id: Int, profileId: String, dataGeneration: Int) {
        session = if (id > 0 && profileId.isNotBlank() && dataGeneration > 0) {
            Session(id, profileId, dataGeneration, null)
        } else {
            null
        }
    }

    @Synchronized
    fun markReturning(id: Int) {
        val current = session ?: return
        if (current.id != id) return
        session = current.copy(pendingSinceMs = nowMs())
    }

    @Synchronized
    fun consumeSession(profileId: String, dataGeneration: Int): Int? {
        val current = session ?: return null
        val pendingAt = current.pendingSinceMs ?: return null
        val age = nowMs() - pendingAt
        val valid = age in 0..ttlMs &&
            current.profileId == profileId &&
            current.dataGeneration == dataGeneration
        // A claim is one-shot even when its caller supplied the wrong owner.
        // The active registry profile is authoritative; retaining a mismatched
        // token for a later switch would turn it into a delayed unlock.
        session = null
        return if (valid) current.id else null
    }

    fun consume(profileId: String, dataGeneration: Int): Boolean =
        consumeSession(profileId, dataGeneration) != null

    @Synchronized
    fun cancel(id: Int) {
        if (session?.id == id) session = null
    }
}

object PlaybackReturnHandoff {
    private val ledger = PlaybackReturnLedger(
        nowMs = { android.os.SystemClock.elapsedRealtime() },
    )

    fun begin(id: Int, profileId: String, dataGeneration: Int) =
        ledger.begin(id, profileId, dataGeneration)

    fun markReturning(id: Int) = ledger.markReturning(id)

    fun consume(profileId: String, dataGeneration: Int): Boolean =
        ledger.consume(profileId, dataGeneration)

    fun consumeSession(profileId: String, dataGeneration: Int): Int? =
        ledger.consumeSession(profileId, dataGeneration)

    fun cancel(id: Int) = ledger.cancel(id)
}
