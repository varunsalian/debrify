package com.debrify.app.tv

import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ListView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.MainActivity
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import com.debrify.app.subtitle.StremioSubtitleService
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog
import java.lang.reflect.Proxy
import java.util.concurrent.TimeUnit

/** Bootstrap the original and drive its real callbacks, IO ladder and borrowed scope. */
@Config(sdk = [28], shadows = [TvPhase14SubtitleFetchShadow::class, TvPhase4CueFetchShadow::class],
    instrumentedPackages = ["com.debrify.app.subtitle.StremioSubtitleService", "com.debrify.app.util.SubtitleCueCache"])
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase14OriginalTest : TvPhase5OriginalTest() {
    protected val endpoint = TvPhase14EndpointMessenger()
    protected var tracks = Tracks.EMPTY
    protected var currentMedia: MediaItem? = null
    protected var currentManifest: Any? = null
    protected val responses = mutableListOf<TvPhase4Response<List<StremioSubtitle>>>()
    private var savedChannel: MethodChannel? = null
    private var destroyed = false
    protected val subtitlePlayer: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
        arrayOf(ExoPlayer::class.java)) { _, method, args ->
        when (method.name) {
            "getCurrentTracks" -> tracks
            "getCurrentMediaItem" -> currentMedia
            "getCurrentManifest" -> currentManifest
            else -> method.invoke(probe.player, *(args ?: emptyArray()))
        }
    } as ExoPlayer

    @Before fun bootstrapPhase14() {
        savedChannel = MainActivity.getAndroidTvPlayerChannel()
        connect()
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
        val item = JSONObject().put("title", "Film.mkv").put("url", "https://phase14.invalid/film")
        activity.intent.putExtra("payload", JSONObject().put("title", "Film").put("contentType", "movie")
            .put("imdbId", "tt140").put("startIndex", 0).put("items", JSONArray().put(item)).toString())
        lifecycle.create().start().resume().visible()
        (field("player") as? ExoPlayer)?.release()
        (field("playerView") as androidx.media3.ui.PlayerView).player = null
        set("player", subtitlePlayer)
        activity.findViewById<View>(com.debrify.app.R.id.android_tv_startup_gate).visibility = View.GONE
        idle()
        endpoint.requests.clear(); probe.events.clear()
        TvPhase14SubtitleFetchShadow.responses.clear(); TvPhase4CueFetchShadow.responses.clear()
        assertNotNull("Activity constructs the borrowed subtitle service", field("stremioSubtitleService"))
        set("userManuallySelectedSubtitle", true) // Slot tests must not start a separate subtitle download.
    }

    protected fun connect() = MainActivity.setAndroidTvPlayerChannel(MethodChannel(endpoint, "com.debrify.app/android_tv_player"))
    protected fun noChannel() = MainActivity.setAndroidTvPlayerChannel(null)
    protected fun model() = field("payload") as PlaybackPayload
    protected fun item() = model().items[0]
    protected fun fetch(item: PlaybackItem = item()) = call("fetchStremioSubtitles", arrayOf(PlaybackItem::class.java), item)
    protected fun known(imdb: String = "tt140", type: String = "movie", item: PlaybackItem = item()) =
        call("fetchStremioSubtitlesWithImdb", arrayOf(stringType, stringType, PlaybackItem::class.java), imdb, type, item)
    protected fun reset() = call("resetSubtitleState", emptyArray())
    protected fun clearLoading() = call("clearStremioLoadingState", emptyArray())
    protected fun autoSelect() = call("tryAutoSelectAddonSubtitle", emptyArray())
    protected fun searchItem() = call("getCurrentSubtitleSearchItem", emptyArray()) as PlaybackItem?
    protected fun identityLabel() = call("currentSubtitleIdentityLabel", emptyArray()) as String
    protected fun ts() = field("trackSelector") as DefaultTrackSelector
    @Suppress("UNCHECKED_CAST") protected fun slots() = field("addonSubtitleResults") as MutableList<AddonSubtitleResult>
    @Suppress("UNCHECKED_CAST") protected fun flat() = field("stremioSubtitles") as MutableList<StremioSubtitle>
    @Suppress("UNCHECKED_CAST") protected fun tokens() = field("addonFetchTokens") as MutableMap<String, Int>
    protected fun loading() = field("isLoadingStremioSubtitles") as Boolean
    protected fun discovery() = field("subtitleAddonDiscoveryReady") as Boolean
    protected fun token() = field("addonSubtitleFetchToken") as Int
    protected fun scope() = field("subtitleScope") as CoroutineScope
    protected fun jobs() = scope().coroutineContext[Job]!!.children.toSet()
    protected fun addon(id: String = "a") = StremioAddon(id, "Addon $id", "https://phase14.invalid/$id/manifest.json",
        "https://phase14.invalid/$id", listOf("subtitles"), listOf("movie", "series"), true, subtitlePriorityId = id)
    protected fun subtitle(url: String = "https://phase14.invalid/a.srt", addon: String = "a", lang: String = "eng",
        label: String? = "English") = StremioSubtitle("id:$url", url, lang, label, "Addon $addon", addon)
    protected fun installAddons(vararg addons: StremioAddon) {
        val json = JSONArray()
        addons.forEach { json.put(JSONObject().put("id", it.id).put("name", it.name)
            .put("manifest_url", it.manifestUrl).put("base_url", it.baseUrl)
            .put("resources", JSONArray(it.resources)).put("types", JSONArray(it.types)).put("enabled", true)
            .put("subtitle_priority_id", it.subtitlePriorityId)) }
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.stremio_addons_v1", json.toString()).commit()
        assertEquals("Real profile projection discovers the installed addons", addons.toList(),
            (field("stremioSubtitleService") as StremioSubtitleService).getSubtitleAddons())
    }
    protected fun response(value: List<StremioSubtitle> = listOf(subtitle()), failure: Throwable? = null,
        released: Boolean = false, addonId: String = "a"): TvPhase4Response<List<StremioSubtitle>> = TvPhase4Response(value, failure).also {
        responses.add(it); TvPhase14SubtitleFetchShadow.responses.computeIfAbsent(addonId) { java.util.concurrent.LinkedBlockingQueue() }.add(it)
        if (released) it.release.countDown()
    }
    protected fun entered(response: TvPhase4Response<List<StremioSubtitle>>) {
        idle()
        assertTrue("blocking attempt entered", response.entered.await(5, TimeUnit.SECONDS))
        assertNotEquals("production attempt runs on IO", Thread.currentThread(), response.thread)
    }
    protected fun complete(response: TvPhase4Response<List<StremioSubtitle>>, job: Job) {
        response.release.countDown()
        assertTrue("HTTP attempt returned", response.returned.await(5, TimeUnit.SECONDS))
        settle(job)
    }
    protected fun settle(job: Job) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
        while (!job.isCompleted && System.nanoTime() < deadline) { idle(); Thread.yield() }
        assertTrue("borrowed scope publishes on production Main", job.isCompleted)
        idle()
    }
    protected fun result(type: String = "movie", name: String = "Found film", imdb: String = "tt141") =
        SubtitleCatalogResult(imdb, type, name, "2024", "Catalog")
    protected fun catalog(vararg results: SubtitleCatalogResult) = results.map {
        mapOf("imdbId" to it.imdbId, "type" to it.type, "name" to it.name, "year" to it.year, "source" to it.source)
    }
    protected fun apply(result: SubtitleCatalogResult = result(), season: Int? = null, episode: Int? = null) =
        call("applyManualSubtitleIdentity", arrayOf(SubtitleCatalogResult::class.java, boxedIntType, boxedIntType), result, season, episode)
    protected fun showSearch() {
        call("showSearchSubtitleDialog", emptyArray())
        assertTrue("production dialog is created", ShadowDialog.getLatestDialog() is AlertDialog)
        assertTrue("production dialog is shown", dialog().isShowing)
        layoutDialog()
    }
    protected fun prompt(result: SubtitleCatalogResult = result("series")) {
        call("showSeasonEpisodePrompt", arrayOf(SubtitleCatalogResult::class.java), result)
        assertTrue("production prompt is created", ShadowDialog.getLatestDialog() is AlertDialog)
        assertTrue("production OnShow listener runs", dialog().isShowing)
        layoutDialog()
    }
    protected fun layoutDialog() {
        val root = dialog().window!!.decorView
        root.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 1080, 720)
        idle()
    }
    protected fun dialog() = ShadowDialog.getLatestDialog() as AlertDialog
    protected fun descendants(view: View = dialog().window!!.decorView): List<View> =
        listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    protected fun query() = descendants().filterIsInstance<EditText>().single()
    protected fun searchButton() = ((query().parent as android.widget.LinearLayout).getChildAt(1) as android.widget.LinearLayout).getChildAt(0) as AppCompatButton
    protected fun resultList() = descendants().filterIsInstance<ListView>().single()
    protected fun status() = (query().parent as android.widget.LinearLayout).getChildAt(2) as TextView
    protected fun catalogRequest() = endpoint.request("searchSubtitleCatalogs")
    protected fun menu() = field("unifiedMenu") as UnifiedMenuController
    protected fun menuCallbacks() = field("unifiedMenuCallbacks") as UnifiedMenuController.Callbacks
    @Suppress("UNCHECKED_CAST") protected fun rows(name: String, vararg args: Any) = invoke(name, *args) as List<UnifiedMenuController.Row>
    protected fun menuModel(index: Int) = call("umSubsModel", arrayOf(listType, intType), emptyList<UnifiedMenuController.Row>(), index) as UnifiedMenuController.Model
    protected fun pref(name: String, value: String?) {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putString("flutter.$name", value).commit()
        refreshLaunchPreferences()
    }
    protected fun flag(name: String, value: Boolean) {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().putBoolean("flutter.$name", value).commit()
        refreshLaunchPreferences()
    }
    private fun refreshLaunchPreferences() {
        // NativePlayerPreferences is a route snapshot. Replace the Activity's
        // borrowed object explicitly rather than expecting prefs writes to mutate it.
        set("playerPreferences", com.debrify.app.profiles.NativePlayerPreferences.fromIntent(activity, android.content.Intent()))
    }
    protected fun destroyNow() { lifecycle.destroy(); destroyed = true }

    @After fun cleanPhase14() {
        responses.forEach { it.release.countDown() }
        jobs().forEach { it.cancel(); settle(it) }
        if (!destroyed) lifecycle.destroy()
        MainActivity.setAndroidTvPlayerChannel(savedChannel)
        TvPhase14SubtitleFetchShadow.responses.clear(); TvPhase4CueFetchShadow.responses.clear()
        ShadowDialog.getLatestDialog()?.dismiss()
        org.robolectric.shadows.ShadowToast.reset()
    }
}
