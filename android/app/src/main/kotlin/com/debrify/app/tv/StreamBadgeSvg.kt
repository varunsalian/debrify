package com.debrify.app.tv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RectF
import android.net.Uri
import com.bumptech.glide.Glide
import com.bumptech.glide.Priority
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.ResourceDecoder
import com.bumptech.glide.load.data.DataFetcher
import com.bumptech.glide.load.engine.Resource
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPool
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.load.model.ModelLoader
import com.bumptech.glide.load.model.ModelLoaderFactory
import com.bumptech.glide.load.model.MultiModelLoaderFactory
import com.bumptech.glide.load.resource.bitmap.BitmapResource
import com.bumptech.glide.signature.ObjectKey
import com.caverock.androidsvg.SVG
import org.w3c.dom.Element
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.StringReader
import java.io.StringWriter
import java.lang.ref.WeakReference
import javax.xml.parsers.DocumentBuilderFactory
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import kotlin.math.min
import kotlin.math.roundToInt

internal const val MAX_BADGE_SVG_BYTES = 128 * 1024
internal fun isBadgeSvgUrl(url: String) = Uri.parse(url).path?.endsWith(".svg", ignoreCase = true) == true
internal fun isBadgeBitmapUrl(url: String) = Regex("\\.(png|jpe?g|webp|gif|bmp|avif|ico)$", RegexOption.IGNORE_CASE)
    .containsMatchIn(Uri.parse(url).path.orEmpty())

/** A dedicated model/data type keeps the SVG decoder out of all other Glide
 * requests (posters and PNG badges continue through their existing pipeline). */
internal data class BadgeSvgUrl(val url: String)
internal class BadgeSvgBytes(val bytes: ByteArray)

internal object StreamBadgeSvg {
    private var registered = WeakReference<Glide>(null)
    @Synchronized fun register(context: Context) {
        val glide = Glide.get(context.applicationContext)
        if (registered.get() === glide) return
        glide.registry.append(BadgeSvgUrl::class.java, BadgeSvgBytes::class.java, SvgModelFactory())
            .append(BadgeSvgBytes::class.java, Bitmap::class.java, BadgeSvgDecoder(glide.bitmapPool))
        registered = WeakReference(glide)
    }
}

private class SvgModelFactory : ModelLoaderFactory<BadgeSvgUrl, BadgeSvgBytes> {
    override fun build(factory: MultiModelLoaderFactory): ModelLoader<BadgeSvgUrl, BadgeSvgBytes> =
        SvgModelLoader(factory.build(GlideUrl::class.java, InputStream::class.java))
    override fun teardown() {}
}

private class SvgModelLoader(private val http: ModelLoader<GlideUrl, InputStream>) : ModelLoader<BadgeSvgUrl, BadgeSvgBytes> {
    override fun handles(model: BadgeSvgUrl) = Uri.parse(model.url).scheme in listOf("https", "http")
    override fun buildLoadData(model: BadgeSvgUrl, width: Int, height: Int, options: Options): ModelLoader.LoadData<BadgeSvgBytes>? {
        val request = http.buildLoadData(GlideUrl(model.url), width, height, options) ?: return null
        // Invalidate bitmaps rendered before CSS/namespace normalization.
        return ModelLoader.LoadData(ObjectKey("stream-badge-svg-v2:${model.url}"), SvgFetcher(request.fetcher))
    }
}

private class SvgFetcher(private val delegate: DataFetcher<InputStream>) : DataFetcher<BadgeSvgBytes> {
    override fun loadData(priority: Priority, callback: DataFetcher.DataCallback<in BadgeSvgBytes>) {
        delegate.loadData(priority, object : DataFetcher.DataCallback<InputStream> {
            override fun onDataReady(data: InputStream?) {
                if (data == null) { callback.onLoadFailed(IOException("Empty SVG response")); return }
                try {
                    // Runs on Glide's bounded source executor, not the UI thread.
                    val bytes = data.use { readBadgeSvg(it) }
                    callback.onDataReady(BadgeSvgBytes(bytes))
                } catch (e: Exception) { callback.onLoadFailed(e) }
            }
            override fun onLoadFailed(e: Exception) { callback.onLoadFailed(e) }
        })
    }
    override fun cleanup() = delegate.cleanup()
    override fun cancel() = delegate.cancel()
    override fun getDataClass() = BadgeSvgBytes::class.java
    override fun getDataSource(): DataSource = delegate.dataSource
}

internal fun readBadgeSvg(input: InputStream): ByteArray {
    val output = ByteArrayOutputStream()
    val chunk = ByteArray(4096)
    val deadline = System.nanoTime() + 8_000_000_000L
    while (true) {
        if (System.nanoTime() > deadline) throw IOException("SVG download timed out")
        val count = input.read(chunk)
        if (count < 0) break
        if (output.size() + count > MAX_BADGE_SVG_BYTES) throw IOException("SVG too large")
        output.write(chunk, 0, count)
    }
    return output.toByteArray()
}

internal class BadgeSvgDecoder(private val pool: BitmapPool) : ResourceDecoder<BadgeSvgBytes, Bitmap> {
    override fun handles(source: BadgeSvgBytes, options: Options) = true
    override fun decode(source: BadgeSvgBytes, width: Int, height: Int, options: Options): Resource<Bitmap> {
        val text = validateBadgeSvg(source.bytes)
        val svg = SVG.getFromString(text)
        val box = svg.documentViewBox
        val naturalWidth = svg.documentWidth.takeIf { it.isFinite() && it > 0 } ?: box?.width() ?: 0f
        val naturalHeight = svg.documentHeight.takeIf { it.isFinite() && it > 0 } ?: box?.height() ?: 0f
        if (!naturalWidth.isFinite() || !naturalHeight.isFinite() || naturalWidth <= 0 || naturalHeight <= 0) {
            throw IOException("Invalid SVG dimensions")
        }
        val scale = min(width.coerceIn(1, 1024) / naturalWidth, height.coerceIn(1, 256) / naturalHeight)
        val outWidth = (naturalWidth * scale).roundToInt().coerceIn(1, 1024)
        val outHeight = (naturalHeight * scale).roundToInt().coerceIn(1, 256)
        val bitmap = pool.get(outWidth, outHeight, Bitmap.Config.ARGB_8888)
        try {
            if (box == null) svg.setDocumentViewBox(0f, 0f, naturalWidth, naturalHeight)
            svg.setDocumentWidth("100%")
            svg.setDocumentHeight("100%")
            svg.renderToCanvas(Canvas(bitmap), RectF(0f, 0f, outWidth.toFloat(), outHeight.toFloat()))
            return BitmapResource(bitmap, pool)
        } catch (e: Exception) { pool.put(bitmap); throw e }
    }
}

/** Same normalization and static/self-contained limits as Flutter. Always render
 * the returned XML, never the input: no CSS is passed to the second parser. */
internal fun validateBadgeSvg(bytes: ByteArray): String {
    if (bytes.size > MAX_BADGE_SVG_BYTES) throw IOException("SVG too large")
    val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
    if ('\u0000' in text || Regex("<!\\s*(DOCTYPE|ENTITY)", RegexOption.IGNORE_CASE).containsMatchIn(text)) {
        throw IOException("SVG document declarations are not supported")
    }
    // Android's DOM parser is recursive. Enforce depth with a streaming parser
    // first, rather than overflowing its stack before our tree visit can run.
    val preflight = XmlPullParserFactory.newInstance().newPullParser().apply {
        setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        setInput(StringReader(text))
    }
    var xmlElements = 0
    while (preflight.nextToken() != XmlPullParser.END_DOCUMENT) {
        if (preflight.eventType == XmlPullParser.DOCDECL) throw IOException("SVG document declaration")
        if (preflight.eventType == XmlPullParser.START_TAG &&
            (++xmlElements > 2048 || preflight.depth > 33)) throw IOException("Unsupported SVG structure")
    }
    val factory = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
    }
    val builder = factory.newDocumentBuilder().apply {
        setEntityResolver { _, _ -> throw org.xml.sax.SAXException("External SVG entity") }
    }
    val parsed = builder.parse(org.xml.sax.InputSource(StringReader(text))).documentElement
    if (parsed.localName != "svg" || !isSvgNamespace(parsed.namespaceURI)) throw IOException("Not SVG")
    val normalized = builder.newDocument()
    val root = badgeSvgElement(parsed, normalized)
    normalized.appendChild(root)
    root.setAttributeNS("http://www.w3.org/2000/xmlns/", "xmlns", SVG_NAMESPACE)
    root.setAttributeNS("http://www.w3.org/2000/xmlns/", "xmlns:xlink", XLINK_NAMESPACE)
    // Marker work depends on vertices/inheritance, not literal references. Block
    // it before rendering. Stylesheets are outside the shared supported subset:
    // Flutter ignores them and would silently render different colours.
    val forbidden = setOf("script", "foreignObject", "image", "use", "pattern", "marker", "style", "filter", "animate", "animateMotion", "animateTransform", "set")
    val urls = Regex("url\\s*\\(([^)]*)\\)", RegexOption.IGNORE_CASE)
    val graph = mutableMapOf<String, MutableList<String>>()
    val nodes = mutableMapOf<String, Int>()
    val masks = mutableSetOf<String>()
    val referencedIds = mutableListOf<String>()
    var elements = 0
    var references = 0
    var sourceWork = 0
    fun checkProperty(name: String, value: String) {
        // Match Flutter's limit: dash expansion happens before output sizing.
        // Checking all declarations also prevents inheritance/override bypasses.
        if (name.equals("stroke-dasharray", ignoreCase = true) && value.trim() != "none") {
            throw IOException("SVG dash patterns are not supported")
        }
    }
    fun checkValue(value: String, owners: List<String>, href: Boolean = false): String {
        if (value.contains("@import", ignoreCase = true)) throw IOException("External SVG styles")
        val refs = (if (href) listOf(value) else emptyList()) +
            urls.findAll(value).map { it.groupValues[1].trim().trim('\'', '"') }.toList()
        refs.forEach { ref ->
            if (!ref.startsWith("#") || ++references > 256) throw IOException("Unsupported SVG reference")
            val id = ref.substring(1)
            if (Regex("[\\s'\"()\\\\]").containsMatchIn(id)) throw IOException("Unsupported SVG fragment")
            referencedIds.add(id)
            owners.forEach { graph.getOrPut(it) { mutableListOf() }.add(id) }
        }
        return urls.replace(value) { match -> "url(${match.groupValues[1].trim().trim('\'', '"')})" }
    }
    fun visit(element: Element, owners: List<String>, depth: Int) {
        if (++elements > 2048 || depth > 32 || element.localName in forbidden) throw IOException("Unsupported SVG structure")
        // CSS wins over presentation attributes independent of XML order. Only
        // presentation properties are materialized, never structural id/href/d.
        if (element.hasAttribute("style")) {
            badgeSvgStyle(element.getAttribute("style")).forEach { (name, value) ->
                checkProperty(name, value)
                if (name in badgeSvgPresentationProperties) element.setAttribute(name, value)
            }
            element.removeAttribute("style")
        }
        if (element.hasAttribute("id")) {
            val id = element.getAttribute("id").trim()
            if (id.isEmpty() || Regex("[\\s'\"()\\\\]").containsMatchIn(id)) throw IOException("Unsupported SVG id")
            element.setAttribute("id", id)
            if (nodes.containsKey(id)) throw IOException("Duplicate SVG id")
        }
        val active = if (element.hasAttribute("id")) owners + element.getAttribute("id") else owners
        if (element.localName == "mask" && element.hasAttribute("id")) masks.add(element.getAttribute("id"))
        var geometry = element.getAttribute("d").length + element.getAttribute("points").length + element.getAttribute("transform").length
        for (i in 0 until element.childNodes.length) {
            val child = element.childNodes.item(i)
            if (child.nodeType == org.w3c.dom.Node.TEXT_NODE || child.nodeType == org.w3c.dom.Node.CDATA_SECTION_NODE) geometry += child.nodeValue.trim().length
        }
        val work = 1 + (geometry + 31) / 32
        sourceWork += work
        active.forEach { nodes[it] = (nodes[it] ?: 0) + work }
        for (i in 0 until element.attributes.length) {
            val attribute = element.attributes.item(i)
            val name = attribute.localName ?: attribute.nodeName
            if (name.startsWith("on", ignoreCase = true)) throw IOException("SVG event handler")
            checkProperty(name, attribute.nodeValue)
            attribute.nodeValue = checkValue(attribute.nodeValue, active, name == "href")
        }
        for (i in 0 until element.childNodes.length) {
            (element.childNodes.item(i) as? Element)?.let { visit(it, active, depth + 1) }
        }
    }
    visit(root, emptyList(), 0)
    val costs = mutableMapOf<String, Int>()
    fun expansionCost(id: String, chain: Set<String>): Int {
        if (id in chain || chain.size > 32) throw IOException("Cyclic SVG reference")
        costs[id]?.let { return it }
        var cost = nodes[id] ?: 1
        graph[id]?.forEach {
            cost += expansionCost(it, chain + id)
            if (cost > 4096) throw IOException("SVG reference expansion too large")
        }
        // AndroidSVG 1.4 popLayer renders each mask twice. Multiplication must
        // include its descendants: even a single-reference chain is exponential.
        if (id in masks) cost *= 2
        if (cost > 4096) throw IOException("SVG reference expansion too large")
        costs[id] = cost
        return cost
    }
    graph.keys.forEach { expansionCost(it, emptySet()) }
    // Include every use, including references on elements without an id. A
    // document cannot repeat an individually affordable mask without a bound.
    var totalCost = sourceWork
    if (totalCost > 4096) throw IOException("SVG geometry too large")
    referencedIds.forEach {
        totalCost += expansionCost(it, emptySet())
        if (totalCost > 4096) throw IOException("SVG reference expansion too large")
    }
    val output = StringWriter()
    val serializer = android.util.Xml.newSerializer().apply {
        setOutput(output)
        setPrefix("", SVG_NAMESPACE)
        setPrefix("xlink", XLINK_NAMESPACE)
    }
    fun serialize(element: Element) {
        serializer.startTag(SVG_NAMESPACE, element.localName)
        for (i in 0 until element.attributes.length) {
            val attribute = element.attributes.item(i)
            if (attribute.nodeName == "xmlns" || attribute.prefix == "xmlns") continue
            serializer.attribute(attribute.namespaceURI, attribute.localName ?: attribute.nodeName, attribute.nodeValue)
        }
        for (i in 0 until element.childNodes.length) {
            val child = element.childNodes.item(i)
            if (child is Element) serialize(child)
            else serializer.text(child.nodeValue)
        }
        serializer.endTag(SVG_NAMESPACE, element.localName)
    }
    serialize(root)
    serializer.flush()
    return output.toString()
}

private const val SVG_NAMESPACE = "http://www.w3.org/2000/svg"
private const val XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"
private fun isSvgNamespace(uri: String?) = uri.isNullOrEmpty() || uri == SVG_NAMESPACE

/** Canonical SVG names only; editor metadata cannot become renderer attributes. */
private fun badgeSvgElement(source: Element, document: org.w3c.dom.Document): Element {
    val target = document.createElementNS(SVG_NAMESPACE, source.localName)
    for (i in 0 until source.attributes.length) {
        val attribute = source.attributes.item(i)
        val name = attribute.localName ?: attribute.nodeName
        val prefix = attribute.prefix
        if (name == "xmlns" || prefix == "xmlns") continue
        when {
            name == "href" && (prefix == null || attribute.namespaceURI == XLINK_NAMESPACE) ->
                target.setAttributeNS(XLINK_NAMESPACE, "xlink:href", attribute.nodeValue)
            prefix == null -> target.setAttribute(name, attribute.nodeValue)
            prefix == "xml" && name == "space" ->
                target.setAttributeNS("http://www.w3.org/XML/1998/namespace", "xml:space", attribute.nodeValue)
        }
    }
    if (source.hasAttribute("href")) target.setAttributeNS(XLINK_NAMESPACE, "xlink:href", source.getAttribute("href"))
    for (i in 0 until source.childNodes.length) {
        val child = source.childNodes.item(i)
        if (child is Element && isSvgNamespace(child.namespaceURI)) {
            target.appendChild(badgeSvgElement(child, document))
        } else if (child.nodeType == org.w3c.dom.Node.TEXT_NODE || child.nodeType == org.w3c.dom.Node.CDATA_SECTION_NODE) {
            target.appendChild(document.importNode(child, false))
        }
    }
    return target
}

// Keep in sync with stream_badge_svg.dart; shared fixtures cover both renderers.
private val badgeSvgPresentationProperties = setOf(
    "color", "display", "visibility", "opacity", "overflow", "clip", "clip-path",
    "clip-rule", "mask", "fill", "fill-rule", "fill-opacity", "stroke",
    "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
    "stroke-opacity", "stroke-dasharray", "stroke-dashoffset", "stop-color",
    "stop-opacity", "font-family", "font-size", "font-style", "font-weight",
    "font-variant", "font-stretch", "text-anchor", "text-decoration",
    "letter-spacing", "word-spacing", "direction", "unicode-bidi",
    "vector-effect", "marker", "marker-start", "marker-mid", "marker-end",
    "solid-color", "solid-opacity", "paint-order",
)

/** Linear inline declaration parser. No raw CSS survives into the renderer. */
private fun badgeSvgStyle(input: String): Map<String, String> {
    if ('\\' in input) throw IOException("SVG CSS escapes are not supported")
    val declarations = mutableListOf<String>()
    val value = StringBuilder()
    var quote: Char? = null
    var parentheses = 0
    var i = 0
    while (i < input.length) {
        val char = input[i]
        when {
            quote != null -> {
                value.append(char)
                if (char == quote) quote = null
            }
            char == '/' && i + 1 < input.length && input[i + 1] == '*' -> {
                val end = input.indexOf("*/", i + 2)
                if (end < 0) throw IOException("Unclosed SVG CSS comment")
                i = end + 1
            }
            char == '"' || char == '\'' -> { quote = char; value.append(char) }
            char == '(' -> { parentheses++; value.append(char) }
            char == ')' -> {
                if (--parentheses < 0) throw IOException("Invalid SVG CSS")
                value.append(char)
            }
            char == ';' && parentheses == 0 -> { declarations.add(value.toString()); value.setLength(0) }
            else -> value.append(char)
        }
        i++
    }
    if (quote != null || parentheses != 0) throw IOException("Unclosed SVG CSS value")
    declarations.add(value.toString())
    val result = linkedMapOf<String, String>()
    val important = mutableSetOf<String>()
    val priority = Regex("\\s*!\\s*important\\s*$", RegexOption.IGNORE_CASE)
    declarations.forEach { declaration ->
        if (declaration.isBlank()) return@forEach
        val colon = declaration.indexOf(':')
        if (colon < 0) throw IOException("Invalid SVG CSS declaration")
        val name = declaration.substring(0, colon).trim().lowercase(java.util.Locale.ROOT)
        val raw = declaration.substring(colon + 1).trim()
        val isImportant = priority.containsMatchIn(raw)
        val property = raw.replace(priority, "").trim()
        if (name == "stroke-dasharray" && property != "none") throw IOException("SVG dash patterns are not supported")
        if (isImportant || name !in important) result[name] = property
        if (isImportant) important.add(name)
    }
    return result
}
