import 'package:debrify/services/tracking_source_policy.dart';

class EpisodesPanelProgress {
  Map<String, double> episodeWatchProgress = {};

  TrackingSourcePolicy trackingPolicy = const TrackingSourcePolicy(
    scrobbleTargets: <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
    progressSource: WatchProgressSource.smart,
    homeTickSources: <TrackingSource>{
      TrackingSource.local,
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
  );

  Map<String, int> episodeMdblistRatings = {};
}
