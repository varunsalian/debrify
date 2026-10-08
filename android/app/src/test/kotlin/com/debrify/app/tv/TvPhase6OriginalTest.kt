package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.media3.ui.SubtitleView
import com.debrify.app.profiles.NativePlayerPreferences
import com.debrify.app.recording.RecordingRegistry
import org.junit.After
import org.robolectric.Shadows.shadowOf

/** Original entry points, real attached trees/dispatch, paused clock; no player/network. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@org.robolectric.annotation.Config(instrumentedPackages = ["com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvIptvZapBannerController", "com.debrify.app.tv.TvIptvZapBannerStyledRenderer"])
internal open class TvPhase6OriginalTest : TvPhase3OriginalTest() {
    protected val now = 1_000_000L
    protected lateinit var dock: View
    protected lateinit var subtitles: SubtitleView

    protected fun setup(style: String = "classic", width: Int = 1000) {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear()
            .putString("flutter.iptv_player_guide_style", style).commit()
        lifecycle.create().start().resume().visible()
        bindViews()
        set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
        activity.resources.displayMetrics.widthPixels = width
        android.os.SystemClock.setCurrentTimeMillis(now)
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        dock = View(activity).also { root.addView(it, FrameLayout.LayoutParams(width, 100)); it.layout(0, 0, width, 100) }
        subtitles = SubtitleView(activity).also { root.addView(it, FrameLayout.LayoutParams(width, 600)); it.layout(0, 0, width, 600) }
        set("controlsOverlay", dock); set("subtitleOverlay", subtitles)
        set("subtitleControlsLift", SubtitleControlsLiftController(subtitles, dp(24)))
        set("controlsMenuVisible", false); set("iptvGuideVisible", false)
    }

    protected fun entry(name: String = "Cinema", number: Int? = 7, index: Int = 0,
                        logo: String? = null, group: String? = " Movies ") =
        IptvChannelEntry(index, number, name, "test://$name", logo, group, true, true,
            epgNowTitle = "Programme", epgNowStartMs = now - 120_000,
            epgNowStopMs = now + 480_000, epgNextTitle = "Next programme",
            epgNextStartMs = now + 480_000, epgLoaded = true, epgCatchupMetadataLoaded = true)

    protected fun channels(e: IptvChannelEntry = entry(), count: Int = 2) {
        set("iptvChannels", (0 until count).map { if (it == 0) e else entry("Other", index = it) }.toMutableList())
        set("currentIptvIndex", 0)
    }
    protected fun show(e: IptvChannelEntry, docked: Boolean = false) =
        call("showIptvZapBanner", arrayOf(IptvChannelEntry::class.java, boolType), e, docked)
    protected fun showDefault(e: IptvChannelEntry) =
        defaultCall("showIptvZapBanner", arrayOf(IptvChannelEntry::class.java, boolType), 2, e, false)
    protected fun build() = invoke("ensureIptvZapBanner") as FrameLayout
    protected fun banner() = field("iptvZapBanner") as FrameLayout
    protected fun view(name: String) = field(name) as View
    protected fun text(name: String) = field(name) as TextView
    protected fun progress() = field("iptvZapBannerProgress") as ProgressBar
    protected fun dp(value: Int) = call("dp", arrayOf(intType), value) as Int
    protected fun paint(e: IptvChannelEntry) = call("paintIptvZapBannerEpg", arrayOf(IptvChannelEntry::class.java), e)
    protected fun position(e: IptvChannelEntry) = call("paintIptvZapBannerPosition", arrayOf(IptvChannelEntry::class.java), e)
    protected fun frame(v: View) = v.layoutParams as FrameLayout.LayoutParams
    protected fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup)
        (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    protected fun tickPending() = (field("progressHandler") as Handler).hasMessages(0, field("iptvZapBannerTickToken"))
    protected fun hidePending() = (field("progressHandler") as Handler).hasMessages(0, field("iptvZapBannerHideToken"))

    @After fun settleBannerWork() {
        (field("progressHandler") as Handler).removeCallbacksAndMessages(null)
        (field("iptvBrowseHandler") as Handler).removeCallbacksAndMessages(null)
        (field("externalSubtitleHandler") as Handler).removeCallbacksAndMessages(null)
        (field("iptvZapBanner") as? View)?.animate()?.cancel()
        if (::subtitles.isInitialized) (field("subtitleControlsLift") as SubtitleControlsLiftController).cancel()
        (field("iptvZapBannerLogo") as? android.widget.ImageView)?.let { if (!activity.isDestroyed) com.bumptech.glide.Glide.with(activity).clear(it) }
        RecordingRegistry.live.clear()
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
    }
}
