import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';
import 'support/player_actions.dart';
import 'support/startup_driver.dart';

void main() {
  for (final external in [false, true]) {
    for (final rejected in [false, true]) {
      testWidgets(
        'P16 source ${rejected ? 'rollback' : 'success'} ${external ? 'reattaches split audio without subtitle reset' : 'resets addon subtitle files'}',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          debugPrint = (message, {wrapWidth}) {
            if (message != null) d.logs.add(message);
            d.oldPrint(message, wrapWidth: wrapWidth);
          };
          final a = startupSource('external-a', headers: {'X-Outgoing': 'a'}),
              b = startupSource('external-b', headers: {'X-Incoming': 'b'});
          const audio = 'https://startup.test/audio.m4a';
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: a.directUrl!,
                title: 'P16 external',
                httpHeaders: a.httpHeaders,
                audioUrl: external ? audio : null,
                stremioSources: [a, b],
                resolveStremioSource: (s) async => s.directUrl,
              ),
            );
            expect(await d.addon('preserved'), isTrue);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await d.f.advance(t);
            final files = d.f.directory
                .listSync()
                .whereType<File>()
                .where((f) => f.path.contains('stremio_sub_'))
                .toList();
            expect(files, hasLength(1));
            expect(files.single.readAsStringSync(), contains('Caption'));
            await d.player.seek(const Duration(seconds: 37));
            await d.f.advance(t);
            final before = d.player.calls.length;
            if (rejected) {
              d.player.failures['open'] = StateError('fixture open failed');
            }
            playerControls(t).onShowStremioSources!();
            await d.f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final action = d.f.actions.start(
              'split audio source choice',
              () async {
                final dynamic choose = sheet.onSourceSelected;
                final dynamic result = choose(1, b.directUrl!);
                if (result is Future) await result;
              },
            );
            await d.f.finish(t, action.future);
            await d.f.actions.settle(t);
            final calls = d.player.calls.skip(before).toList();
            final opens = calls
                .where((v) => v.$1 == 'open')
                .map((v) => v.$2 as (mk.Playable, bool))
                .toList();
            expect(
              opens.map((v) => (v.$1 as mk.Media).uri),
              rejected ? [b.directUrl, a.directUrl] : [b.directUrl],
            );
            expect(opens.first.$2, !external);
            expect(files.single.existsSync(), external);
            if (external) {
              final attach = calls.indexWhere(
                (v) => v.$1 == 'audio' && (v.$2 as mk.AudioTrack).id == audio,
              );
              final seek = calls.indexWhere((v) => v.$1 == 'seek');
              expect(attach, isNonNegative);
              expect(seek, greaterThan(attach));
              if (!rejected) {
                expect(
                  calls.indexWhere((v) => v.$1 == 'play'),
                  greaterThan(seek),
                );
              }
              expect(files.single.readAsStringSync(), contains('Caption'));
            }
            expect(
              d.player.state.playlist.medias.single.uri,
              rejected ? a.directUrl : b.directUrl,
            );
            expect(d.player.state.position, const Duration(seconds: 37));
            expect(
              find.text('This source is unavailable. Choose another source.'),
              rejected ? findsOneWidget : findsNothing,
            );
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
  for (final variant in [
    'new direct',
    'restored outgoing',
    'restored outgoing after pack rejection',
  ]) {
    final rejected = variant != 'new direct';
    final pack = variant == 'restored outgoing after pack rejection';
    testWidgets(
      'P16 $variant source restores saved audio and subtitle choices without awaiting the subtitle acknowledgement',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        debugPrint = (message, {wrapWidth}) {
          if (message != null) d.logs.add(message);
          d.oldPrint(message, wrapWidth: wrapWidth);
        };
        final a = startupSource('prefs-a'), b = startupSource('prefs-b');
        const title = 'P16 saved source tracks';
        final ack = Completer<void>();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: title,
              stremioSources: [a, b],
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: pack
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: s.directUrl!, title: s.name),
                    ]
                  : null,
            ),
          );
          final menu = await d.menu();
          await d.f.finish(t, d.observe(() => menu.onAudioSelected('2', '1')));
          await d.f.actions.settle(t);
          expect(await d.select('3', panel: menu, audio: '2'), isTrue);
          final stored = await d.saved(title: title);
          expect(stored?['audioTrackId'], '2');
          expect(stored?['subtitleTrackId'], '3');
          menu.onClose();
          await d.f.advance(t);
          await d.player.seek(const Duration(seconds: 37));
          await d.f.advance(t);
          final restores = d.logs
              .where((s) => s.contains('restore done —'))
              .length;
          d.player.onOpen = () {
            d.player.publishFrame();
            d.publish(selected: '1');
            d.f.controllers.last.publishFrame();
          };
          if (rejected) {
            d.player.failures['open'] = StateError('fixture source rejection');
          }
          if (pack) {
            // The ordinary video checkpoint replaces its whole row, including
            // track preferences. Keep this real transient-duration window
            // separate so the saved-choice restoration itself is observable.
            d.player.state = d.player.state.copyWith(duration: Duration.zero);
            d.player.emit('duration', Duration.zero);
            await d.f.advance(t);
            expect((await d.saved(title: title))?['subtitleTrackId'], '3');
          }
          d.player.delays['subtitle'] = ack;
          final before = d.player.calls.where((c) => c.$1 == 'subtitle').length;
          playerControls(t).onShowStremioSources!();
          await d.f.advance(t, const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final selectedUrl = (await d.f.finish(t, sheet.resolveSource(b)))!;
          final action = d.observe(
            () =>
                d.f.actions.start('source preference restore caller', () async {
                  final dynamic callback = sheet.onSourceSelected;
                  final dynamic result = callback(1, selectedUrl);
                  if (result is Future) await result;
                }, held: true),
          );
          await d.f.until(
            t,
            () =>
                d.player.calls.where((c) => c.$1 == 'subtitle').length > before,
          );
          expect(ack.isCompleted, isFalse);
          expect(
            action.isCompleted,
            isTrue,
            reason:
                'Stored preferences restore in the background after the source callback returns',
          );
          expect(d.player.state.track.subtitle.id, '1');
          expect(
            d.player.state.playlist.medias.single.uri,
            rejected ? a.directUrl : b.directUrl,
          );
          ack.complete();
          await d.f.finish(t, action.future);
          await d.f.until(
            t,
            () =>
                d.player.state.track.audio.id == '2' &&
                d.player.state.track.subtitle.id == '3' &&
                d.logs.where((s) => s.contains('restore done —')).length >
                    restores,
          );
          expect(d.player.state.track.audio.language, 'spa');
          expect(d.player.state.track.subtitle.language, 'fra');
          final saved = await d.saved(title: title);
          expect(saved?['audioTrackId'], '2');
          expect(saved?['subtitleTrackId'], '3');
          expect(d.errors, isEmpty);
        } finally {
          ack.completeIfPending();
          await d.close();
        }
      },
    );
  }
  for (final boundary in ['readiness', 'play', 'rollback audio']) {
    testWidgets(
      'P16 split-audio source selection waits at the real $boundary boundary before its later calls and commit',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('split-boundary-a'),
            b = startupSource('split-boundary-b');
        final ack = Completer<void>();
        try {
          await d.begin(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: a.name,
              audioUrl: 'https://startup.test/shared.m4a',
              stremioSources: [a, b],
              resolveStremioSource: (s) async => s.directUrl,
              onStremioSourceCommitted: (s) async => d.commits.add(s),
            ),
          );
          await d.initialized();
          expect(d.commits, isEmpty);
          await d.player.seek(const Duration(seconds: 37));
          await d.tick();
          if (boundary == 'readiness') {
            d.openGates[b.directUrl!] = ack;
            d.replies[b.directUrl!] = (p) {
              p.state = p.state.copyWith(
                duration: Duration.zero,
                width: 0,
                height: 0,
                position: Duration.zero,
              );
              p.emit('duration', Duration.zero);
              p.emit<int?>('width', 0);
              p.emit('position', Duration.zero);
            };
          } else if (boundary == 'play') {
            d.player.delays['play'] = ack;
          } else {
            d.openFailures[b.directUrl!] = StateError(
              'fixture split candidate rejection',
            );
            d.player.delays['audio'] = ack;
          }
          final beforeAudio = d.player.calls
              .where((c) => c.$1 == 'audio')
              .length;
          final beforePlay = d.player.calls.where((c) => c.$1 == 'play').length;
          final beforeSeek = d.player.calls.where((c) => c.$1 == 'seek').length;
          final sheet = await d.sheet();
          final action = d.select(sheet, 1, b.directUrl!);
          if (boundary == 'readiness') {
            await d.openEntered(2);
            d.player.state = d.player.state.copyWith(duration: Duration.zero);
            d.player.emit('duration', Duration.zero);
            await d.tick();
            expect(ack.isCompleted, isFalse);
            ack.complete();
            await d.f.until(
              t,
              () => d.trace.contains('open-ack:${b.directUrl!}'),
            );
            await d.tick(const Duration(milliseconds: 100));
            expect(action.isCompleted, isFalse);
            expect(
              d.player.calls.where((c) => c.$1 == 'audio'),
              hasLength(beforeAudio),
            );
            expect(d.player.state.playing, isFalse);
            expect(d.commits, isEmpty);
            d.frame();
          } else if (boundary == 'play') {
            await d.f.until(
              t,
              () =>
                  d.player.calls.where((c) => c.$1 == 'play').length >
                  beforePlay,
            );
            expect(action.isCompleted, isFalse);
            expect(d.player.state.playing, isFalse);
            expect(d.commits, isEmpty);
          } else {
            await d.f.until(
              t,
              () =>
                  d.player.calls.where((c) => c.$1 == 'audio').length >
                  beforeAudio,
            );
            expect(action.isCompleted, isFalse);
            expect(d.player.state.playlist.medias.single.uri, a.directUrl);
            expect(
              d.player.calls.where((c) => c.$1 == 'seek'),
              hasLength(beforeSeek),
            );
            expect(d.commits, isEmpty);
          }
          ack.completeIfPending();
          await d.f.finish(t, action.future);
          expect(d.player.state.playing, isTrue);
          expect(d.player.state.position, const Duration(seconds: 37));
          expect(
            d.player.state.playlist.medias.single.uri,
            boundary == 'rollback audio' ? a.directUrl : b.directUrl,
          );
          expect(d.commits, boundary == 'rollback audio' ? isEmpty : [b]);
          expect(d.errors, isEmpty);
        } finally {
          ack.completeIfPending();
          await d.close();
        }
      },
    );
  }
}
