import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/episode_progress_merge.dart';

/// Each tracker's launch-time per-episode snapshot for one show, keyed by
/// `"season_episode"`, as the native TV payload consumes them.
///
/// One home for what the payload builder, native launch and metadata push
/// each used to load and mask by hand. Every percent passes through the
/// policy's guide mask, so a tracker that isn't the Progress source (or is
/// disconnected) contributes nothing.
final class EpisodeTrackerPercents {
  const EpisodeTrackerPercents._(
    this._trakt,
    this._simkl,
    this._mdblist,
    this._ledger,
  );

  static const EpisodeTrackerPercents empty = EpisodeTrackerPercents._(
    <String, double>{},
    <String, double>{},
    <String, double>{},
    <String, double>{},
  );

  final Map<String, double> _trakt;
  final Map<String, double> _simkl;
  final Map<String, double> _mdblist;
  final Map<String, double> _ledger;

  /// Every snapshot of one show, read concurrently (Ledger's only while its
  /// feature flag is on); pass the result to [EpisodeTrackerPercents.of].
  /// Callers await this directly and use [empty] without a show id, so a
  /// launch awaits exactly the reads it did before these were shared.
  static Future<List<Map<String, double>>> read(String imdbId) => Future.wait([
    TrackerEpisodeProgressStorage.getEpisodeTraktProgress(imdbId: imdbId),
    TrackerEpisodeProgressStorage.getEpisodeSimklProgress(imdbId: imdbId),
    TrackerEpisodeProgressStorage.getConnectedEpisodeMdblistProgress(
      imdbId: imdbId,
    ),
    if (kLedgerEnabled)
      TrackerEpisodeProgressStorage.getConnectedEpisodeLedgerProgress(
        imdbId: imdbId,
      ),
  ]);

  /// The snapshots [read] returned.
  factory EpisodeTrackerPercents.of(List<Map<String, double>> maps) => EpisodeTrackerPercents._(
    maps[0],
    maps[1],
    maps[2],
    maps.length > 3 ? maps[3] : const <String, double>{},
  );

  /// The policy-masked percent of each tracker for [episodeKey] (all null
  /// when the key is null).
  ({double? trakt, double? simkl, double? mdblist, double? ledger}) guide(
    TrackingSourcePolicy policy,
    String? episodeKey,
  ) {
    double? of(TrackingSource source, Map<String, double> map) =>
        episodeKey == null ? null : policy.guideProgressFrom(source, map[episodeKey]);
    return (
      trakt: of(TrackingSource.trakt, _trakt),
      simkl: of(TrackingSource.simkl, _simkl),
      mdblist: of(TrackingSource.mdblist, _mdblist),
      ledger: of(TrackingSource.ledger, _ledger),
    );
  }

  /// The furthest masked tracker percent for [episodeKey], or null.
  double? furthest(TrackingSourcePolicy policy, String? episodeKey) {
    if (episodeKey == null) return null;
    final g = guide(policy, episodeKey);
    return furthestEpisodeTrackerPercent([g.trakt, g.simkl, g.mdblist, g.ledger]);
  }
}
