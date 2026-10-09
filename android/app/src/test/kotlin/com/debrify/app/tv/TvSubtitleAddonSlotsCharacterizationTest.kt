package com.debrify.app.tv

import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleAddonSlotsCharacterizationTest : TvPhase14OriginalTest() {
    private fun slot(id: String = "a", status: AddonSubtitleStatus = AddonSubtitleStatus.LOADING,
        subs: List<com.debrify.app.subtitle.StremioSubtitle> = emptyList(), error: String? = null) =
        AddonSubtitleResult(addon(id), status, subs, error)
    private fun launch(id: String = "a", type: String = "movie", imdb: String = "tt140", item: PlaybackItem = item(), content: Int = token()) =
        call("launchAddonSubtitleFetch", arrayOf(com.debrify.app.subtitle.StremioAddon::class.java, stringType, stringType, PlaybackItem::class.java, intType),
            addon(id), type, imdb, item, content)
    private fun setSlot(id: String, status: AddonSubtitleStatus, subs: List<com.debrify.app.subtitle.StremioSubtitle>, error: String?) =
        call("setAddonSubtitleSlot", arrayOf(stringType, AddonSubtitleStatus::class.java, listType, stringType), id, status, subs, error)
    private fun retry(id: String = "a") = invoke("retryAddonSubtitles", id)
    private fun rebuild() = call("rebuildFlatStremioSubtitles", emptyArray())

    @Test fun independentFanoutRetainsOrderAndLoadingUntilTheLastSlotReturns() {
        installAddons(addon("a"), addon("b")); val first = response(); val second = response(listOf(subtitle("https://phase14.invalid/b.vtt", "b")), addonId = "b")
        slots().add(slot("old")); known(); entered(first); entered(second)
        assertEquals(listOf("a", "b"), slots().map { it.addon.id }); assertEquals(listOf(1, 1), listOf(tokens()["a"], tokens()["b"]))
        val pending = jobs().toList()
        first.release.countDown(); assertTrue(first.returned.await(5, java.util.concurrent.TimeUnit.SECONDS))
        val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(5)
        while (slots()[0].status == AddonSubtitleStatus.LOADING && System.nanoTime() < deadline) { idle(); Thread.yield() }
        assertEquals(AddonSubtitleStatus.OK, slots()[0].status); assertEquals(AddonSubtitleStatus.LOADING, slots()[1].status)
        assertTrue(loading()); assertEquals(listOf(subtitle()), flat())
        second.release.countDown(); pending.forEach(::settle)
        assertFalse(loading()); assertEquals(listOf("a", "b"), flat().map { it.addonId })
    }
    @Test fun responseFormatsAreFilteredBeforeSlotAndFlatPublication() {
        installAddons(addon()); val response = response(listOf(subtitle("https://phase14.invalid/a.ttml?x=1"), subtitle("https://phase14.invalid/a.dfxp"), subtitle("https://phase14.invalid/a.ass")))
        known(); entered(response); complete(response, jobs().single())
        assertEquals(listOf(subtitle("https://phase14.invalid/a.ass")), slots().single().subtitles)
        assertEquals(slots().single().subtitles, flat())
    }
    @Test fun contentSupersessionRejectsACompletedWorkerBeforeSlotPublication() {
        installAddons(addon()); val response = response(); known(); entered(response)
        val job = jobs().single(); set("addonSubtitleFetchToken", token() + 1); complete(response, job)
        assertEquals(AddonSubtitleStatus.LOADING, slots().single().status); assertTrue(flat().isEmpty()); assertTrue(loading())
    }
    @Test fun perSlotRetrySupersedesOnlyItsOlderWorker() {
        slots().add(slot()); val older = response(); launch(); entered(older); val oldJob = jobs().single()
        val newer = response(listOf(subtitle("https://phase14.invalid/new.srt"))); launch(); entered(newer)
        val newJob = (jobs() - oldJob).single(); assertEquals(2, tokens()["a"])
        complete(newer, newJob); complete(older, oldJob)
        assertEquals(listOf(subtitle("https://phase14.invalid/new.srt")), flat()); assertFalse(loading())
    }
    @Test fun launchSetsLoadingAndClearsOnlyTheTargetSlotsOldErrorAndSubtitles() {
        slots().add(slot(status = AddonSubtitleStatus.FAILED, subs = listOf(subtitle()), error = "old failure"))
        slots().add(slot("b", AddonSubtitleStatus.OK, listOf(subtitle(addon = "b"))))
        tokens()["a"] = 7; val response = response(); launch(); entered(response)
        val job = jobs().single(); assertEquals(8, tokens()["a"])
        assertEquals(slot(), slots()[0]); assertEquals(AddonSubtitleStatus.OK, slots()[1].status); assertTrue(loading())
        complete(response, job)
    }
    @Test fun absentBorrowedServicePublishesAnEmptySuccessfulSlot() {
        slots().add(slot()); set("stremioSubtitleService", null); launch(); idle(); jobs().toList().forEach(::settle)
        assertEquals(slot(status = AddonSubtitleStatus.OK), slots().single()); assertFalse(loading())
    }
    @Test fun realThreeAttemptLadderPublishesFailureMessageAndEmptySlot() {
        installAddons(addon()); response(failure = IllegalStateException("attempt one"), released = true)
        response(failure = IllegalStateException("attempt two"), released = true)
        response(failure = IllegalStateException("server exploded"), released = true)
        known(); idle(); val job = jobs().single(); settle(job)
        assertEquals(3, responses.count { it.entered.count == 0L })
        assertEquals(slot(status = AddonSubtitleStatus.FAILED, error = "server exploded"), slots().single())
        assertFalse(loading()); assertTrue(flat().isEmpty())
    }
    @Test fun emptySuccessfulManualSearchToastsOnlyWhenAllSlotsHaveFinished() {
        installAddons(addon("a"), addon("b")); set("manualSubtitleImdbId", "tt-manual")
        val first = response(emptyList()); val second = response(emptyList(), addonId = "b"); known(); entered(first); entered(second)
        val pending = jobs().toList(); ShadowToast.reset(); first.release.countDown()
        assertTrue(first.returned.await(5, java.util.concurrent.TimeUnit.SECONDS))
        val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(5)
        while (slots()[0].status == AddonSubtitleStatus.LOADING && System.nanoTime() < deadline) { idle(); Thread.yield() }
        assertTrue(loading()); assertEquals(0, ShadowToast.shownToastCount())
        second.release.countDown(); pending.forEach(::settle)
        assertEquals(1, ShadowToast.shownToastCount()); assertEquals("No online subtitles found for this title", ShadowToast.getTextOfLatestToast())
    }
    @Test fun nonManualEmptySearchDoesNotToast() {
        installAddons(addon()); val response = response(emptyList()); known(); entered(response); ShadowToast.reset()
        complete(response, jobs().single()); assertEquals(0, ShadowToast.shownToastCount()); assertFalse(loading())
    }
    @Test fun manualSuccessfulNonemptySearchDoesNotToast() {
        installAddons(addon()); set("manualSubtitleImdbId", "tt-manual"); val response = response(); known(); entered(response); ShadowToast.reset()
        complete(response, jobs().single()); assertEquals(0, ShadowToast.shownToastCount()); assertEquals(1, flat().size)
    }
    @Test fun setSlotMatchesIdAndPreservesAddonMetadataAndOtherSlots() {
        slots().add(slot("b")); slots().add(slot()); val before = slots()[0]
        setSlot("a", AddonSubtitleStatus.FAILED, listOf(subtitle()), "specific message")
        assertEquals(before, slots()[0]); assertEquals(slot(status = AddonSubtitleStatus.FAILED, subs = listOf(subtitle()), error = "specific message"), slots()[1])
    }
    @Test fun unknownSlotUpdateDoesNotAppend() {
        slots().add(slot()); val before = slots().toList()
        setSlot("missing", AddonSubtitleStatus.OK, listOf(subtitle()), null); assertEquals(before, slots())
    }
    @Test fun flatRebuildDeduplicatesNonemptyUrlsInAddonOrderAndRepinsActiveUrl() {
        val old = subtitle("https://phase14.invalid/active.srt", "b"); flat().add(old); set("currentStremioSubtitleIndex", 0)
        val shared = subtitle("https://phase14.invalid/shared.srt")
        slots().add(slot(status = AddonSubtitleStatus.OK, subs = listOf(subtitle(""), shared, shared.copy(addonId = "duplicate"))))
        slots().add(slot("b", AddonSubtitleStatus.FAILED, listOf(old, shared.copy(addonId = "b"))))
        rebuild(); assertEquals(listOf(shared, old), flat()); assertEquals(1, field("currentStremioSubtitleIndex"))
        slots().removeAt(0); rebuild(); assertEquals(0, field("currentStremioSubtitleIndex"))
    }
    @Test fun flatRebuildClearsRemovedOrOutOfRangeSelection() {
        flat().add(subtitle()); set("currentStremioSubtitleIndex", 0); rebuild(); assertEquals(-1, field("currentStremioSubtitleIndex")); assertTrue(flat().isEmpty())
        set("currentStremioSubtitleIndex", 99); slots().add(slot(subs = listOf(subtitle()))); rebuild()
        assertEquals(-1, field("currentStremioSubtitleIndex")); assertEquals(1, flat().size)
    }
    @Test fun retryWithoutPayloadAddonItemOrImdbDoesNotLaunch() {
        val saved = model(); set("payload", null); retry(); assertTrue(tokens().isEmpty())
        set("payload", saved); retry(); assertTrue(tokens().isEmpty())
        slots().add(slot()); set("currentIndex", 7); retry(); assertTrue(tokens().isEmpty())
        set("currentIndex", 0); saved.imdbId = null; retry(); assertTrue(tokens().isEmpty()); assertTrue(jobs().isEmpty())
    }
    @Test fun retryUsesManualIdentityBeforePerItemCacheAndPayloadFallback() {
        slots().add(slot()); set("manualSubtitleImdbId", "tt-manual"); model().perItemImdbIds[0] = "tt-cache"
        val response = response(); retry(); entered(response)
        val job = jobs().single(); assertEquals("https://phase14.invalid/a/subtitles/movie/tt-manual.json", response.arguments[1]); complete(response, job)
    }
    @Test fun retryUsesPerItemCacheBeforePayloadFallback() {
        slots().add(slot()); model().perItemImdbIds[0] = "tt-cache"
        val response = response(); retry(); entered(response)
        val job = jobs().single(); assertEquals("https://phase14.invalid/a/subtitles/movie/tt-cache.json", response.arguments[1]); complete(response, job)
    }
    @Test fun retrySeriesTypeIsCaseInsensitiveAndUsesManualNumbers() {
        slots().add(slot()); set("manualSubtitleType", "SeRiEs"); set("manualSubtitleSeason", 6); set("manualSubtitleEpisode", 11)
        val response = response(); retry(); entered(response)
        val job = jobs().single(); assertEquals("https://phase14.invalid/a/subtitles/series/tt140:6:11.json", response.arguments[1]); complete(response, job)
    }
    @Test fun retryUsesLiveContentTokenAndRejectsItsSubsequentReplacement() {
        slots().add(slot()); set("addonSubtitleFetchToken", 8); val response = response(); retry(); entered(response)
        val job = jobs().single(); set("addonSubtitleFetchToken", 9); complete(response, job)
        assertEquals(AddonSubtitleStatus.LOADING, slots().single().status); assertTrue(flat().isEmpty())
    }
}
