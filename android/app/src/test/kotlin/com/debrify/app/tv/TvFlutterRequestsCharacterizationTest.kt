package com.debrify.app.tv

import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvFlutterRequestsCharacterizationTest : TvFlutterRequestsOriginalTest() {
    @Test fun torrentRequestsPinArgumentsAsyncResultsNullChannelAndSendFailure() {
        val item = p2Item(); val answers = mutableListOf<Pair<String?, String?>>()
        val callback: (String?, String?) -> Unit = { url, provider -> assertMainThread(); answers.add(url to provider) }
        fun request() = call("requestStreamFromFlutter", arrayOf(PlaybackItem::class.java, intType, function2Type), item, 7, callback)
        for ((reply, expected) in listOf(mapOf("url" to "stream", "provider" to "TorBox") to ("stream" to "TorBox"),
            mapOf("url" to 7, "provider" to false) to (null to null), "wrong" to (null to null), null to (null to null))) {
            answers.clear(); request()
            assertRequest("requestTorrentStream", mapOf("resumeId" to "resume", "itemId" to "item", "index" to 7))
            assertTrue(answers.isEmpty()); messenger.success(reply); assertTrue(answers.isEmpty()); idle()
            assertEquals(listOf(expected), answers)
        }
        for (error in listOf(true, false)) {
            answers.clear(); request(); if (error) messenger.error() else messenger.notImplemented(); assertTrue(answers.isEmpty()); idle()
            assertEquals(listOf(null to null), answers)
        }
        MainActivity.setAndroidTvPlayerChannel(null); answers.clear(); request(); idle(); assertTrue(answers.isEmpty())
        reconnectChannel(); messenger.throwOnSend = true; request(); assertEquals(listOf(null to null), answers)
    }

    @Test fun movieMetadataPinsFilenameAsyncResultsNullChannelAndSendFailure() {
        val item = p2Item("Release.mkv"); val answers = mutableListOf<String?>()
        val callback: (String?) -> Unit = { assertMainThread(); answers.add(it) }
        fun request() = call("requestMovieMetadataFromFlutter", arrayOf(PlaybackItem::class.java, intType, function1Type), item, 3, callback)
        for ((reply, expected) in listOf(mapOf("imdbId" to "tt123") to "tt123", mapOf("imdbId" to 3) to null, "wrong" to null, null to null)) {
            answers.clear(); request(); assertRequest("requestMovieMetadata", mapOf("index" to 3, "filename" to "Release.mkv"))
            assertTrue(answers.isEmpty()); messenger.success(reply); assertTrue(answers.isEmpty()); idle(); assertEquals(listOf(expected), answers)
        }
        for (error in listOf(true, false)) {
            answers.clear(); request(); if (error) messenger.error() else messenger.notImplemented(); idle(); assertEquals(listOf<String?>(null), answers)
        }
        MainActivity.setAndroidTvPlayerChannel(null); answers.clear(); request(); idle(); assertTrue(answers.isEmpty())
        reconnectChannel(); messenger.throwOnSend = true; request(); assertEquals(listOf<String?>(null), answers)
    }

    private fun proveMessengerNullSemantics() {
        val events = mutableListOf<String>()
        val result = object : MethodChannel.Result {
            override fun success(value: Any?) { assertMainThread(); assertNull(value); events.add("success") }
            override fun error(code: String, message: String?, details: Any?) { events.add("error") }
            override fun notImplemented() { assertMainThread(); events.add("notImplemented") }
        }
        MainActivity.getAndroidTvPlayerChannel()!!.invokeMethod("codecProbe", null, result)
        messenger.success(null); assertTrue(events.isEmpty()); idle(); assertEquals(listOf("success"), events)
        MainActivity.getAndroidTvPlayerChannel()!!.invokeMethod("codecProbe", null, result)
        messenger.notImplemented(); assertEquals(listOf("success"), events); idle(); assertEquals(listOf("success", "notImplemented"), events)
    }

    @Test fun streamUrlsPinCandidateFilteringLabelsMessagesAndSynchronousFailurePaths() {
        proveMessengerNullSemantics()
        val answers = mutableListOf<Pair<List<Pair<String, String>>, String?>>()
        val callback: (List<Any>, String?) -> Unit = { candidates, message ->
            assertMainThread()
            val values = candidates.map {
                assertEquals(TvPlayerOriginalAccess.type("AndroidTvTorrentPlayerActivity\$IptvStremioCandidate"), it.javaClass)
                (TvPlayerOriginalAccess.callTyped(it, "getUrl", emptyArray()) as String) to
                    (TvPlayerOriginalAccess.callTyped(it, "getLabel", emptyArray()) as String)
            }
            answers.add(values to message)
        }
        fun request(name: String? = "Cinema") = call("requestIptvStreamUrls", arrayOf(stringType, stringType, function2Type), "stremio-tv://id", name, callback)
        request(); assertRequest("requestIptvStreamUrls", mapOf("channelUrl" to "stremio-tv://id", "channelName" to "Cinema"))
        messenger.success(mapOf("candidates" to listOf(7, emptyMap<String, Any>(), mapOf("url" to ""), mapOf("url" to 4),
            mapOf("url" to "one", "label" to "Main"), mapOf("url" to "two", "label" to " "), mapOf("url" to "three")), "message" to "Reason"))
        assertTrue(answers.isEmpty()); idle()
        assertEquals(listOf((listOf("one" to "Main", "two" to "Source", "three" to "Source")) to "Reason"), answers)
        for (value in listOf(null, "wrong", mapOf("candidates" to 3, "message" to " "))) {
            answers.clear(); request(null); assertRequest("requestIptvStreamUrls", mapOf("channelUrl" to "stremio-tv://id", "channelName" to null))
            messenger.success(value); idle(); assertEquals(listOf(emptyList<Pair<String, String>>() to null), answers)
        }
        for (error in listOf(true, false)) {
            answers.clear(); request(); if (error) messenger.error() else messenger.notImplemented(); idle()
            assertEquals(listOf(emptyList<Pair<String, String>>() to null), answers)
        }
        MainActivity.setAndroidTvPlayerChannel(null); answers.clear(); request()
        assertEquals(listOf(emptyList<Pair<String, String>>() to null), answers) // No looper advance: synchronous.
        reconnectChannel(); messenger.throwOnSend = true; answers.clear(); request()
        assertEquals(listOf(emptyList<Pair<String, String>>() to null), answers)
    }

    @Test fun streamResultReportPinsFireAndForgetArgumentsAndSwallowsSendExceptions() {
        fun report(url: String?, success: Boolean) = call("reportIptvStreamResult", arrayOf(stringType, stringType, boolType), "channel", url, success)
        report("stream", true); assertRequest("reportIptvStreamResult", mapOf("channelUrl" to "channel", "url" to "stream", "success" to true))
        assertNull(messenger.requests.last().reply); messenger.success(null); messenger.error(); messenger.notImplemented(); idle()
        report(null, false); assertRequest("reportIptvStreamResult", mapOf("channelUrl" to "channel", "url" to null, "success" to false))
        MainActivity.setAndroidTvPlayerChannel(null); val sent = messenger.requests.size; report(null, false); assertEquals(sent, messenger.requests.size)
        reconnectChannel(); messenger.throwOnSend = true
        assertNull("reporting swallows messenger exceptions", runCatching { report("stream", false) }.exceptionOrNull())
    }

    @Test fun quickPlayPinsFireAndForgetArgumentsNullChannelAndPropagatingSendException() {
        fun request() = call("requestQuickPlayNextEpisode", arrayOf(stringType, intType, intType), "tt123", 2, 4)
        request(); assertRequest("requestQuickPlayNextEpisode", mapOf("imdbId" to "tt123", "season" to 2, "episode" to 4))
        assertNull(messenger.requests.last().reply); messenger.success(null); messenger.error(); messenger.notImplemented(); idle()
        MainActivity.setAndroidTvPlayerChannel(null); val sent = messenger.requests.size; request(); assertEquals(sent, messenger.requests.size)
        reconnectChannel(); messenger.throwOnSend = true
        assertThrows(IllegalStateException::class.java) { request() }
    }
}
