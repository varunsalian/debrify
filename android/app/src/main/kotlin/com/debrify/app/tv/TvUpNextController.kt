package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.annotation.OptIn
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.bumptech.glide.Glide
        private const val UP_NEXT_THRESHOLD_MS = 25_000L   // show card when this much remains
        private const val UP_NEXT_MIN_DURATION_MS = 5 * 60_000L  // skip for short clips
        private const val UP_NEXT_TICK_MS = 500L

@OptIn(UnstableApi::class)
internal class TvUpNextController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val player: ExoPlayer?
        val payload: PlaybackPayload?
        val currentIndex: Int
        val continuousShuffleEnabled: Boolean
        val isIptvMode: Boolean
        val isStremioTvMode: Boolean
        var isAutoAdvancing: Boolean
        fun isCleanPlaybackState(): Boolean
        fun canShuffleWholeShow(): Boolean
        fun pickShuffleIndex(): Int?
        fun getNextPlayableIndex(i: Int): Int?
        fun playItem(index: Int)
    }

    // Up Next card (slide-in near end of episode)
    lateinit var upNextCard: View
    lateinit var upNextPoster: android.widget.ImageView
    lateinit var upNextTitle: TextView
    lateinit var upNextCountdown: TextView
    var upNextVisible = false
    private var upNextTargetIndex: Int? = null
    private var upNextDismissedForIndex = -1
    val upNextHandler = Handler(Looper.getMainLooper())

    // Called periodically from the progress loop. Shows the Up Next card when
    // the current episode is near its end and a playable next item exists.
    fun maybeShowUpNext() {
        if (upNextVisible) return
        if (host.continuousShuffleEnabled && host.canShuffleWholeShow()) return
        if (host.isIptvMode || host.isStremioTvMode) return
        if (upNextDismissedForIndex == host.currentIndex) return
        if (!host.isCleanPlaybackState()) return
        val p = host.player ?: return
        if (p.playbackState != Player.STATE_READY || !p.isPlaying) return
        val duration = p.duration
        if (duration <= UP_NEXT_MIN_DURATION_MS) return
        val remaining = duration - p.currentPosition
        if (remaining <= 0 || remaining > UP_NEXT_THRESHOLD_MS) return
        // Mirror the STATE_ENDED auto-advance: shuffle picks a random eligible
        // episode, otherwise advance to the linear next.
        val nextIndex = if (host.continuousShuffleEnabled) {
            host.pickShuffleIndex()
        } else {
            host.getNextPlayableIndex(host.currentIndex)
        } ?: return
        showUpNextCard(nextIndex)
    }

    private val upNextTicker = object : Runnable {
        override fun run() {
            val p = host.player
            val target = upNextTargetIndex
            val duration = p?.duration ?: 0L
            if (p == null || target == null || duration <= 0) {
                hideUpNextCard()
                return
            }
            // A panel/controls opened — pull the card; the progress loop can
            // re-show it later if still near the end.
            if (!host.isCleanPlaybackState()) {
                hideUpNextCard()
                return
            }
            val remaining = duration - p.currentPosition
            // User seeked back well before the end — drop the card.
            if (remaining > UP_NEXT_THRESHOLD_MS + 5_000L) {
                hideUpNextCard()
                return
            }
            if (remaining <= UP_NEXT_TICK_MS + 250L) {
                triggerUpNext()
                return
            }
            val secs = ((remaining + 999L) / 1000L).toInt()
            upNextCountdown.text = "Starting in ${secs}s"
            upNextHandler.postDelayed(this, UP_NEXT_TICK_MS)
        }
    }

    private fun showUpNextCard(nextIndex: Int) {
        val model = host.payload ?: return
        if (nextIndex < 0 || nextIndex >= model.items.size) return
        val item = model.items[nextIndex]
        upNextTargetIndex = nextIndex

        val badge = item.seasonEpisodeLabel()
        upNextTitle.text = if (badge.isNotEmpty()) "$badge · ${item.title}" else item.title

        val art = item.artwork
        if (!art.isNullOrEmpty()) {
            upNextPoster.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(activity).load(art).into(upNextPoster)
        } else {
            upNextPoster.visibility = View.GONE
        }

        upNextVisible = true
        upNextCard.visibility = View.VISIBLE
        upNextCard.alpha = 0f
        upNextCard.translationX = 40f
        upNextCard.animate().alpha(1f).translationX(0f).setDuration(220).start()

        upNextHandler.removeCallbacks(upNextTicker)
        upNextHandler.post(upNextTicker)
    }

    fun triggerUpNext() {
        // playItem() hides the card (and cancels the ticker) as part of its
        // per-item reset, so no explicit hide is needed here.
        val target = upNextTargetIndex ?: return
        host.isAutoAdvancing = true
        host.playItem(target)
    }

    fun dismissUpNext() {
        upNextDismissedForIndex = host.currentIndex
        hideUpNextCard()
    }

    fun hideUpNextCard() {
        upNextHandler.removeCallbacks(upNextTicker)
        upNextTargetIndex = null
        if (!upNextVisible) {
            upNextCard.visibility = View.GONE
            return
        }
        upNextVisible = false
        upNextCard.animate().alpha(0f).translationX(40f).setDuration(160).withEndAction {
            upNextCard.visibility = View.GONE
            upNextCard.translationX = 0f
        }.start()
    }
}
