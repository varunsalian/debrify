import 'dart:convert';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support/menu_metadata_driver.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'by id', 'Stremio guide']) {
    testWidgets(
      'P17 $route clears discovered single-file identity and re-arms the metadata lookup',
      (t) async {
        final d = _ChannelMetadataDriver(t);
        await d.setup();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Menu.Movie.2024.mkv',
              channelDirectory: route == 'by id' ? tvDirectory : null,
              requestChannelById: route == 'by id'
                  ? (id) async => {
                      'url': 'https://player.test/b.mp4',
                      'title': 'Other.Movie.2023.mkv',
                    }
                  : null,
              requestNextChannel: route == 'next'
                  ? () async => {
                      'url': 'https://player.test/b.mp4',
                      'title': 'Other.Movie.2023.mkv',
                    }
                  : null,
              stremioTvChannels: route == 'Stremio guide' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: route == 'Stremio guide'
                  ? (id) async => null
                  : null,
            ),
          );
          d.tracks();
          await d.f.until(t, () => d.pending.isNotEmpty);
          d.release();
          await d.f.until(
            t,
            () => d.logs.any(
              (v) => v.contains('Found IMDB ID "tt1300001" for single-file'),
            ),
          );
          await d.shown();
          d.panel.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          // The first menu took its snapshot while the eager lookup was held.
          // Reopen through the real caller after that lookup has completed.
          d.tracks();
          await d.shown();
          expect(d.panel.contentImdbId, 'tt1300001');
          d.panel.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          final before = d.pending.length;
          if (route == 'next') {
            final dynamic action = playerControls(t).onNextChannel!;
            await d.f.finish<dynamic>(t, d.observe<dynamic>(() => action()));
          } else {
            playerControls(t).onShowGuide!();
            await d.f.advance(t);
            if (route == 'by id') {
              final guide = t.widget<ChannelGuide>(find.byType(ChannelGuide));
              final dynamic action = guide.onChannelSelected;
              await d.f.finish<dynamic>(
                t,
                d.observe<dynamic>(() => action(guide.channels.last)),
              );
            } else {
              final dynamic action = t
                  .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
                  .onChannelSwitched;
              await d.f.finish<dynamic>(
                t,
                d.observe<dynamic>(
                  () => action(
                    'b',
                    'https://player.test/b.mp4',
                    'Other.Movie.2023.mkv',
                    contentType: 'movie',
                  ),
                ),
              );
            }
          }
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          d.observe(playerControls(t).onSpeed);
          await d.shown();
          expect(
            d.panel.contentImdbId,
            isNull,
            reason:
                'The quick menu must not inherit the outgoing discovered movie ID',
          );
          expect(d.pending, hasLength(before));
          d.panel.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          d.tracks();
          await d.f.until(t, () => d.pending.length > before);
          for (final response in d.pending.skip(before)) {
            if (!response.isCompleted) {
              response.complete(
                http.Response(
                  jsonEncode({
                    'metas': [
                      {
                        'id': 'tt1700002',
                        'name': 'Other Movie',
                        'year': '2023',
                        'type': 'movie',
                      },
                    ],
                  }),
                  200,
                ),
              );
            }
          }
          await d.f.until(
            t,
            () =>
                find.byType(PlayerMenuPanel).evaluate().isNotEmpty &&
                d.panel.contentImdbId == 'tt1700002',
          );
          expect(d.searches.last.toLowerCase(), contains('other'));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}

class _ChannelMetadataDriver extends MenuMetadataDriver {
  _ChannelMetadataDriver(super.t);
  final _captured = P17ObservedErrors();
  @override
  List<Object> get errors => _captured;
}
