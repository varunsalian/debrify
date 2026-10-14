import 'dart:io';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  for (final caller in [
    'magic next',
    'next channel',
    'guide channel',
    'Stremio guide',
    'raw playlist',
    'direct source',
  ]) {
    testWidgets(
      'subtitle $caller retained reset deletes its outgoing addon file before reopening media',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final first = source('First.mkv', 'https://player.test/first.mp4');
        final second = source('Second.mkv', 'https://player.test/second.mp4');
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: first.directUrl!,
              title: 'Reset original',
              requestMagicNext: caller == 'magic next'
                  ? () async => {'url': second.directUrl!, 'title': 'Next'}
                  : null,
              requestNextChannel: caller == 'next channel'
                  ? () async => {
                      'firstUrl': second.directUrl!,
                      'firstTitle': 'Next',
                    }
                  : null,
              requestChannelById: caller == 'guide channel'
                  ? (id) async => {
                      'firstUrl': second.directUrl!,
                      'firstTitle': 'Next',
                    }
                  : null,
              channelDirectory: caller == 'guide channel'
                  ? [
                      {'id': 'a', 'name': 'A'},
                      {'id': 'b', 'name': 'B'},
                    ]
                  : null,
              stremioTvChannels: caller == 'Stremio guide'
                  ? [
                      {'id': 'a', 'name': 'A'},
                      {'id': 'b', 'name': 'B'},
                    ]
                  : null,
              stremioTvCurrentChannelId: caller == 'Stremio guide' ? 'a' : null,
              stremioTvChannelSwitchProvider: caller == 'Stremio guide'
                  ? (id) async => null
                  : null,
              viewMode: caller == 'raw playlist' ? PlaylistViewMode.raw : null,
              playlist: caller == 'raw playlist'
                  ? [
                      PlaylistEntry(url: first.directUrl!, title: 'First'),
                      PlaylistEntry(url: second.directUrl!, title: 'Second'),
                    ]
                  : null,
              stremioSources: caller == 'direct source'
                  ? [first, second]
                  : null,
              stremioCurrentSourceIndex: caller == 'direct source' ? 0 : null,
              resolveStremioSource: caller == 'direct source'
                  ? (s) async => s.directUrl
                  : null,
            ),
          );
          expect(
            await d.addon('outgoing-${caller.replaceAll(' ', '-')}'),
            isTrue,
          );
          final file = File(d.player.state.track.subtitle.id);
          expect(file.existsSync(), isTrue);
          expect(d.player.state.track.subtitle.uri, isTrue);
          (await d.menu()).onClose();
          await d.f.advance(t);
          d.player.onOpen = () {
            d.player.publishFrame();
            d.f.controllers.last.publishFrame();
          };
          if (caller == 'magic next' || caller == 'raw playlist') {
            final dynamic next = playerControls(t).onNext!;
            await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          } else if (caller == 'next channel') {
            final dynamic next = playerControls(t).onNextChannel!;
            await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          } else if (caller == 'guide channel') {
            playerControls(t).onShowGuide!();
            await d.f.until(
              t,
              () => find.byType(ChannelGuide).evaluate().isNotEmpty,
            );
            final guide = t.widget<ChannelGuide>(find.byType(ChannelGuide));
            d.observe(() => guide.onChannelSelected(guide.channels.last));
          } else if (caller == 'Stremio guide') {
            playerControls(t).onShowGuide!();
            await d.f.until(
              t,
              () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
            );
            final guide = t.widget<StremioTvGuideSheet>(
              find.byType(StremioTvGuideSheet),
            );
            d.observe(
              () => guide.onChannelSwitched('b', second.directUrl!, 'Next'),
            );
          } else {
            playerControls(t).onShowStremioSources!();
            await d.f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final url = await d.f.finish(t, sheet.resolveSource(second));
            final dynamic selected = d.observe<dynamic>(
              () => (sheet.onSourceSelected as dynamic)(1, url!),
            );
            if (selected is Future) {
              await d.f.finish<dynamic>(t, selected);
            }
          }
          await d.f.until(
            t,
            () => d.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          expect(file.existsSync(), isFalse);
          expect(d.f.directory.existsSync(), isTrue);
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
}
