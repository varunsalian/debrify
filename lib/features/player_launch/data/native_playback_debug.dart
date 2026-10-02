import 'package:debrify/features/player_launch/data/android_tv_payload_builder.dart';
import 'package:debrify/features/player_launch/data/native_mdblist_session.dart';
import 'package:debrify/features/player_launch/data/native_progress_handler.dart';
import 'package:debrify/features/player_launch/data/native_scrobble_session.dart';
import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';

final class NativePlaybackDebug {
  static Future<List<int>> debugNativeResumePositions(
    VideoPlayerLaunchArgs args,
    List<PlaylistEntry> entries,
  ) async {
    final states = await AndroidTvPlaybackPayloadBuilder(args).fetchPerItemPlaybackState(
      entries,
      contentType: args.contentType == 'series'
          ? PlaybackContentType.series
          : PlaybackContentType.single,
      seriesPlaylist: null,
    );
    return states.map((state) => state.positionMs).toList();
  }

  static Future<Map<String, dynamic>> debugNativePlaybackSession(
    VideoPlayerLaunchArgs args,
    List<Map<String, dynamic>> updates, {
    MdblistService? mdblistService,
    bool Function()? canContinue,
  }) async {
    final built = await AndroidTvPlaybackPayloadBuilder(
      args,
      canContinue: canContinue,
    ).build();
    if (built == null) throw StateError('Native payload could not be built');
    final payload = built.payload;
    final initial = payload.toMap();
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.traktLastKnownProgress = 0;
    NativeScrobbleSession.traktLastKnownSeason = null;
    NativeScrobbleSession.traktLastKnownEpisode = null;
    try {
      await NativeMdblistSession.initializeNativeMdblist(payload, service: mdblistService);
      for (final update in updates) {
        await NativeProgressHandler.handleProgressUpdate(payload, update);
      }
    } finally {
      await NativeProgressHandler.handlePlaybackFinished(payload);
      StreamRedirectResolver.clearResolvedStreams(built.entries.map((entry) => entry.resumeId));
    }
    return initial;
  }
}
