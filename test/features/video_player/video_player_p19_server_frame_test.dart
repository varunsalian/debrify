import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

final _wakeDrain = Object();

const _firstFrame = 'SourceSelect: event=media_server_first_frame ';

void main() {
  testWidgets(
    'P19 a media-server source logs its first frame once per opened media',
    (t) async {
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
        final frames = logs.where((l) => l.startsWith(_firstFrame)).toList();
        expect(frames, hasLength(1));
        final fields = frames.single.split(' ').skip(1).toList();
        expect(fields.first, 'event=media_server_first_frame');
        expect(
          fields.where((w) => !w.contains('=')),
          isEmpty,
          reason: 'every field is a single key=value token',
        );
        expect(frames.single, endsWith(' player=mpv'));
        expect(frames.single, isNot(contains('sourceId=null')));
        f.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        f.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        f.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await f.advance(t, const Duration(seconds: 1));
        expect(logs.where((l) => l.startsWith(_firstFrame)), hasLength(1));
      } finally {
        debugPrint = oldPrint;
        await f.close(t);
        await f.advance(t, const Duration(milliseconds: 800));
        server.restoreFactories();
        // As EngineDriver.close: leave the shared wakelock queue's cursor in
        // the real zone so later cases in this isolate do not stall.
        late Future<void> pending;
        await t.runAsync(() async {
          pending = PlayerDisplayControls.instance.setWakelockOwner(
            _wakeDrain,
            false,
          );
        });
        await f.finish<void>(t, pending);
      }
    },
  );

  testWidgets('P19 a plain URL never logs a media-server first frame', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
      await d.f.advance(t, const Duration(seconds: 1));
      expect(d.logs.where((l) => l.startsWith(_firstFrame)), isEmpty);
    } finally {
      await d.close();
    }
  });
}
