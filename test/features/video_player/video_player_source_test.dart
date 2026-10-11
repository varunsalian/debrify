import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

Torrent source(String name, String url) => Torrent(
  rowid: 0,
  infohash: '',
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'fixture',
  streamType: StreamType.directUrl,
  directUrl: url,
);

void main() {
  for (final playlist in [false, true]) {
    testWidgets(
      'manual ${playlist ? 'playlist' : 'direct'} source rejection restores outgoing media and position',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        final original = source('Original', 'https://player.test/original.mp4');
        final rejected = source('Rejected', 'https://player.test/rejected.mp4');
        final committed = <Torrent>[];
        final diagnostics = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) diagnostics.add(message);
        };
        try {
          await fixture.mount(
            tester,
            VideoPlayerScreen(
              videoUrl: original.directUrl!,
              title: 'Original',
              playlist: playlist
                  ? [
                      PlaylistEntry(
                        url: original.directUrl!,
                        title: original.name,
                      ),
                    ]
                  : null,
              stremioSources: [original, rejected],
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (candidate) async => candidate.directUrl,
              resolveSourceToPlaylist: playlist
                  ? (candidate, {canContinue}) async => [
                      PlaylistEntry(
                        url: candidate.directUrl!,
                        title: candidate.name,
                      ),
                    ]
                  : null,
              onStremioSourceCommitted: (candidate) async =>
                  committed.add(candidate),
            ),
          );
          await fixture.player.seek(const Duration(minutes: 5));
          await fixture.advance(tester, const Duration(milliseconds: 200));
          fixture.player.onOpen = () {
            final url = fixture.player.state.playlist.medias.first.uri;
            if (url == rejected.directUrl) {
              fixture.player.state = fixture.player.state.copyWith(
                duration: Duration.zero,
                videoParams: const mk.VideoParams(),
                width: 0,
                height: 0,
              );
              fixture.player.emit('error', 'Failed to open media: HTTP 404');
            } else {
              fixture.player.publishFrame();
              fixture.controllers.last.publishFrame();
            }
          };
          playerControls(tester).onShowStremioSources!();
          await fixture.advance(tester, const Duration(milliseconds: 300));
          final sheet = tester.widget<SourceSheet>(find.byType(SourceSheet));
          final url = await fixture.finish(
            tester,
            sheet.resolveSource(rejected),
          );
          expect(url, rejected.directUrl);
          sheet.onSourceSelected(1, url!);
          await fixture.until(
            tester,
            () => find
                .text('This source is unavailable. Choose another source.')
                .evaluate()
                .isNotEmpty,
            reason: 'Original validator rejects the explicit candidate',
          );
          expect(
            fixture.player.state.playlist.medias.single.uri,
            original.directUrl,
          );
          expect(fixture.player.state.playing, isTrue);
          expect(fixture.player.state.position, const Duration(minutes: 5));
          expect(committed, isNot(contains(rejected)));
          if (!playlist) {
            expect(
              diagnostics,
              contains(
                'Player: manual Stremio source rejected (_ManualSourceValidationFailure)',
              ),
            );
          }
          final opens = fixture.player.calls
              .where((call) => call.$1 == 'open')
              .map(
                (call) => ((call.$2 as (mk.Playable, bool)).$1 as mk.Media).uri,
              )
              .toList();
          expect(opens, [
            original.directUrl,
            rejected.directUrl,
            original.directUrl,
          ]);
          playerControls(tester).onShowStremioSources!();
          await fixture.advance(tester, const Duration(milliseconds: 300));
          expect(
            tester
                .widget<SourceSheet>(find.byType(SourceSheet))
                .currentSourceIndex,
            0,
          );
        } finally {
          try {
            await fixture.close(tester);
          } finally {
            debugPrint = previousDebugPrint;
          }
        }
      },
    );
  }
}
