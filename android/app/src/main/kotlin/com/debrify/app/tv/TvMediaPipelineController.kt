package com.debrify.app.tv

import android.util.Log
import android.view.View
import com.debrify.app.audio.NativeAudioRouting
import com.debrify.app.audio.NativeAudioRenderersFactory
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import android.net.ConnectivityManager
import android.net.Network
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import android.net.Uri
import com.debrify.app.util.LanguageMapper
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings
import kotlin.concurrent.thread
import android.content.Context

@OptIn(UnstableApi::class)
internal class TvMediaPipelineController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val activeVodHeaders: Pair<Set<String>, Map<String, String>>
        val currentIptvHttpHeaders: Map<String, String>
        val currentIptvIndex: Int
        val displayController: TvPlaybackDisplayController
        val iptvChannels: MutableList<IptvChannelEntry>
        val iptvDecoderMode: String
        var iptvNetworkCallback: ConnectivityManager.NetworkCallback?
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvRecordingController: IptvRecordingController
        val iptvStrictTsActive: Boolean
        val iptvTuneController: TvIptvTuneController
        val iptvTuneDiagnostics: IptvTuneDiagnostics
        val isIptvMode: Boolean
        val nativeAudioRouting: NativeAudioRouting
        val networkBuffer: String
        val networkPatience: String
        var offsetRenderersFactory: OffsetRenderersFactory?
        val payload: PlaybackPayload?
        val playbackListener: Player.Listener
        var player: ExoPlayer?
        val playerPreferences: com.debrify.app.profiles.NativePlayerPreferences
        val playerView: PlayerView
        var protectedStreamClient: okhttp3.OkHttpClient
        var speechTap: SpeechFeatureTap?
        val startupGateController: TvStartupGateController
        val subtitleController: TvSubtitleController
        var subtitleListener: Player.Listener?
        val subtitleOverlay: SubtitleView
        var trackSelector: DefaultTrackSelector?
        fun restartProgressUpdates(): Unit
    }

    private val iptvDiagAnalyticsListener = object : AnalyticsListener {
        override fun onRenderedFirstFrame(
            eventTime: AnalyticsListener.EventTime,
            output: Any,
            renderTimeMs: Long,
        ) {
            host.startupGateController.mediaServerPlaybackLog("first_frame")
            host.iptvTuneDiagnostics.onFirstFrame()
            if (host.startupGateController.manualSourceRestoreInProgress) {
                host.startupGateController.manualSourceRestoreInProgress = false
                host.restartProgressUpdates()
            }
            host.startupGateController.commitManualSourceCandidate()
            host.startupGateController.commitStartupCandidate()
        }

        override fun onLoadCompleted(
            eventTime: AnalyticsListener.EventTime,
            loadEventInfo: androidx.media3.exoplayer.source.LoadEventInfo,
            mediaLoadData: androidx.media3.exoplayer.source.MediaLoadData,
        ) {
            host.iptvTuneDiagnostics.onBytesLoaded(loadEventInfo.bytesLoaded)
        }
    }

    /**
     * Video decoder order for IPTV, honouring the user's Playback setting.
     *
     * A frozen picture with running audio on live TV is the box's hardware
     * decoder mishandling the stream (MediaTek/Amlogic boxes are the usual
     * reports, and ExoPlayer issue #10369 is the same signature) — it can't
     * be fixed from the app, only routed around, which is why every IPTV
     * player exposes this switch. 'software' promotes Android's own software
     * codecs; the rejected decoders stay in the list as fallbacks because
     * setEnableDecoderFallback(true) can still reach them. Audio decoding and
     * every non-IPTV playback keep the platform's own order.
     */
    private fun iptvMediaCodecSelector(): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val infos = MediaCodecSelector.DEFAULT.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder,
            )
            if (!host.isIptvMode || host.iptvDecoderMode == "auto" || !MimeTypes.isVideo(mimeType)) {
                infos
            } else {
                val preferSoftware = host.iptvDecoderMode == "software"
                val preferred = infos.filter { it.softwareOnly == preferSoftware }
                if (preferred.isEmpty()) {
                    infos
                } else {
                    preferred + infos.filterNot { it.softwareOnly == preferSoftware }
                }
            }
        }
    }

    fun setupPlayer() {
        host.trackSelector = DefaultTrackSelector(activity)

        // Get default language settings
        val defaultAudioLang = host.playerPreferences.getString("player_default_audio_language", null)
        val defaultSubtitleLang = host.playerPreferences.getString("player_default_subtitle_language", null)

        // Build track selector parameters with robust language matching
        val paramsBuilder = host.trackSelector?.buildUponParameters()
            // HDMI can temporarily lose surround support during a display-mode
            // switch. Reconsider PCM fallback when the capabilities return.
            ?.setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
            ?.setPreferredAudioMimeType("audio/opus")
            ?.setIgnoredTextSelectionFlags(C.SELECTION_FLAG_DEFAULT)

        // Live IPTV: never adapt between video tracks in a way that forces a
        // codec reconfigure. That switch — not the stream itself — is where
        // strict decoders wedge into "frozen picture, audio still running"
        // (ExoPlayer #10369, an ABR switch on an Amlogic STB with no
        // MediaCodec error at all). Seamless adaptation within one codec
        // configuration is untouched, so multi-variant channels still adapt.
        if (host.isIptvMode) {
            paramsBuilder?.setAllowVideoNonSeamlessAdaptiveness(false)
        }

        // Apply audio language preference
        if (defaultAudioLang != null) {
            val audioVariants = LanguageMapper.getLanguageVariantsForExoPlayer(defaultAudioLang)
            if (audioVariants.isNotEmpty()) {
                paramsBuilder?.setPreferredAudioLanguages(*audioVariants.toTypedArray())
            } else {
                paramsBuilder?.setPreferredAudioLanguage(defaultAudioLang)
            }
        } else {
            // Default to English if no preference set
            val englishVariants = LanguageMapper.getLanguageVariantsForExoPlayer("en")
            paramsBuilder?.setPreferredAudioLanguages(*englishVariants.toTypedArray())
        }

        // Apply subtitle language preference
        when {
            defaultSubtitleLang == "off" -> {
                paramsBuilder?.setPreferredTextLanguage("")
                paramsBuilder?.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            }
            defaultSubtitleLang != null -> {
                // Get all language variants (ISO 639-1, ISO 639-2, etc.) for robust matching
                val variants = LanguageMapper.getLanguageVariantsForExoPlayer(defaultSubtitleLang)
                if (variants.isNotEmpty()) {
                    paramsBuilder?.setPreferredTextLanguages(*variants.toTypedArray())
                } else {
                    paramsBuilder?.setPreferredTextLanguage(defaultSubtitleLang)
                }
            }
            else -> {
                // Default to English if no preference set
                val englishVariants = LanguageMapper.getLanguageVariantsForExoPlayer("en")
                paramsBuilder?.setPreferredTextLanguages(*englishVariants.toTypedArray())
            }
        }

        // Start with text off until the selected audio is known. This also
        // prevents a file's default/forced track flashing before policy runs.
        // Wait for exact regional matching; ExoPlayer can treat pt-PT as a
        // partial match for pt-BR during its initial track selection.
        if (host.playerPreferences.getBoolean("subtitle_only_foreign_audio", false) ||
            host.playerPreferences.getBoolean("subtitle_forced_only", false) ||
            defaultSubtitleLang?.equals("pt-BR", ignoreCase = true) == true) {
            paramsBuilder?.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        }
        host.trackSelector?.parameters = paramsBuilder?.build()!!

        // Subtitle auto-sync's PCM tap rides the audio sink as a user
        // AudioProcessor: it sees every decoded sample the player plays, at
        // media rate (user processors sit before the speed processors), for
        // free. Created fresh per player build so a rebuild can't feed an old
        // tap. Passthrough audio bypasses processors entirely — the tap then
        // simply never fills and auto-sync declines instead of guessing.
        val tap = SpeechFeatureTap(
            mainPost = { action -> activity.runOnUiThread(action) },
            positionMs = { host.player?.currentPosition ?: 0L },
        ).also { host.speechTap = it }
        host.nativeAudioRouting.update(host.displayController.nightModeIndex > 0, host.displayController.systemAudioEffectsEnabled, host.displayController.playbackSpeeds[host.displayController.playbackSpeedIndex])
        val baseRenderersFactory = NativeAudioRenderersFactory(
            activity, host.nativeAudioRouting, arrayOf(tap.processor),
        )
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(iptvMediaCodecSelector())
        val renderersFactory = OffsetRenderersFactory(baseRenderersFactory)
            .also { host.offsetRenderersFactory = it }

        // Create HTTP data source factory with redirect support for HLS/live streams.
        // The browser UA rides in defaultRequestProperties, NOT setUserAgent:
        // media3 applies the userAgent field LAST in makeConnection, silently
        // clobbering any per-request User-Agent — which would break IPTV
        // channels that declare their own UA (injected via the resolver's
        // dataSpec headers, which override defaults in the merge).
        // Connection patience preset: longer connect/read timeouts for slow
        // origins (Plex-backed addons can take >15s to first byte while the
        // upstream server wakes). VOD only — IPTV's resilience ladder depends
        // on failing fast enough to retry, so it keeps the stock 15s.
        val networkTimeoutMs = if (!host.isIptvMode) when (host.networkPatience) {
            "extended" -> 30_000
            "patient" -> 60_000
            else -> 15_000
        } else 15_000
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(networkTimeoutMs)
            .setReadTimeoutMs(networkTimeoutMs)
            .setDefaultRequestProperties(
                mapOf(
                    "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
            )

        // Wrap with DefaultDataSource.Factory for local file/content URI support
        host.protectedStreamClient = ProtectedStreamHttp.client(networkTimeoutMs)
        val vodHttpFactory = VodHttpDataSource.Factory(
            httpDataSourceFactory,
            ProtectedStreamHttp.dataSourceFactory(host.protectedStreamClient),
        )
        val upstreamDataSourceFactory = DefaultDataSource.Factory(
            activity, if (host.isIptvMode) httpDataSourceFactory else vodHttpFactory,
        )
        val dataSourceFactory = run {
            ResolvingDataSource.Factory(
                upstreamDataSourceFactory,
                object : ResolvingDataSource.Resolver {
                    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                        val (protectedMediaOrigins, playbackHeaders) = host.activeVodHeaders
                        val origin = originKey(dataSpec.uri)
                        return if (origin != null && protectedMediaOrigins.contains(origin)) {
                            dataSpec.withAdditionalHeaders(playbackHeaders)
                        } else {
                            dataSpec
                        }
                    }

                    override fun resolveReportedUri(uri: Uri): Uri = uri
                }
            )
        }

        // IPTV: inject the CURRENT channel's declared headers into every
        // request (playlist + segments — CDNs enforce them on both). Read per
        // request so channel zaps just update [currentIptvHttpHeaders]; the
        // factory-level Chrome UA still applies when a channel names no UA.
        // (Channel UA keys are canonicalized to "User-Agent" at parse time,
        // so the dataSpec entry deterministically replaces the default.)
        val finalDataSourceFactory = if (host.isIptvMode) {
            ResolvingDataSource.Factory(
                dataSourceFactory,
                object : ResolvingDataSource.Resolver {
                    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                        val headers = host.currentIptvHttpHeaders
                        return if (headers.isEmpty()) dataSpec
                        else dataSpec.withAdditionalHeaders(headers)
                    }

                    override fun resolveReportedUri(uri: Uri): Uri = uri
                }
            )
        } else {
            dataSourceFactory
        }

        // IPTV: tee the played bytes to a recording file on demand. Inert unless
        // the user starts a recording (see IptvRecordingController); wraps the
        // fully-resolved factory so recorded bytes carry the channel's headers.
        val recordingDataSourceFactory = if (host.isIptvMode) {
            // A write error (disk full, row revoked) ends the recording on the
            // loader thread; without this the dock would keep saying "Stop".
            host.iptvRecordingController.onAborted = {
                host.iptvRecordingActionsController.updateRecordButtonState()
                Toast.makeText(
                    activity,
                    "Recording stopped — couldn't keep writing to storage",
                    Toast.LENGTH_LONG,
                ).show()
            }
            RecordingDataSource.Factory(finalDataSourceFactory, host.iptvRecordingController)
        } else {
            finalDataSourceFactory
        }

        // Create media source factory that uses the data source. IPTV gets
        // two live-stream aids on top:
        //  - TS extractor flags (Phase 3 of the resilience plan, marked
        //    experimental there): ALLOW_NON_IDR_KEYFRAMES lets a mid-GOP
        //    live join render before the next IDR arrives (broadcast streams
        //    can go seconds between them), DETECT_ACCESS_UNITS lets H.264
        //    parse when the container lies about access-unit boundaries.
        //    Both are what dedicated IPTV players run with.
        //  - the classified load-error policy (Phase 1): loader-level retries
        //    UNDER an intact buffer for transient errors, so the common
        //    connection drop heals without the player ever leaving READY.
        val mediaSourceFactory = if (host.isIptvMode) {
            val aggressiveTs = DefaultExtractorsFactory().setTsExtractorFlags(
                DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
                    DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
            )
            // The fallback the video-stall detector escalates to (see
            // performIptvLiveRetune): stock demux — IDR-only sync points —
            // for channels whose decoder wedges on mid-GOP joins. This is
            // the pre-0.8.1 behavior, and what the browse screen's preview
            // player runs with everywhere (which is why the same channel
            // plays fine in the two-pane stage on those boxes).
            val strictTs = DefaultExtractorsFactory()
            val iptvExtractors = object : ExtractorsFactory {
                override fun createExtractors(): Array<Extractor> =
                    (if (host.iptvStrictTsActive) strictTs else aggressiveTs)
                        .createExtractors()

                override fun createExtractors(
                    uri: Uri,
                    responseHeaders: Map<String, List<String>>,
                ): Array<Extractor> =
                    (if (host.iptvStrictTsActive) strictTs else aggressiveTs)
                        .createExtractors(uri, responseHeaders)
            }
            DefaultMediaSourceFactory(activity, iptvExtractors)
                .setDataSourceFactory(recordingDataSourceFactory)
                .setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy { host.iptvChannels.getOrNull(host.currentIptvIndex)?.isLive == true })
        } else {
            DefaultMediaSourceFactory(activity)
                .setDataSourceFactory(recordingDataSourceFactory)
        }

        val playerBuilder = ExoPlayer.Builder(activity, renderersFactory)
            .setTrackSelector(host.trackSelector!!)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)
            // Hold CPU + Wi-Fi while playing over the network: TV boxes with
            // aggressive Wi-Fi power-save can starve a live stream without
            // this (downloads and recordings already take their own locks —
            // playback was the only network consumer without one).
            .setWakeMode(C.WAKE_MODE_NETWORK)

        when (host.displayController.displayMatchMode) {
            TvContentDisplayMatchMode.OFF -> playerBuilder.setVideoChangeFrameRateStrategy(
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF,
            )
            TvContentDisplayMatchMode.FRAME_RATE,
            TvContentDisplayMatchMode.FRAME_RATE_AND_RESOLUTION,
            -> playerBuilder.setVideoChangeFrameRateStrategy(
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS,
            )
            TvContentDisplayMatchMode.SYSTEM -> Unit
        }

        // IPTV buffering: media3 1.8.0's stock DefaultLoadControl already
        // resumes 2s after a rebuffer (the plan's audit assumed the old 5s
        // default — codex review round 2 corrected it against the 1.8.0
        // constants). Stock is the right call: no override.

        // For YouTube (merged video-only + audio) ONLY, start after buffering
        // ~1s instead of ExoPlayer's conservative 2.5s default — otherwise the
        // two separate googlevideo streams take 20-30s to fill the buffer before
        // the first frame. All other content keeps ExoPlayer's defaults so this
        // can't regress torrent/IPTV/debrid playback.
        val isYouTubeMerge = host.payload?.items?.any {
            !it.hdVideoUrl.isNullOrEmpty() && !it.audioUrl.isNullOrEmpty()
        } == true
        if (isYouTubeMerge) {
            playerBuilder.setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        15_000, // minBufferMs (default 50000)
                        50_000, // maxBufferMs (default 50000)
                        1_000,  // bufferForPlaybackMs (default 2500)
                        2_000,  // bufferForPlaybackAfterRebufferMs (default 5000)
                    )
                    .setPrioritizeTimeOverSizeThresholds(true)
                    .build()
            )
        } else if (!host.isIptvMode && host.networkBuffer != "standard") {
            // Stream buffer preset: wider read-ahead rides over origin
            // stalls. Start thresholds stay stock (only min/max grow), so
            // start latency is unchanged; the byte target is the real memory
            // guard (mirrors the mpv side's demuxer-max-bytes) — loading
            // stops at whichever target hits first, exactly like stock.
            val hugeBuffer = host.networkBuffer == "huge"
            // Unlike mpv's native-memory demuxer cache, this target is JAVA
            // heap (DefaultAllocator's byte[] segments) shared with the
            // Flutter engine, image caches, and every profile/guide
            // structure in this process. The original clamp — HALF the
            // large-heap class — was a ceiling, not headroom: on a 256
            // MiB-class TV box a high-bitrate stream drove the allocator to
            // 128 MiB of live byte[] and the loader thread died with
            // OutOfMemoryError, an Error no player plumbing catches →
            // process death straight to the launcher, on exactly the
            // hardware this preset serves (Mecool KM2+ field report,
            // 2026-08-18: one high-bitrate episode "crashes the app", every
            // source). Budget a QUARTER of the heap instead, cap the
            // requests well below the old 256/512 MiB, and when even the
            // quarter is too small to be worth overriding, keep stock —
            // stock's own byte targets are what the device already
            // survives. Long math throughout: largeMemoryClass is an Int MB
            // count, and `mb / 2 * 1024 * 1024` overflows Int from a 4
            // GiB heap class up.
            val activityManager =
                activity.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val heapBudgetBytes =
                activityManager.largeMemoryClass.toLong() * 1024L * 1024L / 4L
            val requestedBytes = (if (hugeBuffer) 192L else 96L) * 1024L * 1024L
            val targetBytes = minOf(requestedBytes, heapBudgetBytes)
            if (targetBytes >= 48L * 1024L * 1024L) {
                playerBuilder.setLoadControl(
                    DefaultLoadControl.Builder()
                        .setBufferDurationsMs(
                            if (hugeBuffer) 300_000 else 120_000, // minBufferMs
                            if (hugeBuffer) 300_000 else 120_000, // maxBufferMs
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
                        )
                        .setTargetBufferBytes(targetBytes.toInt())
                        .build()
                )
            }
        }

        host.player = playerBuilder.build()
        host.player?.setPlaybackSpeed(host.displayController.playbackSpeeds[host.displayController.playbackSpeedIndex])

        host.player?.addListener(host.playbackListener)
        host.player?.addAnalyticsListener(host.displayController.decoderAnalyticsListener)
        host.player?.addAnalyticsListener(iptvDiagAnalyticsListener)
        host.playerView.player = host.player

        // Hide internal subtitle view, use custom one
        host.playerView.subtitleView?.visibility = View.GONE

        // Connect subtitle output to custom view
        host.subtitleListener = object : Player.Listener {
            override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) {
                // While an external subtitle is side-rendered, the overlay is
                // owned by the ticker — ignore the player's (empty) cue events.
                if (host.subtitleController.externalSubtitleActive) return
                host.subtitleOverlay.setCues(cueGroup.cues)
            }
        }
        host.player?.addListener(host.subtitleListener!!)

        // Setup subtitle styling from saved preferences
        host.subtitleOverlay.setApplyEmbeddedStyles(false)
        host.subtitleOverlay.setApplyEmbeddedFontSizes(false)
        SubtitleSettings.synchronizeProjectedAppearance(activity)
        SubtitleFontManager.synchronizeProjectedFont(activity)
        // The sync offset is per-subtitle and in-memory: start this session at 0
        // and let SubtitleSettings scope it to whatever subtitle is on screen.
        SubtitleSettings.resetSyncOffset()
        SubtitleSettings.setActiveSubtitleIdentityProvider(activity) { host.subtitleController.currentSubtitleIdentity() }
        host.subtitleController.applySubtitleSettings()

        host.playerView.setControllerAutoShow(false)
        host.displayController.applyResizeMode()
        host.playerView.requestFocus()

        if (host.isIptvMode) {
            // Phase 3: hold the last frame across a zap's player reset — the
            // zap banner rides over the old channel's picture instead of a
            // black flash. Cleared on surrender (a dead channel must not
            // keep painting under the failure pill) and re-armed on READY.
            host.playerView.setKeepContentOnPlayerReset(true)

            // Phase 1: connectivity gate for the recovery ladder. While the
            // OS reports no network there is nothing to hammer; the moment a
            // network validates, the parked attempt fires immediately.
            // API 24+ only (registerDefaultNetworkCallback); older boxes
            // just keep the plain timed ladder.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        activity.runOnUiThread { host.iptvTuneController.iptvLiveRecovery.setOffline(false) }
                    }

                    override fun onLost(network: Network) {
                        activity.runOnUiThread { host.iptvTuneController.iptvLiveRecovery.setOffline(true) }
                    }
                }
                try {
                    cm.registerDefaultNetworkCallback(callback)
                    host.iptvNetworkCallback = callback
                    // Cold-start truth: registration alone reports nothing
                    // until the network CHANGES — launched offline, the
                    // ladder must know now, not at the first handover.
                    host.iptvTuneController.iptvLiveRecovery.setOffline(cm.activeNetwork == null)
                } catch (e: Exception) {
                    // Some ROMs throw on registration limits; the ladder
                    // works without the gate, just less politely offline.
                    android.util.Log.w("AndroidTvPlayer", "network callback: $e")
                }
            }
        }
    }
}
