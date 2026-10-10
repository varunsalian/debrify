package com.debrify.app.tv

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.Looper
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowSystemProperties
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Read installed Media3 objects; no production seam, fake factory or field replacement. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase19PipelineTest : TvPhase5OriginalTest() {
    protected lateinit var built: ExoPlayer
    private val created = mutableListOf<ExoPlayer>()
    private var heapBefore = ""

    @Before fun preparePipeline() {
        val properties = Class.forName("android.os.SystemProperties")
        heapBefore = ReflectionHelpers.callStaticMethod(properties, "get",
            ReflectionHelpers.ClassParameter.from(String::class.java, "dalvik.vm.heapsize"))
        val root = (field("playerView") as PlayerView).parent as android.view.ViewGroup
        val subtitles = SubtitleView(activity)
        root.addView(subtitles); set("subtitleOverlay", subtitles)
        set("subtitleControlsLift", SubtitleControlsLiftController(subtitles, 24))
        movie(); set("networkBuffer", "standard"); set("networkPatience", "standard")
        shadowOf(activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).setActiveNetworkInfo(null)
    }

    protected fun read(owner: Any, name: String): Any? {
        var type: Class<*>? = owner.javaClass
        while (type != null) {
            val found = type.declaredFields.firstOrNull { it.name == name }
            if (found != null) return found.apply { isAccessible = true }.get(owner)
            type = type.superclass
        }
        throw AssertionError("Media3 1.8.0 read-back field absent: ${owner.javaClass.name}.$name")
    }
    protected fun required(owner: Any, name: String): Any = read(owner, name).also {
        assertNotNull("installed ${owner.javaClass.name}.$name", it)
    }!!
    protected fun heap(mib: Int) {
        ShadowSystemProperties.override("dalvik.vm.heapsize", "${mib}m")
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        assertEquals("real SDK 28 ActivityManager.largeMemoryClass follows the property", mib, manager.largeMemoryClass)
    }
    protected fun buildPipeline(iptv: Boolean = false): DefaultMediaSourceFactory {
        if (::built.isInitialized) detach()
        set("isIptvMode", iptv)
        try { call("setupPlayer", emptyArray()) } finally {
            val candidate = field("player") as? ExoPlayer
            if (candidate?.javaClass?.name == "androidx.media3.exoplayer.ExoPlayerImpl") {
                built = candidate; created.add(candidate)
            }
        }
        assertEquals("installed real Media3 implementation", "androidx.media3.exoplayer.ExoPlayerImpl", built.javaClass.name)
        return required(built, "mediaSourceFactory") as DefaultMediaSourceFactory
    }
    protected fun loadControl(): Any = required(required(built, "internalPlayer"), "loadControl")
    protected fun sources(factory: DefaultMediaSourceFactory) = required(factory, "dataSourceFactory") as DataSource.Factory
    protected fun resolver(factory: DataSource.Factory) = required(factory, "resolver") as ResolvingDataSource.Resolver
    protected fun upstream(factory: DataSource.Factory) = required(factory, "upstreamFactory") as DataSource.Factory
    protected fun detach() {
        (field("playerView") as PlayerView).player = null
        if (created.remove(built)) built.release()
        set("player", probe.player)
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        (field("iptvNetworkCallback") as? ConnectivityManager.NetworkCallback)?.let(cm::unregisterNetworkCallback)
        set("iptvNetworkCallback", null)
    }
    protected fun <T> worker(block: () -> T): T {
        val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "p19-loader-observer") }
        return try {
            executor.submit(Callable {
                assertNotEquals("resolver invocation stays on a worker", Looper.getMainLooper().thread, Thread.currentThread())
                block()
            }).get(5, TimeUnit.SECONDS)
        } finally {
            executor.shutdownNow(); assertTrue("bounded worker stopped", executor.awaitTermination(5, TimeUnit.SECONDS))
        }
    }
    @After fun cleanPipeline() {
        if (::built.isInitialized) detach()
        created.forEach { it.release() }; created.clear()
        ShadowSystemProperties.override("dalvik.vm.heapsize", heapBefore)
        com.debrify.app.util.SubtitleSettings.clearActiveSubtitleIdentityProvider(activity)
        val tune = field("iptvTuneController")!!
        val lazy = TvPlayerOriginalAccess.field(tune, "iptvLiveRecovery\$delegate") as Lazy<*>
        if (lazy.isInitialized()) (lazy.value as IptvLiveRecovery).cancel()
    }
}
