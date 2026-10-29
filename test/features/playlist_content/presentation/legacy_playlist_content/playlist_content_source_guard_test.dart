import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

void main() {
  test(
    'both caller constructions preserve dialog-popping callback ownership',
    () {
      final playlist = File(
        'lib/screens/playlist_screen.dart',
      ).readAsStringSync();
      expect(
        compact(playlist),
        contains(
          'PlaylistContentViewScreen(playlistItem:item,onPlaybackStarted:()=>Navigator.of(context).pop(),)',
        ),
      );
      final home = File(
        'lib/features/home/presentation/home_playlist_actions.dart',
      ).readAsStringSync();
      expect(
        compact(home),
        contains('PlaylistContentViewScreen(playlistItem:item)'),
      );
    },
  );
  test('series cache clear also clears the transitive TVMaze series cache', () {
    expect(
      File('lib/services/episode_info_service.dart').readAsStringSync(),
      contains('await TVMazeService.clearSeriesCache(seriesTitle)'),
    );
  });
}
