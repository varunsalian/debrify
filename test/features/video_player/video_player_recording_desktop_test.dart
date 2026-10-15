import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_delivery.dart';
import 'support/recording_driver.dart';

void main() {
  for (final ending in ['button', 'zap', 'dispose', 'pause']) {
    testWidgets(
      'p13 desktop continuous capture $ending preserves background ownership',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          final url = await d.loopback();
          await d.mountRecording(url: url, tee: false);
          d.native.properties['file-format'] = 'mpegts';
          d.desktopRecord();
          final capture = await d.captured(url);
          expect(capture.path.endsWith('.ts'), isTrue);
          expect(d.receivedHeaders, ['p13']);
          expect(d.active, isTrue);
          expect(
            d.propertyWrites,
            isEmpty,
            reason: 'desktop never arms mpv TEE',
          );
          if (ending == 'button') await d.dismissNotice();
          final before = capture.bytes;
          switch (ending) {
            case 'button':
              d.desktopRecord();
              await d.f.until(t, () => !capture.isActive);
            case 'zap':
              await d.zap();
            case 'dispose':
              await d.removePlayer();
            case 'pause':
              await d.background();
          }
          if (ending == 'button') {
            await d.f.advance(t, const Duration(milliseconds: 300));
            expect(d.active, isFalse);
            expect(
              find.text('Recording saved: ${capture.path}'),
              findsOneWidget,
            );
          } else {
            await d.f.advance(t, const Duration(milliseconds: 200));
            await d.f.until(t, () => capture.bytes > before);
            expect(capture.isActive, isTrue);
            if (ending == 'zap') {
              expect(
                d.active,
                isFalse,
                reason: 'current-channel lookup excludes old capture',
              );
            }
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final format in ['mpegts', 'hls', 'dash', '', 'probe-error']) {
    for (final urlKind in ['plain', 'xtream', 'non-http']) {
      testWidgets('p13 desktop URL admission format=$format url=$urlKind', (
        t,
      ) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          final base = await d.loopback();
          final origin = Uri.parse(base).origin;
          final url = urlKind == 'xtream'
              ? '$origin/live/user/password/42.m3u8'
              : urlKind == 'non-http'
              ? 'rtmp://player.test/live'
              : base;
          await d.mountRecording(url: url, tee: false);
          d.native.properties['file-format'] = format;
          d.native.beforeOperation = (name, value) {
            if (format == 'probe-error' &&
                name == 'getProperty' &&
                value == 'file-format') {
              throw StateError('unavailable');
            }
          };
          d.desktopRecord();
          // Fixed expected destinations exercise the player's dispatch decision
          // independently of the service URL helpers it calls.
          final expectedPath = <String, Map<String, String?>>{
            'mpegts': {
              'plain': '/live.ts',
              'xtream': '/live/user/password/42.m3u8',
            },
            'hls': {'plain': null, 'xtream': '/live/user/password/42.ts'},
            'dash': {'plain': null, 'xtream': '/live/user/password/42.ts'},
            '': {'plain': '/live.ts', 'xtream': '/live/user/password/42.ts'},
            'probe-error': {
              'plain': '/live.ts',
              'xtream': '/live/user/password/42.ts',
            },
          }[format]![urlKind];
          final expected = expectedPath == null ? null : '$origin$expectedPath';
          if (expected == null) {
            await d.f.until(
              t,
              () => find
                  .text(
                    "This channel can't be recorded on desktop (HLS stream)",
                  )
                  .evaluate()
                  .isNotEmpty,
            );
            expect(DesktopRecordingService.instance.activeCount, 0);
            expect(d.propertyWrites, isEmpty);
          } else {
            final capture = await d.captured(expected);
            expect(capture.url, expected);
            expect(capture.channelName, 'Live / News');
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      });
    }
  }
  for (final boundary in ['format', 'directory', 'resource', 'service']) {
    for (final event in ['zap', 'dispose']) {
      testWidgets(
        'p13 desktop held $boundary then $event retains original capture and mounted windows',
        (t) async {
          final d = RecordingDriver(t);
          await d.setup();
          final gate = Completer<void>();
          RecordingDelivery? delivery;
          try {
            final url = await d.loopback();
            await d.mountRecording(
              url: url,
              tee: false,
              sourceId: boundary == 'resource' ? 'p13-resource' : null,
            );
            d.native.properties['file-format'] = 'mpegts';
            if (boundary == 'directory') d.paths.gate = Completer<String?>();
            if (boundary == 'format') {
              d.native.heldOperation = (name, value) =>
                  name == 'getProperty' && value == 'file-format';
              d.native.beforeOperation = (name, value) async {
                if (d.native.heldOperation!(name, value)) await gate.future;
              };
            }
            if (boundary == 'resource') {
              delivery = RecordingDelivery((v) => v is List<IptvPlaylist>);
            }
            if (boundary == 'service') {
              delivery = RecordingDelivery((v) => v is DesktopRecordingCapture);
            }
            if (delivery != null) {
              delivery.run(d.desktopRecord);
            } else {
              d.desktopRecord();
            }
            await d.f.until(
              t,
              () => boundary == 'directory'
                  ? d.paths.reads > 0
                  : delivery != null
                  ? delivery.pending.isNotEmpty
                  : d.native.calls.any(
                      (c) => c.$1 == 'getProperty' && c.$2 == 'file-format',
                    ),
            );
            DesktopRecordingCapture? started;
            if (boundary == 'service') started = await d.captured(url);
            if (event == 'zap') {
              await d.zap();
            } else {
              await d.removePlayer();
            }
            d.paths.gate?.complete(d.paths.path);
            gate.complete();
            delivery?.release();
            await d.f.actions.settle(t);
            if (event == 'dispose' && boundary != 'service') {
              expect(DesktopRecordingService.instance.activeCount, 0);
            } else {
              final capture = started ?? await d.captured(url);
              expect(capture.url, url);
              expect(
                capture.channelName,
                'Live / News',
                reason: 'channel captured before the await',
              );
              expect(capture.isActive, isTrue);
            }
            expect(d.propertyWrites, isEmpty);
            if (event == 'dispose' && boundary == 'format') {
              expect(d.errors, hasLength(1));
              expect(
                d.errors.single.toString(),
                contains('State no longer has a context'),
                reason: 'original reads context before its next mounted check',
              );
            } else {
              expect(d.errors, isEmpty);
            }
          } finally {
            if (!gate.isCompleted) gate.complete();
            delivery?.release();
            await d.close();
          }
        },
      );
    }
  }
}
