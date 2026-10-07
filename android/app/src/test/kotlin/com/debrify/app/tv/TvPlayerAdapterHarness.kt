package com.debrify.app.tv

import android.app.Activity
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.junit.After
import org.junit.Before
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import java.time.Duration

internal typealias Original = TvPlayerOriginalAccess

/** Real attached/measured rows, plus deterministic direct binds for recycling. */
internal abstract class TvPlayerAdapterHarness {
    private lateinit var lifecycle: org.robolectric.android.controller.ActivityController<Activity>
    protected lateinit var activity: Activity
    protected lateinit var parent: FrameLayout

    @Before fun createHost() {
        lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        activity = lifecycle.get()
        parent = FrameLayout(activity)
        activity.setContentView(parent)
    }

    @After fun destroyHost() {
        parent.removeAllViews()
        lifecycle.pause().stop().destroy()
    }

    protected fun holder(adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>, position: Int = 0): RecyclerView.ViewHolder =
        adapter.createViewHolder(parent, adapter.getItemViewType(position)).also { adapter.onBindViewHolder(it, position) }

    protected fun attach(adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>): RecyclerView {
        val recycler = RecyclerView(activity).apply {
            layoutManager = LinearLayoutManager(activity)
            itemAnimator = null
            this.adapter = adapter
        }
        parent.addView(recycler, FrameLayout.LayoutParams(1000, 900))
        layout()
        return recycler
    }

    protected fun layout() {
        parent.measure(View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY))
        parent.layout(0, 0, 1000, 900)
    }

    protected fun advance(ms: Long = 200) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
    protected fun text(holder: RecyclerView.ViewHolder, id: Int) = holder.itemView.findViewById<TextView>(id).text.toString()
    protected fun view(holder: RecyclerView.ViewHolder, id: Int): View = holder.itemView.findViewById(id)
    protected fun focus(view: View, focused: Boolean) { view.onFocusChangeListener?.onFocusChange(view, focused) }

    protected data class Notice(val kind: String, val position: Int = -1, val count: Int = 0, val payload: Any? = null)
    protected fun notices(adapter: RecyclerView.Adapter<*>): MutableList<Notice> {
        val output = mutableListOf<Notice>()
        adapter.registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() {
            override fun onChanged() { output += Notice("all") }
            override fun onItemRangeChanged(positionStart: Int, itemCount: Int, payload: Any?) {
                output += Notice("change", positionStart, itemCount, payload)
            }
            override fun onItemRangeInserted(positionStart: Int, itemCount: Int) { output += Notice("insert", positionStart, itemCount) }
            override fun onItemRangeRemoved(positionStart: Int, itemCount: Int) { output += Notice("remove", positionStart, itemCount) }
            override fun onItemRangeMoved(fromPosition: Int, toPosition: Int, itemCount: Int) {
                output += Notice("move", fromPosition, itemCount, toPosition)
            }
        })
        return output
    }

    protected fun item(index: Int = 0, season: Int = 1, episode: Int = 1,
                       title: String = "Episode", progress: Int = 40, watched: Boolean = false): PlaybackItem =
        PlaybackItem.fromJson(org.json.JSONObject().put("index", index).put("season", season).put("episode", episode)
            .put("title", title).put("description", " Description ").put("rating", 8.5)
            .put("durationMs", 1_800_000L).put("resumePositionMs", progress * 18_000L).put("watched", watched))
}
