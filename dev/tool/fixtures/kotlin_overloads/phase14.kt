package com.debrify.app.tv
import androidx.appcompat.app.AppCompatActivity
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    fun exhaust() {
        val list = ListView(this).apply {
            this.adapter = null
            Probe.contexts.add(context)
        }
        val adapter = object : ArrayAdapter<String>(this, 0, listOf("row")) {
            override fun getView(position: Int): TextView {
                val item = getItem(position)
                return TextView(context).apply { text = item }
            }
        }
        val addon = Addon(resources = listOf("subtitles"))
        runOnUiThread { Probe.contexts.add(adapter.getView(0).context); Probe.contexts.add(list.context); check(addon.resources.single() == "subtitles") }
    }
}
