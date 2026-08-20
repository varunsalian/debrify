package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class SourceQualityParserTest {
    @Test
    fun explicit1080pWinsOverEmbeddedDs4k() {
        assertEquals(
            "1080p",
            SourceQualityParser.badge("Obsession.2026.1080p.10bit.DS4K.BluRay.x265"),
        )
        assertEquals(null, SourceQualityParser.badge("Obsession.2026.DS4K.BluRay.x265"))
    }

    @Test
    fun standalone4kStillProduces4kBadge() {
        assertEquals("4K", SourceQualityParser.badge("Movie.2026.4K.WEB-DL"))
    }
}
