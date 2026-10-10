package com.debrify.app.tv

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.exoplayer.ExoPlayer
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import org.json.JSONArray
import java.util.Locale
import kotlin.concurrent.thread

internal class TvEpisodeMetadataReceiver(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsOverlayController: TvControlsOverlayController
        val currentIndex: Int
        val ottSkinInstalled: Boolean
        val payload: PlaybackPayload?
        val playbackStartController: TvPlaybackStartController
        val player: ExoPlayer?
        val playlistController: TvPlaylistOverlayController
        val subtitleSourcesController: TvSubtitleSourcesController
    }

    // Broadcast receiver for async metadata updates from Flutter
    var metadataUpdateReceiver: android.content.BroadcastReceiver? = null

    fun setupMetadataReceiver() {
        metadataUpdateReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                // Large JSON arrives as cacheDir file paths — inline extras
                // over the binder limit get the process killed by the system
                // ("can't deliver broadcast"). Inline extras remain as a
                // fallback; a missing/unreadable file just skips the update.
                val updatesJson = readStagedExtra(
                    intent, "metadataUpdatesPath", "episode_metadata_",
                ) ?: intent?.getStringExtra("metadataUpdates")
                val imdbId = intent?.getStringExtra("imdbId")
                val guideJson = readStagedExtra(
                    intent, "guideEpisodesPath", "episode_guide_",
                ) ?: intent?.getStringExtra("guideEpisodes")
                val showName = intent?.getStringExtra("showName")
                handleMetadataUpdate(updatesJson, imdbId, guideJson, showName)
            }
        }

        val filter = android.content.IntentFilter("com.debrify.app.tv.UPDATE_EPISODE_METADATA")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(metadataUpdateReceiver, filter, android.content.Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(metadataUpdateReceiver, filter)
        }
        android.util.Log.d("AndroidTvPlayer", "Metadata update receiver registered")

        // Request metadata from Flutter now that receiver is ready
        requestMetadataFromFlutter()
    }

    /** Reads a staged cacheDir JSON file whose path rides in [key].
     *  Returns null when the extra is absent or the file can't be read.
     *
     *  Read-only on purpose: during an activity handoff two player instances
     *  briefly have live receivers, and a delete-on-read would let the dying
     *  one consume the file before the live one sees it. The sender sweeps
     *  old staged files on each push instead.
     *
     *  Pre-33 the receiver is effectively exported, so never trust the path:
     *  only files of the expected [prefix] directly inside our cacheDir. */
    private fun readStagedExtra(
        intent: android.content.Intent?,
        key: String,
        prefix: String,
    ): String? {
        val path = intent?.getStringExtra(key) ?: return null
        return try {
            val file = java.io.File(path).canonicalFile
            if (file.parentFile?.canonicalPath != activity.cacheDir.canonicalPath ||
                !file.name.startsWith(prefix)
            ) {
                android.util.Log.e("TVMazeUpdate", "Rejected staged $key outside cacheDir")
                return null
            }
            file.readText()
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Failed to read staged $key: ${e.message}")
            null
        }
    }

    private fun handleMetadataUpdate(
        updatesJson: String?,
        imdbId: String?,
        guideJson: String? = null,
        showName: String? = null,
    ) {
        android.util.Log.d("TVMazeUpdate", "handleMetadataUpdate CALLED")
        android.util.Log.d("TVMazeUpdate", "updatesJson length=${updatesJson?.length ?: 0}, imdbId=$imdbId")

        // TVMaze's official show title — the OTT dock's identity line reads
        // it; the payload title (often a release filename) never renders.
        if (!showName.isNullOrBlank()) {
            host.controlsOverlayController.identity.ottShowName = showName.trim()
            if (host.ottSkinInstalled) activity.runOnUiThread { host.controlsOverlayController.identity.updateOttIdentity() }
        }

        val model = host.payload
        if (model == null) {
            android.util.Log.e("TVMazeUpdate", "payload is NULL - cannot update")
            return
        }

        // Handle IMDB ID update for Stremio subtitles
        if (!imdbId.isNullOrEmpty() && imdbId.startsWith("tt")) {
            val previousImdbId = model.imdbId
            if (previousImdbId.isNullOrEmpty()) {
                android.util.Log.d("TVMazeUpdate", "Discovered IMDB ID from TVMaze: $imdbId (was: $previousImdbId)")
                // Update payload with discovered IMDB ID
                model.imdbId = imdbId
                // Fetch Stremio subtitles now that we have IMDB ID
                val currentItem = model.items.getOrNull(host.currentIndex)
                if (currentItem != null) {
                    android.util.Log.d("TVMazeUpdate", "Fetching Stremio subtitles with discovered IMDB ID")
                    host.subtitleSourcesController.fetchStremioSubtitles(currentItem)
                }
            }
        }

        // Full-show episode guide: adopt it and rebuild the series playlist so
        // absent episodes render as fetchable rows (this also enables the
        // playlist overlay for single-stream launches).
        if (!guideJson.isNullOrEmpty()) {
            try {
                val guideArray = JSONArray(guideJson)
                val parsed = mutableListOf<GuideEpisode>()
                for (i in 0 until guideArray.length()) {
                    val g = guideArray.getJSONObject(i)
                    val season = g.optInt("season", -1)
                    val episode = g.optInt("episode", -1)
                    if (season < 0 || episode < 0) continue
                    parsed.add(
                        GuideEpisode(
                            season = season,
                            episode = episode,
                            title = if (g.has("title")) g.optString("title") else null,
                            artwork = if (g.has("artwork")) g.optString("artwork") else null,
                            description = if (g.has("description")) g.optString("description") else null,
                            rating = if (g.has("rating")) g.optDouble("rating") else null,
                            runtime = if (g.has("runtime")) g.optInt("runtime") else null,
                            resumePositionMs = if (g.has("resumePositionMs")) g.optLong("resumePositionMs") else null,
                            durationMs = if (g.has("durationMs")) g.optLong("durationMs") else null,
                            trackerProgressPercent = if (g.has("trackerProgressPercent")) g.optDouble("trackerProgressPercent") else null,
                            watched = g.optBoolean("watched", false),
                            shuffleEligible = g.optBoolean("shuffleEligible", true),
                        )
                    )
                }
                if (parsed.isNotEmpty()) {
                    model.guideEpisodes.clear()
                    model.guideEpisodes.addAll(parsed)
                    android.util.Log.d("TVMazeUpdate", "Adopted ${parsed.size} guide episodes")
                    activity.runOnUiThread {
                        if (model.contentType.lowercase(Locale.US) == "series") {
                            host.playlistController.rebuildPlaylistContent()
                            host.playlistController.seriesPlaylistAdapter?.setActiveIndex(host.currentIndex)
                            host.playbackStartController.navigator.updateCatalogEpisodeControls()
                            model.items.getOrNull(host.currentIndex)?.let { host.controlsOverlayController.identity.updateTitle(it) }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("TVMazeUpdate", "Failed to parse guide episodes: ${e.message}", e)
            }
        }

        // Handle episode metadata updates
        if (updatesJson.isNullOrEmpty()) {
            android.util.Log.d("TVMazeUpdate", "No episode metadata updates to process")
            return
        }

        try {
            val updatesArray = JSONArray(updatesJson)
            android.util.Log.d("TVMazeUpdate", "Parsed ${updatesArray.length()} updates")
            android.util.Log.d("TVMazeUpdate", "model.items.size=${model.items.size}")

            var anyUpdated = false
            var updatedCount = 0
            var skippedCount = 0
            for (i in 0 until updatesArray.length()) {
                val update = updatesArray.getJSONObject(i)
                val requestedIndex = update.optInt("originalIndex", -1)
                val updateSeason = if (update.has("season")) update.optInt("season") else null
                val updateEpisode = if (update.has("episode")) update.optInt("episode") else null
                val originalIndex = if (updateSeason != null && updateEpisode != null) {
                    val requestedItem = model.items.getOrNull(requestedIndex)
                    if (requestedItem?.season == updateSeason && requestedItem.episode == updateEpisode) {
                        requestedIndex
                    } else {
                        model.items.indexOfFirst {
                            it.season == updateSeason && it.episode == updateEpisode
                        }
                    }
                } else {
                    requestedIndex
                }
                if (originalIndex < 0 || originalIndex >= model.items.size) {
                    android.util.Log.w("TVMazeUpdate", "Skipping unmatched update index=$requestedIndex S${updateSeason}E${updateEpisode} (items.size=${model.items.size})")
                    skippedCount++
                    continue
                }

                val item = model.items[originalIndex]
                val newTitle: String? = if (update.has("title")) update.optString("title") else null
                val newDescription: String? = if (update.has("description")) update.optString("description") else null
                val newArtwork: String? = if (update.has("artwork")) update.optString("artwork") else null
                val newRating = if (update.has("rating")) update.optDouble("rating") else null
                val newResumePositionMs = if (update.has("resumePositionMs")) update.optLong("resumePositionMs") else null
                val newDurationMs = if (update.has("durationMs")) update.optLong("durationMs") else null
                val hasWatchedUpdate = update.has("watched")
                val watched = if (hasWatchedUpdate) update.optBoolean("watched", false) else item.watched
                val newTrackerProgress = when {
                    hasWatchedUpdate && watched -> 100.0
                    update.has("trackerProgressPercent") -> update.optDouble("trackerProgressPercent")
                    else -> null
                }
                val isCurrentItem = originalIndex == host.currentIndex
                val livePositionMs = if (isCurrentItem) {
                    (host.player?.currentPosition ?: 0L).coerceAtLeast(0L)
                } else {
                    0L
                }
                val liveDurationMs = if (isCurrentItem) {
                    (host.player?.duration ?: 0L).coerceAtLeast(0L)
                } else {
                    0L
                }

                // Create updated item with new metadata
                val updatedItem = item.copy(
                    title = if (!newTitle.isNullOrEmpty()) newTitle else item.title,
                    description = if (!newDescription.isNullOrEmpty()) newDescription else item.description,
                    artwork = if (!newArtwork.isNullOrEmpty()) newArtwork else item.artwork,
                    rating = newRating ?: item.rating,
                    resumePositionMs = mergeLateMetadataResumePosition(
                        existingPositionMs = item.resumePositionMs,
                        incomingPositionMs = newResumePositionMs,
                        livePositionMs = livePositionMs,
                        isCurrentItem = isCurrentItem,
                    ),
                    durationMs = mergeLateMetadataDuration(
                        existingDurationMs = item.durationMs,
                        incomingDurationMs = newDurationMs,
                        liveDurationMs = liveDurationMs,
                        isCurrentItem = isCurrentItem,
                    ),
                    traktProgressPercent = newTrackerProgress ?: item.traktProgressPercent,
                    watched = watched,
                    allowLocalProgressDisplay = update.optBoolean("allowLocalProgressDisplay", item.allowLocalProgressDisplay),
                )
                model.items[originalIndex] = updatedItem
                anyUpdated = true
                updatedCount++
            }

            android.util.Log.d("TVMazeUpdate", "Updated $updatedCount items, skipped $skippedCount")

            if (anyUpdated) {
                android.util.Log.d("TVMazeUpdate", "Refreshing UI adapters...")
                // Refresh playlist adapter if visible
                activity.runOnUiThread {
                    // seriesPlaylistAdapter and moviePlaylistAdapter extend RecyclerView.Adapter
                    val seriesAdapter = host.playlistController.seriesPlaylistAdapter
                    val movieAdapter = host.playlistController.moviePlaylistAdapter
                    android.util.Log.d("TVMazeUpdate", "seriesAdapter=${seriesAdapter != null}, movieAdapter=${movieAdapter != null}")
                    seriesAdapter?.notifyDataSetChanged()
                    movieAdapter?.notifyDataSetChanged()
                    android.util.Log.d("TVMazeUpdate", "UI refresh done")

                    // Also refresh title bar for currently playing episode
                    val currentItem = model.items.getOrNull(host.currentIndex)
                    if (currentItem != null) {
                        android.util.Log.d("TVMazeUpdate", "Refreshing title for current episode: ${currentItem.title}")
                        host.controlsOverlayController.identity.updateTitle(currentItem)
                    }
                }
            } else {
                android.util.Log.w("TVMazeUpdate", "No items updated - anyUpdated=false")
            }
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Failed to parse metadata updates: ${e.message}", e)
        }
    }

    fun requestMetadataFromFlutter() {
        android.util.Log.d("TVMazeUpdate", "requestMetadataFromFlutter CALLED")
        val model = host.payload ?: return

        // Only request metadata for series content
        if (model.contentType != "series") {
            android.util.Log.d("TVMazeUpdate", "Not requesting metadata - contentType=${model.contentType}")
            return
        }

        try {
            val channel = MainActivity.getAndroidTvPlayerChannel()
            if (channel == null) {
                android.util.Log.e("TVMazeUpdate", "Method channel is null, cannot request metadata")
                return
            }

            android.util.Log.d("TVMazeUpdate", "Invoking requestEpisodeMetadata on method channel")
            // Method channel calls MUST be on the main/UI thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod("requestEpisodeMetadata", null)
                    android.util.Log.d("TVMazeUpdate", "requestEpisodeMetadata invoked successfully")
                } catch (e: Exception) {
                    android.util.Log.e("TVMazeUpdate", "Failed to invoke requestEpisodeMetadata", e)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Error requesting metadata from Flutter", e)
        }
    }
}
