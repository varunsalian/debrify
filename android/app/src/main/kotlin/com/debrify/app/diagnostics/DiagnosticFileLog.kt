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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicBoolean

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
    private const val CRITICAL_RETENTION_MS = 24L * 60L * 60L * 1_000L
    private const val SEGMENT_MS = 15L * 60L * 1_000L
    private const val MAX_SEGMENT_BYTES = 256L * 1_024L
    private const val PREFS_NAME = "debrify_diagnostics"
    private const val LAST_EXIT_TIMESTAMP = "last_exit_timestamp"

    private val executor = DiagnosticWorkQueue()
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

    fun initialize(context: Context) {
        if (!initialized.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        applicationContext = appContext
        accepting = true
        installCrashHandler(appContext)
        recordCritical(
            source = "android", event = "native_diagnostics_initialized",
            message = "pid=${Process.myPid()} sdk=${Build.VERSION.SDK_INT} " +
                "manufacturer=${safeLabel(Build.MANUFACTURER)} " +
                "model=${safeLabel(Build.MODEL)} " +
                "abi=${safeLabel(Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")}",
        )
    }

    /** Retain lifecycle evidence longer, without blocking the calling thread. */
    fun recordCritical(source: String, event: String, message: String? = null, level: String = "info") {
        if (!accepting) return
        val context = applicationContext ?: return
        val timestamp = System.currentTimeMillis()
        val boundedMessage = message?.take(8192)
        executor.submit {
            append(context, source, event, boundedMessage, level, timestamp, "android-critical", true)
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
        val boundedMessage = message?.take(8192)
        executor.submit {
            if (!accepting) return@submit
            append(
                context = context,
                source = source,
                event = event,
                message = boundedMessage,
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
        val message = DiagnosticFailure.describe(throwable)
        recordCritical(source, event, message, "error")
    }

    /** Completes only after every native event queued before this call. */
    fun flush(onComplete: (Boolean) -> Unit) {
        if (!executor.submit { mainHandler.post { onComplete(true) } }) {
            mainHandler.post { onComplete(false) }
        }
    }

    /**
     * Permanently disables this process' writers, then clears queued/native
     * state on the same executor. The file-lock check also closes the crash
     * handler race, whose emergency write does not use the executor.
     */
    fun clearForDeviceReset(onComplete: (Boolean) -> Unit) {
        accepting = false
        val context = applicationContext
        if (!executor.submit {
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
        }) {
            mainHandler.post { onComplete(false) }
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
        executor.submit {
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
            exits
                .asSequence()
                .filter { it.timestamp > lastRecorded }
                .sortedBy { it.timestamp }
                .forEach { exit ->
                    val stored = append(
                        context = context,
                        source = "android_process",
                        event = "previous_exit",
                        message = buildString {
                            append("pid=")
                            append(exit.pid)
                            append(" reason=")
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
                        fileKind = "android-critical",
                        forceSync = true,
                    )
                    if (!stored) return
                    if (exit.timestamp > newestRecorded) newestRecorded = exit.timestamp
                }
            recordCritical("android_process", "exit_history_checked",
                "pid=${Process.myPid()} available=${exits.size} new=${exits.count { it.timestamp > lastRecorded }}")
            if (newestRecorded > lastRecorded) {
                preferences.edit().putLong(LAST_EXIT_TIMESTAMP, newestRecorded).commit()
            }
        } catch (error: Throwable) {
            recordCritical("android_process", "exit_history_unavailable", "type=${error.javaClass.name}", "warning")
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
                val message = buildString {
                    append("thread=")
                    append(safeLabel(thread.name))
                    append(" ")
                    append(DiagnosticFailure.describe(throwable))
                }
                append(
                    context = context,
                    source = "android_process",
                    event = "uncaught_exception",
                    message = message,
                    level = "error",
                    timestampMs = System.currentTimeMillis(),
                    fileKind = "android-crash",
                    forceSync = true,
                )
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

    private fun append(
        context: Context,
        source: String,
        event: String,
        message: String?,
        level: String,
        timestampMs: Long,
        fileKind: String,
        forceSync: Boolean,
    ): Boolean {
        try {
            synchronized(fileLock) {
                if (!accepting) return false
                val directory = File(context.filesDir, "diagnostics")
                if (!directory.exists() && !directory.mkdirs()) return false
                val segmentStart = timestampMs - (timestampMs % SEGMENT_MS)
                val file = File(
                    directory,
                    "$FILE_PREFIX$segmentStart-${safeLabel(fileKind)}$FILE_SUFFIX",
                )
                val record = JSONObject()
                    .put("timestamp", isoTimestamp(timestampMs))
                    .put("level", safeLabel(level))
                    .put("source", safeLabel(source))
                    .put("event", safeLabel(event))
                    .put("droppedQueueEntries", executor.dropped.get())
                if (!message.isNullOrBlank()) {
                    record.put("message", redact(message))
                }
                DiagnosticSegmentFile.append(file, record.toString(), forceSync, MAX_SEGMENT_BYTES)
                if (lastPrunedSegment != segmentStart) {
                    lastPrunedSegment = segmentStart
                    // Historical ApplicationExitInfo entries retain their
                    // original timestamp. Always prune against wall-clock time
                    // so importing one cannot resurrect an expired segment.
                    pruneExpired(context, System.currentTimeMillis())
                }
            }
            return true
        } catch (_: Throwable) {
            // No logging failure may alter playback or crash delegation.
            return false
        }
    }

    private fun pruneExpired(context: Context, nowMs: Long) {
        val directory = File(context.filesDir, "diagnostics")
        val cutoff = nowMs - RETENTION_MS
        directory.listFiles()?.forEach { file ->
            if (!file.isFile ||
                !file.name.startsWith(FILE_PREFIX) ||
                !file.name.endsWith(FILE_SUFFIX) ||
                !(file.name.endsWith("-android.jsonl") ||
                    file.name.endsWith("-android-critical.jsonl") ||
                    file.name.endsWith("-android-crash.jsonl"))
            ) return@forEach
            val segment = file.name
                .removePrefix(FILE_PREFIX)
                .substringBefore('-')
                .toLongOrNull() ?: return@forEach
            val effectiveCutoff = if (file.name.endsWith("-critical.jsonl") || file.name.endsWith("-android-crash.jsonl"))
                nowMs - CRITICAL_RETENTION_MS else cutoff
            if (segment + SEGMENT_MS <= effectiveCutoff) {
                try {
                    file.delete()
                } catch (_: Throwable) {}
            }
        }
    }

    private fun redact(raw: String): String {
        var value = raw
            .replace(Regex("(?i)\\b(?:https?|magnet|stremio-addon):[^\\s'\\\")]+"), "[private-url]")
            .replace(Regex("\\b(?:\\d{1,3}\\.){3}\\d{1,3}(?::\\d+)?\\b"), "[private-address]")
            .replace(Regex("(?i)\\bbearer\\s+[^,;\\s)\\]}]+"), "[private-value]")
            .replace(
                Regex(
                    "(?i)\\b(?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|" +
                        "password|authorization|bearer|secret|payload|headers?|body)" +
                        "\\b\\s*[:=]\\s*[^,;\\s)]+",
                ),
                "[private-value]",
            )
        if (value.length > 8_192) value = value.take(8_191) + "…"
        return value
    }

    private fun safeLabel(raw: String): String {
        val value = raw.replace(Regex("[^a-zA-Z0-9_.-]"), "_").take(64)
        return value.ifBlank { "unknown" }
    }

    private fun isoTimestamp(timestampMs: Long): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date(timestampMs))
    }
}
