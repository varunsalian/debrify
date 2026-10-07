package com.debrify.app.tv

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.FileNotFoundException
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@androidx.annotation.OptIn(UnstableApi::class)
class TvIptvLoadPolicyCharacterizationTest : TvPhase2OriginalTest() {
    private val spec = DataSpec(Uri.parse("https://example.test/media"))
    private fun http(code: Int, headers: Map<String, List<String>> = emptyMap(), cause: IOException? = null) =
        HttpDataSource.InvalidResponseCodeException(code, "status", cause, headers, spec, byteArrayOf())
    private fun info(error: IOException, count: Int) = LoadErrorHandlingPolicy.LoadErrorInfo(
        LoadEventInfo(1, spec, 0L), MediaLoadData(C.DATA_TYPE_MEDIA), error, count,
    )
    private fun policy(): DefaultLoadErrorHandlingPolicy = TvPlayerOriginalAccess.constructTyped(
        "AndroidTvTorrentPlayerActivity\$IptvLiveLoadErrorPolicy", arrayOf(AndroidTvTorrentPlayerActivity::class.java), activity,
    ) as DefaultLoadErrorHandlingPolicy
    private fun live() = TvPlayerOriginalAccess.set(activity, "iptvChannels", mutableListOf(p2Channel()))

    @Test fun errorClassificationPrioritizesFirstHttpAuthThenDecoderCodesThenTransient() {
        fun classify(code: Int, cause: Throwable? = null) = call("classifyIptvError", arrayOf(PlaybackException::class.java), PlaybackException("failure", cause, code))
        val decoder = PlaybackException.ERROR_CODE_DECODER_INIT_FAILED
        for (status in listOf(401, 403, 404)) assertEquals(IptvLiveRecovery.ErrorClass.AUTH, classify(decoder, IOException(http(status))))
        for (code in listOf(PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED, decoder, PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED)) {
            assertEquals(IptvLiveRecovery.ErrorClass.DECODER, classify(code))
            assertEquals(IptvLiveRecovery.ErrorClass.DECODER, classify(code, http(500)))
        }
        assertEquals(IptvLiveRecovery.ErrorClass.TRANSIENT, classify(PlaybackException.ERROR_CODE_IO_UNSPECIFIED))
        assertEquals(IptvLiveRecovery.ErrorClass.TRANSIENT, classify(PlaybackException.ERROR_CODE_IO_UNSPECIFIED, http(429)))
        assertEquals(IptvLiveRecovery.ErrorClass.DECODER, classify(decoder, http(503, cause = http(401))))
    }

    @Test fun policyReadsLiveStateBetweenEveryInvocation() {
        val entries = mutableListOf(p2Channel(), p2Channel(live = false))
        TvPlayerOriginalAccess.set(activity, "iptvChannels", entries)
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 0)
        val policy = policy(); val defaults = DefaultLoadErrorHandlingPolicy(); val failure = info(http(403), 3)
        fun check(live: Boolean) {
            assertEquals("retry reads live=$live now", if (live) C.TIME_UNSET else defaults.getRetryDelayMsFor(failure), policy.getRetryDelayMsFor(failure))
            for (type in listOf(C.DATA_TYPE_MEDIA, C.DATA_TYPE_MEDIA_PROGRESSIVE_LIVE))
                assertEquals(if (live) 20 else defaults.getMinimumLoadableRetryCount(type), policy.getMinimumLoadableRetryCount(type))
        }
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 0); check(true)
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 1); check(false)
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 99); check(false)
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", -1); check(false)
        TvPlayerOriginalAccess.set(activity, "iptvChannels", mutableListOf(p2Channel(live = false)))
        TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 0); check(false)
        TvPlayerOriginalAccess.set(activity, "iptvChannels", mutableListOf(p2Channel())); check(true)
    }

    @Test fun liveAuthIsFatalAndRateLimitHasFourRetryBoundWithHeaderClamps() {
        live(); TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 0); val policy = policy()
        for (status in listOf(401, 403, 404)) for (count in listOf(1, 4, 5, 16)) assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(info(http(status), count)))
        val headers: List<Pair<Map<String, List<String>>, Long>> = listOf(emptyMap<String, List<String>>() to 5000L,
            mapOf("rEtRy-AfTeR" to listOf(" 2 ", "9")) to 2000L, mapOf("Retry-After" to listOf("0")) to 1000L,
            mapOf("Retry-After" to listOf("-2")) to 1000L, mapOf("Retry-After" to listOf("1")) to 1000L,
            mapOf("Retry-After" to listOf("15")) to 15_000L, mapOf("Retry-After" to listOf("16")) to 15_000L,
            mapOf("Retry-After" to listOf("bad")) to 5000L, mapOf("Retry-After" to emptyList<String>()) to 5000L,
            mapOf("Retry-After" to listOf("")) to 5000L,
            linkedMapOf("Retry-After" to listOf("3"), "retry-after" to listOf("9")) to 3000L)
        for (status in listOf(429, 503)) for ((header, expected) in headers) {
            assertEquals(expected, policy.getRetryDelayMsFor(info(http(status, header), 4)))
            assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(info(http(status, header), 5)))
        }
        assertEquals(2000L, policy.getRetryDelayMsFor(info(IOException(http(503, mapOf("Retry-After" to listOf("2")))), 4)))
    }

    @Test fun liveTransportEscalatesAfterFifteenAndOtherExceptionsDelegate() {
        live(); TvPlayerOriginalAccess.set(activity, "currentIptvIndex", 0); val policy = policy(); val defaults = DefaultLoadErrorHandlingPolicy()
        val transport = HttpDataSource.HttpDataSourceException(spec, PlaybackException.ERROR_CODE_IO_UNSPECIFIED, HttpDataSource.HttpDataSourceException.TYPE_READ)
        for (error in listOf(transport, http(500), http(408))) {
            assertEquals(1000L, policy.getRetryDelayMsFor(info(error, 1)))
            assertEquals(1000L, policy.getRetryDelayMsFor(info(error, 15)))
            assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(info(error, 16)))
        }
        for (error in listOf(IOException("plain"), FileNotFoundException("missing"), IOException(http(500))))
            for (count in listOf(1, 3, 15, 16)) assertEquals(defaults.getRetryDelayMsFor(info(error, count)), policy.getRetryDelayMsFor(info(error, count)))
        assertEquals(20, policy.getMinimumLoadableRetryCount(C.DATA_TYPE_MEDIA))
    }
}
