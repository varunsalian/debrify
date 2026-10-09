package com.debrify.app.tv

import android.view.inputmethod.EditorInfo
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], instrumentedPackages = [
    "com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvIptvGuideChromeController",
])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvChromeBoundaryCharacterizationTest : TvPhase12OriginalTest() {
    @Test fun nonHttpSchemesLeaveEpgStateAndTransportUntouched() {
        for (url in listOf("rtmp://host/live", "udp://host/live", "stremio-tv://id",
            "ftp://host/live", "file:///live", "HTTP://host/live", "", " http://host/live")) {
            clearTransport()
            val e = entry().copy(url = url)
            ensure(e)
            assertTrue("No EPG request for $url", requests("requestIptvEpg").isEmpty())
            assertFalse(e.epgLoading)
            assertFalse(e.epgLoaded)
            assertFalse(e.epgCatchupMetadataLoaded)
        }
    }

    @Test fun httpPrefixIncludesHttpsAndLegacyHttpishUrls() {
        for (url in listOf("http://host/live", "https://host/live", "httpish", "http")) {
            clearTransport()
            val e = entry(false).copy(url = url)
            ensure(e)
            assertEquals(1, requests("requestIptvEpg").size)
            assertEquals(url, args("requestIptvEpg")["channelUrl"])
            assertTrue(e.epgLoading)
        }
    }

    private fun staleRetry(queued: Boolean, currentAtDeadline: Boolean, finishing: Boolean = false) {
        val e = playing()
        ensure(e)
        epgAnswer(value = epgReply(archive = false), queued = queued)
        idle()
        e.isCurrent = false
        // An expired row prevents the freshness guard from masking the retry's current guard.
        e.epgNowStopMs = 1L
        untilUptime(replyUptime + 59_999)
        assertEquals(1, requests("requestIptvEpg").size)
        assertTrue(e.epgCatchupMetadataLoaded)
        e.isCurrent = currentAtDeadline
        if (finishing) activity.finish()
        untilUptime(replyUptime + 60_000)
        assertFalse("Metadata clears before the current/lifecycle guards", e.epgCatchupMetadataLoaded)
        assertEquals(if (currentAtDeadline && !finishing) 2 else 1, requests("requestIptvEpg").size)
        assertEquals(currentAtDeadline && !finishing, e.epgLoading)
        if (currentAtDeadline && !finishing) {
            assertEquals(true, args("requestIptvEpg")["includeCatchupMetadata"])
        }
    }

    @Test fun inlineArchiveRetrySkipsExpiredChannelNoLongerCurrent() = staleRetry(false, false)
    @Test fun queuedArchiveRetrySkipsExpiredChannelNoLongerCurrent() = staleRetry(true, false)
    @Test fun retryReadsCurrentAgainAtDeadlineAfterChannelReturns() = staleRetry(false, true)
    @Test fun retrySkipsExpiredCurrentChannelWhileFinishing() = staleRetry(false, true, true)

    private fun openJump() {
        call("showIptvChannelJumpDialog", emptyArray())
        clearTransport()
    }

    @Test fun zeroJumpButtonShowsErrorWithoutDismissingOrRequesting() {
        openJump()
        val input = dialogInput()
        input.setText("0")
        dialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        assertEquals("Enter a valid channel number", input.error?.toString())
        assertTrue(dialog().isShowing)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun zeroJumpEditorGoShowsErrorWithoutDismissingOrRequesting() {
        openJump()
        val input = dialogInput()
        input.setText(" 0 ")
        assertTrue(editor(input, EditorInfo.IME_ACTION_GO))
        assertEquals("Enter a valid channel number", input.error?.toString())
        assertTrue(dialog().isShowing)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun invalidJumpNumbersIncludeNegativeAndIntegerOverflowBoundaries() {
        openJump()
        val input = dialogInput()
        for (value in listOf("", " ", "-1", Int.MIN_VALUE.toString(), "2147483648", "-2147483649", "1.0", "abc")) {
            input.error = null
            input.setText(value)
            dialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertEquals("Invalid channel number: $value", "Enter a valid channel number", input.error?.toString())
            assertTrue(dialog().isShowing)
            assertTrue(requests("requestIptvBrowse").isEmpty())
        }
    }

    @Test fun positiveJumpNumbersIncludeOneAndIntegerMaximum() {
        for (value in listOf(" 1 ", "+1", Int.MAX_VALUE.toString())) {
            openJump()
            val d = dialog()
            val input = dialogInput()
            input.setText(value)
            d.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertFalse(d.isShowing)
            assertNull(input.error)
            assertEquals(1, requests("requestIptvBrowse").size)
            assertEquals(value.trim().toInt(), args("requestIptvBrowse")["channelNumber"])
            // The original pager rejects another jump while the first request is in flight.
            set("iptvZapRequestInFlight", false)
        }
    }
}
