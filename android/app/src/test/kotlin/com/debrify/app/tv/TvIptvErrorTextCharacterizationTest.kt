package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvErrorTextCharacterizationTest : TvPhase11OriginalTest() {
    private fun assertErrorText(default: String, request: () -> Unit) {
        for (queued in listOf(false, true)) {
            for (message in listOf("Provider-specific failure", null, "")) {
                ShadowToast.reset()
                request()
                reply("error", queued = queued, message = message)
                if (queued) {
                    assertNull("queued errors cannot show a Toast before delivery", ShadowToast.getTextOfLatestToast())
                    idle()
                }
                assertEquals("preserve nullable server message exactly", message ?: default, ShadowToast.getTextOfLatestToast())
                assertEquals("accepted error shows exactly one Toast", 1, ShadowToast.shownToastCount())
            }
        }
    }

    @Test fun zapPageErrorUsesServerMessageAndNullOnlyFallbackInlineAndQueued() {
        assertErrorText("Unable to load more channels") {
            page { _, _, _, _, _ -> fail("error cannot deliver a loaded page") }
        }
    }

    @Test fun browseErrorUsesServerMessageAndNullOnlyFallbackInlineAndQueued() {
        assertErrorText("Unable to load IPTV catalog") { browse("") }
    }

    @Test fun channelJumpErrorUsesServerMessageAndNullOnlyFallbackInlineAndQueued() {
        assertErrorText("Unable to look up that channel") { jump() }
    }
}
