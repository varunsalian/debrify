package com.debrify.app.tv

import android.content.Context
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.view.View
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.request.Request
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.recording.RecordingRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowContentResolver
import java.io.File

/** A pending MediaStore destination, with observable publication and real file bytes. */
class TvRecordingMediaStoreProvider : ContentProvider() {
    val inserts = mutableListOf<ContentValues>()
    val publications = mutableListOf<ContentValues>()
    var beforePublish: (() -> Unit)? = null
    var failInsert = false
    var failPublish = false
    lateinit var file: File
    override fun onCreate() = true
    override fun insert(uri: Uri, values: ContentValues?): Uri {
        if (failInsert) throw java.io.IOException("fixture insert failure")
        inserts.add(ContentValues(values)); return Uri.parse("content://media/external/downloads/123")
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE)
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int {
        beforePublish?.invoke()
        if (failPublish) throw java.io.IOException("fixture publish failure")
        publications.add(ContentValues(values)); return 1
    }
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 1
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri) = "video/mp2t"
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPhase3LifecycleCharacterizationTest : TvPhase3OriginalTest() {
    private fun created() {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        lifecycle.create().start().resume()
        bindViews()
    }
    private fun provider(): TvRecordingMediaStoreProvider = TvRecordingMediaStoreProvider().also {
        it.file = File(activity.cacheDir, "phase3-tee.ts")
        it.attachInfo(activity, android.content.pm.ProviderInfo().apply { authority = "media" })
        ShadowContentResolver.registerProviderInternal("media", it)
    }
    private fun listeners() = TvPlayerOriginalAccess.field(RecordingRegistry, "listeners") as List<*>

    @Test fun posterRequestBelongsToActivityGlideManagerAndIsClearedOnDestroy() {
        created(); val model = series()
        // A local resource URL keeps the production Glide request path network-free.
        model.items[1] = model.items[1].copy(artwork = "android.resource://com.debrify.app/${com.debrify.app.R.drawable.splash_logo}")
        invoke("showUpNextCard", 1)
        val poster = field("upNextPoster") as ImageView
        val request = DrawableImageViewTarget(poster).request!!
        val manager = Glide.with(activity)
        assertTrue("poster is tracked by activity lifecycle manager", TvPlayerOriginalAccess.glideTracks(manager, request))
        assertNotSame(Glide.with(activity.applicationContext), manager)
        lifecycle.pause().stop().destroy(); idle()
        assertTrue("activity destruction clears poster request", request.isCleared)
        assertFalse(TvPlayerOriginalAccess.glideTracks(manager, request))
    }

    @Test fun destroyCancelsSleepUpNextSkipScopeAndCacheBeforeReleasingThePlayer() {
        created(); series(); invoke("startSleepCountdown", 1)
        val scope = field("skipSegmentScope") as CoroutineScope
        @Suppress("UNCHECKED_CAST") val cache = field("skipSegmentCache") as MutableMap<String, TvSkipSegments>
        cache["item"] = TvSkipSegments.EMPTY
        var ticked = false
        (field("upNextHandler") as Handler).postDelayed({ ticked = true }, 50)
        val p = PlayerProbe()
        p.onPause = { }
        set("player", p.player)
        val generation = field("skipSegmentFetchGeneration") as Int
        lifecycle.pause().stop().destroy()
        assertEquals("Off", invoke("sleepTimerValueLabel")); assertNull(field("sleepTimerRunnable"))
        assertTrue(scope.coroutineContext[Job]!!.isCancelled); assertTrue(cache.isEmpty())
        assertEquals(generation + 1, field("skipSegmentFetchGeneration"))
        advance(60_000)
        assertFalse("Up Next work cannot outlive destroy", ticked)
        assertEquals(listOf("pause", "release"), p.events)
        assertEquals(false, field("sleepStopLatched"))
    }

    @Test fun teeToggleStartsWritesAndStopsPublishingTheSamePendingRow() {
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.recording_engine_enabled", false).commit()
        val provider = provider()
        set("currentIptvStreamUrl", "https://example.test/plain.ts"); set("iptvChannels", listOf(p2Channel().copy(name = "TV / Cinema")))
        invoke("toggleIptvRecording")
        val tee = invoke("getIptvRecordingController") as IptvRecordingController
        assertTrue("tee started; inserts=${provider.inserts.size} file=${provider.file.exists()}", tee.isActive); assertEquals(1, provider.inserts.size)
        val values = provider.inserts.single()
        assertTrue(values.getAsString(MediaStore.MediaColumns.DISPLAY_NAME).matches(Regex("TV_Cinema_\\d{8}_\\d{6}\\.ts")))
        assertEquals("video/mp2t", values.getAsString(MediaStore.MediaColumns.MIME_TYPE))
        assertEquals(1, values.getAsInteger(MediaStore.MediaColumns.IS_PENDING))
        tee.write(byteArrayOf(1, 2, 3), 0, 3); invoke("toggleIptvRecording")
        assertFalse(tee.isActive); assertArrayEquals(byteArrayOf(1, 2, 3), provider.file.readBytes())
        assertEquals(0, provider.publications.single().getAsInteger(MediaStore.MediaColumns.IS_PENDING))
    }

    @Test fun onStopPublishesTeeBeforePauseAndDestroyRemovesListenerBeforePublication() {
        created(); val provider = provider(); val listener = field("recordingRegistryListener")!!
        assertTrue("onCreate registers listener", listeners().contains(listener))
        val tee = invoke("getIptvRecordingController") as IptvRecordingController
        assertTrue(tee.start("https://example.test/plain.ts", "fixture.ts", "video/mp2t"))
        val p = PlayerProbe(); set("player", p.player)
        provider.beforePublish = { assertTrue(listeners().contains(listener)); assertTrue(p.events.isEmpty()) }
        lifecycle.pause().stop()
        assertFalse(tee.isActive); assertEquals(1, provider.publications.size); assertEquals(listOf("pause"), p.events)
        assertTrue(tee.start("https://example.test/plain.ts", "second.ts", "video/mp2t"))
        provider.beforePublish = { assertFalse("listener removed before tee publish", listeners().contains(listener)) }
        lifecycle.destroy()
        assertEquals(2, provider.publications.size); assertFalse(tee.isActive)
        assertFalse(listeners().contains(listener))
    }
}
