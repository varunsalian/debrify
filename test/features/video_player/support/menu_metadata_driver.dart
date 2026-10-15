import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'player_actions.dart';
import 'subtitle_apply_driver.dart';

class MenuMetadataDriver extends SubtitleApplyDriver {
  MenuMetadataDriver(super.t);
  final pending = <Completer<http.Response>>[];
  final searches = <String>[];
  Future<void> setup() async {
    await initialize();
    MovieMetadataService.clearCache();
    f.network.handler = (r) {
      if (r.url.host == 'v3-cinemeta.strem.io') {
        if (r.url.path == '/manifest.json') return http.Response('{}', 200);
        searches.add(r.url.path);
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      }
      return f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
    };
  }

  Future<void> mountMovies() async {
    await mount(
      screen: VideoPlayerScreen(
        videoUrl: 'https://player.test/menu-one.mp4',
        title: 'Menu.Movie.2024.mkv',
        disableAutoResume: true,
        startIndex: 0,
        playlist: [
          PlaylistEntry(
            url: 'https://player.test/menu-one.mp4',
            title: 'Menu.Movie.2024.mkv',
          ),
          PlaylistEntry(
            url: 'https://player.test/menu-two.mp4',
            title: 'Other.Movie.2023.mkv',
          ),
        ],
      ),
    );
    await f.until(t, () => pending.isNotEmpty);
  }

  void tracks() => observe(() => playerControls(t).onShowTracks());
  PlayerMenuPanel get panel =>
      t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  http.Response metadata({String id = 'tt1300001', bool success = true}) =>
      http.Response(
        jsonEncode({
          'metas': success
              ? [
                  {
                    'id': id,
                    'name': 'Menu Movie',
                    'year': '2024',
                    'type': 'movie',
                  },
                ]
              : [],
        }),
        200,
      );
  Future<void> shown() =>
      f.until(t, () => find.byType(PlayerMenuPanel).evaluate().isNotEmpty);
  void release({bool success = true}) {
    for (final response in pending) {
      if (!response.isCompleted) response.complete(metadata(success: success));
    }
  }

  @override
  Future<void> close() async {
    release(success: false);
    if (f.navigator.currentState?.canPop() ?? false) {
      f.navigator.currentState!.pop();
      await f.advance(t, const Duration(milliseconds: 350));
    }
    await super.close();
    MovieMetadataService.clearCache();
  }
}
