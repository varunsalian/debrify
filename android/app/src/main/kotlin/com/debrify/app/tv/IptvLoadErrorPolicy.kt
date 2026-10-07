package com.debrify.app.tv

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/** 401/403/404 repeat deterministically; decoder failures repeat unless
     *  the hiccup was transient; everything else gets the full ladder. */
internal fun classifyIptvError(error: PlaybackException): IptvLiveRecovery.ErrorClass {
    val http = generateSequence<Throwable>(error) { it.cause }
        .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
        .firstOrNull()?.responseCode
    if (http == 401 || http == 403 || http == 404) {
        return IptvLiveRecovery.ErrorClass.AUTH
    }
    return when (error.errorCode) {
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
        PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED ->
            IptvLiveRecovery.ErrorClass.DECODER
        else -> IptvLiveRecovery.ErrorClass.TRANSIENT
    }
}

/** Phase 1, Layer 1: loader-level retry policy for live IPTV. Retries
     *  happen UNDER an intact buffer — the player never leaves READY, so a
     *  drop the origin repairs within the buffered lead is invisible.
     *  Classified per the plan: 401/403/404 are deterministic (no retry —
     *  escalate to the fatal-error path, where the machine surrenders or
     *  re-resolves), 429/503 honor Retry-After, other transport errors get
     *  a short flat delay and a generous (bounded) retry count. Non-live
     *  entries keep media3 defaults untouched. */
@OptIn(UnstableApi::class)
internal class IptvLiveLoadErrorPolicy(
    private val liveNow: () -> Boolean,
) : DefaultLoadErrorHandlingPolicy() {

    override fun getRetryDelayMsFor(
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo,
    ): Long {
        if (!liveNow()) return super.getRetryDelayMsFor(loadErrorInfo)
        val http = generateSequence(loadErrorInfo.exception as Throwable?) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()
        when (http?.responseCode) {
            401, 403, 404 -> return C.TIME_UNSET // fatal: same answer every time
            429, 503 -> {
                // Bound the TIME this class can hide a failure, not just
                // the count: minimumLoadableRetryCount is a floor, and a
                // 5s-per-retry rate limit would otherwise sit invisible
                // (no pill — the player never errors) for minutes before
                // the machine's ladder even starts (codex r2, finding 9).
                if (loadErrorInfo.errorCount > 4) return C.TIME_UNSET
                val retryAfterSec = http.headerFields.entries
                    .firstOrNull { it.key.equals("Retry-After", ignoreCase = true) }
                    ?.value?.firstOrNull()?.trim()?.toLongOrNull()
                return (retryAfterSec?.times(1000))?.coerceIn(1_000L, 15_000L)
                    ?: 5_000L
            }
        }
        return if (loadErrorInfo.exception is HttpDataSource.HttpDataSourceException) {
            // ~15s of 1s in-buffer retries, then escalate to the machine.
            if (loadErrorInfo.errorCount > 15) C.TIME_UNSET else 1_000L
        } else {
            super.getRetryDelayMsFor(loadErrorInfo)
        }
    }

    // A floor, not a cap — the real bound is the TIME_UNSET escalation
    // by errorCount in getRetryDelayMsFor above. Kept above the default
    // so transport errors actually reach the 15×1s schedule.
    override fun getMinimumLoadableRetryCount(dataType: Int): Int =
        if (liveNow()) 20 else super.getMinimumLoadableRetryCount(dataType)
}
