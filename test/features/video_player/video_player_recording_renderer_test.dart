import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_renderer_test.dart' show RendererFixture;

class _RendererRecordingPaths extends VideoPlayerPaths {
  _RendererRecordingPaths(super.path);
  int reads = 0;
  final release = Completer<String?>();
  @override
  Future<String?> getDownloadsPath() async {
    reads++;
    return release.future;
  }
}

void main() {
  testWidgets(
    'p13 TEE directory start completing in the renderer gap cannot arm its captured player',
    (t) async {
      final h = RendererFixture(t, ios: true);
      _RendererRecordingPaths? paths;
      try {
        await h.mount(live: true);
        paths = _RendererRecordingPaths(h.f.directory.path);
        PathProviderPlatform.instance = paths;
        final dynamic callback = playerControls(t).onRecord;
        expect(callback, isNotNull);
        final pending =
            h.d.observe<dynamic>(() => callback()) as Future<dynamic>;
        await h.f.until(t, () => paths!.reads == 1);
        await h.fallback();
        final native = h.old.platform! as FakeNativePlayer;
        native.calls.clear();
        paths.release.complete(paths.path);
        await h.f.finish<dynamic>(t, pending);
        expect(
          native.calls.where(
            (call) =>
                call.$1 == 'setProperty' &&
                (call.$2 as (String, String)).$1 == 'stream-record',
          ),
          isEmpty,
        );
        expect(h.gate.isCompleted, isFalse);
        await h.release();
        expect(h.d.errors, isEmpty);
      } finally {
        if (paths != null && !paths.release.isCompleted) {
          paths.release.complete(paths.path);
        }
        await h.close();
      }
    },
  );
}
