package com.debrify.app.tv

import android.os.SystemClock
import android.view.View
import androidx.media3.common.C
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStartupGateCommitCharacterizationTest : TvPhase9OriginalTest() {
    @Test fun startupUnknownDurationChecksEvery200MsUntilExactlyOneSecond() {
        sources()[0] = aio(); duration = C.TIME_UNSET; begin()
        invoke("commitStartupCandidate")
        val first = field("startupFirstFrameAtElapsedMs") as Long
        val check = field("startupCommitCheck")
        assertEquals(SystemClock.elapsedRealtime(), first)
        invoke("commitStartupCandidate"); assertSame("only one duration check queued", check, field("startupCommitCheck"))
        advance(199); assertSame(check, field("startupCommitCheck"))
        advance(1); assertNotSame("200 ms check re-arms", check, field("startupCommitCheck"))
        advance(799); assertFalse("999 ms is still grace", candidate().committed)
        advance(1); assertTrue("1000 ms permits unknown duration", candidate().committed)
        assertNull(field("startupCommitCheck")); assertNull(field("startupFailoverTimeout"))
        assertEquals(View.GONE, view("startupGateView").visibility)
        assertEquals(mapOf("sourceIndex" to 0, "sourcePersistenceSessionId" to field("sourcePersistenceSessionId")), requestMap("commitStremioSource"))
    }

    @Test fun manualUnknownDurationUsesItsOwnOneSecondGraceAndClearsCandidateState() {
        sources()[1] = aio(1); duration = 0; manual(); set("manualSourceMediaReplaced", true)
        invoke("commitManualSourceCandidate"); val first = field("manualSourceCommitCheck")
        advance(199); assertSame(first, field("manualSourceCommitCheck"))
        advance(1); assertNotSame(first, field("manualSourceCommitCheck"))
        advance(799); assertNotNull("manual 999 ms is still grace", field("manualSourceSwitchSnapshot"))
        advance(1); assertNull("manual 1000 ms commits", field("manualSourceSwitchSnapshot"))
        assertNull(field("manualSourceSwitchIndex")); assertNull(field("manualSourceSwitchTimeout"))
        assertNull(field("manualSourceCommitCheck")); assertEquals(false, field("manualSourceMediaReplaced"))
        assertEquals("✓ AIO 1", pill().text.toString())
        assertEquals(1, requestMap("commitStremioSource")["sourceIndex"])
    }

    @Test fun lateErrorDurationRejectsManualWithoutReportingACommit() {
        sources()[1] = aio(1); duration = 0; manual(); set("manualSourceMediaReplaced", true)
        invoke("commitManualSourceCandidate"); duration = 30_000; advance(200)
        assertNull(field("manualSourceSwitchSnapshot")); assertTrue(requests("commitStremioSource").isEmpty())
        assertEquals("This source is unavailable — choose another source", pill().text.toString())
        assertTrue(ShadowLog.getLogs().any { it.msg.contains("reason=aiostreams-error-slate:30000") })
        assertEquals(true, field("manualSourceRestoreInProgress"))
    }

    @Test fun lateErrorDurationRejectsStartupBeforeThreeMinuteBoundary() {
        sources()[0] = aio(); duration = 0; begin(); invoke("commitStartupCandidate")
        duration = 179_999; advance(200)
        assertTrue(activity.isFinishing); assertEquals(true, field("startupSourcesExhausted"))
        assertEquals("aiostreams-error-slate:179999", requestMap("startupSourceFailed")["reason"])
        assertTrue(requests("commitStremioSource").isEmpty())
    }

    @Test fun validManualCommitCopiesCandidateUrlAndCancelsEveryOwnedCheck() {
        manual(); set("manualSourceMediaReplaced", true); set("manualSourceCandidateUrl", "https://gate.invalid/validated")
        val ran = mutableListOf<String>()
        for (name in listOf("manualSourceCommitCheck", "pikPakGateReprepare")) {
            val callback = Runnable { ran.add(name) }; set(name, callback); handler.postDelayed(callback, 100)
        }
        invoke("commitManualSourceCandidate"); advance(100)
        assertTrue("cancelled commit/reprepare callbacks", ran.isEmpty())
        assertEquals("https://gate.invalid/validated", model().items[0].url)
        assertNull(field("manualSourceCandidateUrl")); assertNull(field("pikPakGateReprepare"))
        assertEquals("✓ Source 1", pill().text.toString())
    }

    @Test fun manualSnapshotPreservesHeldBookmarkMapsAndTitleBeforeMediaReplacement() {
        model().contentType = "series"; model().nextEpisodeMap = mapOf(0 to 1); model().prevEpisodeMap = mapOf(1 to 0)
        model().perItemImdbIds[0] = "tt-saved"; text(R.id.android_tv_player_title).text = "Saved title"
        set("resumeHoldTargetMs", 44_000L); set("resumeHoldArmedAtMs", SystemClock.elapsedRealtime())
        manual(); val saved = snapshot()
        assertEquals(44_000L, saved.items[0].resumePositionMs)
        assertEquals("series", saved.contentType); assertEquals(mapOf(0 to 1), saved.nextEpisodeMap)
        assertEquals(mapOf(1 to 0), saved.prevEpisodeMap); assertEquals(mapOf(0 to "tt-saved"), saved.perItemImdbIds)
        assertEquals("Saved title", saved.title); assertEquals(0, saved.sourceIndex)
        model().perItemImdbIds[0] = "tt-new"; assertEquals("tt-saved", saved.perItemImdbIds[0])
        assertEquals(false, field("manualSourceMediaReplaced")); assertNull(field("manualSourceCandidateUrl"))
    }

    @Test fun replacedManualFailureRestoresAllMetadataBeforeStopAndSuppressesTraktOnReplay() {
        model().items[0] = model().items[0].copy(traktProgressPercent = 80.0)
        model().nextEpisodeMap = mapOf(0 to 1); model().prevEpisodeMap = mapOf(1 to 0)
        model().collectionGroups = listOf(org.json.JSONObject().put("name", "Saved collection"))
        model().perItemImdbIds[0] = "tt-before"; manual(); val saved = snapshot()
        model().contentType = "collection"; model().items.clear(); model().items.add(p2Item("Rejected"))
        model().nextEpisodeMap = emptyMap(); model().prevEpisodeMap = emptyMap(); model().perItemImdbIds.clear(); model().collectionGroups = null
        set("manualSourceMediaReplaced", true); set("currentStremioSourceIndex", 1)
        val trace = mutableListOf<String>()
        probe.onEvent = { if (it == "stop") {
            assertEquals(saved.items, model().items); assertEquals(saved.contentType, model().contentType)
            assertEquals(saved.nextEpisodeMap, model().nextEpisodeMap); assertEquals(saved.prevEpisodeMap, model().prevEpisodeMap)
            assertEquals(saved.perItemImdbIds, model().perItemImdbIds); assertEquals(saved.collectionGroups, model().collectionGroups)
            assertNull(field("manualSourceSwitchSnapshot")); assertEquals(true, field("manualSourceRestoreInProgress"))
            assertEquals(0, selected()); trace.add("restored-before-stop")
        } }
        assertEquals(true, reject()); assertEquals(listOf("restored-before-stop"), trace)
        assertTrue("replay follows stop", probe.events.indexOf("stop") < probe.events.indexOf("prepare"))
        assertEquals("rollback must suppress tracker resume", 0.0, field("pendingItemTraktPercent"))
        assertEquals("rollback preserves captured live resume", saved.items[0].resumePositionMs, field("pendingSeekMs"))
        assertEquals("This source is unavailable — choose another source", pill().text.toString())
        assertNull(field("manualSourceSwitchIndex")); assertNull(field("manualSourceCandidateUrl"))
    }

    @Test fun supersedingUnreplacedManualCandidateHidesFailureAndSnapshotsRestoredSource() {
        manual(1); set("currentStremioSourceIndex", 1)
        gateHost("showStatusPillTransient", arrayOf(stringType), "old status")
        manual(0)
        assertEquals("superseded snapshot must describe outgoing original source", 0, snapshot().sourceIndex)
        assertEquals(0, field("manualSourceSwitchIndex")); tick(350); assertEquals(View.GONE, pill().visibility)
        assertTrue("no replaced media means no stop", probe.events.none { it == "stop" })
        assertTrue(ShadowLog.getLogs().any { it.msg.contains("reason=superseded") })
    }

    @Test fun startupArmPinsDebridFirstOpenAndRetryCopyFocusAndHeadingAnimation() {
        text(R.id.android_tv_player_title).text = "Film heading"; begin(2)
        assertEquals(View.GONE, view("startupGateView").visibility)
        assertEquals("Loading stream…", (field("startupGateStatus") as android.widget.TextView).text.toString())
        assertEquals("Connecting and waiting for the first frames.", text(R.id.startup_explanation).text.toString())
        val heading = text(R.id.startup_title)
        assertEquals("Film heading", heading.text.toString()); assertEquals(0f, heading.alpha, 0f)
        assertEquals(12f, heading.translationY, 0f); assertEquals(600L, heading.animate().duration)
        assertEquals(1, candidate().nextIndex(2) { true }); arm(1)
        assertEquals(View.VISIBLE, view("startupGateView").visibility)
        assertEquals("Connecting to another source", (field("startupGateStatus") as android.widget.TextView).text.toString())
        assertEquals("The previous source couldn’t start. Trying an alternative.", text(R.id.startup_explanation).text.toString())
        assertTrue(activity.findViewById<View>(R.id.startup_back).hasFocus())
        tick(630); assertEquals(1f, heading.alpha, 0.001f); assertEquals(0f, heading.translationY, 0.001f)
    }

    @Test fun aioChannelArmHasNoDeadlineButKeepsOpeningCopyAndManualDeadline() {
        sources()[0] = aio(); set("isStremioTvMode", true); begin()
        assertNull(field("startupFailoverTimeout")); assertEquals(View.VISIBLE, view("startupGateView").visibility)
        assertEquals("Opening your stream", (field("startupGateStatus") as android.widget.TextView).text.toString())
        manual(); assertNotNull(field("manualSourceSwitchTimeout"))
        advance(12_000); assertNull(field("manualSourceSwitchSnapshot")); assertFalse(activity.isFinishing)
    }

    @Test fun startupCommitCancelsAllChecksBumpsGenerationAndShowsControlsBadge() {
        begin(); val generation = field("startupFailoverGeneration") as Int
        set("controlsMenuVisible", true); val fired = mutableListOf<String>()
        for (name in listOf("startupCommitCheck", "pikPakGateReprepare")) {
            val r = Runnable { fired.add(name) }; set(name, r); handler.postDelayed(r, 100)
        }
        invoke("commitStartupCandidate"); tick(350)
        assertTrue(fired.isEmpty()); assertEquals(generation + 1, field("startupFailoverGeneration"))
        assertTrue(candidate().committed); assertNull(field("startupFailoverTimeout"))
        assertNull(field("startupCommitCheck")); assertNull(field("pikPakGateReprepare"))
        assertEquals(View.VISIBLE, badge().visibility); assertEquals(View.GONE, view("startupGateView").visibility)
    }
}
