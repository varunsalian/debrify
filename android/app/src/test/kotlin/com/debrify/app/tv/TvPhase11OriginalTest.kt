package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.widget.EditText
import androidx.media3.exoplayer.ExoPlayer
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.shadows.ShadowToast

/** Real onCreate IPTV bootstrap and installed listeners; fake transport and player observations. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase11OriginalTest : TvPhase5OriginalTest() {
    protected val function0 = kotlin.jvm.functions.Function0::class.java
    protected val function5 = kotlin.jvm.functions.Function5::class.java
    protected val main = Handler(Looper.getMainLooper())
    private var created = false

    @Before fun bootstrapPhase11() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        activity.intent.putExtra("payload", bootstrapJson().toString())
        lifecycle.create().visible()
        created = true
        assertTrue("real IPTV bootstrap completed", field("isIptvMode") as Boolean)
        (field("player") as ExoPlayer).release()
        (field("playerView") as androidx.media3.ui.PlayerView).player = null
        set("player", probe.player)
        activity.findViewById<View>(R.id.android_tv_startup_gate).visibility = View.GONE
        idle() // Complete the real ViewRoot traversal; do not strand synchronous replies behind its barrier.
        set("controlsMenuVisible", false)
        set("iptvZapRequestInFlight", false)
        // Retire bootstrap EPG watchdogs with fresh archive-aware fake replies.
        messenger.requests.indices.filter { messenger.requests[it].call.method == "requestIptvEpg" }.forEach {
            reply(value=mapOf("now" to mapOf("title" to "Bootstrap", "stopMs" to System.currentTimeMillis()+3_600_000L,"hasArchive" to true)),request=it)
        }
        idle()
        messenger.requests.clear(); probe.events.clear(); ShadowToast.reset()
    }
    protected fun rawChannel(name: String = "Alpha", number: Int = 1, live: Boolean = true,
                             group: String = "News", type: String = if (live) "live" else "episodes") = mapOf(
        "name" to name, "url" to "https://phase11.invalid/$number", "channelNumber" to number,
        "isLive" to live, "group" to group, "sourceId" to "provider", "sourceName" to "Provider",
        "contentType" to type, "seriesId" to "series", "seriesName" to "Show", "season" to 2,
        "episode" to number, "hasNextEpisode" to true, "duration" to 100)
    protected open fun bootstrapJson() = JSONObject().put("mode", "iptv").put("sourceId", "provider")
        .put("sourceName", "Provider").put("contentType", "live").put("selectedCategory", "News")
        .put("sources", JSONArray().put(JSONObject(mapOf("id" to "provider", "name" to "Provider", "type" to "xtream"))))
        .put("categories", JSONArray(listOf("News", "Movies")))
        .put("channels", JSONArray(listOf(JSONObject(rawChannel()), JSONObject(rawChannel("Beta", 2)))))
        .put("startIndex", 0).put("seriesAudioKey", "provider::series").put("preferredAudioLang", "fr")
    @Suppress("UNCHECKED_CAST") protected fun channels() = field("iptvChannels") as MutableList<IptvChannelEntry>
    @Suppress("UNCHECKED_CAST") protected fun browseChannels() = field("iptvBrowseChannels") as MutableList<IptvChannelEntry>
    @Suppress("UNCHECKED_CAST") protected fun queue() = field("iptvZapPendingInputs") as java.util.ArrayDeque<Int>
    protected fun adapter() = field("iptvChannelAdapter") as IptvChannelAdapter
    protected fun guideList() = field("iptvGuideList") as RecyclerView
    protected fun search() = field("iptvGuideSearch") as EditText
    protected fun show() = call("showIptvGuide", emptyArray())
    protected fun hide() = call("hideIptvGuide", emptyArray())
    protected fun browse(query: String = search().text.toString().trim(), action: String = "browse") =
        call("requestIptvBrowse", arrayOf(stringType,stringType,stringType,stringType,stringType), action,query,null,null,null)
    protected fun browseDefault() = defaultCall("requestIptvBrowse", arrayOf(stringType,stringType,stringType,stringType,stringType),30,"browse",null,null,null,null)
    protected fun page(category: String? = "News", offset: Int = 0, anchor: IptvChannelEntry? = null,
                       fromEnd: Boolean = false, failure: (() -> Unit)? = null,
                       ready: (MutableList<IptvChannelEntry>,Int,Int,String?,List<String>) -> Unit) =
        call("requestIptvZapPage", arrayOf(stringType,intType,IptvChannelEntry::class.java,boolType,function0,function5),category,offset,anchor,fromEnd,failure,ready)
    protected fun jump(number: Int = 7) = call("requestIptvChannelJump", arrayOf(intType),number)
    protected fun switch(entry: IptvChannelEntry, adopt: Boolean = true, checkpoint: Boolean = true) =
        call("switchToIptvChannel", arrayOf(IptvChannelEntry::class.java,boolType,boolType),entry,adopt,checkpoint)
    protected fun prefetch(delta: Int = 1, force: Boolean = false) = call("prefetchIptvZapPage", arrayOf(intType,boolType),delta,force)
    protected fun install(entries: MutableList<IptvChannelEntry>, offset: Int = 0, total: Int = entries.size,
                          category: String? = "News", preserve: Boolean = true) =
        call("installIptvZapWindow",arrayOf(MutableList::class.java,intType,intType,stringType,listType,boolType),entries,offset,total,category,listOf("News","Movies"),preserve)
    protected fun reply(kind: String = "success", value: Any? = response(), queued: Boolean = false,
                        request: Int = messenger.requests.lastIndex, message: String? = "detail") {
        val binary = messenger.requests[request].reply!!
        val envelope = when(kind) {
            "error" -> StandardMethodCodec.INSTANCE.encodeErrorEnvelope("E11",message,null)
            "missing" -> null
            else -> StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value)
        }?.apply { flip() }
        val deliver = Runnable { binary.reply(envelope) }
        if (queued) assertTrue("main-looper binary reply accepted",main.post(deliver)) else deliver.run()
    }
    protected fun response(vararg extra: Pair<String,Any?>) = mapOf(
        "channels" to listOf(rawChannel("Reply",7)), "pageOffset" to 0, "totalChannels" to 30,
        "selectedCategory" to "News", "categories" to listOf("News","Movies"), *extra)
    protected fun clickRow(entry: IptvChannelEntry) {
        adapter().updateChannels(mutableListOf(entry))
        val holder=adapter().onCreateViewHolder(guideList(),0)
        adapter().onBindViewHolder(holder,0); holder.itemView.performClick()
    }
    // ShadowActivity keeps a separate currentFocus slot; mirror the real attached window.
    protected fun syncFocus() { org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(activity.window.decorView.findFocus()) }
    protected fun key(code: Int, action: Int = KeyEvent.ACTION_DOWN, repeat: Int = 0): Boolean {
        syncFocus()
        return activity.dispatchKeyEvent(KeyEvent(0L,0L,action,code,repeat))
    }
    protected fun args(method: String): Map<*,*> {
        val emitted=requests(method)
        assertTrue("expected emitted bridge request: $method",emitted.isNotEmpty())
        return emitted.last().call.arguments as Map<*,*>
    }
    protected fun clearTransport() { messenger.requests.clear(); probe.events.clear(); ShadowToast.reset() }
    protected fun settled() { idle(); clearTransport(); set("iptvZapRequestInFlight",false) }
    protected fun destroyNow() { lifecycle.destroy(); created=false }
    @After fun cleanupPhase11() { if (created) lifecycle.destroy(); main.removeCallbacksAndMessages(null) }
}
