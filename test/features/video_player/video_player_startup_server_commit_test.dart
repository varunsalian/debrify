import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/media_server_service.dart';

import 'support/resume_server_driver.dart';
import 'support/startup_driver.dart';

void main() {
  testWidgets(
    'P16 a late startup winner cannot commit the server watch prepared for another opened source',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      final a = server.sources[0], b = server.sources[1];
      final ack = d.openGates[a.directUrl!] = Completer<void>();
      try {
        final seed = server.screen();
        await d.begin(
          VideoPlayerScreen(
            videoUrl: seed.videoUrl,
            title: seed.title,
            httpHeaders: seed.httpHeaders,
            contentImdbId: seed.contentImdbId,
            contentType: seed.contentType,
            resumePolicy: seed.resumePolicy,
            stremioSources: server.sources,
            resolveStremioSource: (s) async => s.directUrl,
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.openEntered();
        d.frame();
        await d.result();
        expect(d.commits, isEmpty);
        final sheet = await d.sheet();
        final selected = d.select(sheet, 1, b.directUrl!);
        await d.f.finish(t, selected.future);
        expect(d.commits, [b]);
        expect(
          server.reports,
          isEmpty,
          reason:
              'The original startup gate still belongs to the held initial open',
        );
        ack.complete();
        await d.initialized();
        expect(d.commits, [b, a]);
        d.player.emit('position', const Duration(seconds: 61));
        await d.f.until(
          t,
          () => server.reports.any(
            (r) =>
                r.url.path.endsWith('/Playing') &&
                server.body(r)['PositionTicks'] == 610000000,
          ),
        );
        final progress = server.reports.lastWhere(
          (r) => r.url.path.endsWith('/Playing'),
        );
        expect(server.body(progress)['MediaSourceId'], 'version_2160');
        expect(
          server.reports.where(
            (r) =>
                r.url.path.endsWith('/Playing') &&
                server.body(r)['MediaSourceId'] == 'version_1080',
          ),
          isEmpty,
          reason:
              'The callback may finish late, but only identical(source, openedWatchSource) may commit server watch',
        );
      } finally {
        ack.completeIfPending();
        await d.close();
        server.restoreFactories();
      }
    },
  );

  testWidgets(
    'P16 a rejected server source reopens its outgoing identity, headers and guarded position before reporting again',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      final a = server.sources[0], b = server.sources[1];
      try {
        await d.begin(server.screen());
        await d.initialized();
        d.player.emit('position', const Duration(seconds: 1));
        await d.tick();
        await d.f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
        );
        await d.player.seek(const Duration(seconds: 37));
        await d.tick();
        final sheet = await d.sheet();
        d.openFailures[b.directUrl!] = StateError(
          'fixture rejected server candidate',
        );
        final selected = d.select(sheet, 1, b.directUrl!);
        await d.f.finish(t, selected.future);
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(
          d.player.state.playlist.medias.single.httpHeaders,
          a.httpHeaders,
        );
        expect(d.player.state.position, const Duration(seconds: 37));
        d.player.emit('position', const Duration(seconds: 62));
        await d.f.until(
          t,
          () => server.reports.any(
            (r) =>
                r.url.path.endsWith('/Progress') &&
                server.body(r)['PositionTicks'] == 620000000,
          ),
        );
        expect(
          server.body(
            server.reports.lastWhere((r) => r.url.path.endsWith('/Progress')),
          )['MediaSourceId'],
          'version_1080',
        );
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsOneWidget,
        );
      } finally {
        await d.close();
        server.restoreFactories();
      }
    },
  );
  testWidgets(
    'P16 a rejected server pack source reopens its outgoing identity, headers and guarded position before reporting again',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      final a = server.sources[0], b = server.sources[1];
      try {
        final seed = server.screen();
        await d.begin(
          VideoPlayerScreen(
            videoUrl: seed.videoUrl,
            title: seed.title,
            contentImdbId: seed.contentImdbId,
            contentType: seed.contentType,
            httpHeaders: seed.httpHeaders,
            resumePolicy: seed.resumePolicy,
            stremioSources: server.sources,
            resolveStremioSource: (s) async => s.directUrl,
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(
                url: s.directUrl!,
                title: s.name,
                httpHeaders: s.httpHeaders,
              ),
            ],
          ),
        );
        await d.initialized();
        d.player.emit('position', const Duration(seconds: 1));
        await d.tick();
        await d.f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
        );
        await d.player.seek(const Duration(seconds: 37));
        await d.tick();
        final sheet = await d.sheet();
        d.openFailures[b.directUrl!] = StateError(
          'fixture rejected server candidate',
        );
        final selectedUrl = (await d.f.finish(t, sheet.resolveSource(b)))!;
        final selected = d.select(sheet, 1, selectedUrl);
        await d.f.finish(t, selected.future);
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(
          d.player.state.playlist.medias.single.httpHeaders,
          a.httpHeaders,
        );
        expect(d.player.state.position, const Duration(seconds: 37));
        d.player.emit('position', const Duration(seconds: 62));
        await d.f.until(
          t,
          () => server.reports.any(
            (r) =>
                r.url.path.endsWith('/Progress') &&
                server.body(r)['PositionTicks'] == 620000000,
          ),
        );
        expect(
          server.body(
            server.reports.lastWhere((r) => r.url.path.endsWith('/Progress')),
          )['MediaSourceId'],
          'version_1080',
        );
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsOneWidget,
        );
      } finally {
        await d.close();
        server.restoreFactories();
      }
    },
  );
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 ${playlist ? 'playlist' : 'direct'} transition blocks server-watch observations before its pause acknowledgement',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final server = ResumeServerDriver(t, d.f);
        await server.prepare();
        final a = server.sources[0], b = server.sources[1];
        final pause = Completer<void>();
        try {
          final seed = server.screen();
          await d.begin(
            VideoPlayerScreen(
              videoUrl: seed.videoUrl,
              title: seed.title,
              contentImdbId: seed.contentImdbId,
              contentType: seed.contentType,
              httpHeaders: seed.httpHeaders,
              resumePolicy: seed.resumePolicy,
              stremioSources: server.sources,
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(
                        url: b.directUrl!,
                        title: 'Incoming',
                        httpHeaders: b.httpHeaders,
                      ),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          d.player.emit('position', const Duration(seconds: 1));
          await d.f.until(
            t,
            () => server.reports.any((r) => r.url.path.endsWith('/Playing')),
          );
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.player.delays['pause'] = pause;
          final before = d.player.calls.where((c) => c.$1 == 'pause').length;
          final action = d.select(sheet, 1, url);
          await d.f.until(
            t,
            () => d.player.calls.where((c) => c.$1 == 'pause').length > before,
          );
          expect(action.isCompleted, isFalse);
          d.player.emit('position', const Duration(seconds: 61));
          await d.settle();
          expect(
            server.reports.where(
              (r) => server.body(r)['PositionTicks'] == 610000000,
            ),
            isEmpty,
          );
          pause.complete();
          await d.f.finish(t, action.future);
          expect(d.player.state.playlist.medias.single.uri, b.directUrl);
          expect(d.opens, [a.directUrl, b.directUrl]);
        } finally {
          pause.completeIfPending();
          await d.close();
          server.restoreFactories();
        }
      },
    );
  }
  testWidgets(
    'P16 an authorization rejection before the initial Stremio watch installs uses the retained catch reporter',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      final server = ResumeServerDriver(t, d.f);
      await server.prepare();
      d.prearm = Completer<void>();
      final resource = (await d.f.finish(
        t,
        MediaServerService.connections(),
      )).single;
      final seed = server.screen();
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: seed.videoUrl,
            title: seed.title,
            contentImdbId: seed.contentImdbId,
            contentType: seed.contentType,
            httpHeaders: seed.httpHeaders,
            resumePolicy: seed.resumePolicy,
            stremioSources: server.sources,
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P16 authorization'},
            ],
            stremioTvCurrentChannelId: 'slot',
          ),
        );
        await d.f.until(t, () => d.prearmEntered);
        expect(d.opens, isEmpty);
        await d.f.finish(
          t,
          MediaServerService.remove(resource, revokeBorrowers: true),
        );
        d.prearm!.complete();
        await d.f.until(
          t,
          () => find
              .text('No playable source could be started.')
              .evaluate()
              .isNotEmpty,
        );
        expect(d.opens, isEmpty);
        expect(d.subscriptions.where((s) => s.owner == 'tv'), isEmpty);
        expect(find.text('No playable source could be started.'), findsWidgets);
        await d.tick(const Duration(seconds: 1));
        await d.f.until(t, () => d.routeReturned);
        expect(d.routeResult, isNull);
        expect(server.reports, isEmpty);
      } finally {
        d.prearm!.completeIfPending();
        await d.close();
        server.restoreFactories();
      }
    },
  );
}
