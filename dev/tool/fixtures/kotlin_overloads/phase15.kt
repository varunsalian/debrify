package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout

class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    private val playerView = PlayerView()
    private var pauseButton: AppCompatButton? = null
    private val ottQualityChips = arrayOfNulls<TextView>(3)
    private var controlsOverlay: View? = null
    private val resizeModes = arrayOf(AspectRatioFrameLayout.RESIZE_MODE_FIT, AspectRatioFrameLayout.RESIZE_MODE_FILL, AspectRatioFrameLayout.RESIZE_MODE_ZOOM)
    fun bind() {
        pauseButton = playerView.findViewById(1)
        ottQualityChips[0] = playerView.findViewById(2)
        controlsOverlay = playerView.findViewById(3)
    }
}
