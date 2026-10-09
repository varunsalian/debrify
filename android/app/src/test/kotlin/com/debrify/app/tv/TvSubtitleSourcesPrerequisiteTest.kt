package com.debrify.app.tv

import android.os.Looper
import android.view.View
import android.widget.ProgressBar
import com.debrify.app.subtitle.AddonSubtitleStatus
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourcesPrerequisiteTest : TvPhase14OriginalTest() {
    @Test fun blockedAttemptRetainsProductionIoAndMainPublication() {
        installAddons(addon())
        val response = response()
        known(); entered(response)
        val job = jobs().single()
        assertTrue(loading()); assertTrue(discovery())
        assertEquals(AddonSubtitleStatus.LOADING, slots().single().status)
        assertTrue(flat().isEmpty())
        assertEquals(listOf(addon(), "https://phase14.invalid/a/subtitles/movie/tt140.json"), response.arguments)
        response.release.countDown()
        assertTrue(response.returned.await(5, java.util.concurrent.TimeUnit.SECONDS))
        assertEquals("IO return alone cannot publish on paused Main", AddonSubtitleStatus.LOADING, slots().single().status)
        settle(job)
        assertEquals(AddonSubtitleStatus.OK, slots().single().status)
        assertEquals(listOf(subtitle()), flat()); assertFalse(loading())
    }

    private fun search(delivery: TvPhase14EndpointMessenger.Delivery) {
        showSearch(); query().setText("  film query  "); searchButton().performClick()
        assertEquals(mapOf("query" to "film query"), catalogRequest().call.arguments)
        assertEquals("Searching...", status().text.toString())
        assertFalse(searchButton().isEnabled); assertFalse(query().isEnabled)
        assertEquals(View.VISIBLE, descendants().filterIsInstance<ProgressBar>().single().visibility)
        endpoint.success("searchSubtitleCatalogs", catalog(result()), delivery)
        if (delivery != TvPhase14EndpointMessenger.Delivery.INLINE) {
            assertEquals("Catalog completion waits for Main dispatch", "Searching...", status().text.toString())
            assertEquals(0, resultList().adapter.count)
            if (delivery == TvPhase14EndpointMessenger.Delivery.WORKER)
                assertNotEquals(Thread.currentThread(), endpoint.replyThread)
            idle()
        } else {
            assertEquals(Thread.currentThread(), endpoint.replyThread)
        }
        assertEquals("1 result", status().text.toString())
        assertEquals(1, resultList().adapter.count)
        assertTrue(searchButton().isEnabled); assertTrue(query().isEnabled)
        assertEquals(View.GONE, descendants().filterIsInstance<ProgressBar>().single().visibility)
        assertSame(Looper.getMainLooper(), Looper.myLooper())
    }
    @Test fun catalogInlineReplyClearsDialogLoadingInline() = search(TvPhase14EndpointMessenger.Delivery.INLINE)
    @Test fun catalogQueuedMainReplyRetainsLoadingUntilMainRuns() = search(TvPhase14EndpointMessenger.Delivery.QUEUED_MAIN)
    @Test fun catalogWorkerReplyDispatchesPublicationOntoMain() = search(TvPhase14EndpointMessenger.Delivery.WORKER)

    @Test fun catalogNullChannelAndSendFailureSynchronouslyClearDialogLoading() {
        showSearch(); noChannel(); searchButton().performClick()
        assertEquals("Subtitle search is unavailable.", status().text.toString())
        assertTrue(searchButton().isEnabled); assertEquals(View.GONE, descendants().filterIsInstance<ProgressBar>().single().visibility)
        connect(); endpoint.throwingEndpoints.add("searchSubtitleCatalogs"); searchButton().performClick()
        assertEquals("Subtitle search failed.", status().text.toString())
        assertTrue(query().isEnabled); assertTrue(searchButton().isEnabled)
    }

    @Test fun metadataNullChannelMakesNoCallbackAndLeavesSourceLoading() {
        model().imdbId = null
        noChannel(); fetch()
        assertTrue("No metadata callback means loading remains pending", loading())
        assertFalse(model().perItemImdbIds.containsKey(item().index))
        assertTrue(endpoint.requests.isEmpty())
    }

    @Test fun metadataSendFailureSynchronouslyCachesNullAndClearsSourceLoading() {
        model().imdbId = null
        endpoint.throwingEndpoints.add("requestMovieMetadata"); fetch()
        assertFalse(loading()); assertTrue(discovery())
        assertTrue("Send failure invokes the metadata callback synchronously", model().perItemImdbIds.containsKey(item().index))
        assertNull(model().perItemImdbIds[item().index])
    }

    @Test fun shownDialogInstallsQueryImeRowAndPositiveButtonCallbacks() {
        showSearch()
        assertEquals("Film", query().text.toString())
        assertTrue(searchButton().hasFocus())
        query().onEditorAction(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH)
        assertEquals("searchSubtitleCatalogs", catalogRequest().call.method)
        endpoint.success("searchSubtitleCatalogs", catalog(result("series")))
        resultList().performItemClick(null, 0, 0)
        layoutDialog()
        assertEquals("Series Episode", dialog().findViewById<android.widget.TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        val inputs = descendants().filterIsInstance<android.widget.EditText>()
        assertEquals(listOf("1", "1"), inputs.map { it.text.toString() })
        assertTrue(inputs[0].hasFocus())
        inputs[0].setText("3"); inputs[1].setText("7")
        dialog().getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE).performClick()
        assertEquals("tt141", field("manualSubtitleImdbId"))
        assertEquals(3, field("manualSubtitleSeason")); assertEquals(7, field("manualSubtitleEpisode"))
        assertFalse(dialog().isShowing)
    }
}
