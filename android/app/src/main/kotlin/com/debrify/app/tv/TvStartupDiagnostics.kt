package com.debrify.app.tv

import android.media.MediaCodecList
import android.net.Uri
import com.debrify.app.diagnostics.DiagnosticFileLog
import java.util.Locale

internal fun androidDecoderStatus(decoderName: String): String {
    val normalized = decoderName.lowercase(Locale.US)
    if (
        normalized.contains(".google.") ||
        normalized.contains(".android.") ||
        normalized.startsWith("c2.android") ||
        normalized.startsWith("c2.google") ||
        normalized.contains("ffmpeg")
    ) {
        return "software"
    }
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
        val codecInfo = runCatching {
            MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.firstOrNull {
                it.name.equals(decoderName, ignoreCase = true)
            }
        }.getOrNull()
        if (codecInfo?.isSoftwareOnly == true) return "software"
        if (codecInfo?.isHardwareAccelerated == true) return "hardware"
    }
    return "unknown"
}

internal fun buildProtectedMediaOrigins(items: List<PlaybackItem>): Set<String> {
    return items
        .mapNotNull { item ->
            if (item.url.isBlank()) {
                null
            } else {
                originKey(Uri.parse(item.url))
            }
        }
        .toSet()
}

internal fun originKey(uri: Uri): String? {
    val scheme = uri.scheme?.lowercase() ?: return null
    if (scheme != "http" && scheme != "https") return null
    val host = uri.host?.lowercase() ?: return null
    val port = when {
        uri.port != -1 -> uri.port
        scheme == "http" -> 80
        scheme == "https" -> 443
        else -> -1
    }
    return "$scheme://$host:$port"
}

internal fun isPikPakPlaybackItem(item: PlaybackItem?): Boolean =
    item != null && (PROVIDER_PIKPAK.equals(item.provider, ignoreCase = true) ||
        item.url.contains("mypikpak.com"))

internal fun diagnosticProvider(value: String?): String {
    if (value.isNullOrBlank()) return "-"
    return value
        .lowercase(Locale.US)
        .replace(Regex("[^a-z0-9_.-]"), "_")
        .take(32)
        .ifBlank { "-" }
}

internal fun startupLog(message: String, warning: Boolean = false) {
    DiagnosticFileLog.record(
        source = "android_tv_player",
        event = "startup_gate",
        message = message,
        level = if (warning) "warning" else "info",
    )
    if (warning) android.util.Log.w(STARTUP_FAILOVER_LOG_TAG, message)
    else android.util.Log.d(STARTUP_FAILOVER_LOG_TAG, message)
}
    private const val STARTUP_FAILOVER_LOG_TAG = "DebrifyStartupGate"

    // PikPak cold storage retry constants
    internal const val PROVIDER_PIKPAK = "pikpak"
