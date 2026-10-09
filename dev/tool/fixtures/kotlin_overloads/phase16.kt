package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.ui.PlayerView

class TvControlsDockController(private val host: Host) {
    interface Host {
        var pauseButton: AppCompatButton?
        val ottQualityChips: Array<TextView?>
        var controlsOverlay: View?
    }
    private val playerView = PlayerView()
    fun bind() {
        host.pauseButton = playerView.findViewById(1)
        host.ottQualityChips[0] = playerView.findViewById(2)
        host.controlsOverlay = playerView.findViewById(3)
    }
}

class TvDockIdentityPresenter {
    @Volatile var ottShowName: String? = null
}
class AndroidTvTorrentPlayerActivity {
    private val identity = TvDockIdentityPresenter()
    fun handleMetadataUpdate(name: String?) { identity.ottShowName = name }
    fun replacePayloadWithStremioTvItem(name: String?) { identity.ottShowName = name }
    val playlistController = object {
        fun name() = identity.ottShowName
    }
}
