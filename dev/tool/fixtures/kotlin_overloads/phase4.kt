package com.debrify.app.tv

import androidx.appcompat.app.AppCompatActivity

class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    private var tick: Runnable? = null
    fun render() {
        val ctx = this
        Accept.read(ctx)
        AutoSyncRingView(this)
        TextView(this)
        LinearLayout(this)
        SubtitleLinePickerController(this)
        SubtitleSyncOverlayController(this)
        Intent(this)
        Builder(this)
        tick = object : Runnable {
            override fun run() {
                if (tick === this) Accept.post(this)
            }
        }
    }
}
