package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

/** Real renderers re-read their providers; transport replies stay inline for these refresh contracts. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPhase10RefreshCharacterizationTest : TvPhase10OriginalTest() {
    private var menuReads = 0
    private var browserReads = 0
    private var menuReadsPerRender = 0
    private var browserReadsPerRender = 0
    private fun prepareRefreshViews() {
        set("seriesSourceTabs", true)
        set("seriesPacksFetched", false)
        val menu = field("unifiedMenu") as UnifiedMenuController
        val original = ReflectionHelpers.getField<UnifiedMenuController.Callbacks>(menu, "callbacks")
        // The legacy Sources model is unreachable from today's rail. Exercise that
        // original provider with the real renderer, without editing production navigation.
        ReflectionHelpers.setField(menu, "sectionIds", listOf("sources"))
        ReflectionHelpers.setField(menu, "callbacks", object : UnifiedMenuController.Callbacks by original {
            override fun buildModel(sectionIndex: Int, col2Index: Int): UnifiedMenuController.Model {
                menuReads++
                return call("umSourcesModel", arrayOf(listType, intType),
                    listOf(UnifiedMenuController.Row("Sources")), col2Index) as UnifiedMenuController.Model
            }
        })
        menu.show("sources")
        val callbacks = ReflectionHelpers.getField<TvSourceBrowserController.Callbacks>(browser(), "callbacks")
        ReflectionHelpers.setField(browser(), "callbacks", object : TvSourceBrowserController.Callbacks by callbacks {
            override fun entries(): List<TvSourceBrowserEntry> { browserReads++; return callbacks.entries() }
        })
        browser().show()
        menuReads = 0; browserReads = 0
        menu.render(); menuReadsPerRender = menuReads
        browser().render(); browserReadsPerRender = browserReads
        assertTrue(menuReadsPerRender > 0); assertTrue(browserReadsPerRender > 0)
        resetReads()
    }
    private fun resetReads() { menuReads = 0; browserReads = 0 }
    private fun assertRefreshes(menu: Int, browser: Int) {
        assertEquals("unified menu re-evaluates its live model for each refresh", menu * menuReadsPerRender, menuReads)
        assertEquals("source browser re-evaluates its live entries for each refresh", browser * browserReadsPerRender, browserReads)
    }
    private fun textUnder(id: Int): List<String> {
        fun read(v: View): List<String> = when(v) {
            is ViewGroup -> (0 until v.childCount).flatMap { read(v.getChildAt(it)) }
            is TextView -> listOf(v.text.toString())
            else -> emptyList()
        }
        return read(activity.findViewById(id))
    }
    private fun addons() { set("sourceAddons", listOf(AndroidTvTorrentPlayerActivity.TvSourceAddon("one", "One", "group"))) }
    @Test fun fetchMoreStartRepaintsLegacyMenuIntoLoadingAndRefreshesBrowser() {
        prepareRefreshViews(); assertTrue(textUnder(R.id.unified_col3).any { it.contains("Load more sources") })
        more(); assertRefreshes(1, 1)
        assertTrue("bound loading row replaces the action", textUnder(R.id.unified_col3).any { it.contains("Loading more sources…") })
    }
    @Test fun fetchMoreSuccessRefreshesBothViewsAfterAdoptionAndUnlock() {
        prepareRefreshViews(); more(); resetReads(); callback(value=result("packsFetched" to true)); assertRefreshes(1, 1)
        assertFalse(textUnder(R.id.unified_col3).any { it.contains("Loading more sources…") })
        assertEquals("1 source", activity.findViewById<TextView>(R.id.tv_source_browser_count).text.toString())
    }
    @Test fun fetchMoreNullReplyRefreshesMenuAndBrowserAfterShowingBrowserError() {
        prepareRefreshViews(); more(); resetReads(); callback(); assertRefreshes(1, 2)
        assertTrue(textUnder(R.id.unified_col3).any { it.contains("Load more sources") })
        assertEquals("Couldn't load more sources — try again", activity.findViewById<TextView>(R.id.tv_source_browser_context).text.toString())
    }
    @Test fun fetchMoreErrorAndMissingRepliesEachRefreshBothViews() {
        prepareRefreshViews()
        for(kind in listOf("error", "missing")) {
            more(); resetReads(); callback(kind); assertRefreshes(1, 2)
            assertTrue(textUnder(R.id.unified_col3).any { it.contains("Load more sources") })
        }
    }
    @Test fun episodeSourceAdoptionRefreshesUnifiedMenuBeforeReplacementPlayback() {
        prepareRefreshViews(); fetch(); resetReads(); callback(value=result()); assertRefreshes(1, 1)
        assertEquals("Fetched source", sources().single().name)
    }
    @Test fun adjacentEpisodeSourceAdoptionRefreshesUnifiedMenuBeforeReplacementPlayback() {
        prepareRefreshViews(); adjacent(); resetReads(); callback(value=result()); assertRefreshes(1, 1)
        assertEquals("Fetched source", sources().single().name)
    }
    @Test fun addonStartRefreshesBrowserAfterFetchingStateIsSet() {
        addons(); prepareRefreshViews(); addon(); assertRefreshes(0, 1)
    }
    @Test fun addonEpisodeSuccessWithoutProbeRefreshesBothViews() {
        addons(); prepareRefreshViews(); addon(); resetReads(); callback(value=result()); assertRefreshes(1, 1)
    }
    @Test fun addonEpisodeSuccessWithProbeRefreshesBrowserAfterProbingStateIsSet() {
        addons(); prepareRefreshViews(); addon(); resetReads(); callback(value=result("packAddonIds" to listOf("one"))); assertRefreshes(1, 1)
        assertTrue((field("addonPackProbing") as Set<*>).contains("group"))
    }
    @Test fun addonProbeWithoutBridgeRefreshesBrowserAgainAfterRetiringProbe() {
        addons(); prepareRefreshViews(); addon(); noChannel(); resetReads(); callback(value=result("packAddonIds" to listOf("one"))); assertRefreshes(1, 2)
        assertTrue((field("addonPackProbing") as Set<*>).isEmpty())
    }
    @Test fun addonPackSuccessRefreshesBothViewsAfterAdoptionAndRetiringProbe() {
        addons(); prepareRefreshViews(); addon(); callback(value=result("packAddonIds" to listOf("one"))); resetReads(); callback(value=result()); assertRefreshes(1, 1)
        assertTrue((field("addonPackProbing") as Set<*>).isEmpty())
    }
    @Test fun addonPackErrorAndMissingEachRefreshBrowserAfterRetiringProbe() {
        addons(); prepareRefreshViews()
        for(kind in listOf("error", "missing")) {
            @Suppress("UNCHECKED_CAST") (field("addonFetchState") as MutableMap<String, String>).clear()
            addon(); callback(value=result("packAddonIds" to listOf("one"))); resetReads(); callback(kind); assertRefreshes(0, 1)
            assertTrue((field("addonPackProbing") as Set<*>).isEmpty())
        }
    }
    @Test fun addonNullErrorAndMissingEachRefreshBrowserIntoFailedState() {
        addons(); prepareRefreshViews()
        for(kind in listOf("success", "error", "missing")) {
            @Suppress("UNCHECKED_CAST") (field("addonFetchState") as MutableMap<String, String>).clear()
            addon(); resetReads(); callback(kind); assertRefreshes(0, 1)
        }
    }
    @Test fun pikPakHideCancelsTheActiveFadeAndClearsAlphaAndVisibility() {
        call("showPikPakRetryOverlay", arrayOf(stringType), "warming")
        tick(100)
        gateHost("hidePikPakRetryOverlay", emptyArray())
        val overlay = view("pikPakReactivationIndicator")
        assertEquals(0f, overlay.alpha, 0f); assertEquals(View.GONE, overlay.visibility)
        tick(300); assertEquals("cancelled show cannot repaint hidden overlay", 0f, overlay.alpha, 0f)
    }
    @Test fun queuedPikPakShowReadsLivenessBeforeRepaintingEitherLabel() {
        val label = field("pikPakReactivationText") as TextView
        val status = field("startupGateStatus") as TextView
        cursor(); label.text = "prior overlay"; status.text = "prior gate"
        val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val worker = Thread { try { call("showPikPakRetryOverlay", arrayOf(stringType), "late warming") } catch(t: Throwable) { failure.set(t) } }
        worker.start(); worker.join(5000)
        assertFalse("overlay worker completed", worker.isAlive)
        failure.get()?.let { throw AssertionError("overlay worker failed", it) }
        destroyed(true); tick(32)
        assertEquals("prior overlay", label.text.toString()); assertEquals("prior gate", status.text.toString())
        destroyed(false)
    }

}
