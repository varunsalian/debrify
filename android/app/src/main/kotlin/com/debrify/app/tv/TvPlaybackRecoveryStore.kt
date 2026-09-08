package com.debrify.app.tv

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ThreadLocalRandom

/** App-private journal. Completions survive auto-advance and later launches. */
object TvPlaybackRecoveryStore {
    private const val FILE_NAME = "tv_playback_recovery.json"
    private const val TEMP_NAME = "tv_playback_recovery.json.tmp"
    private const val MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000L
    // Outlives both activities: Dart can ACK after the player's onDestroy.
    private val writer = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "debrify-tv-progress").apply { isDaemon = true }
    }
    // Random process seed also avoids old on-disk IDs if that file cannot be
    // read. Continue monotonically so host recreation never resets allocation.
    private var nextSessionId = ThreadLocalRandom.current().nextInt(1, Int.MAX_VALUE)
    private var activeSessionId = 0
    private val completedItems = mutableSetOf<String>()
    private var highestSequence = 0L
    private data class FileStamp(val isFile: Boolean, val exists: Boolean, val size: Long, val modified: Long)
    private var cachedPath: String? = null
    private var cachedStamp: FileStamp? = null
    // Published journals/records are immutable. Mutations use fresh arrays and
    // only replace this snapshot after the atomic file replacement succeeds.
    private var cachedJournal: JSONObject? = null
    private var cacheNeedsSave = false
    internal var diskReadCount = 0L
        private set
    internal var diskSyncCount = 0L
        private set

    /** Simulates a cold reader in tests without resetting session fencing. */
    @Synchronized
    internal fun clearMemoryCache() {
        cachedPath = null
        cachedStamp = null
        cachedJournal = null
        cacheNeedsSave = false
    }

    @Synchronized
    fun allocateSessionId(filesDir: File, onReadFailure: (Throwable) -> Unit = {}): Int {
        val journal = runCatching { load(filesDir) }.getOrElse {
            runCatching { onReadFailure(it) }
            emptyJournal() // Recovery bookkeeping must not prevent playback.
        }
        val retainedIds = records(journal).map { it.optInt("sessionId") }.toSet()
        do {
            nextSessionId = if (nextSessionId == Int.MAX_VALUE) 1 else nextSessionId + 1
        } while (nextSessionId in retainedIds)
        return nextSessionId
    }

    @Synchronized
    fun begin(filesDir: File, sessionId: Int) {
        activeSessionId = sessionId
        highestSequence = 0L
        completedItems.clear()
        // Only age out expired data. Failed recovery still needs its next retry.
        runCatching {
            val journal = load(filesDir)
            if (cacheNeedsSave) save(filesDir, journal)
        }
    }

    fun stageAsync(filesDir: File, encoded: String) =
        writer.submit { stage(filesDir, encoded) }

    fun acknowledgeAsync(filesDir: File, sessionId: Int, sequence: Long) =
        writer.submit { acknowledge(filesDir, sessionId, sequence) }

    @Synchronized
    fun stage(filesDir: File, encoded: String) {
        val incoming = runCatching { JSONObject(encoded) }.getOrNull() ?: return
        val session = incoming.optInt("sessionId")
        val sequence = incoming.optLong("sequence")
        if (session != activeSessionId || !isValidRecord(incoming, System.currentTimeMillis())) return

        val journal = runCatching { copyJournal(load(filesDir)) }.getOrNull() ?: return
        val completion = isCompletion(incoming)
        // Completion edges are synchronous, before auto-advance. Once ACKed,
        // cumulative flags on later ticks must not recreate that event.
        val newCompletion = completion && itemKey(incoming) !in completedItems
        if (!newCompletion && sequence <= highestSequence) return
        if (newCompletion) {
            journal.getJSONArray("completions").put(incoming)
        }
        if (sequence > highestSequence) {
            journal.put("latest", filter(journal.getJSONArray("latest")) {
                it.optInt("sessionId") != session
            })
            if (!completion) journal.getJSONArray("latest").put(incoming)
        }
        if (save(filesDir, journal)) {
            highestSequence = maxOf(highestSequence, sequence)
            if (newCompletion) completedItems.add(itemKey(incoming))
        }
    }

    @Synchronized
    fun read(filesDir: File): String? {
        val journal = runCatching { load(filesDir) }.getOrNull() ?: return null
        if (cacheNeedsSave) save(filesDir, journal) // normalize only once
        return if (records(journal).isEmpty()) null else journal.toString()
    }

    /** ACK exactly one applied event, never a different episode or session. */
    @Synchronized
    fun acknowledge(filesDir: File, sessionId: Int, sequence: Long): Boolean {
        val journal = runCatching { copyJournal(load(filesDir)) }.getOrNull() ?: return false
        var removed = false
        for (field in listOf("completions", "latest")) {
            journal.put(field, filter(journal.getJSONArray(field)) {
                val matches = it.optInt("sessionId") == sessionId && it.optLong("sequence") == sequence
                if (matches) removed = true
                !matches
            })
        }
        if (!removed && !cacheNeedsSave) return true
        // The ordinary ACK deletes the last record without a rewrite/fsync.
        // If other records remain, their replacement still needs fsync: an
        // atomic rename alone could lose those unACKed observations on power
        // failure, not merely replay the record being acknowledged.
        return save(filesDir, journal)
    }

    /** Compare-and-delete prevents a malformed read from clearing a newer write. */
    @Synchronized
    fun discard(filesDir: File, encoded: String): Boolean {
        val target = File(filesDir, FILE_NAME)
        val discarded = runCatching {
            !target.exists() || (target.readText() == encoded && target.delete())
        }.getOrDefault(false)
        if (discarded) clearMemoryCache()
        return discarded
    }

    private fun emptyJournal() = JSONObject().put("version", 2)
        .put("completions", JSONArray()).put("latest", JSONArray())

    private fun copyJournal(journal: JSONObject) = emptyJournal().apply {
        for (field in listOf("completions", "latest")) {
            put(field, filter(journal.getJSONArray(field)) { true })
        }
    }

    private fun stamp(file: File) = FileStamp(file.isFile, file.exists(), file.length(), file.lastModified())

    private fun load(filesDir: File): JSONObject {
        val target = File(filesDir, FILE_NAME)
        val currentStamp = stamp(target)
        val cached = cachedJournal
        val now = System.currentTimeMillis()
        if (cached != null && cachedPath == target.absolutePath && cachedStamp == currentStamp) {
            // A long-running process must still expire cached checkpoints.
            if (records(cached).all { now - it.optLong("updatedAtMs") in 0..MAX_AGE_MS }) {
                return cached
            }
            val pruned = copyJournal(cached)
            for (field in listOf("completions", "latest")) {
                pruned.put(field, filter(pruned.getJSONArray(field)) {
                    now - it.optLong("updatedAtMs") in 0..MAX_AGE_MS
                })
            }
            cachedJournal = pruned
            cacheNeedsSave = true
            return pruned
        }
        // I/O failure is retryable, not evidence that a journal is malformed.
        val encoded = if (currentStamp.exists) {
            diskReadCount++
            target.readText()
        } else null
        val source = encoded?.let { runCatching { JSONObject(it) }.getOrNull() }
        val result = emptyJournal()
        fun add(record: JSONObject) {
            if (!isValidRecord(record, now)) return
            result.getJSONArray(if (isCompletion(record)) "completions" else "latest").put(record)
        }
        if (source?.optInt("version") == 1) add(source)
        else if (source?.optInt("version") == 2) records(source).forEach(::add)
        cachedPath = target.absolutePath
        cachedStamp = currentStamp
        cachedJournal = result
        cacheNeedsSave = encoded != null &&
            (records(result).isEmpty() || source?.toString() != result.toString())
        return result
    }

    private fun isValidRecord(record: JSONObject, now: Long): Boolean =
        record.optInt("sessionId") > 0 && record.optLong("sequence") > 0 &&
            record.nullableString("profileId").let { it != null && it != "null" } &&
            record.optInt("dataGeneration") > 0 &&
            now - record.optLong("updatedAtMs") in 0..MAX_AGE_MS &&
            record.optString("mode") != "iptv" &&
            (!record.has("speed") || record.opt("speed") is Number) &&
            record.optString("contentType") in setOf("single", "series", "collection")

    private fun records(journal: JSONObject): List<JSONObject> =
        listOf("completions", "latest").flatMap { field ->
            val array = journal.optJSONArray(field) ?: JSONArray()
            (0 until array.length()).mapNotNull { array.optJSONObject(it) }
        }

    private fun filter(array: JSONArray, keep: (JSONObject) -> Boolean): JSONArray {
        val result = JSONArray()
        for (index in 0 until array.length()) {
            array.optJSONObject(index)?.let { if (keep(it)) result.put(it) }
        }
        return result
    }

    private fun itemKey(record: JSONObject): String = JSONArray().apply {
        put(record.optInt("sessionId"))
        put(record.optString("contentType"))
        put(record.optString("seriesTitle"))
        put(record.optString("resumeId"))
        put(record.optInt("season", -1))
        put(record.optInt("episode", -1))
        put(record.optInt("itemIndex"))
    }.toString()

    private fun isCompletion(record: JSONObject): Boolean {
        val completed = record.optBoolean("completed") || record.optBoolean("completionReached")
        val local = record.optBoolean("localCompleted") || record.optBoolean("localCompletionEligible") ||
            record.optBoolean("localCompletionReached")
        return when (record.optString("contentType")) {
            "series" -> completed || local
            "collection" -> completed
            "single" -> record.optBoolean("localCompletionTracking") &&
                record.nullableString("imdbId").let { it != null && it != "null" } && (completed || local)
            else -> false
        }
    }

    private fun save(filesDir: File, journal: JSONObject): Boolean {
        val target = File(filesDir, FILE_NAME)
        val temp = File(filesDir, TEMP_NAME)
        val saved = if (records(journal).isEmpty()) {
            temp.delete()
            target.delete() || !target.exists()
        } else runCatching {
            temp.outputStream().use { stream ->
                stream.write(journal.toString().toByteArray(Charsets.UTF_8))
                stream.fd.sync()
                diskSyncCount++
            }
            // Android/Linux rename atomically replaces the destination. Keep
            // the last good journal if its replacement fails.
            check(temp.renameTo(target)) { "checkpoint rename failed" }
            true
        }.getOrElse { temp.delete(); false }
        if (saved) {
            cachedPath = target.absolutePath
            cachedStamp = stamp(target)
            cachedJournal = journal
            cacheNeedsSave = false
        }
        return saved
    }
}
