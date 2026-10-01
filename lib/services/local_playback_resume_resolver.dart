import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import '../models/playback_resume_policy.dart';
import '../models/custom_series_identity.dart';

export '../models/playback_resume_policy.dart';

/// Shared local-resume selection for MediaKit and the native ExoPlayer payload.
///
/// Storage remains source-keyed. This resolver changes read precedence only,
/// which preserves legacy rows and keeps generic playback independent while
/// allowing catalog content to use its stable identity.
class LocalPlaybackResumeResolver {
  const LocalPlaybackResumeResolver._();

  static Future<Map<String, dynamic>?> movie({
    required String resumeId,
    required String? imdbId,
    PlaybackResumePolicy policy = PlaybackResumePolicy.sourceSpecific,
  }) async {
    final wanted = imdbId?.trim() ?? '';
    if (wanted.startsWith('medialibrary:')) {
      return VideoProgressStorage.getVideoPlaybackStateByImdbId(wanted);
    }
    if (CustomSeriesIdentity.isCustom(wanted)) {
      return VideoProgressStorage.getVideoPlaybackStateByImdbId(wanted);
    }

    if (policy == PlaybackResumePolicy.catalogCanonical && wanted.isNotEmpty) {
      // Completion is canonical too. In particular, do not resurrect a legacy
      // exact-source row that predates IMDb being written into playback state.
      if (await MovieProgressStorage.isMovieFinished(wanted)) return null;

      final reads = await Future.wait<Map<String, dynamic>?>([
        VideoProgressStorage.getVideoPlaybackStateByImdbId(wanted),
        VideoProgressStorage.getVideoPlaybackState(videoTitle: resumeId),
      ]);
      final canonical = reads[0];
      final exact = _catalogEligibleExact(reads[1], wanted);
      if (canonical != null) {
        return _withExactPresentationPreferences(canonical, exact);
      }
      // A matching or pre-IMDb exact record is the lossless legacy fallback.
      return exact;
    }

    // Existing generic behavior: the precise file/provider record owns resume;
    // IMDb is only a recovery path when that source has never been seen.
    final exact = await VideoProgressStorage.getVideoPlaybackState(
      videoTitle: resumeId,
    );
    if (exact != null) return exact;
    if (wanted.isEmpty) return null;
    return VideoProgressStorage.getVideoPlaybackStateByImdbId(wanted);
  }

  static Future<Map<String, dynamic>?> episode({
    required String seriesTitle,
    required int season,
    required int episode,
    required String? imdbId,
    PlaybackResumePolicy policy = PlaybackResumePolicy.sourceSpecific,
  }) async {
    if (policy != PlaybackResumePolicy.catalogCanonical ||
        imdbId?.trim().isNotEmpty != true) {
      return SeriesProgressStorage.getSeriesPlaybackState(
        seriesTitle: seriesTitle,
        imdbId: imdbId,
        season: season,
        episode: episode,
      );
    }

    final reads = await Future.wait<dynamic>([
      MergedEpisodeProgressStorage.getMergedEpisodeProgress(
        seriesTitle: seriesTitle,
        imdbId: imdbId!.trim(),
      ),
      SeriesProgressStorage.getSeriesPlaybackState(
        seriesTitle: seriesTitle,
        imdbId: imdbId,
        season: season,
        episode: episode,
      ),
    ]);
    final merged = reads[0] as Map<String, Map<String, dynamic>>;
    final exact = reads[1] as Map<String, dynamic>?;
    final canonical = merged['${season}_$episode'];
    if (canonical == null) return exact;
    return _withExactPresentationPreferences(canonical, exact);
  }

  /// Resume position follows canonical content identity, while speed and
  /// aspect preserve the current source's existing settings when it has them.
  /// This keeps the policy change narrowly about resume position.
  static Map<String, dynamic> _withExactPresentationPreferences(
    Map<String, dynamic> canonical,
    Map<String, dynamic>? exact,
  ) {
    if (exact == null) return canonical;
    return <String, dynamic>{
      ...canonical,
      if (exact.containsKey('speed')) 'speed': exact['speed'],
      if (exact.containsKey('aspect')) 'aspect': exact['aspect'],
    };
  }

  /// A colliding source key tagged with another title must never override an
  /// authoritative catalog launch. Rows without an ID remain valid legacy data.
  static Map<String, dynamic>? _catalogEligibleExact(
    Map<String, dynamic>? exact,
    String wanted,
  ) {
    if (exact == null) return null;
    final recorded = exact['imdbId'];
    if (recorded is String &&
        recorded.trim().isNotEmpty &&
        recorded.trim() != wanted) {
      return null;
    }
    return exact;
  }
}
