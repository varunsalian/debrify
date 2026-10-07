package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvNavigationCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun navigationSortsSeriesStablyButKeepsCollectionOrderAndClearsStaleGroups() {
        val items = mutableListOf(p2Item(season = 2, episode = 1), p2Item(season = 1, episode = 3),
            p2Item(), p2Item(season = 1, episode = 2), p2Item(season = 1, episode = 2), p2Item(season = 1))
        val model = PlaybackPayload("Title", null, "old", items, 0, null,
            nextEpisodeMap = mapOf(99 to 98), prevEpisodeMap = mapOf(98 to 99),
            collectionGroups = listOf(JSONObject()), perItemImdbIds = mutableMapOf(0 to "tt1"))
        fun rebuild(type: String) = call("rebuildNavigationMaps", arrayOf(PlaybackPayload::class.java, stringType), model, type)
        rebuild("series")
        assertEquals("series", model.contentType)
        assertEquals(mapOf(3 to 4, 4 to 1, 1 to 5, 5 to 0, 0 to 2), model.nextEpisodeMap)
        assertEquals(mapOf(4 to 3, 1 to 4, 5 to 1, 0 to 5, 2 to 0), model.prevEpisodeMap)
        assertNull(model.collectionGroups); assertTrue(model.perItemImdbIds.isEmpty())
        rebuild("collection")
        assertEquals(mapOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 4 to 5), model.nextEpisodeMap)
        assertEquals(mapOf(1 to 0, 2 to 1, 3 to 2, 4 to 3, 5 to 4), model.prevEpisodeMap)
        items.clear(); items.add(p2Item()); items.add(p2Item()); rebuild("series")
        assertEquals(mapOf(0 to 1), model.nextEpisodeMap); assertEquals(mapOf(1 to 0), model.prevEpisodeMap)
        items.removeAt(1); rebuild("series"); assertTrue(model.nextEpisodeMap.isEmpty()); assertTrue(model.prevEpisodeMap.isEmpty())
        items.clear(); rebuild("series"); assertTrue(model.nextEpisodeMap.isEmpty()); assertTrue(model.prevEpisodeMap.isEmpty())
    }
}
