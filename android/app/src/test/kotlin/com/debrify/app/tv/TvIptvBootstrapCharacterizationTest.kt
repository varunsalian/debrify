package com.debrify.app.tv
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvBootstrapCharacterizationTest : TvPhase11OriginalTest() {
    @Test fun bootstrapInstallsGuideAndPlaybackSourceContext() {
        assertEquals("Provider",field("iptvZapSourceName"))
        assertEquals("provider",field("iptvZapSourceId"))
        assertEquals("News",field("iptvZapCategory"))
        assertEquals(listOf("News","Movies"),field("iptvZapCategories"))
        assertTrue(field("iptvZapOwnsUiContext") as Boolean)
        assertEquals(2,adapter().itemCount)
        assertSame(guideList(),activity.findViewById(com.debrify.app.R.id.iptv_guide_list))
    }
}
