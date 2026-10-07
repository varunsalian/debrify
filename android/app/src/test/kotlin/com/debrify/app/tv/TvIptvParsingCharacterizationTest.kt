package com.debrify.app.tv

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvIptvParsingCharacterizationTest : TvPhase2OriginalTest() {
    @Suppress("UNCHECKED_CAST")
    private fun sources(value: JSONArray?) = call("parseIptvSources", arrayOf(JSONArray::class.java), value) as MutableList<IptvSourceEntry>
    @Suppress("UNCHECKED_CAST")
    private fun lists(value: JSONArray?) = call("parseIptvLists", arrayOf(JSONArray::class.java), value) as MutableList<IptvListEntry>
    @Suppress("UNCHECKED_CAST")
    private fun jsonChannels(value: JSONArray) = call("parseIptvChannels", arrayOf(JSONArray::class.java), value) as MutableList<IptvChannelEntry>
    @Suppress("UNCHECKED_CAST")
    private fun mapChannels(value: List<*>) = call("parseIptvChannels", arrayOf(listType), value) as MutableList<IptvChannelEntry>

    @Test fun sourcesPreserveDefaultsFlagsFilteringAndRevisionPresence() {
        assertTrue(sources(null).isEmpty())
        assertTrue(sources(JSONArray()).isEmpty())
        val result = sources(JSONArray().put(7).put(JSONObject()).put(JSONObject().put("id", "skip").put("isContinue", true))
            .put(JSONObject().put("id", "default"))
            .put(JSONObject().put("id", "full").put("name", "Custom").put("isFavorites", true)
                .put("isXtream", true).put("isList", true).put("listId", "list")
                .put("connectionResourceId", "resource").put("connectionResourceRevision", 9))
            .put(JSONObject().put("id", "zero").put("connectionResourceRevision", "bad")))
        assertEquals(listOf("default", "full", "zero"), result.map { it.id })
        assertEquals(IptvSourceEntry("default", "IPTV", false, false, false, false, null, null, null), result[0])
        assertEquals(IptvSourceEntry("full", "Custom", true, false, true, true, "list", "resource", 9L), result[1])
        assertEquals(0L, result[2].connectionResourceRevision)
        result.add(result[0]) // Public contract is a mutable list, including the empty path.
        sources(null).add(result[0])
    }

    @Test fun listsPreserveDefaultsBuiltinAndIgnoreMalformedEntries() {
        assertTrue(lists(null).isEmpty())
        assertTrue(lists(JSONArray()).isEmpty())
        val result = lists(JSONArray().put(false).put(JSONObject()).put(JSONObject().put("id", "one"))
            .put(JSONObject().put("id", "two").put("name", "Films").put("isBuiltin", true)))
        assertEquals(listOf(IptvListEntry("one", "List", false), IptvListEntry("two", "Films", true)), result)
    }

    @Test fun stringListKeepsWhitespaceAndJsonCoercionButDropsEmptyStrings() {
        assertEquals(emptyList<String>(), call("parseStringList", arrayOf(JSONArray::class.java), null))
        assertEquals(emptyList<String>(), call("parseStringList", arrayOf(JSONArray::class.java), JSONArray()))
        assertEquals(listOf("a", " ", "4", "false", "null"), call("parseStringList", arrayOf(JSONArray::class.java),
            JSONArray().put("a").put("").put(" ").put(4).put(false).put(JSONObject.NULL)))
    }

    @Test fun jsonChannelOverloadKeepsPlaceholdersAndPinsAllOptionalFields() {
        assertTrue(jsonChannels(JSONArray()).isEmpty())
        val result = jsonChannels(JSONArray().put(7).put(JSONObject().put("name", "Default").put("url", "url"))
            .put(JSONObject().put("channelNumber", 8).put("name", "Full").put("url", "full")
                .put("logoUrl", "logo").put("group", "Group").put("contentType", "series").put("duration", 22)
                .put("sourceId", "id").put("sourceName", "Source").put("isFavorite", true)
                .put("seriesId", "series").put("seriesName", "Show").put("season", 0).put("episode", 1)
                .put("hasNextEpisode", false).put("tvArchive", "1").put("tvArchiveDuration", 4)
                .put("resumePositionMs", 5000).put("httpHeaders", JSONObject().put("uSeR-aGeNt", "Agent")
                    .put("Referer", "ref").put("Empty", "")))
            .put(JSONObject().put("channelNumber", -1).put("season", -1).put("episode", -1)
                .put("tvArchiveDuration", 0).put("duration", 0).put("hasNextEpisode", true)))
        assertEquals(listOf(0, 1, 2, 3), result.map { it.index })
        assertEquals(IptvChannelEntry(0, null, "", "", null, null, true, false), result[0])
        assertEquals(IptvChannelEntry(1, null, "Default", "url", null, null, true, false), result[1])
        assertEquals(IptvChannelEntry(2, 8, "Full", "full", "logo", "Group", false, false,
            resumePositionMs = 5000, httpHeaders = mapOf("User-Agent" to "Agent", "Referer" to "ref"),
            contentType = "series", duration = 22, tvArchive = "1", tvArchiveDuration = 4,
            sourceId = "id", sourceName = "Source", isFavorite = true, seriesId = "series", seriesName = "Show",
            season = 0, episode = 1, hasNextEpisode = false), result[2])
        assertEquals(IptvChannelEntry(3, null, "", "", null, null, false, false,
            duration = 0, hasNextEpisode = true), result[3])
    }

    @Test fun mapChannelOverloadFiltersByTypesAndKeepsRawIndexesAndNegativeMetadata() {
        assertTrue(mapChannels(emptyList<Any>()).isEmpty())
        val result = mapChannels(listOf(7, mapOf("name" to "no url"), mapOf("name" to 3, "url" to "x"),
            mapOf("name" to "Default", "url" to "url"),
            mapOf("name" to "Full", "url" to "full", "channelNumber" to 3.8, "logoUrl" to "logo", "group" to "Group",
                "contentType" to "vod", "duration" to 20L, "sourceId" to "id", "sourceName" to "Source",
                "isFavorite" to true, "seriesId" to "series", "seriesName" to "Show", "season" to -1,
                "episode" to -2, "hasNextEpisode" to false, "tvArchive" to "0", "tvArchiveDuration" to -3,
                "resumePositionMs" to 90.5, "httpHeaders" to mapOf("USER-AGENT" to "Agent", "N" to 8, "E" to "", "Z" to null, 3 to "bad")),
            mapOf("name" to "Typed", "url" to "typed", "channelNumber" to "2", "logoUrl" to "", "group" to "",
                "duration" to "5", "isFavorite" to "true", "season" to "1", "episode" to "2", "hasNextEpisode" to "true",
                "tvArchiveDuration" to "3", "resumePositionMs" to "4", "httpHeaders" to 8),
            mapOf("name" to "Bad URL", "url" to 7),
            mapOf("name" to "Zero", "url" to "zero", "channelNumber" to 0)))
        assertEquals(listOf(3, 4, 5, 7), result.map { it.index })
        assertEquals(IptvChannelEntry(3, null, "Default", "url", null, null, true, false), result[0])
        assertEquals(IptvChannelEntry(4, 3, "Full", "full", "logo", "Group", false, false,
            resumePositionMs = 90, httpHeaders = mapOf("User-Agent" to "Agent", "N" to "8"), contentType = "vod", duration = 20,
            tvArchive = "0", tvArchiveDuration = -3, sourceId = "id", sourceName = "Source", isFavorite = true,
            seriesId = "series", seriesName = "Show", season = -1, episode = -2, hasNextEpisode = false), result[1])
        assertEquals(IptvChannelEntry(5, null, "Typed", "typed", null, null, true, false), result[2])
        assertEquals(IptvChannelEntry(7, null, "Zero", "zero", null, null, true, false), result[3])
    }

    @Test fun channelFactoryInfersLiveOnlyForMissingTypeAndMinusOneDuration() {
        val types = arrayOf(intType, boxedIntType, stringType, stringType, stringType, stringType, stringType,
            intType, stringType, stringType, boolType, stringType, stringType, boxedIntType, boxedIntType,
            Boolean::class.javaObjectType, stringType, boxedIntType, longType, mapType)
        for ((type, duration, expectedType, live) in listOf(
            listOf("", -1, "live", true), listOf("", 0, "vod", false), listOf("live", 9, "live", true),
            listOf("Live", -1, "Live", false), listOf("series", -1, "series", false))) {
            val result = call("iptvChannelEntry", types, 2, 3, "Name", "url", "logo", "Group", type, duration,
                "id", "Source", true, "series", "Show", 0, 1, false, "1", 3, 700L, mapOf("K" to "V")) as IptvChannelEntry
            assertEquals(IptvChannelEntry(2, 3, "Name", "url", "logo", "Group", live as Boolean, false,
                resumePositionMs = 700, httpHeaders = mapOf("K" to "V"), contentType = expectedType as String,
                duration = duration as Int, sourceId = "id", sourceName = "Source", isFavorite = true,
                seriesId = "series", seriesName = "Show", season = 0, episode = 1, hasNextEpisode = false,
                tvArchive = "1", tvArchiveDuration = 3), result)
        }
    }
}
