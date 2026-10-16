import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:http/http.dart' as http;
import 'support/trakt_transport.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';

import 'support/local_completion_driver.dart';
import 'support/startup_driver.dart';

void main() {
  TraktTestTransport.install();
  for (final playlist in [false, true]) {
    for (final boundary in [
      'pause',
      'open acknowledgement',
      if (playlist) 'checkpoint',
    ]) {
      testWidgets(
        'P16 ${playlist ? 'playlist' : 'direct'} selection disposal at $boundary drains before any post-disposal source commit',
        (t) async {
          final d = StartupDriver(t, autoFrame: true);
          await d.initialize();
          final a = startupSource('await-a'), b = startupSource('await-b');
          final gate = Completer<void>();
          final checkpoint = CompletionDelivery(
            'switchToSourcePlaylist',
            (v) => v == null,
          );
          checkpoint.armed = boundary == 'checkpoint';
          try {
            await d.begin(
              d.screen(
                sources: [a, b],
                resolve: (s) async => s.directUrl,
                playlist: playlist
                    ? (s, {canContinue}) async => [
                        PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                      ]
                    : null,
              ),
            );
            await d.initialized();
            final sheet = await d.sheet();
            final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
            if (boundary == 'pause') d.player.delays['pause'] = gate;
            if (boundary == 'open acknowledgement') {
              d.openGates[b.directUrl!] = gate;
            }
            final pauses = d.player.calls.where((c) => c.$1 == 'pause').length;
            final action = checkpoint.run(() => d.select(sheet, 1, url));
            await d.f.until(
              t,
              () => boundary == 'checkpoint'
                  ? checkpoint.pending.isNotEmpty
                  : boundary == 'pause'
                  ? d.player.calls.where((c) => c.$1 == 'pause').length > pauses
                  : d.opens.length == 2,
            );
            expect(action.isCompleted, isFalse);
            expect(d.commits, [a]);
            if (boundary == 'open acknowledgement') {
              d.frame();
              await d.result(count: 2);
            }
            await t.pumpWidget(const SizedBox.shrink());
            await d.f.until(t, () => d.player.disposed.isCompleted);
            gate.complete();
            checkpoint.release();
            await d.f.finish(t, action.future);
            expect(
              d.opens,
              hasLength(boundary == 'open acknowledgement' ? 2 : 1),
            );
            expect(d.commits, [a]);
            expect(d.activeProbes, isEmpty);
            expect(d.errors, isEmpty);
          } finally {
            gate.completeIfPending();
            checkpoint.release();
            await d.close();
          }
        },
      );
    }
  }
  testWidgets(
    'P16 the live source callback remains pending until the IPTV owner acknowledges and validates its open',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('live-await-a'),
          b = startupSource('live-await-b');
      final ack = d.openGates[b.directUrl!] = Completer<void>();
      TraktTestTransport.instance.attach(d.f);
      const manifest = 'https://p16-await-addon.test/manifest.json';
      d.f.network.replies[manifest] = http.Response(
        jsonEncode({
          'id': 'p16-await',
          'name': 'P16 await',
          'version': '1.0.0',
          'types': ['tv'],
          'resources': ['stream'],
          'catalogs': [],
        }),
        200,
      );
      d.f.network.replies['https://p16-await-addon.test/stream/tv/live.json'] =
          http.Response(
            jsonEncode({
              'streams': [
                {'url': a.directUrl, 'name': 'A'},
                {'url': b.directUrl, 'name': 'B'},
              ],
            }),
            200,
          );
      final addon = await d.f.finish(
        t,
        StremioService.instance.addAddon(manifest),
      );
      final key = StremioIptvService.buildChannelKey(addon.id, 'live');
      StremioIptvService.instance.invalidate(key);
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 live await',
            iptvChannels: [
              IptvChannel(name: 'Live', url: key, contentType: 'live'),
            ],
            iptvStartIndex: 0,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.initialized();
        final floating = find.byWidgetPredicate(
          (w) => w is IptvZapBanner && !w.flush,
        );
        expect(floating, findsOneWidget);
        final sheet = await d.sheet();
        final banner = t.widget<AnimatedOpacity>(
          find
              .ancestor(of: floating, matching: find.byType(AnimatedOpacity))
              .first,
        );
        expect(banner.opacity, 0);
        final choose = d.select(sheet, 1, b.directUrl!);
        await d.openEntered(2);
        await d.tick();
        expect(ack.isCompleted, isFalse);
        expect(choose.isCompleted, isFalse);
        expect(find.byType(SourceSheet), findsNothing);
        ack.complete();
        await d.f.until(t, () => d.trace.contains('open-ack:${b.directUrl}'));
        d.frame();
        await d.f.finish(t, choose.future);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        expect(d.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
      } finally {
        ack.completeIfPending();
        StremioIptvService.instance.invalidate(key);
        await d.f.finish(
          t,
          StremioService.instance.removeAddon(addon.storageKey),
        );
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );
  for (final mode in ['direct', 'playlist', 'pack restoring direct']) {
    final playlist = mode == 'playlist';
    final pack = mode != 'direct';
    testWidgets(
      'P16 $mode rejected source disposal while outgoing reopen acknowledges preserves its distinct late-seek behaviour',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('late-restore-a'),
            b = startupSource('late-restore-b');
        final ack = Completer<void>();
        final landing = Completer<void>();
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              entries: playlist
                  ? [PlaylistEntry(url: a.directUrl!, title: 'Outgoing')]
                  : null,
              resolve: (s) async => s.directUrl,
              playlist: pack
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          await d.player.seek(const Duration(seconds: 37));
          await d.tick();
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.replies[b.directUrl!] = (p) {
            p.state = p.state.copyWith(
              duration: Duration.zero,
              width: 0,
              height: 0,
              position: Duration.zero,
            );
            p.emit('duration', Duration.zero);
            p.emit('error', 'fixture rejected pick before late restore');
          };
          d.openGates[a.directUrl!] = ack;
          final action = d.select(sheet, 1, url);
          await d.openEntered(3);
          final seeks = d.player.calls.where((c) => c.$1 == 'seek').length;
          expect(action.isCompleted, isFalse);
          expect(ack.isCompleted, isFalse);
          d.player.delays['seek'] = landing;
          await t.pumpWidget(const SizedBox.shrink());
          await d.f.until(t, () => d.player.disposed.isCompleted);
          ack.complete();
          await d.tick();
          if (!playlist) {
            expect(action.isCompleted, isFalse);
            expect(
              d.player.calls.where((c) => c.$1 == 'seek'),
              hasLength(seeks),
            );
            await d.tick(const Duration(milliseconds: 9999));
            expect(action.isCompleted, isFalse);
            expect(
              d.player.calls.where((c) => c.$1 == 'seek'),
              hasLength(seeks),
            );
            await d.tick(const Duration(milliseconds: 1));
          }
          if (!playlist) {
            await d.f.until(
              t,
              () => d.player.calls.where((c) => c.$1 == 'seek').length > seeks,
            );
            expect(
              action.isCompleted,
              isFalse,
              reason:
                  'The original waits for the late restore seek acknowledgement',
            );
          }
          landing.complete();
          await d.f.finish(t, action.future);
          expect(
            d.player.calls.where((c) => c.$1 == 'seek').length,
            seeks + (playlist ? 0 : 1),
          );
          if (!playlist) {
            expect(
              d.player.calls.lastWhere((c) => c.$1 == 'seek').$2,
              const Duration(seconds: 37),
            );
          }
          expect(d.commits, [a]);
          expect(d.errors, isEmpty);
          expect(d.activeProbes, isEmpty);
        } finally {
          ack.completeIfPending();
          landing.completeIfPending();
          await d.close();
        }
      },
    );
  }
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 successful ${playlist ? 'playlist' : 'direct'} selection disposal during the carried seek preserves its existing callback ownership',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('seek-dispose-a'),
            b = startupSource('seek-dispose-b');
        final ack = Completer<void>();
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              entries: playlist
                  ? [PlaylistEntry(url: a.directUrl!, title: 'Same item')]
                  : null,
              resolve: (s) async => s.directUrl,
              playlist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: b.directUrl!, title: 'Same item'),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          await d.player.seek(const Duration(seconds: 37));
          await d.tick();
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          final before = d.player.calls.where((c) => c.$1 == 'seek').length;
          d.player.delays['seek'] = ack;
          final action = d.select(sheet, 1, url);
          await d.f.until(
            t,
            () => d.player.calls.where((c) => c.$1 == 'seek').length > before,
          );
          expect(action.isCompleted, isFalse);
          expect(d.commits, [a]);
          expect(d.opens, [a.directUrl, b.directUrl]);
          expect(d.player.state.playlist.medias.single.uri, b.directUrl);
          expect(ack.isCompleted, isFalse);
          await t.pumpWidget(const SizedBox.shrink());
          await d.f.until(t, () => d.player.disposed.isCompleted);
          ack.complete();
          await d.f.finish(t, action.future);
          expect(d.player.state.position, const Duration(seconds: 37));
          expect(
            d.commits,
            playlist ? [a] : [a, b],
            reason:
                'The direct caller does not recheck mounted after its seek; the playlist caller does',
          );
          expect(d.errors, isEmpty);
        } finally {
          ack.completeIfPending();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 split-audio disposal during attachment still seeks, plays and invokes its synthetic commit after that acknowledgement',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('audio-dispose-a'),
          b = startupSource('audio-dispose-b');
      final ack = Completer<void>();
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 late audio',
            audioUrl: 'https://startup.test/audio.m4a',
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.initialized();
        await d.player.seek(const Duration(seconds: 37));
        await d.tick();
        final sheet = await d.sheet();
        final before = d.player.calls.where((c) => c.$1 == 'audio').length;
        d.player.delays['audio'] = ack;
        final action = d.select(sheet, 1, b.directUrl!);
        await d.f.until(
          t,
          () => d.player.calls.where((c) => c.$1 == 'audio').length > before,
        );
        expect(action.isCompleted, isFalse);
        expect(ack.isCompleted, isFalse);
        expect(d.commits, isEmpty);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        final disposedCalls = d.player.calls.length;
        ack.complete();
        await d.f.finish(t, action.future);
        expect(
          d.player.calls.skip(disposedCalls).map((c) => c.$1),
          containsAllInOrder(['seek', 'play']),
        );
        expect(d.player.state.position, const Duration(seconds: 37));
        expect(d.player.state.playing, isTrue);
        expect(d.commits, [b]);
        expect(d.errors, isEmpty);
      } finally {
        ack.completeIfPending();
        await d.close();
      }
    },
  );
}
