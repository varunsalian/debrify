import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/recording_driver.dart';

void main() {
  for (final (name, base) in [
    ('', 'recording'),
    ('***', 'recording'),
    ('A' * 70, 'A' * 60),
    ('A' * 61, 'A' * 60),
    (' / Live  News ? ', 'Live_News'),
  ]) {
    testWidgets(
      'p13 TEE filename sanitizes "$name" without changing path policy',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          await d.mountRecording(name: name);
          d.record();
          final path = await d.armed();
          await d.started();
          expect(File(path).uri.pathSegments.last, startsWith('${base}_'));
          expect(path, endsWith('.mkv'));
          expect(
            Directory(path).parent.path,
            '${d.f.directory.path}/Debrify/Recordings',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 TEE null Downloads path uses documents without another target policy',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording();
        d.paths.gate = Completer<String?>();
        d.record();
        await d.f.until(t, () => d.paths.reads > 0);
        d.paths.gate!.complete(null);
        final path = await d.armed();
        await d.started();
        expect(path, startsWith('${d.f.directory.path}/Debrify/Recordings/'));
        expect(d.paths.reads, 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 TEE warning logs are filtered and stop cancels the recording log tap',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording();
        d.record();
        await d.armed();
        await d.started();
        for (final level in ['error', 'fatal', 'ERROR', 'warning', 'info']) {
          d.player.emit(
            'log',
            mk.PlayerLog(prefix: 'recorder', level: level, text: 'p13-$level'),
          );
        }
        await d.f.advance(t);
        final lines = d.logs
            .where((s) => s.startsWith('VideoPlayer: mpv['))
            .toList();
        expect(lines, hasLength(3));
        expect(lines.join('|'), contains('p13-error'));
        expect(lines.join('|'), contains('p13-fatal'));
        expect(lines.join('|'), contains('p13-ERROR'));
        d.record();
        await d.f.until(t, () => !d.active);
        await d.f.actions.settle(t);
        d.player.emit(
          'log',
          const mk.PlayerLog(
            prefix: 'recorder',
            level: 'error',
            text: 'p13-after-stop',
          ),
        );
        await d.f.advance(t);
        expect(d.logs.where((s) => s.contains('p13-after-stop')), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final resolved in [false, true]) {
    testWidgets(
      'p13 desktop Stremio playing URL resolved=$resolved controls capture identity',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          final url = await d.loopback();
          await d.mountRecording(
            url: 'stremio-tv://p13/addon',
            playingUrl: resolved ? url : null,
            tee: false,
          );
          d.native.properties['file-format'] = 'mpegts';
          d.desktopRecord();
          if (resolved) {
            final capture = await d.captured(url);
            expect(d.active, isTrue);
            d.desktopRecord();
            await d.f.until(t, () => !capture.isActive);
          } else {
            await d.f.until(
              t,
              () => find
                  .text(
                    "This channel can't be recorded on desktop (HLS stream)",
                  )
                  .evaluate()
                  .isNotEmpty,
            );
          }
          expect(d.propertyWrites, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 channel switch awaits TEE clear before opening its replacement',
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
        await d.zap();
        await d.f.until(t, () => d.propertyWrites.isNotEmpty);
        expect(d.active, isFalse);
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
  for (final crowded in [false, true]) {
    testWidgets(
      'p13 TEE occupied target crowded=$crowded preserves suffix and microsecond fallback',
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
            for (var second = 0; second <= 60; second++) {
              final now = start.add(Duration(seconds: second));
              final stamp =
                  '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
              final prefix = '${dir.path}/Collision_$stamp';
              File('$prefix.mkv').writeAsBytesSync(const []);
              if (crowded) {
                for (var suffix = 2; suffix < 100; suffix++) {
                  File('${prefix}_$suffix.mkv').writeAsBytesSync(const []);
                }
              }
            }
          });
          d.record();
          final path = await d.armed();
          await d.started();
          expect(
            path,
            crowded ? matches(RegExp(r'_\d{16}\.mkv$')) : endsWith('_2.mkv'),
          );
          expect(
            await t.runAsync(() => File(path).exists()),
            isFalse,
            reason: 'existing files are never selected for a new recording',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
