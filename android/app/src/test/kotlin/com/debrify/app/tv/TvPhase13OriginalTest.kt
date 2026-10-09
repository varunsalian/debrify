package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.media3.exoplayer.ExoPlayer
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import com.debrify.app.R
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.util.ReflectionHelpers

/** Real onCreate, retained playlist bindings and installed adapter/listener callbacks. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase13OriginalTest : TvPhase5OriginalTest() {
    protected open val skin = TvControlsSkin.CLASSIC
    private var created = false
    private var frameDelay=java.time.Duration.ofMillis(15)
    @Before fun bootstrapPhase13() {
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit()
            .putString("flutter." + TvControlsSkin.PREF_KEY,skin.name.lowercase()).commit()
        frameDelay=org.robolectric.shadows.ShadowChoreographer.getFrameDelay()
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        val items=JSONArray().put(JSONObject(mapOf("title" to "Episode one","url" to "https://phase13.invalid/one","season" to 1,"episode" to 1)))
            .put(JSONObject(mapOf("title" to "Episode two","url" to "https://phase13.invalid/two","season" to 1,"episode" to 2)))
            .put(JSONObject(mapOf("title" to "Episode three","url" to "https://phase13.invalid/three","season" to 2,"episode" to 1)))
        activity.intent.putExtra("payload",JSONObject().put("title","Show").put("seriesTitle","Show")
            .put("contentType","series").put("items",items).put("startIndex",0).toString())
        lifecycle.create().start().resume().visible();created=true
        (field("player") as? ExoPlayer)?.release()
        (field("playerView") as androidx.media3.ui.PlayerView).player=null
        set("player",probe.player)
        activity.findViewById<View>(R.id.android_tv_startup_gate).visibility=View.GONE
        idle(); messenger.requests.clear();probe.events.clear()
        TvPlaylistUiQueue.attach(activity.window.decorView)
        TvPlaylistUiQueue.pauseFrames()
    }
    protected fun playlist() = field("playlistView") as RecyclerView
    protected fun overlay() = field("playlistOverlay") as View
    protected fun tabs() = field("seasonTabsContainer") as android.widget.LinearLayout
    protected fun model() = field("payload") as PlaybackPayload
    protected fun showPlaylist() = call("showPlaylist",emptyArray())
    protected fun hidePlaylist() = call("hidePlaylist",emptyArray())
    protected fun rebuild() = call("rebuildPlaylistContent",emptyArray())
    protected fun layout() {
        val root=activity.window.decorView
        root.measure(View.MeasureSpec.makeMeasureSpec(1440,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(900,View.MeasureSpec.EXACTLY))
        root.layout(0,0,1440,900)
        playlist().measure(View.MeasureSpec.makeMeasureSpec(1200,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(500,View.MeasureSpec.EXACTLY))
        playlist().layout(0,0,1200,500)
    }
    protected fun open() { showPlaylist();layout();advanceUi(0);layout() }
    protected fun advanceUi(ms: Long) = TvPlaylistUiQueue.advance(ms)
    protected fun handler() = field("focusRecoveryHandler") as Handler
    protected fun target() = field("navigationTargetPosition") as Int
    protected fun navigating() = field("isNavigating") as Boolean
    protected fun move(delta: Int) = call("movePlaylistFocus",arrayOf(intType),delta)
    protected fun transfer(position: Int) = call("transferFocusToPosition",arrayOf(intType),position)
    protected fun find(position: Int,delta: Int) = call("findNextFocusablePosition",arrayOf(intType,intType),position,delta) as Int
    protected fun next(index: Int) = call("getNextPlayableIndex",arrayOf(intType),index) as Int?
    protected fun prev(index: Int) = call("getPrevPlayableIndex",arrayOf(intType),index) as Int?
    protected fun group(items: List<PlaybackItem>) = call("computeMovieGroups",arrayOf(listType),items) as MovieGroups
    protected fun collection(groups: List<JSONObject>? = null) {
        model().contentType="collection";model().collectionGroups=groups;rebuild()
    }
    protected fun key(code: Int,action: Int=KeyEvent.ACTION_DOWN): Boolean {
        val info=ReflectionHelpers.getField<Any?>(playlist(),"mListenerInfo")
        assertNotNull("production setup installs the playlist listener container",info)
        val listener=ReflectionHelpers.getField<View.OnKeyListener?>(info!!,"mOnKeyListener")
        assertNotNull("production setup installs the playlist key listener",listener)
        return listener!!.onKey(playlist(),code,KeyEvent(action,code))
    }
    @Suppress("UNCHECKED_CAST") protected fun attachListener(): RecyclerView.OnChildAttachStateChangeListener {
        val listeners=ReflectionHelpers.getField<MutableList<RecyclerView.OnChildAttachStateChangeListener>?>(playlist(),"mOnChildAttachStateListeners")
        assertNotNull("production installs the child recovery listener list",listeners)
        assertTrue("production installs the child recovery listener",listeners!!.isNotEmpty())
        return listeners.last()
    }
    @Suppress("UNCHECKED_CAST") protected fun seasonTabs() = field("seasonTabs") as MutableList<TextView>
    @Suppress("UNCHECKED_CAST") protected fun movieTabs() = field("movieTabs") as MutableList<MovieTab>
    protected fun focusedPosition() = playlist().focusedChild?.let { playlist().getChildAdapterPosition(it) } ?: -1
    protected fun text(name: String) = (field(name) as? TextView)?.text?.toString()
    protected fun destroyNow() { lifecycle.destroy();created=false }
    @After fun cleanupPhase13() {
        if(created) lifecycle.destroy()
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(frameDelay)
    }
}
