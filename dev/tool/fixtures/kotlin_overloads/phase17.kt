package com.debrify.app.tv

import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class IptvLiveRecovery
object IptvDeviceQuirks { fun startsIptvWithStrictTs() = false }
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    @Volatile private var currentIptvHttpHeaders: Map<String, String> = emptyMap()
    @Volatile private var iptvStrictTsActive = false
    val iptvTuneController = TvIptvTuneController(this, object : TvIptvTuneController.Host {
        override var currentIptvHttpHeaders: Map<String,String>
            get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders
            set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders = value }
        override var iptvStrictTsActive: Boolean
            get() = this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive
            set(value) { this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive = value }
    })
    fun pill() { TextView(this).apply { addContentView(this, android.view.ViewGroup.LayoutParams()) } }
}
class TvIptvTuneController(private val activity: AppCompatActivity, private val host: Host) {
    interface Host {
        var currentIptvHttpHeaders: Map<String,String>
        var iptvStrictTsActive: Boolean
    }
    val iptvLiveRecovery by lazy { IptvLiveRecovery() }
    val iptvStartsWithStrictTs by lazy { IptvDeviceQuirks.startsIptvWithStrictTs() }
    fun pill() { TextView(activity).apply { activity.addContentView(this, android.view.ViewGroup.LayoutParams()) } }
}
