import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Existing resolved transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'secondary_tracker_driver.dart';
import 'video_player_environment.dart';

VideoPlayerScreen completionScreen({
  String? type = 'movie',
  String? id = 'tt7100000',
  String? contentTitle = 'Completion title',
  String title = 'Completion fallback',
  int? season = 2,
  int? episode = 3,
  bool trakt = false,
  bool simkl = false,
  bool mdblist = false,
  List<PlaylistEntry>? playlist,
  int startIndex = 0,
  bool disableAutoResume = false,
  Future<Map<String, String>?> Function()? requestMagicNext,
  PlaylistViewMode? viewMode,
  List<IptvChannel>? iptv,
  List<Map<String, dynamic>>? tv,
}) => VideoPlayerScreen(
  videoUrl: playlist?.first.url ?? 'https://player.test/completion.mp4',
  title: title,
  contentTitle: contentTitle,
  contentType: type,
  contentImdbId: id,
  contentSeason: season,
  contentEpisode: episode,
  traktScrobble: trakt,
  simklScrobble: simkl,
  mdblistScrobble: mdblist,
  playlist: playlist,
  startIndex: startIndex,
  disableAutoResume: disableAutoResume,
  requestMagicNext: requestMagicNext,
  viewMode: viewMode,
  iptvChannels: iptv,
  stremioTvChannels: tv,
);

/// Holds delivery at an executed await, after the actual public storage reader
/// has returned. Unlike the cold preferences barrier, this cannot hold player
/// defaults or construction. Method suffixes survive the declared move rename.
class CompletionDelivery {
  CompletionDelivery(this.awaitName, this.accepts);
  final String awaitName;
  final bool Function(Object?) accepts;
  bool armed = true;
  bool multiple = false;
  final pending = <void Function()>[];
  final values = <Object?>[];
  ZoneSpecification get specification => ZoneSpecification(
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) callback) {
      final frame = StackTrace.current
          .toString()
          .split('\n')
          .where((frame) => frame.contains('package:debrify/'))
          .firstOrNull;
      final selected = frame?.contains(awaitName) ?? false;
      return parent.registerUnaryCallback(zone, (T value) {
        if (armed &&
            selected &&
            accepts(value) &&
            (R.toString() == 'void' || R.toString() == 'dynamic')) {
          if (!multiple) armed = false;
          values.add(value);
          pending.add(() => zone.runUnary(callback, value));
          return null as R;
        }
        return callback(value);
      });
    },
  );
  T run<T>(T Function() body) =>
      runZoned(body, zoneSpecification: specification);
  void releaseAt(int index) {
    final callback = pending.removeAt(index);
    callback();
  }

  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

/// Real preference transport: inspect physical writes, including failed writes
/// for which SharedPreferences may already have updated its in-memory cache.
class CompletionWrites extends InMemorySharedPreferencesStore {
  CompletionWrites(super.values) : super.withData();
  final writes = <(String, Object)>[];
  final removes = <String>[];
  bool Function(String)? reject;
  static Future<CompletionWrites> install() async {
    final store = CompletionWrites(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    if (reject?.call(key) ?? false) throw StateError('completion write $key');
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    removes.add(key);
    if (reject?.call(key) ?? false) throw StateError('completion remove $key');
    return super.remove(key);
  }

  Future<Object?> physical(ProfileScope scope, String logical) async =>
      (await getAll())['flutter.${scope.preferenceKey(logical)}'];
}

class LocalCompletionDriver extends SecondaryTrackerDriver {
  LocalCompletionDriver(super.t, super.f);
  @override
  Future<void> initialize({
    bool target = false,
    Set<TrackingSource> targets = const {},
  }) async {
    await super.initialize(target: target, targets: targets);
    await t.runAsync(
      () => TrackingSourceStorage.setWatchProgressSource(
        WatchProgressSource.smart,
      ),
    );
  }

  @override
  Future<void> mount(VideoPlayerScreen screen) async {
    await super.mount(screen);
    // Real positive frames finish the original startup validation; a second
    // dispatch exercises completion after that async acknowledgement. Early
    // loader-window cases deliberately use mountHeld/f.mount instead.
    await position(1000);
    await drain();
    await position(1000);
    await drain();
  }

  Future<void> thresholds(int movie, int episode) => f.finish(
    t,
    Future.wait([
      LocalCompletionStorage.setMovieCompletionThreshold(movie),
      LocalCompletionStorage.setEpisodeCompletionThreshold(episode),
    ]),
  );
  Future<void> percent(double value) =>
      position((1200000 * value / 100).round());
  Future<Map<String, dynamic>> stateMap() =>
      f.finish(t, PlaybackStateStore.getPlaybackStateMap());
  String episodeKey({
    String title = 'Completion title',
    String? id = 'tt7100000',
  }) => PlaybackIdentityStorage.seriesProgressKey(title, id);
  Future<Map<String, dynamic>?> finishedEpisode({
    String title = 'Completion title',
    String? id = 'tt7100000',
    int season = 2,
    int episode = 3,
  }) async {
    final map = await stateMap();
    return ((map[episodeKey(title: title, id: id)] as Map?)?['finishedEpisodes']
            as Map?)?[season.toString()]?[episode.toString()]
        as Map<String, dynamic>?;
  }

  Future<void> eof() async {
    f.player.emit('completed', true);
    await drain();
  }
}

Future<ProfileScope> completionIncomingProfile(
  WidgetTester t,
  VideoPlayerEnvironment f,
) async {
  final scope = ProfileRuntime.capture();
  final actor = await f.finish(t, f.registry!.getProfile(scope.profileId));
  final incoming = await f.finish(
    t,
    f.registry!.createProfile(
      name: 'Incoming completion profile',
      role: UserProfileRole.admin,
      actingProfileId: scope.profileId,
      actingAuthorizationRevision: actor!.authorizationRevision,
      actingSessionEpoch: scope.sessionEpoch,
    ),
  );
  await f.finish(t, f.registry!.setActiveProfile(incoming.id));
  final next = ProfileScope(
    profileId: incoming.id,
    dataGeneration: 1,
    sessionEpoch: ProfileRuntime.nextEpoch,
  );
  ProfileRuntime.publish(next);
  ProfilePolicyGuard.updateActiveProfile(incoming);
  SubtitleSettingsService.instance.resetProfileScope();
  SubtitleFontService.instance.resetProfileScope();
  return next;
}

Map<String, dynamic> decodeCompletionPhysical(Object? raw) =>
    raw == null ? {} : jsonDecode(raw as String) as Map<String, dynamic>;

Future<ProfileScope> completionActivate(
  WidgetTester t,
  VideoPlayerEnvironment f,
  ProfileScope target,
) async {
  final profile = await f.finish(t, f.registry!.getProfile(target.profileId));
  await f.finish(t, f.registry!.setActiveProfile(target.profileId));
  final scope = ProfileScope(
    profileId: target.profileId,
    dataGeneration: target.dataGeneration,
    sessionEpoch: ProfileRuntime.nextEpoch,
  );
  ProfileRuntime.publish(scope);
  ProfilePolicyGuard.updateActiveProfile(profile);
  SubtitleSettingsService.instance.resetProfileScope();
  SubtitleFontService.instance.resetProfileScope();
  return scope;
}

/// Independent read-only connections inspect the actual profile files, without
/// adopting an outgoing application handle into the incoming runtime scope.
Future<Map<String, Object?>?> completionPhysicalResume(
  VideoPlayerEnvironment f,
  ProfileScope scope,
  String key,
) async {
  final db = await databaseFactoryFfi.openDatabase(
    scope.fileIn(f.directory, 'documents', 'debrify_tv.db').path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final rows = await db.query(
      'video_resume',
      where: 'resume_key = ?',
      whereArgs: [key],
    );
    return rows.firstOrNull;
  } finally {
    await db.close();
  }
}
