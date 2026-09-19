package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class TvControlsSkinTest {
    @Test
    fun explicitMarqueeRemainsMarquee() {
        assertEquals(TvControlsSkin.MARQUEE, TvControlsSkin.fromPref("marquee"))
    }

    @Test
    fun missingAndUnknownPreferencesDefaultToOtt() {
        assertEquals(TvControlsSkin.OTT, TvControlsSkin.fromPref(null))
        assertEquals(TvControlsSkin.OTT, TvControlsSkin.fromPref("unknown"))
    }
}
