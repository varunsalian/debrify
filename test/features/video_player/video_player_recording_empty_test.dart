import 'dart:async';
import 'dart:io';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_driver.dart';

void main() {
  testWidgets(
    'p13 desktop stopping a silent stream reports zero captured bytes and removes its empty file',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      var requests = 0;
      try {
        final server = (await t.runAsync(
          () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ))!;
        d.servers.add(server);
        await t.runAsync(() async {
          server.listen((request) {
            requests++;
            d.responses.add(request.response);
            // The live connection stays open and silent until capture cancellation.
          });
        });
        final url = 'http://127.0.0.1:${server.port}/silent.ts';
        await d.mountRecording(url: url, tee: false);
        d.native.properties['file-format'] = 'mpegts';
        d.desktopRecord();
        await d.f.until(t, () => requests == 1);
        final capture = DesktopRecordingService.instance.captureForUrl(url);
        expect(capture, isNotNull);
        expect(capture!.bytes, 0);
        expect(capture.isActive, isTrue);
        expect(
          find.text(
            'Recording in background — keeps going if you zap or leave. Stop from here or Settings → Recordings.',
          ),
          findsOneWidget,
        );
        await d.dismissNotice();
        d.desktopRecord();
        await d.f.until(t, () => !capture.isActive);
        await d.f.until(
          t,
          () => find
              .text('Recording failed — nothing was captured')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.text('Recording failed — nothing was captured'),
          findsOneWidget,
        );
        expect(await t.runAsync(() => File(capture.path).exists()), isFalse);
        expect(d.propertyWrites, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 desktop service capacity rejection after directory work keeps its failure feedback',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.f.finish(t, LiveRecordingService.setMaxConcurrent(1));
        final url = await d.loopback();
        final busy = await d.loopback();
        await d.mountRecording(url: url, tee: false);
        d.native.properties['file-format'] = 'mpegts';
        d.paths.gate = Completer<String?>();
        d.desktopRecord();
        await d.f.until(t, () => d.paths.reads == 1);
        final blocker = await d.f.finish(
          t,
          HttpOverrides.runWithHttpOverrides(
            () => DesktopRecordingService.instance.start(
              url: busy,
              path: '${d.f.directory.path}/blocker.ts',
              channelName: 'Busy',
              headers: {},
            ),
            d.realNetwork,
          ),
        );
        expect(blocker, isNotNull);
        await d.f.until(t, () => blocker!.bytes >= 188);
        d.paths.gate!.complete(d.paths.path);
        await d.f.until(
          t,
          () => find.text("Couldn't start recording").evaluate().isNotEmpty,
        );
        expect(DesktopRecordingService.instance.captureForUrl(url), isNull);
        expect(DesktopRecordingService.instance.activeCount, 1);
        await d.dismissNotice();
        expect(
          find.textContaining('Recording in background'),
          findsNothing,
          reason: 'failure returns before queuing a success notice',
        );
        expect(d.propertyWrites, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
