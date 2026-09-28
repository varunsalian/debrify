import '../models/media_identity.dart';
import '../models/tracking_source.dart';
import '../models/custom_series_identity.dart';
import 'storage_service.dart';

export '../models/tracking_source.dart';

/// One immutable snapshot of the user's Tracking preferences.
///
/// Keeping all three decisions here prevents individual playback and Home
/// surfaces from growing subtly different interpretations of the settings.
class TrackingSourcePolicy {
  const TrackingSourcePolicy({
    required this.scrobbleTargets,
    required this.progressSource,
    required this.homeTickSources,
    this.nativeIdentity = false,
  });

  final bool nativeIdentity;
  final Set<TrackingSource> scrobbleTargets;
  final WatchProgressSource progressSource;
  final Set<TrackingSource> homeTickSources;

  TrackingSourcePolicy forContent(String? id) =>
      CustomSeriesIdentity.isCustom(id) ||
          (id?.startsWith('medialibrary:') ?? false)
      ? const TrackingSourcePolicy(
          scrobbleTargets: {},
          progressSource: WatchProgressSource.local,
          homeTickSources: {TrackingSource.local},
        )
      : MediaIdentity.isNative(id)
      ? TrackingSourcePolicy(
          scrobbleTargets: scrobbleTargets,
          // Trakt/MDBList resume selection still consumes IMDb-only feeds.
          // Keep the existing local fallback until those readers support native
          // identities; this does not disable writes or Smart progress reads.
          progressSource:
              progressSource == WatchProgressSource.trakt ||
                  progressSource == WatchProgressSource.mdblist
              ? WatchProgressSource.local
              : progressSource,
          homeTickSources: homeTickSources,
          nativeIdentity: true,
        )
      : this;

  static Future<TrackingSourcePolicy> load({
    bool Function()? canContinue,
  }) async {
    void checkCurrent() {
      if (canContinue?.call() == false) {
        throw StateError('Tracking action retired');
      }
    }

    checkCurrent();
    final scrobbleTargets = await StorageService.getTrackingScrobbleTargets(
      canContinue: canContinue,
    );
    checkCurrent();
    var progressSource = await StorageService.getWatchProgressSource();
    checkCurrent();
    final dedicated = switch (progressSource) {
      WatchProgressSource.trakt => TrackingSource.trakt,
      WatchProgressSource.simkl => TrackingSource.simkl,
      WatchProgressSource.mdblist => TrackingSource.mdblist,
      _ => null,
    };
    if (dedicated != null) {
      final connected = switch (dedicated) {
        TrackingSource.trakt => StorageService.hasTraktCredential(
          canContinue: canContinue,
        ),
        TrackingSource.simkl => StorageService.hasSimklCredential(
          canContinue: canContinue,
        ),
        TrackingSource.mdblist => StorageService.hasMdblistCredential(
          canContinue: canContinue,
        ),
        TrackingSource.local => Future<bool>.value(true),
      };
      final hasCredential = await connected;
      checkCurrent();
      if (!hasCredential) {
        await StorageService.fallbackDisconnectedProgressSource(
          dedicated,
          canContinue: canContinue,
        );
        checkCurrent();
        progressSource = WatchProgressSource.smart;
      }
    }
    final ticks = await StorageService.getHomeTickSources();
    checkCurrent();
    return TrackingSourcePolicy(
      scrobbleTargets: scrobbleTargets,
      progressSource: progressSource,
      homeTickSources: ticks,
    );
  }

  bool scrobbles(TrackingSource source) =>
      source == TrackingSource.local || scrobbleTargets.contains(source);

  /// Smart preserves the legacy merged/recency behavior. A dedicated source
  /// admits only itself; local means data written by this Debrify profile.
  bool progressFrom(TrackingSource source) => switch (progressSource) {
    WatchProgressSource.smart => true,
    WatchProgressSource.local => source == TrackingSource.local,
    WatchProgressSource.trakt => source == TrackingSource.trakt,
    WatchProgressSource.simkl => source == TrackingSource.simkl,
    WatchProgressSource.mdblist => source == TrackingSource.mdblist,
  };

  bool homeTicksFrom(TrackingSource source) => homeTickSources.contains(source);

  /// Episode-guide supplier mask: ticks AND partial bars both follow
  /// [progressSource] (Varun, 2026-08-27 — supersedes the earlier
  /// ticks-always-merged decision). Also used by the native TV payload so
  /// late metadata cannot reintroduce a foreign entry.
  double? guideProgressFrom(TrackingSource source, double? percent) {
    if (percent == null || !percent.isFinite) return null;
    if (!progressFrom(source)) return null;
    return percent.clamp(0.0, 100.0).toDouble();
  }

  bool get forcesLocalCompletion => progressSource == WatchProgressSource.local;

  /// Scrobbling support is independent of Continue Watching ownership.
  /// Trakt/MDBList CW feeds still require IMDb IDs; native titles must retain
  /// their existing Simkl/local owner even while we send those trackers writes.
  bool usesLocalCompletionTracking({
    required bool traktScrobble,
    required bool simklScrobble,
    required bool mdblistScrobble,
  }) =>
      forcesLocalCompletion ||
      (!simklScrobble &&
          (nativeIdentity || (!traktScrobble && !mdblistScrobble)));

  bool get isSmart => progressSource == WatchProgressSource.smart;
}
