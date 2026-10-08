package com.debrify.app.tv
import androidx.appcompat.app.AppCompatActivity
import android.view.View
import android.widget.TextView
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    var overrideFinishes = 0
    override fun finish() { overrideFinishes++; super.finish() }
    fun exhaust() {
        findViewById<TextView>(1)
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
        }
        val result = object : Runnable {
            override fun run() {
                runOnUiThread { if (!isFinishing && !isDestroyed) findViewById<View>(2) }
            }
        }
        result.run()
        finish()
    }
}
