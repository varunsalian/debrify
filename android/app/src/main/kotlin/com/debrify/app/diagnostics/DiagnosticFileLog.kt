package com.debrify.app.diagnostics

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Small native companion to Dart's rolling diagnostics store.
 *
 * Android TV playback lives in a native Activity, so a Dart-only sink misses
 * the exact interval between launching ExoPlayer and the process disappearing.
 * Native and Dart use separate segment files to avoid concurrent append races;
 * the Dart exporter merges both JSONL streams by timestamp.
 */
object DiagnosticFileLog {
    private const val FILE_PREFIX = "debrify-diagnostics-"
    private const val FILE_SUFFIX = ".jsonl"
    private const val RETENTION_MS = 2L * 60L * 60L * 1_000L
    private const val SEGMENT_MS = 15L * 60L * 1_000L
    private const val MAX_SEGMENT_BYTES = 256L * 1_024L
    private const val PREFS_NAME = "debrify_diagnostics"
    private const val LAST_EXIT_TIMESTAMP = "last_exit_timestamp"

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "debrify-diagnostics").apply { isDaemon = true }
    }
    private val initialized = AtomicBoolean(false)
    private val crashHandlerInstalled = AtomicBoolean(false)
    private val fileLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var applicationContext: Context? = null

    @Volatile
    private var accepting = false

    @Volatile
    private var lastPrunedSegment = Long.MIN_VALUE

    // Write-failure visibility. Every sink in this class swallows Throwable by
    // design (diagnostics must never break the app), which made real write
    // failures indistinguishable from silence: a launch whose init event never
    // landed exported as an empty gap (field report 2026-09-03, Bravia
    // Android 14 — no `native_diagnostics_initialized`, no `previous_exit`,
    // while writes seconds later succeeded). Count the drops and surface them
    // on the next append that works, so the NEXT export shows the hole.
    private val droppedWrites = AtomicInteger(0)

    @Volatile
    private var lastDropCause: String = "unknown"

    // Fallback stamp for the crash handler's minimal write: the exporter
    // discards records whose timestamp does not parse or falls outside the
    // window, so a slightly stale-but-valid stamp beats a fresh one the
    // formatter failed to produce under memory pressure.
    @Volatile
    private var lastIsoTimestamp: String = ""

    // Compiled once. The crash handler runs these under memory pressure, and
    // per-call Regex construction was an allocation the emergency path could
    // not afford; ordinary appends paid for it on every record too.
    private val safeLabelRegex = Regex("[^a-zA-Z0-9_.-]")
    private val redactUrlRegex =
        Regex("(?i)\\b(?:https?|magnet|stremio-addon):[^\\s'\\\")]+")
    private val redactAddressRegex =
        Regex("\\b(?:\\d{1,3}\\.){3}\\d{1,3}(?::\\d+)?\\b")
    private val redactBearerRegex = Regex("(?i)\\bbearer\\s+[^,;\\s)\\]}]+")
    private val redactSecretRegex = Regex(
        "(?i)\\b(?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|" +
            "password|authorization|bearer|secret|payload|headers?|body)" +
            "\\b\\s*[:=]\\s*[^,;\\s)]+",
    )

    // SimpleDateFormat is not thread-safe; every use stays under [fileLock].
    private val isoFormatter =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    fun initialize(context: Context) {
        if (!initialized.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        applicationContext = appContext
        accepting = true
        installCrashHandler(appContext)
        executor.execute {
            if (!accepting) return@execute
            // The init event goes FIRST: pruning used to run before it, so any
            // failure there silently ate the one record that identifies the
            // device — and append() prunes newly-touched segments itself.
            val memory = try {
                val activityManager =
                    appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val info = ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(info)
                "totalMemMb=${info.totalMem / (1024L * 1024L)} " +
                    "lowRamDevice=${activityManager.isLowRamDevice}"
            } catch (_: Throwable) {
                "totalMemMb=unknown"
            }
            append(
                context = appContext,
                source = "android",
                event = "native_diagnostics_initialized",
                message = "sdk=${Build.VERSION.SDK_INT} " +
                    "manufacturer=${safeLabel(Build.MANUFACTURER)} " +
                    "model=${safeLabel(Build.MODEL)} " +
                    "abi=${safeLabel(Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")} " +
                    memory,
                level = "info",
                timestampMs = System.currentTimeMillis(),
                fileKind = "android",
                forceSync = false,
            )
            pruneExpired(appContext, System.currentTimeMillis())
        }
    }

    fun record(
        source: String,
        event: String,
        message: String? = null,
        level: String = "info",
    ) {
        if (!accepting) return
        val context = applicationContext ?: return
        val timestamp = System.currentTimeMillis()
        executor.execute {
            if (!accepting) return@execute
            append(
                context = context,
                source = source,
                event = event,
                message = message,
                level = level,
                timestampMs = timestamp,
                fileKind = "android",
                forceSync = false,
            )
        }
    }

    fun recordError(
        source: String,
        event: String,
        throwable: Throwable,
    ) {
        val message = buildString {
            append("type=")
            append(throwable.javaClass.name)
            append(" stack=")
            append(throwable.stackTrace.take(24).joinToString(" | "))
        }
        record(source, event, message, "error")
    }

    /** Completes only after every native event queued before this call. */
    fun flush(onComplete: () -> Unit) {
        executor.execute { mainHandler.post(onComplete) }
    }

    /**
     * Permanently disables this process' writers, then clears queued/native
     * state on the same executor. The file-lock check also closes the crash
     * handler race, whose emergency write does not use the executor.
     */
    fun clearForDeviceReset(onComplete: (Boolean) -> Unit) {
        accepting = false
        val context = applicationContext
        executor.execute {
            val cleared = try {
                if (context != null) {
                    synchronized(fileLock) {
                        val directory = File(context.filesDir, "diagnostics")
                        val filesCleared = !directory.exists() || directory.deleteRecursively()
                        val preferencesCleared = context
                            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .clear()
                            .commit()
                        lastPrunedSegment = Long.MIN_VALUE
                        filesCleared && preferencesCleared
                    }
                } else {
                    true
                }
            } catch (_: Throwable) {
                false
            }
            mainHandler.post { onComplete(cleared) }
        }
    }

    /**
     * Android 11+ retains the reason the previous process disappeared. This is
     * often the only durable distinction between Java crash, native decoder
     * crash, ANR, low-memory kill, and a normal user stop.
     */
    fun recordPreviousProcessExit(context: Context) {
        if (!accepting || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val appContext = context.applicationContext
        executor.execute {
            if (accepting) recordPreviousProcessExitApi30(appContext)
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private fun recordPreviousProcessExitApi30(context: Context) {
        if (!accepting) return
        try {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val exits = activityManager.getHistoricalProcessExitReasons(
                context.packageName,
                0,
                8,
            )
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastRecorded = preferences.getLong(LAST_EXIT_TIMESTAMP, 0L)
            var newestRecorded = lastRecorded
            val pending = exits
                .filter { it.timestamp > lastRecorded }
                .sortedBy { it.timestamp }
            for (exit in pending) {
                    // Advance the watermark only past exits that actually
                    // reached the log: append() swallows failures, and a
                    // watermark stamped past an unwritten exit would filter
                    // it out of every later flush retry permanently (codex
                    // review round 1, finding 8). The throwing core makes
                    // success observable; a failed write leaves the
                    // watermark behind so the next flush retries. A failed
                    // preference commit after a successful write can at
                    // worst duplicate an entry — the survivable direction.
                    val written = try {
                        synchronized(fileLock) {
                            if (!accepting) return
                            writeRecordLocked(
                                context = context,
                                source = "android_process",
                                event = "previous_exit",
                                message = buildString {
                                    append("reason=")
                                    append(exitReason(exit.reason))
                                    append(" status=")
                                    append(exit.status)
                                    append(" importance=")
                                    append(exit.importance)
                                    append(" pssKb=")
                                    append(exit.pss)
                                    append(" rssKb=")
                                    append(exit.rss)
                                },
                                level = if (
                                    exit.reason == ApplicationExitInfo.REASON_CRASH ||
                                    exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
                                    exit.reason == ApplicationExitInfo.REASON_ANR ||
                                    exit.reason == ApplicationExitInfo.REASON_LOW_MEMORY
                                ) "warning" else "info",
                                timestampMs = exit.timestamp,
                                fileKind = "android",
                                forceSync = false,
                            )
                        }
                        true
                    } catch (failure: Throwable) {
                        droppedWrites.incrementAndGet()
                        lastDropCause = failure.javaClass.name
                        false
                    }
                    // Stop at the first failure: entries are ascending, so
                    // letting a later success advance the watermark would
                    // filter the failed one out of every retry.
                    if (!written) break
                    if (exit.timestamp > newestRecorded) {
                        newestRecorded = exit.timestamp
                    }
                }
            if (newestRecorded > lastRecorded) {
                preferences.edit().putLong(LAST_EXIT_TIMESTAMP, newestRecorded).commit()
            }
        } catch (_: Throwable) {
            // Exit-history capture is diagnostic only and must never affect launch.
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private fun exitReason(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "unknown_$reason"
    }

    private fun installCrashHandler(context: Context) {
        if (!crashHandlerInstalled.compareAndSet(false, true)) return
        val prior = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                // Two-stage write: the full record allocates freely (stack
                // join, JSON, redaction), which is exactly what an
                // OutOfMemoryError landing here may not be able to afford —
                // and an OOM is the crash this recorder most needs to keep.
                // When the full write fails, fall back to a minimal record
                // built from what is already resident.
                if (!writeCrashRecordFull(context, thread, throwable)) {
                    writeCrashRecordMinimal(context, thread, throwable)
                }
            } catch (_: Throwable) {
                // Always delegate, even if the emergency write itself failed.
            } finally {
                if (prior != null) {
                    prior.uncaughtException(thread, throwable)
                } else {
                    Process.killProcess(Process.myPid())
                    kotlin.system.exitProcess(10)
                }
            }
        }
    }

    private fun writeCrashRecordFull(
        context: Context,
        thread: Thread,
        throwable: Throwable,
    ): Boolean = try {
        // Heap occupancy at the moment of death — primitives only, and the
        // one signal that separates "heap exhausted" from every other cause
        // when ApplicationExitInfo has nothing to say.
        val runtime = Runtime.getRuntime()
        val message = buildString {
            append("thread=")
            append(safeLabel(thread.name))
            append(" type=")
            append(throwable.javaClass.name)
            append(" heapUsedKb=")
            append((runtime.totalMemory() - runtime.freeMemory()) / 1024L)
            append(" heapMaxKb=")
            append(runtime.maxMemory() / 1024L)
            append(" stack=")
            append(throwable.stackTrace.take(32).joinToString(" | "))
        }
        synchronized(fileLock) {
            if (!accepting) return true // deliberately dropped, not failed
            writeRecordLocked(
                context = context,
                source = "android_process",
                event = "uncaught_exception",
                message = message,
                level = "error",
                timestampMs = System.currentTimeMillis(),
                fileKind = "android-crash",
                forceSync = true,
            )
        }
        true
    } catch (_: Throwable) {
        false
    }

    /**
     * Last-resort crash record: no JSONObject, no regex, no string templates
     * beyond small appends — assembled from values that are already resident
     * so it can complete inside the heap headroom an OOM leaves behind. The
     * exporter requires a parseable in-window ISO timestamp, so a cached one
     * from the last ordinary append backs up the live format call.
     */
    private fun writeCrashRecordMinimal(
        context: Context,
        thread: Thread,
        throwable: Throwable,
    ) {
        try {
            val timestampMs = System.currentTimeMillis()
            val stamp = try {
                synchronized(fileLock) { isoFormatter.format(Date(timestampMs)) }
            } catch (_: Throwable) {
                lastIsoTimestamp.ifEmpty { return }
            }
            val builder = StringBuilder(256)
            builder.append("{\"timestamp\":\"").append(stamp)
            builder.append("\",\"level\":\"error\",\"source\":\"android_process\"")
            builder.append(",\"event\":\"uncaught_exception_minimal\"")
            builder.append(",\"message\":\"type=")
            appendSanitized(builder, throwable.javaClass.name)
            builder.append(" thread=")
            appendSanitized(builder, thread.name)
            builder.append("\"}\n")
            val segmentStart = timestampMs - (timestampMs % SEGMENT_MS)
            val file = File(
                File(context.filesDir, "diagnostics"),
                "$FILE_PREFIX$segmentStart-android-crash$FILE_SUFFIX",
            )
            file.parentFile?.mkdirs()
            FileOutputStream(file, true).use { output ->
                output.write(builder.toString().toByteArray(Charsets.UTF_8))
                output.fd.sync()
            }
        } catch (_: Throwable) {
            // Nothing left to try; delegation still runs.
        }
    }

    /** Character-filtered append — keeps the minimal record valid JSON without
     *  invoking the redaction regexes. */
    private fun appendSanitized(builder: StringBuilder, raw: String) {
        for (index in 0 until minOf(raw.length, 128)) {
            val char = raw[index]
            if (char.isLetterOrDigit() || char == '.' || char == '_' || char == '-' || char == '$') {
                builder.append(char)
            } else {
                builder.append('_')
            }
        }
    }

    private fun append(
        context: Context,
        source: String,
        event: String,
        message: String?,
        level: String,
        timestampMs: Long,
        fileKind: String,
        forceSync: Boolean,
    ) {
        try {
            synchronized(fileLock) {
                if (!accepting) return
                val dropped = droppedWrites.get()
                if (dropped > 0) {
                    // Surface earlier silent failures before the new record,
                    // so an export shows WHERE the log has holes instead of
                    // presenting a clean-looking gap. Subtract (not reset):
                    // failures racing in from other threads stay counted.
                    writeRecordLocked(
                        context = context,
                        source = "android",
                        event = "diagnostics_write_failed",
                        message = "dropped=$dropped lastCause=$lastDropCause",
                        level = "warning",
                        timestampMs = System.currentTimeMillis(),
                        fileKind = "android",
                        forceSync = false,
                    )
                    droppedWrites.addAndGet(-dropped)
                }
                writeRecordLocked(
                    context = context,
                    source = source,
                    event = event,
                    message = message,
                    level = level,
                    timestampMs = timestampMs,
                    fileKind = fileKind,
                    forceSync = forceSync,
                )
            }
        } catch (failure: Throwable) {
            // No logging failure may alter playback or crash delegation — but
            // it must not stay invisible either: count it for the next
            // successful append, and leave a logcat trail for adb sessions.
            droppedWrites.incrementAndGet()
            lastDropCause = failure.javaClass.name
            try {
                android.util.Log.w("DebrifyDiagnostics", "diagnostic write failed", failure)
            } catch (_: Throwable) {}
        }
    }

    /** Core record write. Caller holds [fileLock]; throws on failure so the
     *  wrapper can count the drop. */
    private fun writeRecordLocked(
        context: Context,
        source: String,
        event: String,
        message: String?,
        level: String,
        timestampMs: Long,
        fileKind: String,
        forceSync: Boolean,
    ) {
        val directory = File(context.filesDir, "diagnostics")
        if (!directory.exists() && !directory.mkdirs()) {
            throw java.io.IOException("diagnostics directory unavailable")
        }
        val segmentStart = timestampMs - (timestampMs % SEGMENT_MS)
        val file = File(
            directory,
            "$FILE_PREFIX$segmentStart-${safeLabel(fileKind)}$FILE_SUFFIX",
        )
        val stamp = isoTimestamp(timestampMs)
        val record = JSONObject()
            .put("timestamp", stamp)
            .put("level", safeLabel(level))
            .put("source", safeLabel(source))
            .put("event", safeLabel(event))
        if (!message.isNullOrBlank()) {
            record.put("message", redact(message))
        }
        val bytes = (record.toString() + "\n").toByteArray(Charsets.UTF_8)
        FileOutputStream(file, true).use { output ->
            output.write(bytes)
            if (forceSync) output.fd.sync()
        }
        lastIsoTimestamp = stamp
        // Maintenance after this point is best-effort: the record is on disk,
        // so a transient trim/prune failure must not report it as dropped
        // (codex review round 1, finding 9).
        try {
            trimSegment(file)
            if (lastPrunedSegment != segmentStart) {
                lastPrunedSegment = segmentStart
                // Historical ApplicationExitInfo entries retain their
                // original timestamp. Always prune against wall-clock time
                // so importing one cannot resurrect an expired segment.
                pruneExpired(context, System.currentTimeMillis())
            }
        } catch (_: Throwable) {}
    }

    private fun trimSegment(file: File) {
        if (file.length() <= MAX_SEGMENT_BYTES) return
        val bytes = file.readBytes()
        // Keep headroom after a trim so a burst cannot make every following
        // event rewrite the entire segment on slower TV storage.
        var start = (bytes.size - (MAX_SEGMENT_BYTES / 2L).toInt()).coerceAtLeast(0)
        while (start < bytes.size && bytes[start] != '\n'.code.toByte()) start++
        if (start < bytes.size) start++
        val retained = if (start < bytes.size) bytes.copyOfRange(start, bytes.size) else byteArrayOf()
        file.writeBytes(retained)
    }

    private fun pruneExpired(context: Context, nowMs: Long) {
        val directory = File(context.filesDir, "diagnostics")
        val cutoff = nowMs - RETENTION_MS
        directory.listFiles()?.forEach { file ->
            if (!file.isFile ||
                !file.name.startsWith(FILE_PREFIX) ||
                !file.name.endsWith(FILE_SUFFIX)
            ) return@forEach
            val segment = file.name
                .removePrefix(FILE_PREFIX)
                .substringBefore('-')
                .toLongOrNull() ?: return@forEach
            if (segment + SEGMENT_MS <= cutoff) {
                try {
                    file.delete()
                } catch (_: Throwable) {}
            }
        }
    }

    private fun redact(raw: String): String {
        var value = raw
            .replace(redactUrlRegex, "[private-url]")
            .replace(redactAddressRegex, "[private-address]")
            .replace(redactBearerRegex, "[private-value]")
            .replace(redactSecretRegex, "[private-value]")
        if (value.length > 8_192) value = value.take(8_191) + "…"
        return value
    }

    private fun safeLabel(raw: String): String {
        val value = raw.replace(safeLabelRegex, "_").take(64)
        return value.ifBlank { "unknown" }
    }

    /** Caller holds [fileLock]; [isoFormatter] is not thread-safe. */
    private fun isoTimestamp(timestampMs: Long): String =
        isoFormatter.format(Date(timestampMs))
}
