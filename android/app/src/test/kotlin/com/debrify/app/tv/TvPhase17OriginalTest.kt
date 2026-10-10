package com.debrify.app.tv

import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import android.net.Uri
import java.io.IOException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.robolectric.Shadows.shadowOf

/** Real original tune/listener/ticker entry points; no production test seam. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@org.robolectric.annotation.Config(sdk=[28])
internal open class TvPhase17OriginalTest : TvPhase5OriginalTest() {
    protected val original = "http://h/live/u/p/1.m3u8"
    protected val twin = "http://h/live/u/p/1.ts"
    protected var booted = false
    @Before fun prepareTuneProbe() {
        probe.extended = true; probe.playIntent = true
        probe.videoFormat = Format.Builder().setSampleMimeType("video/avc").build()
        advance(1_000)
    }
    protected fun tune(entry: IptvChannelEntry = iptv(channel(original)), url: String = entry.url) {
        call("setIptvMediaItem",arrayOf(IptvChannelEntry::class.java,stringType),entry,url)
    }
    protected fun retune(source: String = "video-stall", attempt: Int = 2) = invoke("performIptvLiveRetune",source,attempt)
    protected fun begin() {
        val entry=iptv(channel(original)); call("beginIptvTwinTrial",arrayOf(IptvChannelEntry::class.java,stringType,stringType),entry,original,twin)
    }
    protected fun quiet() { (field("progressHandler") as Handler).removeCallbacksAndMessages(null) }
    protected fun recovery() = invoke("getIptvLiveRecovery") as IptvLiveRecovery
    protected fun listener() = field("playbackListener") as Player.Listener
    protected fun tick() { (field("progressRunnable") as Runnable).run(); quiet() }
    protected fun reconnectPill(): android.widget.TextView {
        val value=field("iptvReconnectPill");assertNotNull("recovery callback creates its narration pill",value)
        return value as android.widget.TextView
    }
    protected fun timeout(): Runnable {
        val value=field("iptvTwinTrialTimeout");assertNotNull("trial owns its posted timeout Runnable",value)
        return value as Runnable
    }
    protected fun trial(): String? = field("iptvTwinTrialUrl") as String?
    protected fun pref() = field("iptvTwinPreferredUrls") as MutableMap<String,String>
    protected fun failed() = field("iptvTwinFailedUrls") as MutableSet<String>
    protected fun strict() = field("iptvStrictTsUrls") as MutableSet<String>
    protected fun forced() = field("iptvHlsForcedUrls") as MutableSet<String>
    protected fun error(cause: Throwable = IOException("network"), code: Int = 2000) = ExoPlaybackException.createForSource(cause as IOException,code)
    protected fun sniff() = error(IOException("wrapper",UnrecognizedInputFormatException("unrecognized",Uri.parse(twin))))
    protected fun deliver(error: ExoPlaybackException) { probe.error=error;listener().onPlayerError(error) }
    protected fun bootstrap() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        val cm=activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        shadowOf(cm).setActiveNetworkInfo(null)
        activity.intent.putExtra("payload",JSONObject().put("mode","iptv").put("sourceId","p17").put("sourceName","Provider")
            .put("channels",JSONArray().put(JSONObject().put("name","Probe").put("url",original).put("isLive",true))).put("startIndex",0).toString())
        lifecycle.create().visible();booted=true
        val real=field("player") as ExoPlayer
        (field("playerView") as androidx.media3.ui.PlayerView).player=null;real.release();set("player",probe.player)
        idle() // Complete bootstrap traversal using real Robolectric vsync, not a stranded barrier.
        quiet();probe.events.clear();probe.mediaItems.clear()
    }
    protected fun bootstrapVod() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        activity.intent.putExtra("payload",JSONObject().put("title","Film").put("contentType","single")
            .put("items",JSONArray().put(JSONObject().put("id","p17").put("title","Film").put("url","https://phase17.invalid/film.mp4"))).toString())
        lifecycle.create();booted=true
        val real=field("player") as? ExoPlayer
        (field("playerView") as androidx.media3.ui.PlayerView).player=null;real?.release();set("player",probe.player);quiet();idle()
    }
    @After fun cleanTuneProbe() {
        (field("iptvTwinTrialHandler") as Handler).removeCallbacksAndMessages(null)
        val deferred=field("iptvLiveRecovery\$delegate") as Lazy<*>
        if(deferred.isInitialized()) (deferred.value as IptvLiveRecovery).cancel()
        if(booted) lifecycle.destroy()
    }
}
