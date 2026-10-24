import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

final _wakeDrain = Object();

const _open = 'SourceSelect: event=media_server_open ';
const _error = 'SourceSelect: event=media_server_player_error ';

/// A media-server launch with the screen's own print capture.
Future<void> _server(
  WidgetTester t,
  Future<void> Function(
    VideoPlayerEnvironment f,
    List<String> logs,
    ResumeServerDriver server,
  )
  body,
) async {
  final f = VideoPlayerEnvironment();
  await t.runAsync(f.initialize);
  final server = ResumeServerDriver(t, f);
  final logs = <String>[];
  final oldPrint = debugPrint;
  debugPrint = (String? line, {int? wrapWidth}) {
    if (line != null) logs.add(line);
  };
  try {
    await server.prepare();
    await f.mount(t, server.screen());
    await f.actions.settle(t);
    await body(f, logs, server);
  } finally {
    debugPrint = oldPrint;
    await f.close(t);
    await f.advance(t, const Duration(milliseconds: 800));
    server.restoreFactories();
    late Future<void> pending;
    await t.runAsync(() async {
      pending = PlayerDisplayControls.instance.setWakelockOwner(
        _wakeDrain,
        false,
      );
    });
    await f.finish<void>(t, pending);
  }
}

void main() {
  testWidgets('P20 a media-server source logs its open once, before the open', (
    t,
  ) async {
    await _server(t, (f, logs, _) async {
      final opens = logs.where((l) => l.startsWith(_open)).toList();
      expect(opens, hasLength(1));
      expect(opens.single, endsWith(' player=mpv'));
      expect(opens.single, isNot(contains('sourceId=null')));
    });
  });

  for (final (message, reason) in [
    ('HTTP error 403 Forbidden', 'http_auth'),
    ('Connection timed out', 'timeout'),
    ('generic failure', 'player_error'),
  ]) {
    testWidgets(
      'P20 a media-server player error is logged by category ($reason) without its text',
      (t) async {
        await _server(t, (f, logs, _) async {
          f.player.emit('error', message);
          await f.advance(t);
          final errors = logs.where((l) => l.startsWith(_error)).toList();
          expect(errors, hasLength(1));
          expect(errors.single, contains(' reason=$reason '));
          expect(errors.single, isNot(contains(message)));
        });
      },
    );
  }

  testWidgets(
    'P20 a plain URL logs neither a media-server open nor a player error',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        d.player.emit('error', 'HTTP error 403 Forbidden');
        await d.f.advance(t);
        expect(
          d.logs.where((l) => l.startsWith(_open) || l.startsWith(_error)),
          isEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 media-server open and error lines are single key=value fields ending in player=mpv',
    (t) async {
      await _server(t, (f, logs, _) async {
        f.player.emit('error', 'HTTP error 404 Not Found');
        await f.advance(t);
        for (final prefix in [_open, _error]) {
          final lines = logs.where((l) => l.startsWith(prefix)).toList();
          expect(lines, hasLength(1), reason: prefix);
          final fields = lines.single.split(' ').skip(1).toList();
          expect(fields.where((w) => !w.contains('=')), isEmpty);
          expect(fields.last, 'player=mpv');
        }
      });
    },
  );

  testWidgets(
    'P20 a pause edge reports the paused position to the server session without a further position tick',
    (t) async {
      await _server(t, (f, logs, server) async {
        f.player.emit('position', const Duration(seconds: 1));
        await f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
        );
        final before = server.reports.length;
        f.player.state = f.player.state.copyWith(playing: false);
        f.player.emit('playing', false);
        await f.advance(t, const Duration(seconds: 1));
        await f.actions.settle(t);
        final after = server.reports.skip(before).toList();
        expect(after.map((r) => r.url.path), [
          endsWith('/Sessions/Playing/Progress'),
        ]);
        expect(server.body(after.single)['IsPaused'], isTrue);
        expect(server.body(after.single)['PositionTicks'], 10000000);
      });
    },
  );
}
