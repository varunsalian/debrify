import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:flutter/foundation.dart';

abstract interface class VpStartupFailoverHost {
  set activeHttpHeaders(Map<String, String>? v);
  set activePlaylist(List<PlaylistEntry>? v);
  set cachedSeriesPlaylist(SeriesPlaylist? v);
  set currentIndex(int v);
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  set currentStreamUrl(String? v);
  int? get effectiveContentEpisode;
  int? get effectiveContentSeason;
  String? get effectiveContentType;
  Future<String?> Function(Torrent)? get effectiveResolver;
  List<Torrent>? get effectiveSources;
  int get playlistIdentityToken;
  set playlistIdentityToken(int v);
  bool get screenDisposed;
  bool get startupGateOverlayHidden;
  set startupGateOverlayHidden(bool v);
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  });
  Future<bool> openStartupDebridDirect(
    String url, {
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
    Duration timeout = const Duration(seconds: 12),
  });
  String startupSourceFields(int? index, Torrent? source);
  Future<void> commitValidatedStremioSource(Torrent? source);
  void setStartupGateActive(bool active);
  void setStartupGateMessage(String message);
  void setState(VoidCallback fn);
  bool get mounted;
  bool get startupFailoverEnabled;
  String? get startupResolverProvider;
  SourcePlaylistResolve? get resolveSourceToPlaylist;
  String get title;
}

class VpStartupFailover {
  VpStartupFailover(this._host);
  final VpStartupFailoverHost _host;

  /// Startup-only automatic failover for Stremio/Quick Play VOD. Candidates
  /// remain behind the player loading surface until the actual player decodes
  /// one. The successful URL is never reopened, which is essential for
  /// single-use and first-request-IP-bound debrid links.
  Future<bool> openInitialVodWithFailover(
    String initialUrl, {
    Map<String, String>? httpHeaders,
    bool initialAttemptAlreadyFailed = false,
  }) async {
    final sources = _host.effectiveSources;
    final contentType = _host.effectiveContentType;
    final isVod = contentType == 'movie' || contentType == 'series';
    if (!isVod) {
      debugPrint(
        '[StartupFailover] event=bypass platform=flutter reason=non_vod '
        'contentType=${contentType ?? 'unknown'}',
      );
      return _host.tryOpenStartupVod(initialUrl, httpHeaders: httpHeaders);
    }

    _host.setStartupGateActive(true);
    if (sources == null || sources.isEmpty) {
      debugPrint(
        '[StartupFailover] event=begin platform=flutter contentType=$contentType '
        'sourceCount=0 policy=single_candidate',
      );
      final ok = await _host.tryOpenStartupVod(
        initialUrl,
        httpHeaders: httpHeaders,
      );
      // A successful candidate stays gated through resume/track restoration
      // in the caller. Failure must release the surface before route cleanup.
      if (!ok) _host.setStartupGateActive(false);
      return ok;
    }

    final rules = _host.startupFailoverEnabled
        ? await QuickPlayStorage.getQuickPlayRules(
            isMovie: contentType == 'movie',
          )
        : null;
    final tryNext = rules?.tryNextOnFailure ?? false;
    final maxAttempts = tryNext ? rules!.maxAttempts.clamp(1, 10) : 1;
    final firstIndex = _host.currentSourceIndex.clamp(0, sources.length - 1);
    final start = StartupStreamPolicy.rankedFailoverStart(
      selectedSourceIndex: firstIndex,
      initialAttemptAlreadyFailed: initialAttemptAlreadyFailed,
    );
    var attempts = start.attempts;
    debugPrint(
      '[StartupFailover] event=begin platform=flutter contentType=$contentType '
      'sourceCount=${sources.length} selectedIndex=$firstIndex '
      'startIndex=${start.sourceIndex} initialFailed=$initialAttemptAlreadyFailed '
      'tryNext=$tryNext maxAttempts=$maxAttempts '
      'targetSeason=${_host.effectiveContentSeason ?? '-'} '
      'targetEpisode=${_host.effectiveContentEpisode ?? '-'}',
    );

    final pikPakResolver =
        _host.startupResolverProvider?.toLowerCase() == 'pikpak';
    var pikPakTorrentAcquisitionAttempted =
        StartupStreamPolicy.initialPikPakAcquisitionAttempted(
          isPikPakResolver: pikPakResolver,
          initialSourceIsTorrent:
              sources[firstIndex].streamType == StreamType.torrent,
          hasResolvedInitialUrl: initialUrl.isNotEmpty,
          initialAttemptAlreadyFailed: initialAttemptAlreadyFailed,
        );

    for (
      var sourceIndex = start.sourceIndex;
      sourceIndex < sources.length && attempts < maxAttempts;
      sourceIndex++
    ) {
      final source = sources[sourceIndex];
      // The launch URL is already resolved and playable in-app regardless of
      // how its source row is typed — never skip it over streamType.
      final isResolvedLaunchUrl =
          sourceIndex == firstIndex && initialUrl.isNotEmpty;
      if (!isResolvedLaunchUrl && source.streamType == StreamType.externalUrl) {
        debugPrint(
          '[StartupFailover] event=candidate_skip platform=flutter '
          '${_host.startupSourceFields(sourceIndex, source)} reason=external_url',
        );
        continue;
      }
      if (pikPakResolver &&
          !isResolvedLaunchUrl &&
          source.streamType == StreamType.torrent) {
        if (pikPakTorrentAcquisitionAttempted) {
          debugPrint(
            '[StartupFailover] event=candidate_skip platform=flutter '
            '${_host.startupSourceFields(sourceIndex, source)} '
            'reason=pikpak_acquisition_limit',
          );
          continue;
        }
        // Count the acquisition before resolving: a cold-storage request may
        // have been queued even when the resolver ultimately returns null.
        pikPakTorrentAcquisitionAttempted = true;
      }
      attempts++;
      final sourceFields = _host.startupSourceFields(sourceIndex, source);
      // A debrid-direct first open isn't "checking" anything — it's loading
      // the user's own source; say so. Failover retries keep the counter
      // (the ladder really is trying alternatives at that point).
      final firstAttempt = attempts == 1 && !initialAttemptAlreadyFailed;
      final debridFirstOpen =
          firstAttempt &&
          !pikPakResolver &&
          source.streamType == StreamType.torrent;
      if (_host.startupGateOverlayHidden != debridFirstOpen) {
        _host.startupGateOverlayHidden = debridFirstOpen;
        if (_host.mounted) _host.setState(() {});
      }
      _host.setStartupGateMessage(
        debridFirstOpen
            ? 'Loading stream…'
            : firstAttempt
            ? 'Checking stream 1 of $maxAttempts…'
            : 'Stream unavailable · Trying $attempts of $maxAttempts…',
      );

      String? url;
      List<PlaylistEntry>? resolvedPlaylist;
      var resolvedPlaylistIndex = 0;
      if (isResolvedLaunchUrl) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=launch_url',
        );
        url = initialUrl;
      } else if (source.streamType == StreamType.directUrl &&
          source.directUrl?.isNotEmpty == true) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=direct_url',
        );
        url = source.directUrl;
      } else if (_host.resolveSourceToPlaylist != null) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=playlist',
        );
        try {
          resolvedPlaylist = await _host.resolveSourceToPlaylist!(
            source,
            canContinue: () => _host.mounted && !_host.screenDisposed,
          );
        } catch (e) {
          debugPrint(
            '[StartupFailover] event=resolve_result platform=flutter '
            '$sourceFields ok=false reason=exception exception=${e.runtimeType}',
          );
          resolvedPlaylist = null;
        }
        if (resolvedPlaylist != null && resolvedPlaylist.isNotEmpty) {
          if (StartupStreamPolicy.requiresExactEpisodeMatch(
                isSeries: contentType == 'series',
                playlistLength: resolvedPlaylist.length,
              ) &&
              _host.effectiveContentSeason != null &&
              _host.effectiveContentEpisode != null) {
            final parsed = SeriesPlaylist.fromPlaylistEntries(
              resolvedPlaylist,
              collectionTitle: _host.title,
              forceSeries: true,
            );
            final target = parsed.findOriginalIndexBySeasonEpisode(
              _host.effectiveContentSeason!,
              _host.effectiveContentEpisode!,
            );
            final exactIndex = StartupStreamPolicy.resolvedPlaylistIndex(
              requiresEpisodeMatch: true,
              matchedEpisodeIndex: target,
            );
            if (exactIndex == null) {
              // A pack that omits the requested episode is not a valid
              // fallback. Opening row zero would silently play the wrong
              // episode and then adopt that unrelated playlist.
              resolvedPlaylist = null;
              debugPrint(
                '[StartupFailover] event=candidate_reject platform=flutter '
                '$sourceFields reason=playlist_missing_episode '
                'targetSeason=${_host.effectiveContentSeason} '
                'targetEpisode=${_host.effectiveContentEpisode}',
              );
              continue;
            }
            resolvedPlaylistIndex = exactIndex;
          }
          url = resolvedPlaylist[resolvedPlaylistIndex].url;
        }
      } else if (_host.effectiveResolver != null) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=single_url',
        );
        try {
          url = await _host.effectiveResolver!(source);
        } catch (e) {
          debugPrint(
            '[StartupFailover] event=resolve_result platform=flutter '
            '$sourceFields ok=false reason=exception exception=${e.runtimeType}',
          );
          url = null;
        }
      }

      if (url == null || url.isEmpty) {
        debugPrint(
          '[StartupFailover] event=candidate_reject platform=flutter '
          '$sourceFields reason=empty_resolution',
        );
        continue;
      }
      // Debrid-resolved torrents bypass the decode probe (see
      // _openStartupDebridDirect); addon direct URLs keep it, and so do
      // PikPak sessions — cold-storage opens are the slowest in the app and
      // have their own readiness needs.
      final isDebridResolved =
          !pikPakResolver && source.streamType == StreamType.torrent;
      final candidateHeaders = isResolvedLaunchUrl
          ? httpHeaders
          : resolvedPlaylist != null
          ? resolvedPlaylist[resolvedPlaylistIndex].httpHeaders
          : source.httpHeaders;
      final ok = isDebridResolved
          ? await _host.openStartupDebridDirect(
              url,
              httpHeaders: candidateHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            )
          : await _host.tryOpenStartupVod(
              url,
              httpHeaders: candidateHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            );
      if (!_host.mounted) return false;
      if (!ok) continue;

      _host.activeHttpHeaders = candidateHeaders;

      _host.currentSourceIndex = sourceIndex;
      _host.currentStreamUrl = url;
      if (resolvedPlaylist != null && resolvedPlaylist.isNotEmpty) {
        _host.activePlaylist = resolvedPlaylist;
        _host.currentIndex = resolvedPlaylistIndex;
        _host.cachedSeriesPlaylist = null;
        _host.playlistIdentityToken++;
      }
      unawaited(_host.commitValidatedStremioSource(source));
      debugPrint(
        '[StartupFailover] event=commit platform=flutter '
        'attempt=$attempts/$maxAttempts $sourceFields '
        'playlistItems=${resolvedPlaylist?.length ?? 0} '
        'playlistIndex=$resolvedPlaylistIndex',
      );
      return true;
    }
    _host.setStartupGateActive(false);
    debugPrint(
      '[StartupFailover] event=exhausted platform=flutter '
      'attempts=$attempts maxAttempts=$maxAttempts sourceCount=${sources.length}',
    );
    return false;
  }
}
