import 'dart:async';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/startup_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  TraktTestTransport.install();
  for (final aio in [false, true]) {
    testWidgets(
      'P16 startup watch aio=$aio releases tracking at readiness only for the AIO guard before held restoration returns',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        TraktTestTransport.instance.attach(d.f);
        final cipher = (await t.runAsync(() => seedTrakt()))!;
        cipher.hold = true;
        d.f.network.handler = traktReply;
        final tracks = CompletionDelivery(
          'restoreTrackPreferences',
          (v) => v == null,
        );
        final a = startupSource(
          'watch',
          addon: aio ? 'org.aiostreams' : 'ordinary',
        );
        try {
          await tracks.run(
            () => d.begin(
              VideoPlayerScreen(
                videoUrl: a.directUrl!,
                title: 'P16 watch',
                contentType: 'movie',
                contentImdbId: 'tt5100000',
                traktScrobble: true,
                stremioSources: [a],
                stremioTvChannels: const [
                  {'id': 'slot', 'name': 'P16 watch', 'channelNumber': 7},
                ],
                stremioTvCurrentChannelId: 'slot',
              ),
            ),
          );
          await d.openEntered();
          cipher.releaseAll();
          await d.settle();
          expect(d.event('candidate_open'), isEmpty);
          expect(d.subscriptions.where((s) => s.owner == 'tv'), hasLength(5));
          expect(
            d.f.network.requests.where((r) => r.url.path == '/scrobble/start'),
            isEmpty,
          );
          d.frame();
          await d.f.until(t, () => tracks.pending.isNotEmpty);
          await d.settle();
          expect(
            d.f.network.requests.where((r) => r.url.path == '/scrobble/start'),
            hasLength(aio ? 1 : 0),
          );
          expect(
            d.subscriptions
                .where((s) => s.owner == 'tv')
                .every((s) => s.cancelled),
            isTrue,
          );
          expect(tracks.pending, isNotEmpty);
          tracks.release();
          await d.settle();
          expect(
            d.f.network.requests.where((r) => r.url.path == '/scrobble/start'),
            hasLength(1),
          );
          expect(
            d.periodic.where(
              (r) => r.$1 == const Duration(minutes: 2) && r.$2.isActive,
            ),
            hasLength(1),
          );
        } finally {
          tracks.release();
          cipher.releaseAll();
          await d.close();
          TraktTestTransport.instance.recorder = null;
        }
      },
    );
  }

  testWidgets(
    'P16 failed Stremio watch cancels its deferred slot seek before later metadata arrives',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('cancel-slot', addon: 'AIOStreams');
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 cancel slot',
            startAtPercent: .5,
            stremioSources: [a],
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P16 TV'},
            ],
            stremioTvCurrentChannelId: 'slot',
          ),
        );
        await d.openEntered();
        d.player.emit('error', 'fixture watch failure');
        await d.tick();
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('No playable source could be started.'),
          ),
          findsNWidgets(2),
        );
        d.frame();
        await d.settle();
        expect(d.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        expect(
          d.subscriptions
              .where((s) => s.owner == 'tv')
              .every((s) => s.cancelled),
          isTrue,
        );
        await d.tick(const Duration(seconds: 1));
        await d.f.until(t, () => d.routeReturned);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 disposed Stremio watch receives no further events and cannot report or seek',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('disposed-watch', addon: 'AIOStreams');
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 disposed watch',
            startAtPercent: .5,
            stremioSources: [a],
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P16 TV'},
            ],
            stremioTvCurrentChannelId: 'slot',
          ),
        );
        await d.openEntered();
        expect(d.subscriptions.where((s) => s.owner == 'tv'), hasLength(5));
        // Finish the duration wait before disposal, while keeping width at zero
        // so the startup watch itself is still pending.
        d.player.emit('duration', const Duration(minutes: 20));
        await d.tick();
        await d.initialized();
        await d.settle();
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        final seeks = d.player.calls.where((c) => c.$1 == 'seek').length;
        final timers = d.timers.length;
        d.player.emit('error', 'late watch error');
        d.frame();
        await d.tick(const Duration(seconds: 1));
        expect(d.player.calls.where((c) => c.$1 == 'seek'), hasLength(seeks));
        expect(d.timers, hasLength(timers));
        expect(
          d.subscriptions
              .where((s) => s.owner == 'tv')
              .every((s) => s.cancelled),
          isTrue,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 renderer restart installs a new Stremio watch and carries its pending slot seek to the new instance',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      final a = startupSource('watch-restart', addon: 'AIOStreams');
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 watch restart',
            startAtPercent: .25,
            stremioSources: [a],
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P16 TV'},
            ],
            stremioTvCurrentChannelId: 'slot',
          ),
        );
        await d.openEntered();
        final old = d.player;
        old.emit('error', 'fixture MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        final watches = d.subscriptions.where((s) => s.owner == 'tv').toList();
        expect(watches, hasLength(10));
        expect(
          watches
              .where((s) => identical(s.player, old))
              .every((s) => s.cancelled),
          isTrue,
        );
        expect(
          watches
              .where((s) => identical(s.player, d.player))
              .every((s) => !s.cancelled),
          isTrue,
        );
        d.frame();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'seek'));
        expect(
          d.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
          contains(const Duration(minutes: 5)),
        );
        await d.settle();
        expect(
          d.subscriptions
              .where((s) => s.owner == 'tv')
              .every((s) => s.cancelled),
          isTrue,
        );
        expect(d.routeReturned, isFalse);
        expect(d.opens, [a.directUrl, a.directUrl]);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 a failed replacement open reports the current pending Stremio startup watch failure',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      final a = startupSource('watch-reopen-failed', addon: 'AIOStreams');
      final printed = <String>[];
      try {
        await runZoned(
          () => d.begin(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'P16 failed renderer watch',
              stremioSources: [a],
              stremioTvChannels: const [
                {'id': 'slot', 'name': 'P16 TV'},
              ],
              stremioTvCurrentChannelId: 'slot',
            ),
          ),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              printed.add(line);
              parent.print(zone, line);
            },
          ),
        );
        await d.openEntered();
        d.player.emit('duration', const Duration(minutes: 20));
        await d.initialized();
        d.openFailures[a.directUrl!] = StateError(
          'fixture renderer reopen failure',
        );
        d.player.emit('error', 'fixture MediaCodec video output failure');
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.openEntered(2);
        await d.f.until(
          t,
          () => find
              .text('No playable source could be started.')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          printed.any((s) => s.contains('phase=fallback status=failed')),
          isTrue,
        );
        expect(find.text('No playable source could be started.'), findsWidgets);
        expect(
          d.subscriptions
              .where((s) => s.owner == 'tv')
              .every((s) => s.cancelled),
          isTrue,
        );
        expect(d.routeReturned, isFalse);
        await d.tick(const Duration(seconds: 1));
        await d.f.until(t, () => d.routeReturned);
        expect(d.routeResult, isNull);
        expect(d.event('candidate_open'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
