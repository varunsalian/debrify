package com.debrify.app.tv

import android.view.View
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.recording.RecordingRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvZapBannerIdentityCharacterizationTest : TvPhase6OriginalTest() {
    private fun identity(e: IptvChannelEntry) = call("paintIptvZapBannerIdentity", arrayOf(IptvChannelEntry::class.java), e)
    private fun logo() = view("iptvZapBannerLogo") as android.widget.ImageView
    private fun resource() = "android.resource://com.debrify.app/${com.debrify.app.R.drawable.splash_logo}"
    private fun request() = DrawableImageViewTarget(logo()).request!!

    @Test fun classicIdentityUsesRawNameNumberFallbackAndPlaceholder() {
        setup(); build(); val e = entry(name = "cinema", number = null, index = 9); channels(e); identity(e)
        assertEquals("10", text("iptvZapBannerNumber").text.toString())
        assertEquals("cinema", text("iptvZapBannerName").text.toString()); assertEquals("C", text("iptvZapBannerLetter").text.toString())
        assertEquals(View.GONE, logo().visibility); assertEquals(View.VISIBLE, view("iptvZapBannerLetter").visibility)
        identity(entry(name = "", number = 0)); assertEquals("?", text("iptvZapBannerLetter").text.toString())
        assertEquals("0", text("iptvZapBannerNumber").text.toString())
    }
    @Test fun styledNumbersUseGlassPlainEditionChAndConsoleThreeDigits() {
        setup("console"); build(); identity(entry(number = 7))
        assertEquals("007", text("iptvZapBannerNumber").text.toString())
        identity(entry(number = 1234)); assertEquals("1234", text("iptvZapBannerNumber").text.toString())
    }
    @Test fun editionNumberUsesChPrefixAndRawName() {
        setup("edition"); build(); identity(entry(number = null, index = 9))
        assertEquals("CH 10", text("iptvZapBannerNumber").text.toString()); assertEquals("Cinema", text("iptvZapBannerName").text.toString())
    }
    @Test fun glassIdentityKeepsPlainNumberAndPlaceholder() {
        setup("glass"); build(); identity(entry(name = "cinema", number = 7))
        assertEquals("7", text("iptvZapBannerNumber").text.toString()); assertEquals("C", text("iptvZapBannerLetter").text.toString())
        assertEquals(View.GONE, logo().visibility); assertEquals(View.VISIBLE, view("iptvZapBannerLetter").visibility)
    }
    @Test fun positionUsesPagedTotalLocalizedNumbersAndTrimmedGroup() {
        setup(); build(); val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US); channels(); set("iptvZapPagingActive", true); set("iptvZapCategoryTotal", 2000)
            position(entry(index = 1000)); assertEquals("·  Movies  ·  1,001 of 2,000", text("iptvZapBannerMeta").text.toString())
            set("iptvZapCategoryTotal", 0); position(entry(index = 0, group = "  "))
            assertEquals("·  1 of 2", text("iptvZapBannerMeta").text.toString())
            set("iptvChannels", mutableListOf<IptvChannelEntry>()); position(entry(group = " "))
            assertEquals("", text("iptvZapBannerMeta").text.toString())
        } finally { Locale.setDefault(previous) }
    }
    @Test fun hintVisibilityRequiresZapAndRejectsFavoriteSourceForJumpOnly() {
        setup(); build(); val e = entry(); channels(e, 1); position(e)
        assertEquals(View.GONE, view("iptvZapBannerHintChannel").visibility); assertEquals(View.GONE, view("iptvZapBannerHintJump").visibility)
        set("iptvZapPagingActive", true); position(e)
        assertEquals(View.VISIBLE, view("iptvZapBannerHintChannel").visibility); assertEquals(View.VISIBLE, view("iptvZapBannerHintJump").visibility)
        set("iptvSources", listOf(IptvSourceEntry("fav", "Saved", true, false, false))); set("iptvZapSourceId", "fav"); position(e)
        assertEquals(View.VISIBLE, view("iptvZapBannerHintChannel").visibility); assertEquals(View.GONE, view("iptvZapBannerHintJump").visibility)
        set("iptvZapSourceId", "other"); position(e); assertEquals(View.VISIBLE, view("iptvZapBannerHintJump").visibility)
    }
    @Test fun sameChannelRepaintPreservesLogoRequestButUpdatesPosition() {
        setup(); val e = entry(logo = resource()); channels(e); show(e, true); val first = request()
        val replacement = e.copy(index = 12, group = " News ", logoUrl = "android.resource://com.debrify.app/1")
        show(replacement, true); assertSame("unchanged URL/name do not refetch logo", first, request())
        assertEquals("·  News  ·  13 of 2", text("iptvZapBannerMeta").text.toString())
        assertSame(replacement, field("iptvZapBannerEntry"))
    }
    @Test fun changedNameRepaintsIdentityEvenWhenUrlIsUnchanged() {
        setup(); val e = entry(logo = resource()); channels(e); show(e, true); val first = request()
        show(e.copy(name = "News"), true); assertEquals("News", text("iptvZapBannerName").text.toString())
        assertTrue("outgoing request is cleared", first.isCleared); assertNotSame(first, request())
    }
    @Test fun changedUrlRepaintsIdentityEvenWhenNameIsUnchanged() {
        setup(); val e = entry(logo = resource()); channels(e); show(e, true); val first = request()
        show(e.copy(url = "test://second"), true); assertTrue(first.isCleared); assertNotSame(first, request())
    }
    private fun lifecycleOwner(style: String) {
        setup(style); val e = entry(logo = resource()); channels(e); show(e, true)
        val request = request(); val manager = Glide.with(activity)
        assertTrue("logo belongs to activity manager", TvPlayerOriginalAccess.glideTracks(manager, request))
        assertNotSame(Glide.with(activity.applicationContext), manager)
        lifecycle.pause().stop().destroy(); idle()
        assertTrue("destroy clears logo", request.isCleared); assertFalse(TvPlayerOriginalAccess.glideTracks(manager, request))
    }
    @Test fun classicLogoUsesActivityGlideLifecycleAndClearsOnDestroy() = lifecycleOwner("classic")
    @Test fun glassLogoUsesActivityGlideLifecycleAndClearsOnDestroy() = lifecycleOwner("glass")

    @Suppress("UNCHECKED_CAST")
    private fun logoCallbacks(style: String) {
        setup(style); build(); identity(entry(logo = resource()))
        val target = DrawableImageViewTarget(logo())
        val listeners = TvPlayerOriginalAccess.field(request(), "requestListeners") as List<com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable>>
        assertEquals(1, listeners.size); val listener = listeners.single()
        assertEquals(View.VISIBLE, logo().visibility); assertEquals(View.VISIBLE, view("iptvZapBannerLetter").visibility)
        assertTrue(listener.onLoadFailed(null, resource(), target, true))
        assertEquals(View.GONE, logo().visibility); assertEquals(View.VISIBLE, view("iptvZapBannerLetter").visibility)
        assertEquals("C", text("iptvZapBannerLetter").text.toString())
        assertFalse(listener.onResourceReady(android.graphics.drawable.ColorDrawable(android.graphics.Color.RED), resource(), target,
            com.bumptech.glide.load.DataSource.LOCAL, true))
        assertEquals(View.GONE, view("iptvZapBannerLetter").visibility)
    }
    @Test fun classicLogoListenerPinsFailurePlaceholderAndReadyRetirement() = logoCallbacks("classic")
    @Test fun glassLogoListenerPinsFailurePlaceholderAndReadyRetirement() = logoCallbacks("glass")

    @Test fun windowInstallAndMergeRefreshVisiblePositionAndRetainKnownEpg() {
        setup(); val e = entry(); channels(e); show(e, true)
        set("iptvZapPagingActive", true)
        call("installIptvZapWindow", arrayOf(MutableList::class.java, intType, intType, stringType, listType, boolType),
            mutableListOf(e.copy(index = 0, epgNowTitle = null, epgLoaded = false)), 20, 200, null, emptyList<String>(), true)
        assertEquals("·  Movies  ·  21 of 200", text("iptvZapBannerMeta").text.toString())
        assertEquals("Programme", text("iptvZapBannerNow").text.toString())
        call("mergeIptvZapPage", arrayOf(MutableList::class.java, intType, intType, stringType, listType),
            mutableListOf(e.copy(index = 0, epgNowTitle = null, epgLoaded = false)), 20, 300, null, emptyList<String>())
        assertEquals("·  Movies  ·  21 of 300", text("iptvZapBannerMeta").text.toString())
        assertEquals("Programme", text("iptvZapBannerNow").text.toString())
        banner().visibility = View.INVISIBLE; set("iptvZapCategoryTotal", 400); invoke("refreshIptvZapBannerPosition")
        assertEquals("·  Movies  ·  21 of 300", text("iptvZapBannerMeta").text.toString())
    }
    @Test fun recBadgeReadsCurrentRegistryEveryTickAndHidesWhenTaskStops() {
        setup("console"); val e = entry(); channels(e); set("currentIptvStreamUrl", "https://test.invalid/live.ts"); show(e, true)
        assertEquals(View.GONE, view("iptvZapStyledRec").visibility)
        RecordingRegistry.live["task"] = RecordingRegistry.Live("https://test.invalid/live.ts", "TV", "recording", 0)
        advance(1000); assertEquals(View.VISIBLE, view("iptvZapStyledRec").visibility)
        RecordingRegistry.live.clear(); advance(1000); assertEquals(View.GONE, view("iptvZapStyledRec").visibility)
    }
    @Test fun teeActiveRecordsEvenWithoutEngineTaskAndEngineDisabledIgnoresRegistry() {
        setup("glass"); build()
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putBoolean("flutter.recording_engine_enabled", false).commit()
        set("currentIptvStreamUrl", "https://test.invalid/live.ts")
        RecordingRegistry.live["task"] = RecordingRegistry.Live("https://test.invalid/live.ts", "TV", "recording", 0)
        paint(entry()); assertEquals(View.GONE, view("iptvZapStyledRec").visibility)
        val tee = TvPlayerOriginalAccess.get(activity, "iptvRecordingController")!!; TvPlayerOriginalAccess.set(tee, "active", true)
        paint(entry()); assertEquals(View.VISIBLE, view("iptvZapStyledRec").visibility)
        TvPlayerOriginalAccess.set(tee, "active", false); paint(entry()); assertEquals(View.GONE, view("iptvZapStyledRec").visibility)
    }
}
