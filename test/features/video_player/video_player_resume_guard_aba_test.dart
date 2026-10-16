import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final boundary in ['poll', 'confirmation']) {
    testWidgets(
      'Resume P14 $boundary abort delivery cannot retry after three held restores change guard A B A',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) {
            if (boundary == 'poll') {
              p.seekAcknowledgementPosition = Duration.zero;
            }
          },
        );
        await t.runAsync(f.initialize);
        final states = CompletionDelivery(
          'maybeRestoreResume',
          (v) => v is Map<String, dynamic> && v.containsKey('positionMs'),
        )..multiple = true;
        final verdict = CompletionDelivery(
          'verifyResumeLanding',
          (v) => v is bool,
        );
        final verifier = ResumeVerifierDriver(t, f);
        final sources = [
          for (final id in ['a', 'b', 'c'])
            source('P14 ABA $id.mkv', 'https://player.test/p14-aba-$id.mp4'),
        ];
        final tasks = <Future<dynamic>>[];
        try {
          for (final (id, pos) in [
            ('a', 120000),
            ('b', 300000),
            ('c', 240000),
          ]) {
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume('pikpak_aba-$id', {
                'positionMs': pos,
                'speed': 1.0,
                'aspect': 'contain',
              }),
            );
          }
          await verdict.run(
            () => verifier.observe(
              () => states.run(
                () => f.mount(
                  t,
                  VideoPlayerScreen(
                    videoUrl: sources[0].directUrl!,
                    title: sources[0].name,
                    playlist: [
                      PlaylistEntry(
                        url: sources[0].directUrl!,
                        title: sources[0].name,
                        provider: 'pikpak',
                        pikpakFileId: 'aba-a',
                      ),
                    ],
                    traktProgressPercent: 20,
                    stremioSources: sources,
                    stremioCurrentSourceIndex: 0,
                    resolveStremioSource: (s) async => s.directUrl,
                    resolveSourceToPlaylist: (s, {canContinue}) async => [
                      PlaylistEntry(
                        url: s.directUrl!,
                        title: s.name,
                        provider: 'pikpak',
                        pikpakFileId:
                            'aba-${sources.indexOf(s) == 1 ? 'b' : 'c'}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await f.until(t, () => states.pending.length == 1);
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          for (final index in [1, 2]) {
            if (index == 2) {
              playerControls(t).onShowStremioSources!();
              await f.advance(t, const Duration(milliseconds: 300));
            }
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final callback = sheet.onSourceSelected as dynamic;
            final url = (await f.finish(
              t,
              sheet.resolveSource(sources[index]),
            ))!;
            final task = verdict.run(
              () => verifier.observe(
                () => states.run(
                  () => f.actions.start('held source $index', () async {
                    final result = callback(index, url);
                    if (result is Future) await result;
                  }, held: true),
                ),
              ),
            );
            tasks.add(task.future);
            await f.until(t, () => states.pending.length == index + 1);
          }
          expect(
            f.player.state.playlist.medias.first.uri,
            sources[2].directUrl,
          );
          states.releaseAt(0);
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'seek').length == 1,
          );
          await f.until(t, () => verifier.pending);
          expect(
            verifier.timers.last.$1,
            Duration(milliseconds: boundary == 'poll' ? 200 : 800),
          );
          f.player.seekAcknowledgementPosition = Duration.zero;
          states.releaseAt(0);
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'seek').length == 2,
          );
          await f.advance(
            t,
            Duration(milliseconds: boundary == 'poll' ? 200 : 800),
          );
          await f.until(t, () => verdict.pending.isNotEmpty);
          expect(states.pending, hasLength(1));
          states.releaseAt(0);
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'seek').length == 3,
          );
          expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
            const Duration(minutes: 4),
            const Duration(minutes: 5),
            const Duration(minutes: 4),
          ]);
          verdict.release();
          await f.advance(t, const Duration(milliseconds: 200));
          expect(
            f.player.calls.where((c) => c.$1 == 'seek'),
            hasLength(3),
            reason:
                'The stopped verifier returns using its resolved abort verdict even though a later restore re-armed the same target',
          );
          await verifier.drain();
          for (final task in tasks) {
            await f.finish(t, task);
          }
        } finally {
          states.release();
          verdict.release();
          await t.pumpWidget(const SizedBox.shrink());
          await f.advance(t, const Duration(milliseconds: 800));
          await verifier.drain();
          for (final task in tasks) {
            await f.finish(t, task);
          }
          await f.close(t);
        }
      },
    );
  }
}
