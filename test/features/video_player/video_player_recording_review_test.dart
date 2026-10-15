import 'dart:async';
import 'dart:io';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_driver.dart';
import 'support/recording_stremio_launch.dart';

void main() {
  testWidgets('p13 TEE existing empty output reports mpv wrote no file', (
    t,
  ) async {
    final d = RecordingDriver(t);
    await d.setup();
    try {
      await d.mountRecording();
      d.record();
      final path = await d.armed();
      await d.started();
      await t.runAsync(() => File(path).writeAsBytes(const []));
      expect(await t.runAsync(() => File(path).exists()), isTrue);
      expect(await t.runAsync(() => File(path).length()), 0);
      await d.dismissNotice();
      d.record();
      await d.f.until(t, () => d.recordActions.every((a) => a.isCompleted));
      await d.f.advance(t);
      expect(d.active, isFalse);
      expect(d.native.properties['stream-record'], '');
      expect(
        find.text('Recording failed — mpv wrote no file (see logs)'),
        findsOneWidget,
      );
      expect(find.textContaining('Recording saved'), findsNothing);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'p13 TEE occupied base and suffixes two through four choose suffix five',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording(name: 'Collision');
        await t.runAsync(() async {
          final dir = Directory('${d.f.directory.path}/Debrify/Recordings');
          await dir.create(recursive: true);
          final start = DateTime.now();
          String two(int n) => n.toString().padLeft(2, '0');
          // Admit the filesystem work across a real-clock second boundary.
          for (var second = 0; second <= 60; second++) {
            final now = start.add(Duration(seconds: second));
            final stamp =
                '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
            final prefix = '${dir.path}/Collision_$stamp';
            for (final suffix in ['', '_2', '_3', '_4']) {
              File('$prefix$suffix.mkv').writeAsBytesSync(const []);
            }
          }
        });
        d.record();
        final path = await d.armed();
        await d.started();
        expect(path, endsWith('_5.mkv'));
        expect(await t.runAsync(() => File(path).exists()), isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 addon IPTV Play forwards unresolved URL and rejects recording after open fails',
    (t) async {
      final open = Completer<void>();
      final d = RecordingDriver(
        t,
        configurePlayer: (p) {
          p.delays['open'] = open;
          p.failures['open'] = StateError('p13 unresolved addon open');
        },
      );
      final launch = RecordingStremioLaunch(d);
      await d.setup();
      try {
        await launch.launch();
        open.complete();
        await d.f.until(
          t,
          () => d.logs.any((line) => line.contains('initial open failed')),
        );
        d.native.calls.clear();
        expect(d.active, isFalse);
        expect(
          DesktopRecordingService.instance.captureForUrl(
            RecordingStremioLaunch.unresolved,
          ),
          isNull,
        );
        d.desktopRecord();
        await d.f.until(t, () => d.recordActions.every((a) => a.isCompleted));
        await d.f.advance(t);
        expect(d.active, isFalse);
        expect(DesktopRecordingService.instance.activeCount, 0);
        expect(
          DesktopRecordingService.instance.captureForUrl(
            RecordingStremioLaunch.unresolved,
          ),
          isNull,
        );
        expect(d.paths.reads, 0);
        expect(d.propertyWrites, isEmpty);
        expect(
          find.text("This channel can't be recorded on desktop (HLS stream)"),
          findsOneWidget,
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!open.isCompleted) open.complete();
        await launch.close();
      }
    },
  );
  for (final failed in [false, true]) {
    testWidgets(
      'p13 addon IPTV Play ignores opaque-key capture openFailed=$failed',
      (t) async {
        final open = Completer<void>();
        final d = RecordingDriver(
          t,
          configurePlayer: (p) {
            p.delays['open'] = open;
            p.failures['open'] = StateError('p13 unresolved addon open');
          },
        );
        final launch = RecordingStremioLaunch(d);
        await d.setup();
        try {
          await launch.launch();
          if (failed) {
            open.complete();
            await d.f.until(
              t,
              () => d.logs.any((line) => line.contains('initial open failed')),
            );
          }
          final capture = await launch.competingCapture();
          await d.f.advance(t);
          expect(
            DesktopRecordingService.instance.captureForUrl(
              RecordingStremioLaunch.unresolved,
            ),
            same(capture),
          );
          expect(capture.isActive, isTrue);
          expect(d.offered, isTrue);
          expect(d.active, isFalse);
          d.native.calls.clear();
          d.desktopRecord();
          await d.f.until(t, () => d.recordActions.every((a) => a.isCompleted));
          await d.f.advance(t);
          expect(capture.isActive, isTrue);
          expect(d.active, isFalse);
          expect(d.paths.reads, 0);
          expect(d.propertyWrites, isEmpty);
          expect(
            find.text("This channel can't be recorded on desktop (HLS stream)"),
            findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!open.isCompleted) open.complete();
          await launch.close();
        }
      },
    );
  }
}
