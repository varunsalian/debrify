import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'player_actions.dart';
import 'trakt_transport.dart';
import 'video_player_environment.dart';

VideoPlayerScreen traktScreen({
  bool enabled = true,
  String? id = 'tt5100000',
  String? type = 'series',
  int? season = 2,
  int? episode = 3,
  double? percent,
  List<PlaylistEntry>? playlist,
}) => VideoPlayerScreen(
  videoUrl: playlist?.first.url ?? 'https://player.test/trakt.mp4',
  title: playlist?.first.title ?? 'Trakt fixture',
  contentImdbId: id,
  contentType: type,
  contentSeason: season,
  contentEpisode: episode,
  traktScrobble: enabled,
  traktProgressPercent: percent,
  playlist: playlist,
);

class TraktPlayerDriver {
  TraktPlayerDriver(this.t, this.f);
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  late TraktCipherReads cipher;
  final heartbeats = <Timer>[];
  final uncaught = <Object>[];
  List<http.Request> get requests => f.network.requests
      .where(
        (r) =>
            r.url.host == 'api.trakt.tv' && r.url.path.startsWith('/scrobble/'),
      )
      .toList();
  List<String> get actions =>
      requests.map((r) => r.url.path.split('/').last).toList();
  List<Duration> get seeks => f.player.calls
      .where((c) => c.$1 == 'seek')
      .map((c) => c.$2 as Duration)
      .toList();

  Future<void> initialize({bool target = true}) async {
    await t.runAsync(f.initialize);
    TraktTestTransport.instance.attach(f);
    cipher = (await t.runAsync(() => seedTrakt(target: target)))!;
    f.network.handler = traktReply;
  }

  Future<void> drain() async {
    await f.actions.settle(t);
    expect(
      uncaught,
      isEmpty,
      reason: 'Normal original playback must emit no uncaught error',
    );
  }

  Future<void> mount(VideoPlayerScreen screen) async {
    // Make the original init completion arrive after playing/duration, rather
    // than depending on SQLite/decryption scheduling to choose that ordering.
    cipher.hold = true;
    await runZoned(
      () => f.mount(t, screen),
      zoneSpecification: ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stack) {
          // Keep the error as an asserted observable; init/error cases use
          // their independent guarded mount and pin the expected failure.
          uncaught.add(error);
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createPeriodicTimer(zone, duration, callback);
          // Analytics is four minutes; resume saves are six seconds. Only
          // Trakt's periodic checkpoint is two minutes in these Trakt cases.
          if (duration == const Duration(minutes: 2)) heartbeats.add(timer);
          return timer;
        },
      ),
    );
    expect(requests, isEmpty);
    cipher.releaseAll();
    await drain();
  }

  Future<void> position(int milliseconds) async {
    f.player.state = f.player.state.copyWith(
      position: Duration(milliseconds: milliseconds),
    );
    f.player.emit('position', f.player.state.position);
    await f.advance(t);
  }

  Future<void> playing(bool value) async {
    value ? await f.player.play() : await f.player.pause();
    await drain();
  }

  Future<void> seek(double fraction) async {
    final controls = playerControls(t);
    controls.onSeekBarChanged(fraction);
    await f.advance(t);
    expect(
      () => runZoned(
        controls.onSeekBarChangeEnd,
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            if (duration == const Duration(minutes: 2)) heartbeats.add(timer);
            return timer;
          },
        ),
      ),
      returnsNormally,
      reason: 'The original seek-completion callback must return normally',
    );
    await drain();
  }

  void expectRequest(
    int index,
    String action,
    double percent, {
    String id = 'tt5100000',
    bool movie = false,
    int season = 2,
    int episode = 3,
    String token = 'vplayer-synthetic-access',
  }) {
    final request = requests[index];
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.trakt.tv/scrobble/$action');
    expect(request.headers['authorization'], 'Bearer $token');
    expect(request.headers['trakt-api-version'], '2');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body, {
      movie ? 'movie' : 'show': {
        'ids': {'imdb': id},
      },
      if (!movie) 'episode': {'season': season, 'number': episode},
      'progress': percent,
    });
  }

  Future<void> close() async {
    cipher.releaseAll();
    await f.close(t);
    TraktTestTransport.instance.recorder = null;
  }
}
