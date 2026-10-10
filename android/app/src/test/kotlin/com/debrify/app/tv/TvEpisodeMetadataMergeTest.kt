package com.debrify.app.tv

import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeMetadataMergeTest : TvPhase19MetadataTest() {
    @Test fun titleNonemptyUpdateAndEmptyFallback() {
        update("title" to "Replacement")
        assertEquals("Replacement", first.title)
        update("title" to "")
        assertEquals("empty provider text preserves the field", "Replacement", first.title)
        changes(2, 2)
    }

    @Test fun descriptionNonemptyUpdateAndEmptyFallback() {
        update("description" to "Replacement")
        assertEquals("Replacement", first.description)
        update("description" to "")
        assertEquals("empty provider text preserves the field", "Replacement", first.description)
        changes(2, 2)
    }

    @Test fun artworkNonemptyUpdateAndEmptyFallback() {
        update("artwork" to "Replacement")
        assertEquals("Replacement", first.artwork)
        update("artwork" to "")
        assertEquals("empty provider text preserves the field", "Replacement", first.artwork)
        changes(2, 2)
    }

    @Test fun ratingZeroIsARealUpdateAndAbsentFieldsArePreserved() {
        update("rating" to 0.0)
        assertEquals(0.0, first.rating!!, 0.0)
        assertEquals("Original", first.title); assertEquals("Description", first.description); assertEquals("art", first.artwork)
        assertEquals(25.0, first.traktProgressPercent!!, 0.0)
        assertFalse(first.watched); changes(1, 1)
    }

    @Test fun watchedTrueDominatesTrackerAndPinsBothAdaptersAndTitle() {
        update("watched" to true, "trackerProgressPercent" to 42.0, "title" to "Watched")
        assertTrue(first.watched); assertEquals(100.0, first.traktProgressPercent!!, 0.0)
        assertEquals("Watched", tv("titleView").text.toString()); changes(1, 1)
    }

    @Test fun watchedFalseAndExplicitTrackerAreAdopted() {
        model.items[0] = first.copy(watched = true)
        update("watched" to false, "trackerProgressPercent" to 42.0)
        assertFalse(first.watched); assertEquals(42.0, first.traktProgressPercent!!, 0.0)
    }

    @Test fun watchedAndTrackerAbsentKeepPreviousValues() {
        model.items[0] = first.copy(watched = true, traktProgressPercent = 91.0)
        update()
        assertTrue(first.watched); assertEquals(91.0, first.traktProgressPercent!!, 0.0)
        changes(1, 1)
    }

    @Test fun allowLocalDisplayAbsentAndExplicitFalseAreSeparate() {
        model.items[0] = first.copy(allowLocalProgressDisplay = true)
        update(); assertTrue(first.allowLocalProgressDisplay)
        update("allowLocalProgressDisplay" to false); assertFalse(first.allowLocalProgressDisplay)
        update("allowLocalProgressDisplay" to true); assertTrue(first.allowLocalProgressDisplay)
    }

    @Test fun currentResumeAndDurationProtectActualPlayback() {
        probe.position = 30_000; probe.duration = 120_000
        update("resumePositionMs" to 5_000L, "durationMs" to 20_000L)
        assertEquals(30_000L, first.resumePositionMs); assertEquals(120_000L, first.durationMs)
    }

    @Test fun noncurrentResumeAndDurationAdoptIncoming() {
        probe.position = 99_000; probe.duration = 199_000
        metadata("[{\"originalIndex\":1,\"resumePositionMs\":5000,\"durationMs\":20000}]")
        assertEquals(5_000L, model.items[1].resumePositionMs); assertEquals(20_000L, model.items[1].durationMs)
    }

    @Test fun negativeLiveValuesCannotOverwriteValidHistory() {
        probe.position = -50; probe.duration = -1
        update("resumePositionMs" to -3L, "durationMs" to -1L)
        assertEquals(0L, first.resumePositionMs); assertEquals(-1L, first.durationMs)
    }

    @Test fun absentPlayerDoesNotEraseHistory() {
        set("player", null); update()
        assertEquals(9_000L, first.resumePositionMs); assertEquals(90_000L, first.durationMs)
    }

    @Test fun matchingSeasonEpisodeKeepsRequestedIndex() {
        metadata("[{\"originalIndex\":1,\"season\":2,\"episode\":3,\"title\":\"Matched\"}]")
        assertEquals("Original", first.title); assertEquals("Matched", model.items[1].title)
    }

    @Test fun mismatchedRequestedIndexRematchesSeasonEpisode() {
        metadata("[{\"originalIndex\":0,\"season\":2,\"episode\":3,\"title\":\"Rematched\"}]")
        assertEquals("Original", first.title); assertEquals("Rematched", model.items[1].title)
    }

    @Test fun absentRequestedIndexCanRematchButCannotUpdateWithoutCoordinates() {
        metadata("[{\"season\":2,\"episode\":3,\"title\":\"Rematched\"}]")
        assertEquals("Rematched", model.items[1].title)
        metadata("[{\"title\":\"Ignored\"}]"); assertEquals("Original", first.title); changes(1, 1)
    }

    @Test fun oneCoordinateUsesRequestedIndex() {
        metadata("[{\"originalIndex\":0,\"season\":2,\"title\":\"Index\"}]")
        assertEquals("Index", first.title); assertEquals("Second", model.items[1].title)
    }

    @Test fun invalidNegativeUpdateDoesNotNotify() {
        metadata("[{\"originalIndex\":-1,\"title\":\"Ignored\"}]")
        assertEquals("Original", first.title); assertEquals("Before", tv("titleView").text.toString()); changes(0, 0)
    }

    @Test fun invalidAtSizeUpdateDoesNotNotify() {
        metadata("[{\"originalIndex\":2,\"title\":\"Ignored\"}]")
        assertEquals("Original", first.title); assertEquals("Before", tv("titleView").text.toString()); changes(0, 0)
    }

    @Test fun invalidBeyondUpdateDoesNotNotify() {
        metadata("[{\"originalIndex\":10,\"title\":\"Ignored\"}]")
        assertEquals("Original", first.title); assertEquals("Before", tv("titleView").text.toString()); changes(0, 0)
    }

    @Test fun unmatchedCoordinatesDoNotFallBackToWrongRequestedItem() {
        metadata("[{\"originalIndex\":0,\"season\":9,\"episode\":9,\"title\":\"Ignored\"}]")
        assertEquals("Original", first.title); changes(0, 0)
    }

    @Test fun updatesNullLeaveAdaptersUntouched() {
        metadata(null)
        assertEquals("Original", first.title); changes(0, 0)
    }

    @Test fun updatesEmptyLeaveAdaptersUntouched() {
        metadata("")
        assertEquals("Original", first.title); changes(0, 0)
    }

    @Test fun updatesMalformedLeaveAdaptersUntouched() {
        metadata("broken")
        assertEquals("Original", first.title); changes(0, 0)
    }

    @Test fun updatesEmptyArrayLeaveAdaptersUntouched() {
        metadata("[]")
        assertEquals("Original", first.title); changes(0, 0)
    }

    @Test fun validUpdateFollowedByMalformedRowKeepsItsImmediateWrite() {
        metadata("[{\"originalIndex\":0,\"title\":\"First applied\"},3]")
        assertEquals("First applied", first.title); changes(0, 0)
    }

    @Test fun missingCurrentItemStillNotifiesBothAdapters() {
        set("currentIndex", 99); update("title" to "Applied")
        assertEquals("Applied", first.title); assertEquals("Before", tv("titleView").text.toString()); changes(1, 1)
    }

    @Test fun workerWritesModelBeforeQueuedAdapterAndTitlePublication() {
        val worker = Thread { metadata("[{\"originalIndex\":0,\"title\":\"Worker\"}]") }
        worker.start(); worker.join(5000); assertFalse(worker.isAlive)
        assertEquals("Worker", first.title); changes(0, 0); assertEquals("Before", tv("titleView").text.toString())
        step(0); changes(1, 1); assertEquals("Worker", tv("titleView").text.toString())
    }

    @Test fun defaultArgumentDispatchStillUpdatesWithoutGuideOrShow() {
        set("ottShowName", "Old")
        defaultCall("handleMetadataUpdate", arrayOf(stringType, stringType, stringType, stringType), 12, "[{\"originalIndex\":0,\"title\":\"Default\"}]", null, "[{\"season\":9,\"episode\":9}]", "Ignored")
        assertEquals("Default", first.title); assertTrue(model.guideEpisodes.isEmpty()); assertEquals("Old", field("ottShowName"))
    }
    @Test fun sameSeasonWrongEpisodeRematchesInsteadOfOverwritingRequestedItem() {
        model.items[1] = model.items[1].copy(season = 1, episode = 2)
        metadata("[{\"originalIndex\":0,\"season\":1,\"episode\":2,\"title\":\"Episode match\"}]")
        assertEquals("Original", first.title); assertEquals("Episode match", model.items[1].title)
    }
    @Test fun sameEpisodeWrongSeasonRematchesInsteadOfOverwritingRequestedItem() {
        model.items[1] = model.items[1].copy(season = 2, episode = 1)
        metadata("[{\"originalIndex\":0,\"season\":2,\"episode\":1,\"title\":\"Season match\"}]")
        assertEquals("Original", first.title); assertEquals("Season match", model.items[1].title)
    }
    @Test fun incomingCurrentResumeAheadOfLivePlaybackIsPreserved() {
        probe.position = 30_000
        update("resumePositionMs" to 60_000L)
        assertEquals("late snapshot is not moved behind live time", 60_000L, first.resumePositionMs)
    }
}
