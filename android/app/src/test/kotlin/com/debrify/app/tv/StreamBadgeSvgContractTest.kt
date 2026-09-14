package com.debrify.app.tv

import com.bumptech.glide.load.Options
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPoolAdapter
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StreamBadgeSvgContractTest {
    @Test fun sharedNormalizationAndPixelContract() {
        val fixtures = JSONArray(File("../../test/fixtures/stream_badge_svg_contract.json").readText())
        for (i in 0 until fixtures.length()) {
            val fixture = fixtures.getJSONObject(i)
            val name = fixture.getString("name")
            val svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20" ${fixture.optString("root")}>${fixture.getString("body")}</svg>"""
            if (!fixture.getBoolean("accept")) {
                assertThrows(name, Exception::class.java) { validateBadgeSvg(svg.toByteArray()) }
                continue
            }
            val normalized = validateBadgeSvg(svg.toByteArray())
            assertFalse(name, normalized.contains("style="))
            assertEquals(name, normalized, validateBadgeSvg(normalized.toByteArray()))
            val resource = BadgeSvgDecoder(BitmapPoolAdapter()).decode(BadgeSvgBytes(svg.toByteArray()), 100, 20, Options())
            try {
                val rgba = fixture.getString("pixel").toLong(16)
                val argb = ((rgba and 0xff) shl 24) or (rgba ushr 8)
                assertEquals(name, argb.toInt(), resource.get().getPixel(50, 10))
            } finally { resource.recycle() }
        }
    }

    @Test fun depthIsRejectedBeforeAndroidsRecursiveDomParserRuns() {
        val property = "javax.xml.parsers.DocumentBuilderFactory"
        val previous = System.getProperty(property)
        try {
            // Robolectric otherwise uses the desktop JDK's different DOM parser.
            System.setProperty(property, "org.apache.harmony.xml.parsers.DocumentBuilderFactoryImpl")
            // Also exercise valid parsing and serialization with Android's DOM.
            val valid = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><rect width="100" height="20" style="fill:red"/></svg>"""
            val resource = BadgeSvgDecoder(BitmapPoolAdapter()).decode(BadgeSvgBytes(valid.toByteArray()), 100, 20, Options())
            try { assertEquals(android.graphics.Color.RED, resource.get().getPixel(50, 10)) }
            finally { resource.recycle() }
            for (depth in listOf(100, 5000, 15000)) {
                val svg = "<svg>" + "<g>".repeat(depth) + "</g>".repeat(depth) + "</svg>"
                assertThrows(IOException::class.java) { validateBadgeSvg(svg.toByteArray()) }
            }
        } finally {
            if (previous == null) System.clearProperty(property) else System.setProperty(property, previous)
        }
    }

    @Test fun maskExpansionBudgetIncludesGeometryNotJustXmlNodes() {
        val path = "M0 0" + "L1 1".repeat(4000)
        val masks = (0..4).joinToString("") { i ->
            val reference = if (i < 4) " mask=\"url(#m${i + 1})\"" else ""
            "<mask id=\"m$i\"><path d=\"$path\"$reference/></mask>"
        }
        val svg = "<svg><defs>$masks</defs><path mask=\"url(#m0)\"/></svg>"
        assertTrue(svg.length < MAX_BADGE_SVG_BYTES)
        assertThrows(IOException::class.java) { validateBadgeSvg(svg.toByteArray()) }
    }
}
