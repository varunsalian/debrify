package com.debrify.app.tv

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.os.Looper
import android.widget.ImageView
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPoolAdapter
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode
import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.ServerSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class StreamBadgeSvgTest {
    private val svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><rect width="100" height="20" fill="#ff0000"/></svg>"""
    private val dashedSvg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><path d="M0 10H100" stroke="red" stroke-dasharray="0.001 0.001"/></svg>"""

    @Test fun rejectsDashExpansionInAttributesAndInheritedInlineDeclarations() {
        val inputs = listOf(
            dashedSvg,
            dashedSvg.replace("stroke-dasharray=\"0.001 0.001\"", "style=\"stroke-dasharray: 0.001 0.001\""),
            """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20" stroke-dasharray="0.001 0.001"><path d="M0 10H100" stroke="red"/></svg>""",
            """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><g style="stroke: red; stroke-dasharray: 0.001 0.001"><path d="M0 10H100" stroke-dasharray="inherit"/></g></svg>""",
            dashedSvg.replace("stroke-dasharray=\"0.001 0.001\"", "style=\"stroke-da/**/sharray: 0.001 0.001\""),
            dashedSvg.replace("stroke-dasharray=\"0.001 0.001\"", "style=\"stroke-dasharray: 1e-8,1e-8; stroke-dasharray: none\""),
        )
        for (input in inputs) assertThrows(IOException::class.java) { validateBadgeSvg(input.toByteArray()) }
    }

    @Test fun rendersAspectRatioColourAndBoundedBitmap() {
        val decoder = BadgeSvgDecoder(BitmapPoolAdapter())
        val image = decoder.decode(BadgeSvgBytes(svg.toByteArray()), 210, 30, Options())
        assertEquals(150, image.get().width)
        assertEquals(30, image.get().height)
        assertEquals(Color.RED, image.get().getPixel(75, 15))
        image.recycle()
    }
    @Test fun rootDimensionsWithoutViewBoxAndTransparentPixelsArePreserved() {
        val text = """<svg xmlns="http://www.w3.org/2000/svg" width="100" height="20"><rect x="10" width="80" height="20" fill="#00ff00"/></svg>"""
        val image = BadgeSvgDecoder(BitmapPoolAdapter()).decode(BadgeSvgBytes(text.toByteArray()), 210, 30, Options())
        assertEquals(Color.TRANSPARENT, image.get().getPixel(0, 0))
        assertEquals(Color.GREEN, image.get().getPixel(75, 15))
        image.recycle()
    }
    @Test fun routingHandlesQueriesAndUpperCaseWithoutChangingPng() {
        assertTrue(isBadgeSvgUrl("https://host/logo.SVG?raw=true"))
        assertFalse(isBadgeSvgUrl("https://host/logo.png?file=x.svg"))
        assertTrue(isBadgeBitmapUrl("https://host/logo.PNG?raw=true"))
        assertFalse(isBadgeBitmapUrl("https://host/logo"))
    }
    @Test fun rejectsActiveExternalRecursiveAndOversizedArtwork() {
        val bad = listOf(
            "<script/>", "<image href=\"https://host/x.png\"/>", "<use href=\"#a\"/>",
            "<animate/>", "<filter/>", "<foreignObject/>", "<path onload=\"bad()\"/>",
            "<path fill=\"url(https://host/a)\"/>", "<style>@import 'https://host/a';</style>",
            "<linearGradient id=\"a\" href=\"#b\"/><linearGradient id=\"b\" href=\"#a\"/>",
            "<mask id=\"a\"><path mask=\"url(#a)\"/></mask>",
            "<g>".repeat(34) + "</g>".repeat(34), "<path/>".repeat(2048),
            " ".repeat(MAX_BADGE_SVG_BYTES),
        )
        bad.forEach { body ->
            assertThrows(Exception::class.java) { validateBadgeSvg("<svg>$body</svg>".toByteArray()) }
        }
        assertThrows(Exception::class.java) { validateBadgeSvg("<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><svg>&x;</svg>".toByteArray()) }
        assertThrows(Exception::class.java) { validateBadgeSvg("<html/>".toByteArray()) }
    }
    @Test fun byteReaderRejectsOversizedResponsesWithoutAllocatingTheirFullSize() {
        assertThrows(Exception::class.java) { readBadgeSvg(ByteArrayInputStream(ByteArray(MAX_BADGE_SVG_BYTES + 1))) }
        assertArrayEquals(svg.toByteArray(), readBadgeSvg(ByteArrayInputStream(svg.toByteArray())))
    }
    @Test fun rejectsExponentialReferenceExpansionWithoutRequiringACycle() {
        val masks = (0..11).joinToString("") { "<mask id=\"m$it\"><path mask=\"url(#m${it + 1})\"/><path mask=\"url(#m${it + 1})\"/></mask>" }
        assertThrows(Exception::class.java) { validateBadgeSvg("<svg><defs>$masks<mask id=\"m12\"><path/></mask></defs></svg>".toByteArray()) }
    }
    @Test fun rejectsLinearMaskChainsWithMultiplicativeRenderCost() {
        assertThrows(IOException::class.java) { validateBadgeSvg(maskChain(30).toByteArray()) }
    }
    @Test fun rejectsStylesheetReferencesWithoutAssigningThemToStyleAncestors() {
        assertThrows(IOException::class.java) { validateBadgeSvg(stylesheetCycle.toByteArray()) }
    }
    @Test fun rejectsPerVertexMarkerExpansionAndInheritedMarkerCycles() {
        for (input in listOf(markerChain, inheritedMarkerCycle)) {
            assertThrows(IOException::class.java) { validateBadgeSvg(input.toByteArray()) }
        }
    }
    @Test fun rejectsStylesheetArtworkInsteadOfAcceptingDifferentPlatformColours() {
        assertThrows(IOException::class.java) { validateBadgeSvg(stylesheetColour.toByteArray()) }
    }
    @Test fun countsRepeatedMaskUsesOnElementsWithoutIds() {
        val repeated = maskChain(7).replace("</svg>", """<rect width="100" height="20" mask="url(#m0)"/>""".repeat(20) + "</svg>")
        assertThrows(IOException::class.java) { validateBadgeSvg(repeated.toByteArray()) }
    }
    @Test fun rejectsObfuscatedStylesheetReferencesAndOwnedInlineCycles() {
        for (reference in listOf("URL( '#c' )", "u/**/rl(#c)", "u\\72l(#c)", "url(/**/#c)")) {
            val input = stylesheetCycle.replace("clip-path: url(#c)", "clip-path: $reference")
            assertThrows(IOException::class.java) { validateBadgeSvg(input.toByteArray()) }
        }
        val inlineCycle = stylesheetCycle.replace("<style>.loop { clip-path: url(#c); }</style>", "")
            .replace("class=\"loop\"", "style=\"clip-path: u/**/rl(#c)\"")
        assertThrows(IOException::class.java) { validateBadgeSvg(inlineCycle.toByteArray()) }
        val cssMask = maskChain(2).replace("<defs>", "<style>rect { mask: url(#m0); }</style><defs>")
        assertThrows(IOException::class.java) { validateBadgeSvg(cssMask.toByteArray()) }
    }
    @Test fun rejectedInputsNeverReachBitmapAllocationOrRasterization() {
        val pool = object : BitmapPoolAdapter() {
            override fun get(width: Int, height: Int, config: Bitmap.Config): Bitmap {
                throw AssertionError("Rejected SVG reached bitmap allocation")
            }
        }
        val decoder = BadgeSvgDecoder(pool)
        for (input in listOf(maskChain(30), stylesheetCycle, stylesheetColour, markerChain, inheritedMarkerCycle, dashedSvg)) {
            assertThrows(IOException::class.java) {
                decoder.decode(BadgeSvgBytes(input.toByteArray()), 210, 30, Options())
            }
        }
    }
    @Test fun explicitDashNoneRetainsSolidStrokeRendering() {
        for (declaration in listOf("stroke-dasharray=\"none\"", "style=\"stroke-dasharray: none\"")) {
            val input = dashedSvg.replace("stroke-dasharray=\"0.001 0.001\"", declaration)
                .replace("stroke=\"red\"", "stroke=\"red\" stroke-width=\"2\"")
            val resource = BadgeSvgDecoder(BitmapPoolAdapter()).decode(BadgeSvgBytes(input.toByteArray()), 150, 30, Options())
            try {
                assertEquals(Color.RED, resource.get().getPixel(75, 15))
                assertEquals(Color.TRANSPARENT, resource.get().getPixel(0, 0))
            } finally { resource.recycle() }
        }
    }
    @Test fun simpleMasksInlineColoursGradientsAndClipsStillRender() {
        val inputs = listOf(
            maskChain(2),
            """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs><clipPath id="c"><rect width="100" height="20"/></clipPath></defs><rect width="100" height="20" style="fill: #ff0000; clip-path: url(#c)"/></svg>""",
            """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs><linearGradient id="g"><stop stop-color="red"/><stop offset="1" stop-color="red"/></linearGradient></defs><rect width="100" height="20" fill="url(#g)"/></svg>""",
        )
        for (input in inputs) {
            val result = BadgeSvgDecoder(BitmapPoolAdapter()).decode(BadgeSvgBytes(input.toByteArray()), 210, 30, Options())
            try {
                assertEquals(Color.RED, result.get().getPixel(75, 15))
            } finally { result.recycle() }
        }
    }

    private fun maskChain(count: Int): String {
        val masks = (0 until count).joinToString("") { i ->
            val reference = if (i + 1 < count) " mask=\"url(#m${i + 1})\"" else ""
            "<mask id=\"m$i\"><rect width=\"100\" height=\"20\" fill=\"white\"$reference/></mask>"
        }
        return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs>$masks</defs><rect width="100" height="20" fill="red" mask="url(#m0)"/></svg>"""
    }
    private val stylesheetCycle = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><style>.loop { clip-path: url(#c); }</style><defs><clipPath id="c" class="loop"><rect width="100" height="20"/></clipPath></defs><rect width="100" height="20" clip-path="url(#c)"/></svg>"""
    private val stylesheetColour = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><style>.red { fill: #ff0000; }</style><rect class="red" width="100" height="20"/></svg>"""
    private val markerPoints = "0,0 1,1 2,0 3,1 4,0 5,1"
    private val markerChain: String get() {
        val markers = (0..6).joinToString("") { i ->
            val reference = if (i < 6) " marker-mid=\"url(#m${i + 1})\"" else ""
            "<marker id=\"m$i\"><polyline points=\"$markerPoints\"$reference/></marker>"
        }
        return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs>$markers</defs><polyline points="$markerPoints" marker-mid="url(#m0)"/></svg>"""
    }
    private val inheritedMarkerCycle: String get() = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20" marker-mid="url(#m)"><defs><marker id="m"><polyline points="$markerPoints"/></marker></defs><polyline points="$markerPoints"/></svg>"""
    @Test fun registeredDecoderWorksThroughGlideAndSharesWarmBitmaps() {
        val lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = lifecycle.get()
        val server = SvgTestServer(svg)
        val targets = mutableListOf<com.bumptech.glide.request.FutureTarget<android.graphics.Bitmap>>()
        try {
            StreamBadgeSvg.register(activity)
            StreamBadgeSvg.register(activity)
            // Exercise the production URL fetcher, decoder and warm cache.
            // Only a local loopback HTTP server is used.
            val glide = com.bumptech.glide.Glide.with(activity as Context)
            val data = BadgeSvgUrl("http://127.0.0.1:${server.localPort}/badge.svg")
            fun load() = java.util.concurrent.Executors.newSingleThreadExecutor().let { executor ->
                try { executor.submit<android.graphics.Bitmap> {
                    val target = glide.asBitmap().load(data).override(210, 30)
                        .diskCacheStrategy(com.bumptech.glide.load.engine.DiskCacheStrategy.RESOURCE).submit()
                    targets.add(target)
                    target.get(10, java.util.concurrent.TimeUnit.SECONDS)
                }.get(15, java.util.concurrent.TimeUnit.SECONDS) } finally { executor.shutdownNow() }
            }
            val first = load()
            val second = load()
            assertSame(first, second)
            assertEquals(Color.RED, second.getPixel(75, 15))
            assertEquals(1, server.requests.get())
        } finally {
            targets.forEach { com.bumptech.glide.Glide.with(activity as Context).clear(it) }
            server.close()
            lifecycle.pause().stop().destroy()
        }
    }

    @Test fun productionStripRendersSvgAndExtensionlessArtworkAndRetainsViews() {
        val lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = lifecycle.get()
        val server = SvgTestServer(svg)
        try {
            for (path in listOf("badge.SVG?raw=true", "badge")) {
                val strip = TvStreamBadgeStrip(activity)
                activity.setContentView(strip)
                val badges = listOf(mapOf<String, Any>(
                    "label" to "4K", "imageUrl" to "http://127.0.0.1:${server.localPort}/$path",
                    "fillColor" to Color.BLACK, "textColor" to Color.WHITE,
                ))
                strip.show(badges)
                val view = strip.getChildAt(0) as ImageView
                val deadline = System.nanoTime() + 10_000_000_000L
                while (view.drawable !is BitmapDrawable && System.nanoTime() < deadline) {
                    shadowOf(Looper.getMainLooper()).idle()
                    Thread.sleep(10)
                }
                assertTrue("SVG should render through the production Drawable request: $path", view.drawable is BitmapDrawable)
                val bitmap = (view.drawable as BitmapDrawable).bitmap
                assertEquals(Color.RED, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
                repeat(8) {
                    strip.show(badges)
                    assertSame(view, strip.getChildAt(0))
                    assertSame(bitmap, (view.drawable as BitmapDrawable).bitmap)
                }
                strip.show(emptyList())
            }
        } finally {
            server.close()
            lifecycle.pause().stop().destroy()
        }
    }
}

/** Local HTTP only: exercise the real Glide fetch/decode path without a CDN. */
private class SvgTestServer(svg: String) : java.io.Closeable {
    private val server = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
    val localPort get() = server.localPort
    val requests = AtomicInteger()
    private val serverThread = Thread {
        try {
            while (!server.isClosed) server.accept().use { socket ->
                socket.soTimeout = 5000
                val reader = socket.getInputStream().bufferedReader()
                while (!reader.readLine().isNullOrEmpty()) { /* headers */ }
                requests.incrementAndGet()
                val bytes = svg.toByteArray()
                socket.getOutputStream().apply {
                    write("HTTP/1.1 200 OK\r\nContent-Type: image/svg+xml\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
                    write(bytes)
                    flush()
                }
            }
        } catch (e: java.io.IOException) { if (!server.isClosed) throw e }
    }.apply { isDaemon = true; start() }

    override fun close() {
        server.close()
        serverThread.join(1000)
    }
}
