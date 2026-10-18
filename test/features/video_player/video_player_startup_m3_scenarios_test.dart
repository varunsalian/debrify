import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/player_actions.dart';
import 'support/recording_driver.dart';
import 'support/resume_driver.dart';
import 'support/startup_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_resume_deadline_epoch_test.dart' show DeadlinePollDelivery;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'P16 M3 live source pick stops its TEE before opening and leaves the pending movie playlist untouched until the non-live branch',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      debugPrint = (message, {wrapWidth}) {
        if (message != null) d.logs.add(message);
        d.oldPrint(message, wrapWidth: wrapWidth);
      };
      const manifest = 'https://p16-addon.test/manifest.json';
      const endpoint = 'https://p16-addon.test/stream/tv/live.json';
      const a = 'https://p16-live.test/a.ts',
          b = 'https://p16-live.test/b.ts',
          c = 'https://p16-live.test/plain.ts';
      d.f.network.replies[manifest] = http.Response(
        jsonEncode({
          'id': 'p16-live',
          'name': 'P16 live',
          'version': '1.0.0',
          'types': ['tv'],
          'resources': ['stream'],
          'catalogs': [],
        }),
        200,
      );
      d.f.network.replies[endpoint] = http.Response(
        jsonEncode({
          'streams': [
            {'url': a, 'name': 'A'},
            {'url': b, 'name': 'B'},
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
      final channels = [
        IptvChannel(name: 'Addon live', url: key, contentType: 'live'),
        IptvChannel(name: 'Plain live', url: c, contentType: 'live'),
      ];
      final fallback = [
        startupSource('fallback-a', url: a),
        startupSource('fallback-b', url: b),
      ];
      VideoPlayerScreen screen(bool resolver) => VideoPlayerScreen(
        videoUrl: a,
        title: 'P16 source handoff',
        iptvChannels: channels,
        iptvStartIndex: 0,
        stremioSources: fallback,
        resolveStremioSource: (s) async => s.directUrl,
        resolveSourceToPlaylist: resolver
            ? (s, {canContinue}) async => [
                const PlaylistEntry(url: b, title: 'Live pending pack'),
              ]
            : null,
      );
      final current = ValueNotifier(screen(true));
      final trace = <String>[];
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: ValueListenableBuilder<VideoPlayerScreen>(
                valueListenable: current,
                builder: (_, value, _) => value,
              ),
            ),
          ),
        );
        await d.f.until(t, () => d.f.players.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        VpS2Hooks.install(VpS2Hooks(ios: () => true));
        d.player.onOpen = () {
          d.player.publishFrame();
          d.f.controllers.last.publishFrame();
          // The live owner arms only after the open Future acknowledges.
          Timer(
            const Duration(milliseconds: 1),
            () => d.player.emit<int?>('width', d.player.state.width),
          );
        };
        d.player.beforeOperation = (name, value) {
          if (name == 'open') {
            trace.add(
              'open:${((value as (mk.Playable, bool)).$1 as mk.Media).uri}',
            );
          }
        };
        d.native.beforeOperation = (name, value) {
          if (name == 'setProperty') {
            final pair = value as (String, String);
            if (pair.$1 == 'stream-record' && pair.$2.isEmpty) {
              trace.add('tee-stop');
            }
          }
        };
        d.record();
        final path = await d.armed();
        await t.runAsync(
          () => File(path).writeAsBytes(List<int>.filled(188 * 4, 71)),
        );
        await d.started();
        final seeks = d.player.calls.where((v) => v.$1 == 'seek').length;
        playerControls(t).onShowStremioSources!();
        await d.f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        expect(sheet.sources, hasLength(2));
        expect(await d.f.finish(t, sheet.resolveSource(sheet.sources[1])), b);
        final dynamic pick = sheet.onSourceSelected;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => pick(1, b)) as Future<dynamic>,
        );
        await d.f.actions.settle(t);
        expect(d.active, isFalse);
        expect(trace.indexOf('tee-stop'), isNonNegative);
        expect(
          trace.indexOf('open:$b'),
          greaterThan(trace.indexOf('tee-stop')),
        );
        expect(d.player.calls.where((v) => v.$1 == 'seek'), hasLength(seeks));
        expect(d.player.state.playlist.medias.single.uri, b);
        expect(File(path).existsSync(), isTrue);
        expect(File(path).lengthSync(), 188 * 4);
        await d.zap();
        await d.f.until(
          t,
          () => d.player.state.playlist.medias.single.uri == c,
        );
        current.value = screen(false);
        await d.f.advance(t);
        playerControls(t).onShowStremioSources!();
        await d.f.advance(t, const Duration(milliseconds: 300));
        final plain = t.widget<SourceSheet>(find.byType(SourceSheet));
        final resolved = (await d.f.finish(
          t,
          plain.resolveSource(fallback.first),
        ))!;
        expect(resolved, a);
        final dynamic next = plain.onSourceSelected;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next(0, resolved)) as Future<dynamic>,
        );
        expect(
          d.player.state.playlist.medias.single.uri,
          b,
          reason:
              'The live branch did not consume its pending playlist; the later direct-resolver branch adopts that original pending row',
        );
        expect(File(path).lengthSync(), 188 * 4);
      } finally {
        StremioIptvService.instance.invalidate(key);
        await d.f.finish(
          t,
          StremioService.instance.removeAddon(addon.storageKey),
        );
        await d.close();
        current.dispose();
      }
    },
  );

  testWidgets(
    'P16 M3 a source handoff carries an unlanded resume and saves the held target in the physical incoming row',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();

      final verifier = ResumeVerifierDriver(t, d.f);
      final a = startupSource('held-a'), b = startupSource('held-b');
      d.replies[b.directUrl!] = (p) {
        p.publishFrame();
        d.f.controllers.last.publishFrame();
      };
      try {
        await verifier.observe(
          () => d.begin(
            d.screen(
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              startAtPercent: .25,
            ),
          ),
        );
        await d.openEntered();
        d.player.seekAcknowledgementPosition = const Duration(seconds: 5);
        d.frame();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'seek'));
        await d.tick();
        expect(
          d.player.calls.where((c) => c.$1 == 'seek').first.$2,
          const Duration(minutes: 5),
        );
        expect(d.player.state.position, const Duration(seconds: 5));
        final sheet = await d.sheet();
        final selected = verifier.observe(
          () => d.select(sheet, 1, b.directUrl!),
        );
        await d.f.finish(t, selected.future);
        expect(
          d.player.calls.where((c) => c.$1 == 'seek').last.$2,
          const Duration(minutes: 5),
        );
        expect(d.player.state.position, const Duration(seconds: 5));
        final menu = await openPlayerMenu(t, d.f);
        menu.onSpeedSelected(1.5);
        await d.tick();
        final saved = await d.f.finish(
          t,
          VideoResumeStorage.getVideoResume(a.directUrl!),
        );
        expect(saved?['positionMs'], 300000);
        expect(saved?['speed'], 1.5);
        final durable = await d.f.finish(
          t,
          VideoProgressStorage.getVideoPlaybackState(videoTitle: 'P16 startup'),
        );
        expect(durable?['positionMs'], 300000);
        expect(durable?['speed'], 1.5);
        expect(durable?['url'], b.directUrl);
        expect(
          await d.f.finish(t, VideoResumeStorage.getVideoResume(b.directUrl!)),
          isNull,
          reason:
              'The original single-item legacy key remains the launch URL; the enhanced row carries the incoming URL',
        );
        expect(d.commits, [a, b]);
        d.player.seekAcknowledgementPosition = null;
        d.player.state = d.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        d.player.emit('position', d.player.state.position);
        await d.tick();
        await verifier.drain();
      } finally {
        d.player.seekAcknowledgementPosition = null;
        await d.close();
        await verifier.drain();
      }
    },
  );

  testWidgets(
    'P16 M3 failover winner restores the physical bookmark before gate release and the first Trakt scrobble',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules();
      TraktTestTransport.instance.attach(d.f);
      final cipher = (await t.runAsync(() => seedTrakt()))!;
      cipher.hold = true;
      d.f.network.handler = traktReply;
      final a = startupSource('first-dead'), b = startupSource('winner');
      d.openFailures[a.directUrl!] = StateError('dead first source');
      try {
        await d.f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(a.directUrl!, {
            'positionMs': 300000,
            'durationMs': 1200000,
            'speed': 1.25,
            'aspect': 'contain',
          }),
        );
        await d.begin(
          d.screen(
            sources: [a, b],
            failover: true,
            id: 'tt5100000',
            trakt: true,
          ),
        );
        await d.committed();
        await d.settle();
        cipher.releaseAll();
        await d.settle();
        await d.f.until(
          t,
          () =>
              d.f.network.requests.any((r) => r.url.path == '/scrobble/start'),
        );
        final sent = d.f.network.requests
            .where((r) => r.url.path == '/scrobble/start')
            .single;
        expect((jsonDecode(sent.body) as Map)['progress'], 25);
        expect(d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
        ]);
        expect(d.player.state.rate, 1.25);
        expect(d.commits, [b]);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.event('candidate_result').firstOrNull, contains('ok=false'));
        expect(d.event('candidate_result').lastOrNull, contains('ok=true'));
        expect(
          d.periodic.where(
            (r) => r.$1 == const Duration(minutes: 2) && r.$2.isActive,
          ),
          hasLength(1),
        );
      } finally {
        cipher.releaseAll();
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );
  testWidgets(
    'P16 M3 choosing a source aborts an expired startup verifier before the held pause permits another native open',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final verifier = ResumeVerifierDriver(t, d.f);
      final poll = DeadlinePollDelivery();
      final pause = Completer<void>();
      final a = startupSource('abort-a'), b = startupSource('abort-b');
      d.replies[b.directUrl!] = (p) {
        p.publishFrame();
        d.f.controllers.last.publishFrame();
      };
      try {
        await poll.observe(
          () => verifier.observe(
            () => d.begin(
              d.screen(
                sources: [a, b],
                resolve: (s) async => s.directUrl,
                startAtPercent: .25,
              ),
            ),
          ),
        );
        await d.openEntered();
        d.player.seekAcknowledgementPosition = const Duration(seconds: 5);
        d.frame();
        await d.f.until(t, () => poll.pending != null);
        await d.initialized();
        expect(d.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
        await t.runAsync(() async {
          final remaining =
              const Duration(milliseconds: 1600) - poll.clock.elapsed;
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        });
        expect(
          poll.clock.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 1500)),
        );
        final sheet = await d.sheet();
        d.player.delays['pause'] = pause;
        final pauseCount = d.player.calls.where((c) => c.$1 == 'pause').length;
        final selected = d.select(sheet, 1, b.directUrl!);
        await d.f.until(
          t,
          () =>
              d.player.calls.where((c) => c.$1 == 'pause').length > pauseCount,
        );
        expect(selected.isCompleted, isFalse);
        expect(d.opens, [a.directUrl]);
        expect(verifier.pending, isTrue);
        poll.release();
        await verifier.drain();
        expect(
          d.player.calls.where((c) => c.$1 == 'seek'),
          hasLength(1),
          reason:
              'The selection epoch changes before the pause await, not just when the new source eventually opens',
        );
        expect(selected.isCompleted, isFalse);
        expect(poll.clock.elapsed, lessThan(const Duration(seconds: 10)));
        pause.complete();
        d.player.delays.remove('pause');
        await d.f.finish(t, selected.future);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
          const Duration(minutes: 5),
        ]);
        d.player.seekAcknowledgementPosition = null;
        d.player.state = d.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        d.player.emit('position', d.player.state.position);
        await d.tick();
      } finally {
        if (!pause.isCompleted) pause.complete();
        poll.release();
        d.player.delays.remove('pause');
        d.player.seekAcknowledgementPosition = null;
        await d.close();
        await verifier.drain();
      }
    },
  );
}
