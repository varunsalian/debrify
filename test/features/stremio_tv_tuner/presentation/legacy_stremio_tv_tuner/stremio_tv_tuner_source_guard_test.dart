import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dial ignores nested scroll-end notifications', () {
    final files = [
      File('lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart'),
      if (Directory('lib/features/stremio_tv_tuner').existsSync())
        ...Directory('lib/features/stremio_tv_tuner')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];
    expect(
      files.map((f) => f.readAsStringSync()).join('\n'),
      matches(r'n\.depth == 0 && n is ScrollEndNotification'),
      reason: 'dial scroll-end handling keeps its depth-zero source guard',
    );
  });

  test(
    'no playback, keep-alive or sibling-feature additions in facade or feature',
    () {
      final files = [
        File('lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart'),
        if (Directory('lib/features/stremio_tv_tuner').existsSync())
          ...Directory('lib/features/stremio_tv_tuner')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(
            matches(
              r'KeepAlive|AutomaticKeepAliveClientMixin|IndexedStack|package:media_kit|hero_trailer_backdrop|video_player_launcher|features/player_launch|features/stremio_tv/|features/stremio_tv_catalogs/',
            ),
          ),
          reason: file.path,
        );
      }
    },
  );
}
