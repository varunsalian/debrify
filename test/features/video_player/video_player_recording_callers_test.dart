import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/player_actions.dart';
import 'support/fake_player.dart';
import 'support/recording_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_renderer_test.dart' show RendererFixture;

class _RecordingEarlyPaths extends VideoPlayerPaths {
  _RecordingEarlyPaths(super.path);
  int reads = 0;
  @override
  Future<String?> getDownloadsPath() async {
    reads++;
    return path;
  }
}

void main() {
  for (final trigger in ['eof', 'error']) {
    testWidgets(
      'p13 recording caller live $trigger retune awaits the native clear',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        final gate = Completer<void>();
        try {
          await d.mountRecording();
          d.record();
          await d.armed();
          await d.started();
          d.player.calls.clear();
          d.native.calls.clear();
          d.native.heldOperation = (name, value) =>
              name == 'setProperty' && value == ('stream-record', '');
          d.native.beforeOperation = (name, value) async {
            if (d.native.heldOperation!(name, value)) await gate.future;
          };
          if (trigger == 'eof') {
            d.player.emit('completed', true);
          } else {
            d.player.emit('error', 'synthetic live transport failure');
          }
          await d.f.until(t, () => d.propertyWrites.isNotEmpty);
          expect(d.player.calls.where((c) => c.$1 == 'open'), isEmpty);
          gate.complete();
          await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
          expect(d.propertyWrites.single.$2, ('stream-record', ''));
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 recording caller Start Over awaits the native clear before timeshift open',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final gate = Completer<void>();
      try {
        final now = DateTime.now();
        d.f.network.handler = (r) {
          if (r.url.path.contains('/timeshift/')) return http.Response('', 200);
          if (r.url.path.endsWith('/player_api.php')) {
            return http.Response(
              jsonEncode({
                'epg_listings': [
                  {
                    'title': 'Current broadcast',
                    'description': '',
                    'start_timestamp':
                        '${now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000}',
                    'stop_timestamp':
                        '${now.add(const Duration(minutes: 45)).millisecondsSinceEpoch ~/ 1000}',
                    'start':
                        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 01:00:00',
                    'has_archive': 1,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        };
        await d.mountRecording(
          url: 'https://p13-start-over.test/live/user/pass/123.ts',
        );
        await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
        d.record();
        await d.armed();
        await d.started();
        d.player.calls.clear();
        d.native.calls.clear();
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' && value == ('stream-record', '');
        d.native.beforeOperation = (name, value) async {
          if (d.native.heldOperation!(name, value)) await gate.future;
        };
        d.observe(() => playerControls(t).onLiveEdgeAction!());
        await d.f.until(t, () => d.propertyWrites.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'open'), isEmpty);
        gate.complete();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        expect(
          d.player.state.playlist.medias.single.uri,
          contains('/timeshift/'),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 recording caller IPTV source replacement awaits its own TEE stop',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final gate = Completer<void>();
      try {
        const manifest = 'https://p13-live-addon.test/manifest.json';
        const first = 'https://player.test/live-first.ts',
            second = 'https://player.test/live-second.ts';
        d.f.network.replies[manifest] = http.Response(
          jsonEncode({
            'id': 'p13-live',
            'name': 'P13 live',
            'version': '1.0.0',
            'types': ['tv'],
            'resources': ['stream'],
            'catalogs': [],
          }),
          200,
        );
        final addon = await d.f.finish(
          t,
          StremioService.instance.addAddon(manifest),
        );
        d.f.network.handler = (r) => r.url.path == '/stream/tv/p13.json'
            ? http.Response(
                jsonEncode({
                  'streams': [
                    {'url': first},
                    {'url': second},
                  ],
                }),
                200,
              )
            : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
        await d.mountRecording(
          url: StremioIptvService.buildChannelKey(addon.id, 'p13'),
          playingUrl: first,
        );
        await d.f.until(
          t,
          () => playerControls(t).onShowStremioSources != null,
        );
        d.record();
        await d.armed();
        await d.started();
        d.player.calls.clear();
        d.native.calls.clear();
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' && value == ('stream-record', '');
        d.native.beforeOperation = (name, value) async {
          if (d.native.heldOperation!(name, value)) await gate.future;
        };
        playerControls(t).onShowStremioSources!();
        await d.f.until(
          t,
          () => find.byType(SourceSheet).evaluate().isNotEmpty,
        );
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        d.observe(() => sheet.onSourceSelected(1, second));
        await d.f.until(t, () => d.propertyWrites.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'open'), isEmpty);
        gate.complete();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        d.player.publishFrame();
        await d.f.actions.settle(t);
        expect(d.player.state.playlist.medias.single.uri, second);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
  for (final tee in [false, true]) {
    testWidgets(
      'p13 recording saved callback with no current channel tee=$tee returns before IO',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          await d.mountRecording(tee: tee);
          final callback = playerControls(t).onRecord!;
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: const VideoPlayerScreen(
                videoUrl: 'https://player.test/live.ts',
                title: 'Recording fixture',
              ),
            ),
          );
          await d.f.advance(t);
          d.player.calls.clear();
          d.native.calls.clear();
          d.observe(callback);
          await d.f.actions.settle(t);
          expect(d.paths.reads, 0);
          expect(d.propertyWrites, isEmpty);
          expect(playerControls(t).hasRecord, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 recording saved callback in the renderer gap performs no directory work',
    (t) async {
      final h = RendererFixture(t, ios: true);
      try {
        await h.mount(live: true);
        final callback = playerControls(t).onRecord!;
        final paths = _RecordingEarlyPaths(h.f.directory.path);
        PathProviderPlatform.instance = paths;
        await h.fallback();
        h.old.calls.clear();
        (h.old.platform as FakeNativePlayer).calls.clear();
        callback();
        await h.f.actions.settle(t);
        expect(paths.reads, 0);
        expect(
          (h.old.platform as FakeNativePlayer).calls.where(
            (c) =>
                c.$1 == 'setProperty' &&
                (c.$2 as (String, String)).$1 == 'stream-record',
          ),
          isEmpty,
        );
        await h.release();
        expect(h.d.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );
  testWidgets(
    'p13 recording TV dock uses the same real Record and active-state callbacks',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mountRecording();
        expect(d.tvControls, isNotNull);
        expect(d.tvControls!.hasRecord, isTrue);
        d.record();
        await d.armed();
        await d.started();
        expect(d.tvControls!.isRecording, isTrue);
        d.record();
        await d.f.until(t, () => !d.active);
        await d.f.actions.settle(t);
        expect(
          d.propertyWrites.map((c) => (c.$2 as (String, String)).$2).last,
          '',
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
