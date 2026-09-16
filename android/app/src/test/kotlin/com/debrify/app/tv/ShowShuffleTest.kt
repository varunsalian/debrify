package com.debrify.app.tv

import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Test

class ShowShuffleTest {
    @Test fun visitsAllSeasonsBeforeRepeating() {
        val shuffle = ShowShuffle(Random(7))
        val episodes = listOf(ShuffleEpisode(1, 1), ShuffleEpisode(1, 2), ShuffleEpisode(2, 1), ShuffleEpisode(3, 1))
        var current = episodes.first()
        val visited = mutableSetOf(current)
        repeat(episodes.size - 1) {
            val next = shuffle.pick(episodes.reversed(), current)!!
            assertTrue(visited.add(next))
            current = next
        }
        assertEquals(episodes.toSet(), visited)
        assertNotEquals(current, shuffle.pick(episodes, current))
    }

    @Test fun unavailableEpisodesAreNotRetriedWithinARequest() {
        val shuffle = ShowShuffle(Random(1))
        val current = ShuffleEpisode(1, 1)
        val episodes = listOf(current, ShuffleEpisode(2, 1), ShuffleEpisode(3, 1))
        val first = shuffle.pick(episodes, current)!!
        val second = shuffle.pick(episodes, current, setOf(first))!!
        assertNotEquals(first, second)
        assertNull(shuffle.pick(episodes, current, setOf(first, second)))
    }

    @Test fun handlesEmptySingleAndChangedCatalogs() {
        val shuffle = ShowShuffle(Random(5))
        val current = ShuffleEpisode(1, 1)
        val other = ShuffleEpisode(2, 1)
        assertNull(shuffle.pick(emptyList(), null))
        assertNull(shuffle.pick(listOf(current, current), current))
        assertEquals(other, shuffle.pick(listOf(current, other), current))
        val added = ShuffleEpisode(4, 1)
        assertEquals(added, shuffle.pick(listOf(current, added), current))
        shuffle.clear()
        assertEquals(other, shuffle.pick(listOf(other), current))
    }
}
