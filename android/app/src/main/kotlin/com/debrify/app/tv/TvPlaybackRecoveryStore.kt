package com.debrify.app.tv

import org.json.JSONObject
import java.io.File

/** App-private, atomic last-position checkpoint for native TV playback. */
object TvPlaybackRecoveryStore {
    private const val FILE_NAME = "tv_playback_recovery.json"
    private const val TEMP_NAME = "tv_playback_recovery.json.tmp"

    @Synchronized
    fun begin(filesDir: File) {
        File(filesDir, FILE_NAME).delete()
        File(filesDir, TEMP_NAME).delete()
    }

    /** Older queued writes may arrive after the synchronous exit checkpoint. */
    @Synchronized
    fun stage(filesDir: File, encoded: String) {
        val incoming = runCatching { JSONObject(encoded) }.getOrNull() ?: return
        val session = incoming.optInt("sessionId", 0)
        val sequence = incoming.optLong("sequence", 0L)
        if (session <= 0 || sequence <= 0L) return

        val target = File(filesDir, FILE_NAME)
        val current = readObject(target)
        if (current != null &&
            current.optInt("sessionId", 0) == session &&
            current.optLong("sequence", 0L) > sequence
        ) {
            return
        }

        val temp = File(filesDir, TEMP_NAME)
        runCatching {
            temp.writeText(encoded)
            if (!temp.renameTo(target)) {
                target.delete()
                if (!temp.renameTo(target)) throw IllegalStateException("checkpoint rename failed")
            }
        }.onFailure { temp.delete() }
    }

    @Synchronized
    fun read(filesDir: File): String? {
        val target = File(filesDir, FILE_NAME)
        return runCatching {
            val text = target.readText()
            JSONObject(text) // validate before crossing the channel
            text
        }.getOrNull()
    }

    /** Delete only the checkpoint whose successful Dart write is being ACKed. */
    @Synchronized
    fun acknowledge(filesDir: File, sessionId: Int, sequence: Long): Boolean {
        val target = File(filesDir, FILE_NAME)
        val current = readObject(target) ?: return true
        if (current.optInt("sessionId", 0) != sessionId ||
            current.optLong("sequence", 0L) != sequence
        ) {
            return false
        }
        val deleted = target.delete() || !target.exists()
        File(filesDir, TEMP_NAME).delete()
        return deleted
    }

    private fun readObject(file: File): JSONObject? = runCatching {
        if (!file.exists()) null else JSONObject(file.readText())
    }.getOrNull()
}
