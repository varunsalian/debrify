package com.debrify.app.tv

import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.net.Uri
import com.debrify.app.MainActivity
import com.debrify.app.R
import org.json.JSONObject
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt

@OptIn(UnstableApi::class)
internal class TvSourceSwitchApplier(
    private val activity: AppCompatActivity,
    private val host: TvSourceSwitchController.Host,
    private val switcher: TvSourceSwitchController,
) {

    fun switchToSourcePlaylist(
        sourceIndex: Int,
        rawItems: List<*>,
        targetSeason: Int? = null,
        targetEpisode: Int? = null,
        suppressTargetResume: Boolean = false,
        requireExactStartupEpisode: Boolean = false,
        shuffleAttempt: ShufflePlaybackAttempt? = null,
    ) {
        android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist: sourceIndex=$sourceIndex, rawItems=${rawItems.size}, target=S${targetSeason}E${targetEpisode}")

        val model = host.payload ?: return
        if (shuffleAttempt != null) {
            val outgoingItems = model.items.toList()
            val outgoingIndex = host.currentIndex
            val outgoingSource = host.currentStremioSourceIndex
            val outgoingType = model.contentType
            shuffleAttempt.restorePreparation = {
                model.items.clear()
                model.items.addAll(outgoingItems)
                host.currentIndex = outgoingIndex
                host.currentStremioSourceIndex = outgoingSource
                rebuildNavigationMaps(model, outgoingType)
                host.updateCatalogEpisodeControls()
            }
        }

        // Capture playback position + current item identity so the new source
        // resumes the same content instead of restarting from the beginning.
        // An unlanded resume outranks the live position (same rule as
        // switchToStremioSource): carry the HELD bookmark into the new pack,
        // not the ~0 a dropped/clamped resume left playback at. playItem's
        // READY re-arm restarts the hold window for the new source.
        // An explicit episode-guide target is different content: land there
        // instead, and never carry the current position onto it.
        val liveSwitchPos = (host.player?.currentPosition ?: 0L).coerceAtLeast(0L)
        val resumePositionMs = host.heldResumePositionMs(liveSwitchPos) ?: liveSwitchPos
        val currentItem = model.items.getOrNull(host.currentIndex)
        val explicitTarget = targetSeason != null && targetEpisode != null
        val resumeSeason = targetSeason ?: currentItem?.season
        val resumeEpisode = targetEpisode ?: currentItem?.episode
        val sameContent = !explicitTarget ||
            (targetSeason == currentItem?.season && targetEpisode == currentItem?.episode)

        // Parse metadata entry (first item with __meta__ flag)
        var contentType = model.contentType
        val itemMaps = mutableListOf<Map<*, *>>()
        for (raw in rawItems) {
            val map = raw as? Map<*, *> ?: continue
            if (map["__meta__"] == true) {
                contentType = (map["contentType"] as? String) ?: contentType
                continue
            }
            itemMaps.add(map)
        }

        if (itemMaps.isEmpty()) {
            android.util.Log.e("AndroidTvPlayer", "switchToSourcePlaylist - no valid items after parsing")
            if (!host.failManualSourceCandidate("playlist-empty-after-parse")) {
                host.showStatusPillTransient("Source unavailable")
            }
            return
        }

        // Parse items into PlaybackItem list
        val newItems = mutableListOf<PlaybackItem>()
        for (map in itemMaps) {
            try {
                newItems.add(PlaybackItem.fromMap(map))
            } catch (e: Exception) {
                android.util.Log.w("AndroidTvPlayer", "switchToSourcePlaylist - failed to parse item: ${e.message}")
            }
        }

        if (newItems.isEmpty()) {
            android.util.Log.e("AndroidTvPlayer", "switchToSourcePlaylist - no items parsed successfully")
            if (!host.failManualSourceCandidate("playlist-items-invalid")) {
                host.showStatusPillTransient("Source unavailable")
            }
            return
        }

        if ((requireExactStartupEpisode || host.manualSourceSwitchSnapshot != null) &&
            resumeSeason != null &&
            resumeEpisode != null &&
            !startupPlaylistSatisfiesEpisode(
                newItems.map { it.season to it.episode },
                resumeSeason,
                resumeEpisode,
            )
        ) {
            startupLog(
                "event=candidate_reject reason=playlist_missing_episode " +
                    "targetSeason=$resumeSeason targetEpisode=$resumeEpisode " +
                    "itemCount=${newItems.size} ${host.startupSourceFields(sourceIndex)}",
                warning = true,
            )
            android.util.Log.w(
                "AndroidTvPlayer",
                "Startup playlist source $sourceIndex omits S${resumeSeason}E$resumeEpisode",
            )
            if (!host.failManualSourceCandidate("playlist-missing-episode") &&
                !host.failStartupResolution(sourceIndex, "playlist-missing-episode")
            ) {
                host.showStatusPillTransient("Source does not contain this episode")
            }
            return
        }

        // A singleton direct stream has no pack filenames from which Flutter
        // can infer an episode. Preserve the catalog identity across a manual
        // source switch as well as an adjacent-episode fetch.
        if (contentType == "series" && newItems.size == 1 &&
            (newItems[0].season == null || newItems[0].episode == null) &&
            resumeSeason != null && resumeEpisode != null) {
            newItems[0] = newItems[0].copy(
                season = resumeSeason,
                episode = resumeEpisode,
            )
        }

        android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - parsed ${newItems.size} items, contentType=$contentType")

        // Carry the FETCHED episode metadata (TVMaze titles/artwork/ratings)
        // from the outgoing items onto the new source's matching episodes.
        // The new payload's titles are the new pack's raw filenames, and the
        // metadata re-request below round-trips through Flutter — without
        // this hand-off the dock identity regresses to the release name for
        // that window (or for good, if the re-request fails). An old title
        // counts as fetched only when a metadata push actually replaced it
        // (title differs from the preserved sourceTitle).
        val oldBySeasonEpisode = model.items
            .filter { it.season != null && it.episode != null }
            .associateBy { it.season to it.episode }
        for (i in newItems.indices) {
            val ni = newItems[i]
            if (ni.season == null || ni.episode == null) continue
            val old = oldBySeasonEpisode[ni.season to ni.episode]
            val oldFetchedTitle = old?.title?.takeIf {
                it.isNotBlank() && old.sourceTitle != null && it != old.sourceTitle
            }
            val guide = model.guideEpisodes.firstOrNull {
                it.season == ni.season && it.episode == ni.episode
            }
            newItems[i] = ni.copy(
                title = resolveSwitchedEpisodeTitle(
                    episode = ni.episode,
                    incomingTitle = ni.title,
                    sourceTitle = ni.sourceTitle,
                    guideTitle = guide?.title,
                    previousEpisodeTitle = oldFetchedTitle,
                ),
                artwork = ni.artwork ?: guide?.artwork ?: old?.artwork,
                description = ni.description ?: guide?.description ?: old?.description,
                rating = ni.rating ?: guide?.rating ?: old?.rating,
            )
        }

        // Movies / single-file payloads have no S/E to match on: when the
        // switch stays on the SAME content, the identity must not change
        // just because the file name did — keep the outgoing title (the
        // clean movie name on catalog launches) plus artwork/rating. The
        // quality chips still re-parse from the NEW source via sourceTitle.
        if (newItems.size == 1 && newItems[0].season == null &&
            sameContent && currentItem != null
        ) {
            val ni = newItems[0]
            newItems[0] = ni.copy(
                title = currentItem.title.ifBlank { ni.title },
                artwork = ni.artwork ?: currentItem.artwork,
                description = ni.description ?: currentItem.description,
                rating = ni.rating ?: currentItem.rating,
            )
        }

        // Find which item in the new source's playlist matches what the user was
        // watching, so we resume the same content rather than restarting at file 0.
        //  - Single item: unambiguous — it's the content (movie, or one episode).
        //  - Series (multi-file): match by season+episode.
        //  - Collection (multi-file movie torrent): match by title; if names
        //    differ across sources, keep the same list position but don't carry
        //    the timestamp onto what could be a different movie.
        var targetIndex = 0
        var matchedSameContent = false
        if (newItems.size == 1) {
            targetIndex = 0
            matchedSameContent = sameContent
        } else if (resumeSeason != null && resumeEpisode != null) {
            val matched = newItems.indexOfFirst {
                it.season == resumeSeason && it.episode == resumeEpisode
            }
            if (matched >= 0) {
                targetIndex = matched
                matchedSameContent = sameContent
            } else {
                // The exact episode isn't in this source. Do NOT fall back to
                // file 0 — in torrent order that's often an extras/bonus clip
                // (a season pack may list "Extras/" or a featurette first).
                // Land on the first REAL episode (skip season 0 / specials),
                // and tell the user we couldn't find what they were watching.
                val firstReal = newItems.indexOfFirst {
                    val s = it.season
                    s != null && s != 0 && it.episode != null
                }
                targetIndex = if (firstReal >= 0) firstReal else 0
                Toast.makeText(
                    activity,
                    "S${resumeSeason}E${resumeEpisode} not in this source — playing from the start",
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (currentItem != null) {
            val byTitle = newItems.indexOfFirst {
                it.title.isNotEmpty() && it.title == currentItem.title
            }
            if (byTitle >= 0) {
                targetIndex = byTitle
                matchedSameContent = true
            } else {
                targetIndex = host.currentIndex.coerceIn(0, newItems.lastIndex)
            }
        }
        if (matchedSameContent && resumePositionMs > 0 && targetIndex in newItems.indices) {
            newItems[targetIndex] = newItems[targetIndex].copy(resumePositionMs = resumePositionMs)
            android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - resuming item $targetIndex at $resumePositionMs ms")
        } else {
            android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - playing item $targetIndex from start (matchedSameContent=$matchedSameContent)")
        }

        // Update source state
        host.currentStremioSourceIndex = sourceIndex
        switcher.updateStremioQualityBadge()
        host.sourceBrowser?.render()

        // Cancel any ongoing PikPak retry
        host.cancelPikPakRetry()

        // Replace payload items and content type
        model.items.clear()
        model.items.addAll(newItems)
        host.shuffleBag.clear()

        // Rebuild navigation maps for new items
        rebuildNavigationMaps(model, contentType)

        // Point currentIndex at the item we're about to play BEFORE rebuilding
        // the UI: setupSeasonTabs / buildList default the season tab and the
        // active highlight off currentIndex. If it still held the OLD source's
        // index (into a differently-ordered list), the now-playing episode could
        // land outside the selected tab and be neither shown nor highlighted.
        // playItem() re-affirms currentIndex = targetIndex momentarily later.
        host.currentIndex = targetIndex

        // Rebuild playlist UI (without re-adding RecyclerView listeners)
        host.rebuildPlaylistContent()

        // Re-run the TVMaze pipeline for the new payload: launch was the only
        // requester, so a switched-in source would otherwise keep raw pack
        // filenames wherever the carry-over above had no match (episodes the
        // old source lacked, or a first switch before any push arrived).
        // No-ops for non-series content; rebuildNavigationMaps already set
        // model.contentType above.
        host.requestMetadataFromFlutter()

        // Update the title content for the next controls reveal.
        val currentSource = host.stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            host.titleView.text = currentSource.displayTitle
        }

        // Resume the previously-playing item; the captured position is carried
        // on the item above as resumePositionMs. Suppress tracker/startAt percent
        // seeks so they can't override our explicit resume position — but ONLY
        // when the new source landed on the SAME content: a fallback episode
        // (exact episode missing from the new source) has no captured position
        // and must keep its own per-episode tracker resume, matching the Dart
        // player's landedOnSameContent behaviour.
        //
        // EXCEPT during startup failover: the failed candidate never rendered,
        // so there is no live position to protect (resumePositionMs is 0) —
        // latching here would burn the launch tracker percent (watched on
        // another device) and start the episode at 0:00. The single-URL
        // failover route keeps that percent; this route must match.
        if (host.startupFailoverCursor?.committed != false) {
            host.percentSeekApplied = true
        }
        if (host.manualSourceSwitchSnapshot != null) {
            host.manualSourceMediaReplaced = true
            host.manualSourceCandidateUrl = newItems.getOrNull(targetIndex)?.url
        }
        host.playItem(
            targetIndex,
            suppressTrakt = matchedSameContent,
            suppressResume = suppressTargetResume,
            shuffleAttempt = shuffleAttempt,
        )

        // Report the switch outcome once playback settles
        if (host.startupFailoverCursor?.committed != false &&
            host.manualSourceSwitchSnapshot == null
        ) {
            switcher.watchSourceSwitchOutcome(sourceIndex)
        }
    }

    fun switchToStremioSource(url: String, sourceIndex: Int, mimeType: String? = null, mimeDiscovered: Boolean = false) {
        // Live Stremio IPTV channel: the movie path below seeks to the
        // previous position and runs PikPak/YouTube bookkeeping — all wrong
        // for a live stream. Route to the dedicated live switch.
        if (host.isIptvMode && host.iptvChannelStartController.iptvStremioChannelKey != null) {
            host.iptvChannelStartController.switchToIptvStremioSource(url, sourceIndex)
            return
        }
        val sourceHeaders = host.stremioSources.getOrNull(sourceIndex)?.httpHeaders.orEmpty()
        if (!mimeDiscovered && ProtectedStreamHttp.needsDiscovery(url, sourceHeaders)) {
            host.discoverProtectedMime(url, sourceHeaders) { discovered ->
                switchToStremioSource(url, sourceIndex, discovered, mimeDiscovered = true)
            }
            return
        }
        host.mediaPreparationGeneration++
        android.util.Log.d("AndroidTvPlayer", "switchToStremioSource: index=$sourceIndex, url=${url.take(60)}...")

        // Capture current position for resume. If a resume hold is active the
        // live position is a not-yet-landed artifact — carry the HELD target
        // into the new source so the switch restores the bookmark, not ~0.
        // The hold's settle window restarts: the new source gets its own full
        // chance to land the restore before real playback wins.
        val livePos = host.player?.currentPosition ?: 0L
        val heldPos = host.heldResumePositionMs(livePos)
        if (heldPos != null) {
            host.resumeHoldArmedAtMs = android.os.SystemClock.elapsedRealtime()
        }
        val currentPos = heldPos ?: livePos
        val headers = host.stremioSources.getOrNull(sourceIndex)?.httpHeaders.orEmpty()
        host.activeVodHeaders = setOfNotNull(originKey(Uri.parse(url))) to headers
        host.payload?.items?.getOrNull(host.currentIndex)?.let { item ->
            host.payload?.items?.set(host.currentIndex, item.copy(url = url, httpHeaders = headers, mimeType = mimeType))
        }

        // Update state
        host.currentStremioSourceIndex = sourceIndex
        switcher.updateStremioQualityBadge()
        host.sourceBrowser?.render()

        // Cancel any ongoing PikPak retry before switching
        host.cancelPikPakRetry()

        // Switch ExoPlayer source, preserving position. For high-res YouTube the
        // current item carries a separate audio track that ALL qualities share,
        // so merge the newly picked (video-only) url with that audio — otherwise
        // switching to a video-only quality would go silent. Non-YouTube sources
        // (no separate audio) use the single url as-is.
        val currentAudioUrl = host.payload?.items?.getOrNull(host.currentIndex)?.audioUrl
        val mergedSource = if (!currentAudioUrl.isNullOrEmpty()) {
            host.buildMergedSource(url, currentAudioUrl)
        } else {
            null
        }
        if (host.manualSourceSwitchSnapshot != null) {
            host.manualSourceMediaReplaced = true
            host.manualSourceCandidateUrl = url
        }
        if (mergedSource != null) {
            host.subtitleTrackReadiness.onMediaReplacement()
            host.player?.setMediaSource(mergedSource)
        } else {
            host.subtitleTrackReadiness.onMediaReplacement()
            host.player?.setMediaItem(MediaItem.Builder().setUri(url).setMimeType(mimeType).build())
        }
        host.player?.prepare()
        if (currentPos > 0) {
            host.player?.seekTo(currentPos)
        }
        host.player?.play()

        // Report the switch outcome once playback settles
        if (host.startupFailoverCursor?.committed != false &&
            host.manualSourceSwitchSnapshot == null
        ) {
            switcher.watchSourceSwitchOutcome(sourceIndex)
        }

        // Update the title content for the next controls reveal.
        val currentSource = host.stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            host.titleView.text = currentSource.displayTitle
        }

        // For PikPak URLs, start cold storage retry monitoring
        if (url.contains("mypikpak.com")) {
            android.util.Log.d("AndroidTvPlayer", "switchToStremioSource: PikPak URL detected, starting retry logic")
            host.pikPakRetryId++
            val myRetryId = host.pikPakRetryId
            host.pikPakRetryCount = 0
            host.isPikPakRetrying = false
            host.hidePikPakRetryOverlay()
            // Build a temporary PlaybackItem for the retry loop
            val tempItem = PlaybackItem(
                id = "stremio_source_$sourceIndex",
                title = currentSource?.displayTitle ?: "",
                url = url,
                index = sourceIndex,
                season = null,
                episode = null,
                artwork = null,
                description = null,
                resumePositionMs = currentPos,
                durationMs = 0L,
                updatedAt = 0L,
                resumeId = null,
                sizeBytes = currentSource?.sizeBytes,
                rating = null,
                provider = PROVIDER_PIKPAK,
            )
            host.attemptPikPakPlaybackLoop(tempItem, 0, myRetryId)
        }
    }
}
