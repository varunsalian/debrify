import 'dart:async';

import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

Future<EngineDriver> _mount(
  WidgetTester t, [
  Map<String, String> properties = const {
    'container-fps': '23.976',
    'video-codec': 'hevc',
  },
]) async {
  final d = EngineDriver(
    t,
    tvos: true,
    configurePlayer: (p) =>
        (p.platform! as FakeNativePlayer).properties.addAll(properties),
  );
  await d.initialize();
  await d.f.finish<void>(
    t,
    PlayerNetworkStorage.setContentDisplayMatchMode(
      ContentDisplayMatchMode.frameRate,
    ),
  );
  await d.mount();
  await d.f.advance(t, const Duration(seconds: 1));
  return d;
}

List<Map<Object?, Object?>> _applies(EngineDriver d) => [
  for (final call in d.displayMatch)
    if (call.method == 'apply') call.arguments as Map<Object?, Object?>,
];

/// Selects a video track carrying [fps]/[codec], then delivers new params.
Future<void> _withTrack(
  EngineDriver d, {
  double? fps,
  String? codec,
  int width = 1920,
}) async {
  final video = mk.VideoTrack('1', 'Video', null, fps: fps, codec: codec);
  d.player.publishTracks(
    mk.Tracks(video: [video]),
    selected: d.player.state.track.copyWith(video: video),
  );
  d.player.emit('videoParams', mk.VideoParams(w: width, h: 1080));
  await d.f.advance(d.t, const Duration(seconds: 1));
}

void main() {
  testWidgets(
    'P19 tvOS a usable track rate and codec are requested without property reads',
    (t) async {
      final d = await _mount(t);
      try {
        final reads = d.propertyReads().length;
        await _withTrack(d, fps: 25, codec: 'av1');
        expect(_applies(d), hasLength(2));
        expect(_applies(d).last, {
          'width': 1920,
          'height': 1080,
          'refreshRate': 25.0,
          'matchResolution': false,
          'codec': 'av1',
        });
        expect(
          d
              .propertyReads()
              .skip(reads)
              .where(
                (r) => const {
                  'container-fps',
                  'estimated-vf-fps',
                  'video-codec',
                }.contains(r),
              ),
          isEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );

  for (final fps in [0.0, double.nan]) {
    testWidgets(
      'P19 tvOS a track rate of $fps falls back to the first positive property rate',
      (t) async {
        final d = await _mount(t, {
          'container-fps': '0',
          'estimated-vf-fps': '50',
          'video-codec': 'hevc',
        });
        try {
          await _withTrack(d, fps: fps, codec: '');
          expect(_applies(d).map((a) => a['width']), [1280, 1920]);
          expect(_applies(d).last['refreshRate'], 50.0);
          expect(
            _applies(d).last['codec'],
            'hevc',
            reason: 'an empty track codec is read from the player',
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P19 tvOS a zero track rate without any usable property requests nothing',
    (t) async {
      final d = await _mount(t);
      try {
        d.native.properties
          ..['container-fps'] = '0'
          ..['estimated-vf-fps'] = 'nan';
        await _withTrack(d, fps: 0, codec: 'hevc');
        expect(_applies(d), hasLength(1), reason: 'only the mount request');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS an empty track codec whose read fails is requested without a codec',
    (t) async {
      final d = await _mount(t);
      try {
        d.native.beforeOperation = (name, value) =>
            name == 'getProperty' && value == 'video-codec'
            ? throw PlatformException(code: 'no_codec')
            : null;
        await _withTrack(d, fps: 25, codec: '');
        expect(_applies(d), hasLength(2));
        expect(_applies(d).last['codec'], isNull);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS a boundary and new params at once abandon the in-flight request',
    (t) async {
      final gate = Completer<void>();
      final d = await _mount(t);
      try {
        final native = d.native;
        native.beforeOperation = (name, value) =>
            name == 'getProperty' &&
                value == 'container-fps' &&
                !gate.isCompleted
            ? gate.future
            : null;
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(
          t,
          () => native.calls.where((c) => c.$2 == 'container-fps').length == 2,
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d).map((a) => a['width']), [1280, 1920]);
        expect(
          d.propertyReads().where((r) => r == 'video-codec'),
          hasLength(2),
          reason: 'the mount request and the 1920 request only',
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS an answer arriving after a boundary is neither logged nor remembered',
    (t) async {
      final d = await _mount(t);
      try {
        final answer = Completer<Map<String, Object?>>();
        var held = true;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('debrify/tvos_display_match'),
          (call) async {
            d.displayMatch.add(call);
            if (call.method != 'apply') return null;
            if (held) {
              held = false;
              return answer.future;
            }
            return const {'matchingEnabled': true};
          },
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(t, () => _applies(d).length == 2);
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        answer.complete(const {'matchingEnabled': true});
        await d.f.advance(t, const Duration(milliseconds: 100));
        expect(
          d.logs.where((l) => l.startsWith('DisplayMatch: tvOS requested ')),
          hasLength(1),
          reason: 'only the mount request was recorded',
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(3));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS any positive track rate is trusted, even below one', (
    t,
  ) async {
    final d = await _mount(t);
    try {
      final reads = d.propertyReads().length;
      await _withTrack(d, fps: 0.5, codec: 'av1');
      expect(_applies(d), hasLength(2));
      expect(_applies(d).last['refreshRate'], 0.5);
      expect(
        d.propertyReads().skip(reads).where((r) => r.endsWith('-fps')),
        isEmpty,
      );
    } finally {
      await d.close();
    }
  });

  testWidgets('P19 tvOS any positive property rate is used, even below one', (
    t,
  ) async {
    final d = await _mount(t, {'container-fps': '0.5', 'video-codec': 'hevc'});
    try {
      expect(_applies(d), hasLength(1));
      expect(_applies(d).single['refreshRate'], 0.5);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS a boundary during the codec read abandons that request',
    (t) async {
      final gate = Completer<void>();
      final d = await _mount(t);
      try {
        final native = d.native;
        native.beforeOperation = (name, value) =>
            name == 'getProperty' && value == 'video-codec' && !gate.isCompleted
            ? gate.future
            : null;
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(
          t,
          () => native.calls.where((c) => c.$2 == 'video-codec').length == 2,
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d).map((a) => a['width']), [1280, 1920]);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS a rate equal to four decimals is not requested again', (
    t,
  ) async {
    final d = await _mount(t, {
      'container-fps': '23.97600',
      'video-codec': 'hevc',
    });
    try {
      d.native.properties['container-fps'] = '23.97604';
      d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
      await d.f.advance(t, const Duration(seconds: 1));
      expect(_applies(d), hasLength(1));
      d.native.properties['container-fps'] = '23.97700';
      d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
      await d.f.advance(t, const Duration(seconds: 1));
      expect(_applies(d), hasLength(2), reason: 'a real change is requested');
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS a failed codec read and an empty codec are the same request',
    (t) async {
      final d = await _mount(t);
      try {
        var fail = true;
        d.native.beforeOperation = (name, value) =>
            fail && name == 'getProperty' && value == 'video-codec'
            ? throw PlatformException(code: 'no_codec')
            : null;
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(2));
        expect(_applies(d).last.containsKey('codec'), isFalse);
        fail = false;
        d.native.properties['video-codec'] = '';
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(2));
      } finally {
        await d.close();
      }
    },
  );

  for (final (label, readBack, surface, remedy, outcome) in [
    ('settles on nv12', 'nv12', 'nv12', 'nv12', 'confirmed'),
    ('falls to software', 'yuv420p', '', 'software', 'confirmed'),
    ('gives up', 'yuv420p', 'p010', 'gave_up', 'failed'),
  ]) {
    testWidgets(
      'P19 tvOS a high-bit surface runs the remedy ladder and reports it $label',
      (t) async {
        final d = await _mount(t, {
          'hwdec-current': 'videotoolbox',
          'current-vo': 'libmpv',
          'video-params/hw-pixelformat': surface,
        });
        try {
          await d.f.advance(t, const Duration(seconds: 3));
          final native = d.native;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'hwdec-image-format') {
              native.properties['hwdec-image-format'] = readBack;
            }
          };
          final writes = d.propertyWrites().length;
          final lines = d.decoderLines.length;
          d.player.emit(
            'videoParams',
            const mk.VideoParams(w: 3840, h: 2160, hwPixelformat: 'p010'),
          );
          await d.f.advance(t, const Duration(seconds: 10));
          expect(
            d.propertyWrites().skip(writes),
            contains(('hwdec', 'no')),
            reason: 'the ladder started',
          );
          final reported = d.decoderLines.skip(lines).toList();
          expect(reported, isNotEmpty);
          expect(
            reported.last,
            contains(' remedy=$remedy remedy_outcome=$outcome '),
          );
          expect(
            reported.last.split(' ').skip(1).where((w) => !w.contains('=')),
            isEmpty,
            reason: 'every field is a single key=value token',
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets('P19 tvOS the container rate wins over the estimated rate', (
    t,
  ) async {
    final d = await _mount(t, {
      'container-fps': '23.976',
      'estimated-vf-fps': '24',
      'video-codec': 'hevc',
    });
    try {
      expect(_applies(d), hasLength(1));
      expect(_applies(d).single['refreshRate'], 23.976);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS new params replace an in-flight request without a boundary',
    (t) async {
      final gate = Completer<void>();
      final d = await _mount(t);
      try {
        final native = d.native;
        native.beforeOperation = (name, value) =>
            name == 'getProperty' &&
                value == 'container-fps' &&
                !gate.isCompleted
            ? gate.future
            : null;
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(
          t,
          () => native.calls.where((c) => c.$2 == 'container-fps').length == 2,
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 300));
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d).map((a) => a['width']), [1280, 1920]);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
}
