import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/tracker_progress_seeding.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';

/// The Ledger (Debrify's own tracker) part of the shared pre-launch path.
final class LaunchLedgerTracking {
  /// Ledger's feature flag: while it is off the launch path skips every
  /// Ledger step (no extra awaits), exactly as before Ledger.
  static bool get enabled => kLedgerEnabled;

  /// Ledger auto-enable — parallel to the Trakt/Simkl upgrades, with the same
  /// context exclusions. Ledger has its own Continue Watching row, so (like
  /// them) it owns the title from here: the stale local entry is removed and
  /// the persist step skips creating a new one. Returns null when the launch
  /// retired while this ran.
  static Future<VideoPlayerLaunchArgs?> autoEnable(
    VideoPlayerLaunchArgs args,
    TrackingSourcePolicy policy, {
    required bool Function() active,
    required Future<void> Function(Future<void> Function() action) write,
  }) async {
    if (args.ledgerScrobble ||
        args.suppressTrackerAutoSync ||
        !LedgerService.supportsId(args.contentImdbId) ||
        args.stremioTvChannels != null ||
        !policy.scrobbles(TrackingSource.ledger)) {
      return args;
    }
    final authenticated = await LedgerService.instance.isAuthenticated();
    if (!active()) return null;
    if (!authenticated) return args;
    final enabled = args.copyWith(ledgerScrobble: true);
    if (!policy.forcesLocalCompletion && !policy.nativeIdentity) {
      await write(
        () => ContinueWatchingStorage.removeContinueWatchingItem(
          enabled.contentImdbId!,
        ),
      );
      if (!active()) return null;
    }
    return enabled;
  }

  /// [seed] alone while Ledger is off, so those launches await exactly what
  /// they did before Ledger; with it on, [seed] and [seedEpisodes] together.
  static Future<void> alongside(Future<void> seed, VideoPlayerLaunchArgs args) =>
      kLedgerEnabled ? Future.wait([seed, seedEpisodes(args)]) : seed;

  /// Refreshes Ledger's episode snapshot for a series launch while Ledger is
  /// connected (even with scrobbling to it off, so it can't go stale as the
  /// progress source); a no-op otherwise. Never throws.
  static Future<void> seedEpisodes(VideoPlayerLaunchArgs args) async {
    final imdbId = args.contentImdbId;
    if (!LedgerService.supportsId(imdbId)) return;
    if (!args.ledgerScrobble && !await LedgerService.instance.isAuthenticated()) {
      return;
    }
    await TrackerProgressSeeding.seedLedgerEpisodeProgress(imdbId!);
  }
}
