package com.debrify.app.tv

import androidx.appcompat.app.AppCompatActivity
import android.view.View
import android.widget.TextView

class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    var overrideFinishes = 0
    override fun finish() {
        overrideFinishes++
        super.finish()
    }
    fun exhaust() {
        findViewById<TextView>(1)
        findViewById<View>(2)
        findViewById<TextView>(3)
        finish()
    }
}
