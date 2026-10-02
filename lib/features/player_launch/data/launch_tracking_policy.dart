import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/services/tracking_source_policy.dart';

final class LaunchTrackingPolicy {
  /// Resolves the one MDBList ownership decision used by every playback
  /// surface. A launch originating from an MDBList row is still only a
  /// *request* to use MDBList: disabling playback/library sync or disconnecting
  /// the account must hand completion and Continue Watching back to Debrify.

  static bool shouldEnableMdblistTracking({
    required bool requested,
    required bool autoEligible,
    required bool featureEnabled,
    required bool identityAvailable,
    required bool syncEnabled,
    required bool authenticated,
  }) {
    return featureEnabled &&
        identityAvailable &&
        syncEnabled &&
        authenticated &&
        (requested || autoEligible);
  }

  static VideoPlayerLaunchArgs normalizeScrobbleFlags(
    VideoPlayerLaunchArgs args,
    TrackingSourcePolicy policy,
  ) {
    policy = policy.forContent(args.contentImdbId);
    return args.copyWith(
      traktScrobble: args.traktScrobble && policy.scrobbles(TrackingSource.trakt),
      simklScrobble: args.simklScrobble && policy.scrobbles(TrackingSource.simkl),
      mdblistScrobble: args.mdblistScrobble && policy.scrobbles(TrackingSource.mdblist),
    );
  }
}
