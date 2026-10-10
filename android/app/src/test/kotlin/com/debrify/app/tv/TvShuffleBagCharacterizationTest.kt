package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvShuffleBagCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun eligibleNone() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.NONE); set("movieGroups",null)
         assertEquals(listOf(0,1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleSeriesCompleteOnly() {
        model().items.clear(); model().items.addAll(listOf(p2Item(season=1,episode=1),p2Item(season=1),p2Item(episode=1),p2Item(season=0,episode=0))); set("playlistMode",PlaylistMode.SERIES); set("movieGroups",null)
         assertEquals(listOf(0,3),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleSeriesFallback() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.SERIES); set("movieGroups",null)
         assertEquals(listOf(0,1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleMainIgnoreCase() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",MovieGroups(listOf(CollectionGroup("Extras",listOf(0)),CollectionGroup("mAiN",listOf(1)))))
         assertEquals(listOf(1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleFirstGroupFallback() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",MovieGroups(listOf(CollectionGroup("Extras",listOf(1)))))
         assertEquals(listOf(1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleInvalidGroupFallback() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",MovieGroups(listOf(CollectionGroup("Main",listOf(-1,9)))))
         assertEquals(listOf(0,1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleGroupBoundsDuplicates() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",MovieGroups(listOf(CollectionGroup("Main",listOf(-1,0,1,1,2)))))
         assertEquals(listOf(0,1,1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleNullGroupFallback() {
        model().items.clear(); model().items.addAll(listOf(p2Item(),p2Item().copy(index=1))); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",null)
         assertEquals(listOf(0,1),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleMissingPayload() {
        set("payload",null); assertEquals(emptyList<Int>(),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun eligibleEmptyPayload() {
        model().items.clear(); assertEquals(emptyList<Int>(),call("getShuffleEligibleIndices",emptyArray()))
    }

    @Test fun singleEligibleShortcutLeavesBagUntouched() {
        (field("shuffleBag") as MutableList<Int>).addAll(listOf(7,8)); assertEquals(0,call("pickShuffleIndex",emptyArray())); assertEquals(listOf(7,8),field("shuffleBag"))
    }

    @Test fun emptyEligibilityReturnsNull() {
        model().items.clear(); assertNull(call("pickShuffleIndex",emptyArray()))
    }

    @Test fun bagRemovesCurrentAndIneligibleThenPopsLast() {
        payload(p2Item(),p2Item().copy(index=1),p2Item().copy(index=2)); val bag=field("shuffleBag") as MutableList<Int>; bag.addAll(listOf(-1,0,1,2,9))
        assertEquals(2,call("pickShuffleIndex",emptyArray())); assertEquals(listOf(1),bag)
    }

    @Test fun bagCycleExhaustsDistinctEligibleBeforeRepeat() {
        payload(p2Item(),p2Item().copy(index=1),p2Item().copy(index=2)); set("playlistMode",PlaylistMode.COLLECTION); set("movieGroups",MovieGroups(listOf(CollectionGroup("Main",listOf(0,1,1,2)))))
        val picked=(1..2).map { call("pickShuffleIndex",emptyArray()) as Int }; assertEquals(setOf(1,2),picked.toSet()); assertTrue((field("shuffleBag") as List<*>).isEmpty())
    }
}
