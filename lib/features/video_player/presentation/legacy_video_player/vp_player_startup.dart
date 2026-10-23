import 'dart:async';
import 'dart:io';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlayerStartupHost {
  Map<String, String>? get activeHttpHeaders;
  set activeHttpHeaders(Map<String, String>? v);
  List<PlaylistEntry>? get activePlaylist;
  AndroidVideoRendererMode get androidVideoRendererMode;
  set androidVideoRendererMode(AndroidVideoRendererMode v);
  set autosaveTimer(Timer? v);
  int get currentIndex;
  set currentIndex(int v);
  int get currentSourceIndex;
  set currentStreamUrl(String? v);
  Duration get duration;
  set dynamicTitle(String v);
  String? get effectiveContentType;
  List<IptvChannel>? get effectiveIptvChannels;
  List<Torrent>? get effectiveSources;
  List<Map<String, dynamic>>? get effectiveStremioTvChannels;
  bool get engineFlagOn;
  set engineFlagOn(bool v);
  Future<void>? get episodeMetadataReady;
  set episodeMetadataReady(Future<void>? v);
  IptvTuneDiagnostics get iptvDiag;
  IptvLiveRecovery get iptvLiveRecovery;
  mk.Player get player;
  int get playerInstanceGeneration;
  set recordingSupported(bool v);
  int get resumeVerifyEpoch;
  bool get screenDisposed;
  SeriesPlaylist? get seriesPlaylist;
  DeferredStartupSeek get stremioTvStartupSeek;
  ChannelStartupWatch? get stremioTvStartupWatch;
  Future<void> loadDockPrefs();
  Duration? randomStartOffset(Duration duration);
  Duration? percentStartOffset(Duration duration);
  void scheduleAutoHide();
  Future<void> loadPlayerDefaults();
  void createPlayerInstance(AndroidVideoRendererMode rendererMode);
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  bool get mounted;
  void setState(VoidCallback fn);
  String? get audioUrl;
  int? get contentEpisode;
  int? get contentSeason;
  bool get disableAutoResume;
  Map<String, String>? get httpHeaders;
  int? get iptvStartIndex;
  Future<Map<String, String>?> Function()? get requestMagicNext;
  double? get startAtPercent;
  bool get startFromRandom;
  int? get startIndex;
  String get title;
  String get videoUrl;
  bool get isAndroid;
  Future<void> attachAudioEffectSession();
  Future<void> configurePlayerAudio(mk.Player player);
  Future<void> setExternalAudioTrack(String audioUrl);
  List<int> getMainGroupIndices(List<PlaylistEntry> entries);
  Future<void> waitForVideoReady();
  Future<void> preloadEpisodeInfo();
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  });
  Future<String> resolvePlaylistEntryUrl(int index);
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  });
  Future<void> refreshEngineRecordingState();
  String resumeIdForEntry(PlaylistEntry entry);
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  });
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false});
  Future<void> saveResume({bool debounced = false, Duration? positionOverride});
  Future<void> commitValidatedStremioSource(Torrent? source);
  Future<bool> openInitialVodWithFailover(
    String initialUrl, {
    Map<String, String>? httpHeaders,
    bool initialAttemptAlreadyFailed = false,
  });
  Future<void> reportStartupFailure({bool Function()? isCurrent});
  void resumeTrackingAfterValidationGate();
  void setStartupGateActive(bool active);
  void watchStremioTvStartup(String url);
  void installSubtitleAutoSyncForPlayer(mk.Player player);
  Future<void> restoreTrackPreferences();
  Future<void> claimVideoOutput();
}

class VpPlayerStartup {
  VpPlayerStartup(this._host);
  final VpPlayerStartupHost _host;

  Future<void> initializePlayer() async {
    // Load default player settings
    await _host.loadPlayerDefaults();
    unawaited(_host.loadDockPrefs());
    if (_host.isAndroid && !PlatformUtil.isAndroidTvCached) {
      _host.androidVideoRendererMode =
          await PlayerSettingsStorage.getAndroidVideoRendererMode();
    }

    // Determine the initial URL and index
    String initialUrl = _host.videoUrl;
    var initialRankedAttemptFailed = false;
    int initialIndex = 0;

    if (_host.activePlaylist != null && _host.activePlaylist!.isNotEmpty) {
      // Initialize playlist

      // If auto-resume is disabled, use startIndex directly
      if (_host.disableAutoResume) {
        initialIndex = _host.startIndex ?? 0;
        debugPrint(
          'VideoPlayer: auto-resume disabled, using startIndex=$initialIndex',
        );
      } else {
        // Check if this is a series and we should find the first episode by season/episode
        final seriesPlaylist = _host.seriesPlaylist;
        if (seriesPlaylist != null && seriesPlaylist.isSeries) {
          // If a specific target episode was requested (e.g. quick play from Trakt),
          // jump directly to it instead of resuming from last played.
          bool targetEpisodeResolved = false;
          final hadExplicitTarget =
              _host.contentSeason != null && _host.contentEpisode != null;
          if (hadExplicitTarget) {
            final targetIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
              _host.contentSeason!,
              _host.contentEpisode!,
            );
            if (targetIndex != -1) {
              initialIndex = targetIndex;
              targetEpisodeResolved = true;
              debugPrint(
                'VideoPlayer: target episode S${_host.contentSeason}E${_host.contentEpisode} → index=$initialIndex',
              );
            }
          }

          if (!targetEpisodeResolved) {
            // Only resume from the last-played episode when NO specific episode
            // was requested. If a target WAS requested but isn't in this pack
            // (e.g. "Next" with no bound source landed on a source that lacks
            // that episode), resuming would replay the last-played — usually the
            // episode the user just finished — which is the "Next replays the
            // same episode" bug. In that case skip straight to the first episode.
            final lastEpisode = hadExplicitTarget
                ? null
                : await getLastPlayedEpisode(seriesPlaylist);
            if (lastEpisode != null) {
              debugPrint(
                'VideoPlayer: resume series "${seriesPlaylist.seriesTitle}" at S${lastEpisode['season']}E${lastEpisode['episode']} originalIndex=${lastEpisode['originalIndex']}',
              );
              initialIndex = lastEpisode['originalIndex'] as int;
            } else {
              // Find the first episode (lowest season, lowest episode)
              final firstEpisodeIndex = seriesPlaylist
                  .getFirstEpisodeOriginalIndex();
              if (firstEpisodeIndex != -1) {
                initialIndex = firstEpisodeIndex;
              } else {
                initialIndex = _host.startIndex ?? 0;
              }
              debugPrint(
                'VideoPlayer: no resume target for "${seriesPlaylist.seriesTitle}"'
                '${hadExplicitTarget ? ' (requested S${_host.contentSeason}E${_host.contentEpisode} not in pack)' : ''}, defaulting to index=$initialIndex',
              );
            }
          }
        } else {
          // For non-series playlists, try to restore the last played video
          if (_host.activePlaylist != null &&
              _host.activePlaylist!.isNotEmpty) {
            // Try to find the last played video by checking each playlist entry
            int lastPlayedIndex = -1;
            Map<String, dynamic>? lastPlayedState;

            for (int i = 0; i < _host.activePlaylist!.length; i++) {
              final entry = _host.activePlaylist![i];
              final resumeId = _host.resumeIdForEntry(entry);
              debugPrint(
                'Resume: checking entry[$i] title="${entry.title}" resumeId=$resumeId',
              );
              final state = await VideoProgressStorage.getVideoPlaybackState(
                videoTitle: resumeId,
              );
              if (state != null) {
                debugPrint(
                  'Resume: found state for entry[$i] resumeId=$resumeId updatedAt=${state['updatedAt']}',
                );
                final updatedAt = state['updatedAt'] as int? ?? 0;
                if (lastPlayedState == null ||
                    updatedAt > (lastPlayedState['updatedAt'] as int? ?? 0)) {
                  lastPlayedState = state;
                  lastPlayedIndex = i;
                }
              }
            }

            if (lastPlayedIndex != -1) {
              debugPrint('Resume: restoring playlist index $lastPlayedIndex');
              initialIndex = lastPlayedIndex;
            } else {
              debugPrint(
                'Resume: no prior playback state found, using default ordering',
              );
              // Pick the first item from Main group (by year asc then size desc)
              final indices = _host.getMainGroupIndices(_host.activePlaylist!);
              initialIndex = indices.isNotEmpty
                  ? indices.first
                  : (_host.startIndex ?? 0);
            }
          } else {
            // Not a series or no series playlist, use the provided startIndex
            initialIndex = _host.startIndex ?? 0;
          }
        }
      }
    } else {}

    // A stale launch index (resume record from a longer pack, negative
    // startIndex) must not reach list indexing: _currentIndex is used
    // unconditionally below and in later playback paths.
    if (_host.activePlaylist != null && _host.activePlaylist!.isNotEmpty) {
      initialIndex = initialIndex.clamp(0, _host.activePlaylist!.length - 1);
    }

    // Get the initial URL from the determined index
    if (_host.activePlaylist != null &&
        _host.activePlaylist!.isNotEmpty &&
        initialIndex < _host.activePlaylist!.length) {
      final entry = _host.activePlaylist![initialIndex];
      if (entry.url.isNotEmpty) {
        initialUrl = entry.url;
      } else {
        try {
          final resolvedUrl = await _host.resolvePlaylistEntryUrl(initialIndex);
          if (resolvedUrl.isNotEmpty) {
            initialUrl = resolvedUrl;
          } else if (_host.videoUrl.isNotEmpty) {
            initialUrl = _host.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        } catch (e) {
          // Only fall back to widget.videoUrl if resolution fails
          if (_host.videoUrl.isNotEmpty) {
            initialUrl = _host.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        }
      }
    }

    _host.currentIndex = initialIndex;
    _host.dynamicTitle = _host.title;
    await _host.claimVideoOutput();
    if (!_host.mounted) return;
    _host.createPlayerInstance(_host.androidVideoRendererMode);
    await _host.configurePlayerAudio(_host.player);
    _host.installSubtitleAutoSyncForPlayer(_host.player);
    // libmpv exposes `stream-record`; the web backend does not. Gate the
    // record control on having a native player — and, on Android, on the
    // finished file being publishable at all. Below API 29 there is no
    // MediaStore.Downloads and no WRITE_EXTERNAL_STORAGE, so a recording
    // could only sit in app-private storage the user can't reach — offering
    // the button would just be a way to lose footage.
    //
    // Deny-by-default: Android starts unsupported and flips true only on a
    // positive probe. The opposite order would leave a rebuild window where
    // an API 21–28 device shows Record, and a tap in that window starts a
    // recording whose Stop button the probe then hides.
    final nativeBackend = _host.player.platform is mk.NativePlayer;
    // A profile without the recordings feature never sees Record — the
    // platform probe below must not be able to flip it back on.
    final recordingsAllowed = ProfilePolicyGuard.allowsSync(
      ProfileFeature.recordings,
    );
    _host.recordingSupported =
        recordingsAllowed && nativeBackend && !Platform.isAndroid;
    if (recordingsAllowed && nativeBackend && Platform.isAndroid) {
      unawaited(
        AndroidNativeDownloader.canPublishRecordings().then((canPublish) {
          if (!canPublish || !_host.mounted) return;
          _host.setState(() => _host.recordingSupported = true);
        }),
      );
      // Engine flag + any capture of this channel already running (a recording
      // started in an earlier player session survives into this one).
      unawaited(
        LiveRecordingService.engineEnabled().then((on) {
          if (!_host.mounted) return;
          _host.engineFlagOn = on || ProfileRuntime.isProfileCommitted;
          if (_host.engineFlagOn)
            unawaited(_host.refreshEngineRecordingState());
        }),
      );
    }

    // Must happen before the first open() — mpv reads both audio options when
    // it creates the audio output, which is on first playback.
    await _host.attachAudioEffectSession();

    _host.currentStreamUrl = initialUrl.isNotEmpty ? initialUrl : null;
    if (_host.activePlaylist != null &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      _host.activeHttpHeaders =
          _host.activePlaylist![_host.currentIndex].httpHeaders ??
          _host.httpHeaders;
    }

    // IPTV launch: the first tune starts here, before either open branch
    // below (IPTV is never PikPak). Zaps re-arm this in _switchToIptvChannel.
    var launchIsLiveIptv = false;
    final launchIptvChannels = _host.effectiveIptvChannels;
    if (launchIptvChannels != null && initialUrl.isNotEmpty) {
      final launchIdx = _host.iptvStartIndex ?? 0;
      final launchChannel =
          (launchIdx >= 0 && launchIdx < launchIptvChannels.length)
          ? launchIptvChannels[launchIdx]
          : null;
      _host.iptvDiag.onTuneStart(
        launchChannel?.name,
        initialUrl,
        isLive: launchChannel?.isLive ?? true,
      );
      _host.iptvLiveRecovery.onTuneStarted();
      launchIsLiveIptv = launchChannel?.isLive ?? true;
    }

    final canAttemptRankedStartup =
        initialRankedAttemptFailed &&
        (_host.effectiveContentType == 'movie' ||
            _host.effectiveContentType == 'series') &&
        _host.effectiveSources?.isNotEmpty == true;

    // An empty initial URL caused by a failed lazy resolution is itself the
    // first failed candidate. Enter the ranked ladder so remaining sources
    // still get their configured attempts.
    if (initialUrl.isNotEmpty || canAttemptRankedStartup) {
      // For PikPak videos from playlist or any PikPak URL, use cold storage retry logic
      final currentEntry = _host.activePlaylist?[_host.currentIndex];
      final isPikPak =
          currentEntry?.provider?.toLowerCase() == 'pikpak' ||
          currentEntry?.pikpakFileId != null;
      // For non-playlist flows (Debrify TV, Stremio TV, etc.), detect PikPak by URL
      final isPikPakUrl =
          _host.activePlaylist == null && initialUrl.contains('mypikpak.com');
      final isDebrifyTV = isPikPakUrl && _host.requestMagicNext != null;

      if (initialUrl.isNotEmpty &&
          ((isPikPak && _host.activePlaylist != null) || isPikPakUrl)) {
        // The continuation can sleep up to 10s in _waitForVideoReady; the
        // screen may be left (player disposed) or the player replaced by a
        // renderer fallback in that window, so it must re-check before every
        // touch of _player.
        final pikpakGeneration = _host.playerInstanceGeneration;
        bool pikpakStillCurrent() =>
            _host.mounted &&
            !_host.screenDisposed &&
            pikpakGeneration == _host.playerInstanceGeneration;
        final launchSource =
            _host.effectiveSources != null &&
                _host.currentSourceIndex >= 0 &&
                _host.currentSourceIndex < _host.effectiveSources!.length
            ? _host.effectiveSources![_host.currentSourceIndex]
            : null;
        _host.playPikPakVideoWithRetry(initialUrl, isDebrifyTV: isDebrifyTV).then(
          (loaded) async {
            if (!pikpakStillCurrent()) return;
            if (!loaded) return;
            // PikPak uses its own cold-storage readiness gate instead of the
            // ranked VOD gate. Report the winner only after that gate confirms
            // duration, otherwise a queued-but-unplayable file would be pinned.
            unawaited(_host.commitValidatedStremioSource(launchSource));
            // Wait for the video to load and duration to be available
            await _host.waitForVideoReady();
            if (!pikpakStillCurrent()) return;
            // Random start takes precedence over resume, then startAtPercent.
            // Same initial-open shape as the ranked branch below — and PikPak
            // cold-storage streams are the slowest remote opens in the app, the
            // likeliest to answer the startup seek with a restart at 0 — so the
            // same guarded, landing-verified seeks apply.
            if (_host.startFromRandom) {
              final offset = _host.randomStartOffset(_host.duration);
              if (offset != null) {
                // A random start has no bookmark to protect — plain seek.
                await _host.player.seek(offset);
              } else {
                await _host.maybeRestoreResume(verifyLanding: true);
              }
            } else if (_host.startAtPercent != null) {
              final offset = _host.percentStartOffset(_host.duration);
              if (offset != null) {
                await _host.seekForResume(
                  offset.inMilliseconds,
                  verifyLanding: true,
                );
              }
            } else {
              await _host.maybeRestoreResume(verifyLanding: true);
            }
            if (!pikpakStillCurrent()) return;
            // Restore audio and subtitle track preferences
            await _host.restoreTrackPreferences();
          },
        );
      } else {
        // High-res YouTube serves video and audio as separate streams. Open
        // PAUSED, attach the external audio track, then start — so both tracks
        // are loaded before the first frame and play in sync from the start.
        // (Attaching audio mid-playback makes mpv resync, causing a few seconds
        // of A/V drift.)
        final hasExternalAudio =
            _host.audioUrl != null && _host.audioUrl!.isNotEmpty;
        final isStremioTv =
            _host.effectiveStremioTvChannels?.isNotEmpty == true;
        final deferStremioTvStart =
            isStremioTv && initialUrl.isNotEmpty && !_host.startFromRandom;
        var directOpenCompleted = false;
        int? directOpenEpoch;
        try {
          final opened = await StartupStreamPolicy.openInitialMedia(
            hasResolvedUrl: initialUrl.isNotEmpty,
            hasExternalAudio: hasExternalAudio,
            isLiveIptv: launchIsLiveIptv,
            // Stremio TV owns channel selection and slot changes. As on native
            // TV, a slow channel must not hit the VOD gate's one-attempt limit.
            isStremioTv: isStremioTv,
            openDirect: () async {
              final opening = _host.openMedia(
                mk.Media(initialUrl, httpHeaders: _host.activeHttpHeaders),
                play: !hasExternalAudio,
                desiredPlay: true,
                liveStream: launchIsLiveIptv,
                // Subscribe before open: media-kit reports failures later.
                beforeOpen: isStremioTv
                    ? () {
                        _host.watchStremioTvStartup(initialUrl);
                        if (deferStremioTvStart) {
                          _host.stremioTvStartupSeek.arm(
                            _host.startAtPercent,
                            epoch: _host.resumeVerifyEpoch,
                          );
                        }
                        return true;
                      }
                    : null,
              );
              directOpenEpoch = _host.resumeVerifyEpoch;
              await opening;
              directOpenCompleted = true;
            },
            openValidated: () => _host.openInitialVodWithFailover(
              initialUrl,
              httpHeaders: _host.activeHttpHeaders,
              initialAttemptAlreadyFailed: initialRankedAttemptFailed,
            ),
          );
          if (!opened) {
            await _host.reportStartupFailure();
            return;
          }
          // Wait for duration-dependent resume and random-start calculations.
          await _host.waitForVideoReady();
          if (!_host.mounted ||
              _host.screenDisposed ||
              (isStremioTv && _host.stremioTvStartupWatch?.hasFailed == true)) {
            return;
          }
          if (hasExternalAudio) {
            await _host.setExternalAudioTrack(_host.audioUrl!);
          }
          // Random start takes precedence over resume, then startAtPercent.
          if (_host.startFromRandom) {
            final offset = _host.randomStartOffset(_host.duration);
            if (offset != null) {
              // A random start has no bookmark to protect and no "correct"
              // position to verify against — plain seek, as before.
              await _host.player.seek(offset);
            } else {
              await _host.maybeRestoreResume(verifyLanding: true);
            }
          } else if (_host.startAtPercent != null) {
            final offset = deferStremioTvStart
                ? null
                : _host.percentStartOffset(_host.duration);
            if (offset != null) {
              // An explicit promised start position, exposed to the same
              // startup seek failure as a stored resume.
              await _host.seekForResume(
                offset.inMilliseconds,
                verifyLanding: true,
              );
            }
          } else {
            await _host.maybeRestoreResume(verifyLanding: true);
          }
          _host.scheduleAutoHide();
          await _host.restoreTrackPreferences();
          if (hasExternalAudio) await _host.player.play();
          // The candidate is now decoded, resume has been applied, and track
          // restoration is complete. Only now may progress escape to local
          // completion or remote scrobblers.
          _host.setStartupGateActive(false);
          _host.resumeTrackingAfterValidationGate();
        } catch (e) {
          if (isStremioTv &&
              !directOpenCompleted &&
              directOpenEpoch == _host.resumeVerifyEpoch) {
            final watch = _host.stremioTvStartupWatch;
            if (watch != null) {
              watch.fail();
            } else {
              await _host.reportStartupFailure(
                isCurrent: () => directOpenEpoch == _host.resumeVerifyEpoch,
              );
            }
          }
          _host.setStartupGateActive(false);
          // A late throw (seek/track restore) can land after a successful
          // open — playback proceeds, so re-arm tracking or the start
          // scrobble stays swallowed until the next play/pause transition.
          _host.resumeTrackingAfterValidationGate();
          debugPrint('VideoPlayer: initial open failed: $e');
        }
      }
    } else {
      // If no valid URL, try to load the first playlist entry
      if (_host.activePlaylist != null && _host.activePlaylist!.isNotEmpty) {
        _host.loadPlaylistIndex(_host.currentIndex, autoplay: false);
      }
    }
    _host.autosaveTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _host.saveResume(debounced: true),
    );

    // Preload episode information if this is a series
    _host.episodeMetadataReady ??= _host.preloadEpisodeInfo();
  }

  /// Get the last played episode for a series
  Future<Map<String, dynamic>?> getLastPlayedEpisode(
    SeriesPlaylist seriesPlaylist,
  ) async {
    try {
      final lastEpisode = await EpisodeResumeStorage.getLastPlayedEpisode(
        seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
      );

      if (lastEpisode != null) {
        final season = lastEpisode['season'] as int;
        final episode = lastEpisode['episode'] as int;
        debugPrint(
          'VideoPlayer: StorageService returned resume S${season}E$episode for "${seriesPlaylist.seriesTitle}"',
        );

        // Find the original index for this episode
        final originalIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
          season,
          episode,
        );
        if (originalIndex != -1) {
          return {...lastEpisode, 'originalIndex': originalIndex};
        }
        debugPrint(
          'VideoPlayer: resume entry S${season}E$episode not found in playlist for "${seriesPlaylist.seriesTitle}"',
        );
      }
    } catch (e) {
      debugPrint('VideoPlayer: failed to read last episode resume: $e');
    }
    return null;
  }
}
