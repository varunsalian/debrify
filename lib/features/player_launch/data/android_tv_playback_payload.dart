import 'package:debrify/features/player_launch/models/android_tv_playback_item.dart';
import 'package:debrify/features/player_launch/models/launcher_entry.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';

class AndroidTvPlaybackPayload {
  final PlaybackContentType contentType;
  final String? declaredContentType;
  String get trackingContentType =>
      declaredContentType ?? (contentType == PlaybackContentType.series ? 'series' : 'movie');
  final String title;
  final String? subtitle;
  final List<AndroidTvPlaybackItem> items;
  final int startIndex;
  final String? seriesTitle;
  final List<AndroidTvSeriesSeason> seasons;
  final Map<int, int> nextEpisodeMap;
  final Map<int, int> prevEpisodeMap;
  final List<AndroidTvCollectionGroup>? collectionGroups;
  String? imdbId;
  final Map<String, String>? httpHeaders;

  final double? startAtPercent;
  final List<Map<String, dynamic>>? stremioSources;
  final int? stremioCurrentSourceIndex;
  final bool hasPlaylistResolver;
  final bool hasAdjacentEpisodeResolver;
  final bool startupTryNextOnFailure;
  final int startupMaxAttempts;
  final String? startupResolverProvider;
  final bool startupRecoveryAvailable;
  final bool traktScrobble;
  final double? traktProgressPercent;
  // Simkl parallel pair. Only the scrobble flag matters Dart-side (the
  // progress percent folds into the native resume seed via toMap below).
  final bool simklScrobble;
  final double? simklProgressPercent;
  final bool mdblistScrobble;
  final double? mdblistProgressPercent;
  MdblistScrobbleSession? mdblistSession;
  MdblistScrobbleSession Function(MdblistScrobbleTarget)? mdblistSessionFactory;
  int? mdblistSeason;
  int? mdblistEpisode;

  /// Local completion can coexist with scrobbling. Its threshold controls
  /// local resume persistence; trackers keep their own completion rules.
  final bool localCompletionTracking;
  final int movieCompletionThreshold;
  final int episodeCompletionThreshold;
  // Session-only guards; the native activity emits local threshold crossing
  // once per item, while these prevent later progress pings from rebuilding a
  // completed movie's local resume state.
  bool localMovieCompletionRecorded = false;
  bool localMovieRewatchStarted = false;
  // Subtitle tracks known at launch (e.g. YouTube captions), surfaced natively
  // as a pre-loaded provider group without an addon fetch.
  final List<StremioSubtitle>? initialSubtitles;

  AndroidTvPlaybackPayload({
    required this.contentType,
    this.declaredContentType,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.startIndex,
    required this.seriesTitle,
    required this.seasons,
    this.nextEpisodeMap = const {},
    this.prevEpisodeMap = const {},
    this.collectionGroups,
    this.imdbId,
    this.httpHeaders,
    this.startAtPercent,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.hasPlaylistResolver = false,
    this.hasAdjacentEpisodeResolver = false,
    this.startupTryNextOnFailure = false,
    this.startupMaxAttempts = 1,
    this.startupResolverProvider,
    this.startupRecoveryAvailable = false,
    this.traktScrobble = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.mdblistScrobble = false,
    this.mdblistProgressPercent,
    this.localCompletionTracking = false,
    this.movieCompletionThreshold = LocalCompletionStorage.defaultLocalCompletionThreshold,
    this.episodeCompletionThreshold = LocalCompletionStorage.defaultLocalCompletionThreshold,
    this.initialSubtitles,
  });

  /// The effective cross-tracker launch resume percent: the FURTHEST of the
  /// Trakt, Simkl, and MDBList promises (each 0-100, exclusive). Native only
  /// knows one launch-resume input (`traktProgressPercent` in the map below),
  /// so the three-way merge happens here — native then reconciles this
  /// explicit percent against its local position as before.
  double? get _effectiveLaunchPercent {
    double? best;
    for (final pct in [
      traktProgressPercent,
      simklProgressPercent,
      mdblistProgressPercent,
    ]) {
      if (pct == null || pct <= 0 || pct >= 100) continue;
      if (best == null || pct > best) best = pct;
    }
    return best;
  }

  Map<String, dynamic> toMap() {
    return {
      'version': 1,
      'title': title,
      'subtitle': subtitle,
      'contentType': contentType.name,
      'startIndex': startIndex,
      'seriesTitle': seriesTitle,
      'items': items.map((e) => e.toMap()).toList(),
      'seasons': seasons.map((e) => e.toMap()).toList(),
      'nextEpisodeMap': nextEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'prevEpisodeMap': prevEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'collectionGroups': collectionGroups?.map((e) => e.toMap()).toList(),
      'imdbId': imdbId,
      if (httpHeaders != null && httpHeaders!.isNotEmpty) 'httpHeaders': httpHeaders,
      if (startAtPercent != null && startAtPercent! > 0) 'startAtPercent': startAtPercent,
      if (stremioSources != null && stremioSources!.isNotEmpty) 'stremioSources': stremioSources,
      if (stremioCurrentSourceIndex != null) 'stremioCurrentSourceIndex': stremioCurrentSourceIndex,
      if (hasPlaylistResolver) 'hasPlaylistResolver': true,
      if (hasAdjacentEpisodeResolver) 'hasAdjacentEpisodeResolver': true,
      if (stremioSources != null && stremioSources!.isNotEmpty) ...{
        'startupTryNextOnFailure': startupTryNextOnFailure,
        'startupMaxAttempts': startupMaxAttempts.clamp(1, 10),
        if (startupResolverProvider != null) 'startupResolverProvider': startupResolverProvider,
        if (startupRecoveryAvailable) 'startupRecoveryAvailable': true,
      },
      // Keyed 'traktProgressPercent' for the native side's existing resume
      // input, but carries the furthest of the Trakt/Simkl launch percents.
      if (_effectiveLaunchPercent != null) 'traktProgressPercent': _effectiveLaunchPercent,
      if (localCompletionTracking) ...{
        'localCompletionTracking': true,
        'movieCompletionThreshold': movieCompletionThreshold,
        'episodeCompletionThreshold': episodeCompletionThreshold,
      },
      if (initialSubtitles != null && initialSubtitles!.isNotEmpty)
        'initialSubtitles': [
          for (final s in initialSubtitles!)
            {
              'id': s.id,
              'url': s.url,
              'lang': s.lang,
              if (s.label != null) 'label': s.label,
              'source': s.source,
            },
        ],
    };
  }
}

class AndroidTvPlaybackPayloadResult {
  final AndroidTvPlaybackPayload payload;
  final List<LauncherEntry> entries;

  const AndroidTvPlaybackPayloadResult({
    required this.payload,
    required this.entries,
  });
}
