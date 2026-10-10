package com.debrify.app.tv

import androidx.appcompat.app.AppCompatActivity
import kotlin.random.Random

class ShowShuffle(private val random: Random = Random.Default) {
    private val visited = mutableSetOf<Int>()
}

class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    private val showShuffle = ShowShuffle()
    var overrideFinishes = 0
    override fun finish() { overrideFinishes++; super.finish() }
    fun handBack() { finish() }
}

class TvPlaybackNavigator(private val activity: AppCompatActivity) : AppCompatActivity() {
    private val showShuffle = ShowShuffle()
    fun handBack() { activity.finish() }
}

object StaticFinish {
    @JvmStatic fun finish(activity: AppCompatActivity) { activity.finish() }
}
