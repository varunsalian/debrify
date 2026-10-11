import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'player_actions.dart';
import 'video_player_environment.dart';

VideoPlayerScreen skipScreen({
  String? id = 'tt4100000',
  String? type = 'series',
  int? season = 2,
  int? episode = 3,
  String title = 'Skip fixture',
  List<PlaylistEntry>? playlist,
}) => VideoPlayerScreen(
  videoUrl: 'https://player.test/skip.mp4',
  title: title,
  contentImdbId: id,
  contentType: type,
  contentSeason: season,
  contentEpisode: episode,
  playlist: playlist,
);

http.Response skipReply({
  double start = 10,
  double end = 30,
  bool outro = false,
}) => http.Response(
  jsonEncode({
    'segments': {
      outro ? 'outro' : 'intro': {
        'start_ms': (start * 1000).round(),
        'end_ms': (end * 1000).round(),
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

class SkipSegmentDriver {
  SkipSegmentDriver(this.t, this.f);
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  final held = <Completer<http.Response>>[];
  List<http.Request> get requests =>
      f.network.requests.where((r) => r.url.host == 'api.skipdb.tv').toList();

  SkipSegmentUiController get notifier =>
      t
              .widget<ValueListenableBuilder<SkipSegment?>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is ValueListenableBuilder<SkipSegment?> &&
                      w.valueListenable is SkipSegmentUiController,
                ),
              )
              .valueListenable
          as SkipSegmentUiController;

  Future<void> configure({
    bool enabled = true,
    String provider = 'skipdb',
    bool hold = false,
    bool seriesMetadata = false,
  }) async {
    await t.runAsync(() async {
      await SkipSegmentsStorage.setSkipSegmentsEnabled(enabled);
      await SkipSegmentsStorage.setSkipSegmentProvider(provider);
      if (seriesMetadata) await TVMazeService.clearCache();
    });
    f.network.handler = (request) {
      if (seriesMetadata && request.url.host == 'api.tvmaze.com') {
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/episodes')
                ? [
                    for (var n = 1; n <= 3; n++)
                      {'id': n, 'season': 1, 'number': n, 'name': 'Episode $n'},
                  ]
                : {
                    'id': 1,
                    'name': 'Fixture',
                    'externals': {'imdb': 'tt4100000'},
                    'genres': <String>[],
                  },
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host != 'api.skipdb.tv') return http.Response('{}', 404);
      if (!hold) return skipReply();
      final reply = Completer<http.Response>();
      held.add(reply);
      return reply.future;
    };
  }

  Future<void> position(Duration position) async {
    f.player.state = f.player.state.copyWith(position: position);
    f.player.emit('position', position);
    await f.advance(t);
  }

  Future<void> duration(Duration duration) async {
    f.player.state = f.player.state.copyWith(duration: duration);
    f.player.emit('duration', duration);
    await f.advance(t);
  }

  Future<void> tick([int seconds = 15]) => position(Duration(seconds: seconds));
  Future<void> release(int index, {http.Response? reply, Object? error}) async {
    if (error != null) {
      held[index].completeError(error);
    } else {
      held[index].complete(reply ?? skipReply());
    }
    await f.advance(t);
    await f.advance(t);
  }

  void expectQuery({
    String id = 'tt4100000',
    int season = 2,
    int episode = 3,
    int seconds = 1200,
    int index = 0,
  }) {
    expect(requests[index].url.queryParameters, {
      'imdb_id': id,
      'season': '$season',
      'episode': '$episode',
      'duration': '$seconds',
    });
  }

  void expectButton(bool visible, {bool outro = false}) {
    expect(
      find.byType(SkipSegmentButton),
      visible ? findsOneWidget : findsNothing,
    );
    if (visible) {
      expect(
        find.text('${outro ? 'Skip credits' : 'Skip intro'} »'),
        findsOneWidget,
      );
    }
  }

  Future<void> next() async {
    expect(playerControls(t).onNext, isNotNull);
    playerControls(t).onNext!();
    await f.advance(t);
  }

  void releaseAll() {
    for (final reply in held) {
      if (!reply.isCompleted) reply.complete(http.Response('{}', 404));
    }
  }
}
