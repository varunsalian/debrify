import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/simkl/simkl_constants.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'trakt_player_driver.dart';
import 'trakt_transport.dart';
import 'player_actions.dart';

VideoPlayerScreen secondaryScreen({
  bool simkl = true,
  bool mdblist = true,
  bool trakt = false,
  String? id = 'tt5100000',
  String? type = 'series',
  int? season = 2,
  int? episode = 3,
  double? traktPercent,
  double? simklPercent,
  double? mdblistPercent,
  List<PlaylistEntry>? playlist,
}) => VideoPlayerScreen(
  videoUrl: playlist?.first.url ?? 'https://player.test/secondary.mp4',
  title: playlist?.first.title ?? 'Secondary tracker fixture',
  contentImdbId: id,
  contentType: type,
  contentSeason: season,
  contentEpisode: episode,
  simklScrobble: simkl,
  mdblistScrobble: mdblist,
  traktScrobble: trakt,
  traktProgressPercent: traktPercent,
  simklProgressPercent: simklPercent,
  mdblistProgressPercent: mdblistPercent,
  playlist: playlist,
);

http.Response secondaryReply(http.Request request) {
  if (request.url.host == 'api.trakt.tv') return traktReply(request);
  if (request.url.path.startsWith('/scrobble/')) {
    return http.Response(
      jsonEncode({'action': request.url.path.split('/').last}),
      201,
      headers: {'content-type': 'application/json'},
    );
  }
  if (request.url.host == 'api.simkl.com' &&
      request.url.path == '/sync/playback/episodes') {
    return http.Response('[]', 200);
  }
  return http.Response('{}', 404);
}

/// Uses the production singleton clients. The inherited isolate transport
/// keeps their first client alive while directing every request to this case.
class SecondaryTrackerDriver extends TraktPlayerDriver {
  SecondaryTrackerDriver(super.t, super.f);
  static final timerTag = Object();
  final cancellations = <int>[];
  final _timerOrdinals = <Timer, int>{};

  Result observe<Result>(
    Result Function() body, {
    List<Object>? errors,
  }) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, Value>(self, parent, zone, R Function(Value) callback) {
            // Timer.periodic binds its callback before createPeriodicTimer. Tag the
            // unbound callback here so that its original binding cannot discard
            // the observation zone. Other await/stream callbacks pass unchanged.
            return parent.registerUnaryCallback(zone, (Value value) {
              final ordinal = value is Timer ? _timerOrdinals[value] : null;
              if (ordinal != null) {
                return runZoned(
                  () => callback(value),
                  zoneValues: {timerTag: ordinal},
                );
              }
              return callback(value);
            });
          },
      handleUncaughtError: (self, parent, zone, error, stack) {
        (errors ?? uncaught).add(error);
      },
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        if (duration != const Duration(minutes: 2)) {
          return parent.createPeriodicTimer(zone, duration, callback);
        }
        final ordinal = heartbeats.length;
        final delegate = parent.createPeriodicTimer(zone, duration, callback);
        _timerOrdinals[delegate] = ordinal;
        final timer = _ObservedTimer(
          delegate,
          () => cancellations.add(ordinal),
        );
        heartbeats.add(timer);
        return timer;
      },
    ),
  );

  Future<void> mountHeld(VideoPlayerScreen screen, {List<Object>? errors}) =>
      observe(() => f.mount(t, screen), errors: errors);

  @override
  Future<void> mount(VideoPlayerScreen screen) async {
    cipher.hold = true;
    await mountHeld(screen);
    expect(forTracker('trakt'), isEmpty);
    expect(forTracker('simkl'), isEmpty);
    expect(forTracker('mdblist'), isEmpty);
    cipher.releaseAll();
    await drain();
  }

  @override
  Future<void> seek(double fraction) async {
    final controls = playerControls(t);
    controls.onSeekBarChanged(fraction);
    await f.advance(t);
    expect(
      () => observe(controls.onSeekBarChangeEnd),
      returnsNormally,
      reason: 'The original public seek completion must return normally',
    );
    await drain();
  }

  Future<void> seekBeforeLanding(double fraction) async {
    final landing = Completer<void>();
    f.player.delays['seek'] = landing;
    try {
      await seek(fraction);
    } finally {
      landing.complete();
      f.player.delays.remove('seek');
    }
    await drain();
  }

  @override
  Future<void> initialize({
    bool target = true,
    Set<TrackingSource> targets = const {
      TrackingSource.simkl,
      TrackingSource.mdblist,
    },
  }) async {
    await t.runAsync(f.initialize);
    TraktTestTransport.instance.attach(f);
    if (!f.committed) {
      final memory = MemoryDeviceSecretCipher(List.generate(32, (i) => i + 1));
      await memory.initialize();
      DeviceKeyProvider.debugInstallCipher(memory);
    }
    cipher = (await t.runAsync(() => seedTrakt(target: false)))!;
    await t.runAsync(() async {
      await SimklStorage.setSimklAccessToken('vplayer-synthetic-simkl');
      await MdblistStorage.saveMdblistApiKey('vplayer-synthetic-mdblist');
      await TrackingSourceStorage.setTrackingScrobbleTargets(
        target ? targets : {},
      );
    });
    f.network.handler = secondaryReply;
  }

  List<http.Request> forTracker(String tracker) => f.network.requests
      .where(
        (r) =>
            r.url.host == 'api.$tracker.${tracker == 'trakt' ? 'tv' : 'com'}' &&
            r.url.path.startsWith('/scrobble/'),
      )
      .toList();
  List<String> trackerActions(String tracker) =>
      forTracker(tracker).map((r) => r.url.path.split('/').last).toList();

  void expectCheckpoint(
    String tracker,
    int index,
    String action,
    double percent, {
    String id = 'tt5100000',
    bool movie = false,
    int season = 2,
    int episode = 3,
    String token = 'vplayer-synthetic-simkl',
    String apiKey = 'vplayer-synthetic-mdblist',
  }) {
    final request = forTracker(tracker)[index];
    expect(request.method, 'POST');
    expect(request.url.path, '/scrobble/$action');
    if (tracker == 'simkl') {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'api.simkl.com');
      expect(request.url.queryParameters, {
        'client_id': kSimklClientId,
        'app-name': kSimklAppName,
        'app-version': kSimklAppVersion,
      });
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.headers['simkl-api-key'], isNotEmpty);
      expect(jsonDecode(request.body), {
        movie ? 'movie' : 'show': {
          'ids': {'imdb': id},
        },
        if (!movie) 'episode': {'season': season, 'number': episode},
        'progress': percent,
      });
    } else {
      expect(
        request.url.toString(),
        'https://api.mdblist.com/scrobble/$action?apikey=$apiKey',
      );
      expect(jsonDecode(request.body), {
        movie ? 'movie' : 'show': {
          'ids': {'imdb': id},
          if (!movie) 'season': season,
          if (!movie) 'episode': episode,
        },
        'progress': double.parse(percent.toStringAsFixed(2)),
      });
    }
  }

  Future<void> waitCheckpoint(String tracker, int count) => f.until(
    t,
    () => forTracker(tracker).length >= count,
    reason: 'Original $tracker HTTP checkpoint must arrive',
  );

  Future<void> tick(Duration duration) async {
    await f.advance(t, duration);
    await drain();
  }

  Future<void> retired() async {
    await t.pumpWidget(const SizedBox.shrink());
    await drain();
  }
}

/// Delegates the complete Timer contract. Repeated cancellation remains a
/// no-op; only the first active cancellation is recorded for fan-out ordering.
class _ObservedTimer implements Timer {
  _ObservedTimer(this.delegate, this.onCancel);
  final Timer delegate;
  final void Function() onCancel;
  @override
  bool get isActive => delegate.isActive;
  @override
  int get tick => delegate.tick;
  @override
  void cancel() {
    if (isActive) onCancel();
    delegate.cancel();
  }
}
