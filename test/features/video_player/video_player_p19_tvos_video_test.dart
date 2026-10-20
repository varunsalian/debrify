import 'dart:async';
import 'dart:io';

import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

void Function(FakePlayer) _properties(Map<String, String> values) =>
    (p) => (p.platform! as FakeNativePlayer).properties.addAll(values);

const _clip = {'container-fps': '23.976', 'video-codec': 'hevc'};

Future<EngineDriver> _mount(
  WidgetTester t, {
  ContentDisplayMatchMode mode = ContentDisplayMatchMode.frameRate,
  void Function(FakePlayer)? configure,
}) async {
  final d = EngineDriver(
    t,
    tvos: true,
    configurePlayer: configure ?? _properties(_clip),
  );
  await d.initialize();
  await d.f.finish<void>(
    t,
    PlayerNetworkStorage.setContentDisplayMatchMode(mode),
  );
  await d.mount();
  await d.f.advance(t, const Duration(seconds: 1));
  return d;
}

List<Map<Object?, Object?>> _applies(EngineDriver d) => [
  for (final call in d.displayMatch)
    if (call.method == 'apply') call.arguments as Map<Object?, Object?>,
];

/// The single display-match request; any other count fails as an expectation.
Map<Object?, Object?> _only(EngineDriver d) {
  expect(_applies(d), hasLength(1));
  return _applies(d).single;
}

int _clears(EngineDriver d) =>
    d.displayMatch.where((call) => call.method == 'clear').length;

void main() {
  testWidgets(
    'P19 tvOS frame-rate matching clears the boundary, then requests the content cadence once',
    (t) async {
      final d = await _mount(t);
      try {
        expect(d.displayMatch.map((c) => c.method), ['clear', 'apply']);
        expect(_only(d), {
          'width': 1280,
          'height': 720,
          'refreshRate': 23.976,
          'matchResolution': false,
          'codec': 'hevc',
        });
        expect(
          d.logs,
          contains(
            'DisplayMatch: tvOS requested 1280x720@23.976 '
            'mode=frame_rate enabled=true',
          ),
        );
        expect(
          d.timers
              .where((x) => x.stack.contains('scheduleTvosDisplayMatch'))
              .map((x) => x.duration),
          contains(const Duration(milliseconds: 200)),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS resolution matching sends matchResolution', (t) async {
    final d = await _mount(
      t,
      mode: ContentDisplayMatchMode.frameRateAndResolution,
    );
    try {
      expect(_only(d)['matchResolution'], isTrue);
      expect(
        d.logs,
        contains(
          'DisplayMatch: tvOS requested 1280x720@23.976 '
          'mode=frame_rate_resolution enabled=true',
        ),
      );
    } finally {
      await d.close();
    }
  });

  for (final mode in [
    ContentDisplayMatchMode.systemDefault,
    ContentDisplayMatchMode.off,
  ]) {
    testWidgets('P19 tvOS ${mode.storageKey} mode never requests matching', (
      t,
    ) async {
      final d = await _mount(t, mode: mode);
      try {
        // The only clear is the defaults load; the media boundary is silent.
        expect(d.displayMatch.map((c) => c.method), ['clear']);
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(d.displayMatch.map((c) => c.method), ['clear']);
        expect(d.propertyReads().where((r) => r == 'container-fps'), isEmpty);
      } finally {
        await d.close();
      }
    });
  }

  testWidgets(
    'P19 tvOS fps falls back from container-fps to estimated-vf-fps',
    (t) async {
      final d = await _mount(
        t,
        configure: _properties({
          'container-fps': 'nan',
          'estimated-vf-fps': '50',
          'video-codec': 'h264',
        }),
      );
      try {
        expect(_only(d)['refreshRate'], 50.0);
        expect(_only(d)['codec'], 'h264');
        final reads = d.propertyReads();
        expect(
          reads.indexOf('container-fps'),
          lessThan(reads.indexOf('estimated-vf-fps')),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS a failing fps read still tries the second property', (
    t,
  ) async {
    final d = await _mount(
      t,
      configure: (p) {
        final native = p.platform! as FakeNativePlayer;
        native.properties.addAll({'estimated-vf-fps': '59.94'});
        native.beforeOperation = (name, value) {
          if (name == 'getProperty' && value == 'container-fps') {
            throw StateError('no container fps');
          }
        };
      },
    );
    try {
      expect(_only(d)['refreshRate'], 59.94);
      expect(_only(d).containsKey('codec'), isFalse);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets('P19 tvOS without any usable fps requests nothing', (t) async {
    final d = await _mount(
      t,
      configure: _properties({'container-fps': '0', 'estimated-vf-fps': '-1'}),
    );
    try {
      expect(_applies(d), isEmpty);
      expect(d.propertyReads(), contains('estimated-vf-fps'));
      // No fps ends the request before the codec read (the probe's own
      // codec read only follows its twelve-read window).
      expect(d.propertyReads(), isNot(contains('video-codec')));
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS a selected track fps and codec are used without property reads',
    (t) async {
      final d = await _mount(
        t,
        configure: (p) {
          _properties(_clip)(p);
          p.state = p.state.copyWith(
            track: const mk.Track(
              video: mk.VideoTrack('1', null, null, fps: 25.0, codec: 'av1'),
            ),
          );
        },
      );
      try {
        expect(_only(d)['refreshRate'], 25.0);
        expect(_only(d)['codec'], 'av1');
        expect(d.propertyReads(), isNot(contains('container-fps')));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS a failing codec read requests without a codec', (
    t,
  ) async {
    final d = await _mount(
      t,
      configure: (p) {
        final native = p.platform! as FakeNativePlayer;
        native.properties.addAll({'container-fps': '24'});
        var reads = 0;
        native.beforeOperation = (name, value) {
          // The first video-codec read is the display match's.
          if (name == 'getProperty' && value == 'video-codec' && reads++ == 0) {
            throw StateError('codec unavailable');
          }
        };
      },
    );
    try {
      expect(_only(d)['refreshRate'], 24.0);
      expect(_only(d).containsKey('codec'), isFalse);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS identical criteria are not requested twice; changed ones are',
    (t) async {
      final d = await _mount(t);
      try {
        expect(_applies(d), hasLength(1));
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(1));
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(2));
        expect(_applies(d).last['width'], 3840);
        expect(_applies(d).last['height'], 2160);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS rapid params changes inside the debounce request only the latest',
    (t) async {
      final d = await _mount(t);
      try {
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 100));
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d).map((a) => a['width']), [1280, 3840]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS a zero-sized boundary clears, forgets the signature and cancels a pending request',
    (t) async {
      final d = await _mount(t);
      try {
        expect(_clears(d), 1);
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 100));
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_clears(d), 2);
        expect(_applies(d), hasLength(1));
        // The same criteria after a boundary are requested again.
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(2));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS a failed request is logged, swallowed and retried for the same criteria',
    (t) async {
      final d = EngineDriver(
        t,
        tvos: true,
        configurePlayer: _properties(_clip),
      );
      d.displayMatchApplyFailure = PlatformException(code: 'match_refused');
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          PlayerNetworkStorage.setContentDisplayMatchMode(
            ContentDisplayMatchMode.frameRate,
          ),
        );
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(1));
        expect(
          d.logs.where(
            (l) => l.startsWith('DisplayMatch: tvOS request failed: '),
          ),
          hasLength(1),
        );
        d.displayMatchApplyFailure = null;
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS a boundary clear failure is logged and swallowed', (
    t,
  ) async {
    final d = await _mount(t);
    try {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('debrify/tvos_display_match'),
        (call) async {
          d.displayMatch.add(call);
          throw PlatformException(code: 'clear_refused');
        },
      );
      d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
      await d.f.advance(t, const Duration(milliseconds: 100));
      expect(
        d.logs.where(
          (l) => l.startsWith('DisplayMatch: tvOS boundary clear failed: '),
        ),
        hasLength(1),
      );
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 tvOS a request whose fps read outlives the screen is abandoned',
    (t) async {
      final gate = Completer<void>();
      final d = await _mount(t);
      try {
        final native = d.native;
        native.beforeOperation = (name, value) =>
            name == 'getProperty' && value == 'container-fps'
            ? gate.future
            : null;
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(
          t,
          () => native.calls.where((c) => c.$2 == 'container-fps').length == 2,
        );
        await t.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(1));
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS a request superseded during its fps read is abandoned',
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
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(_applies(d), hasLength(1));
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS a request answered after the screen closed records nothing',
    (t) async {
      final d = await _mount(t);
      try {
        final answer = Completer<Map<String, Object?>>();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('debrify/tvos_display_match'),
          (call) async {
            d.displayMatch.add(call);
            return call.method == 'apply' ? answer.future : null;
          },
        );
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.until(t, () => _applies(d).length == 2);
        await t.pumpWidget(const SizedBox.shrink());
        answer.complete(const {'matchingEnabled': true});
        await d.f.advance(t, const Duration(seconds: 1));
        expect(
          d.logs.where((l) => l.startsWith('DisplayMatch: tvOS requested ')),
          hasLength(1),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 tvOS decoder diagnostics go to the tvlog channel with remedy fields',
    (t) async {
      final d = await _mount(
        t,
        mode: ContentDisplayMatchMode.off,
        configure: _properties({
          'hwdec-current': 'videotoolbox',
          'current-vo': 'libmpv',
        }),
      );
      try {
        await d.f.advance(t, const Duration(seconds: 3));
        expect(d.decoderLines, [
          'DEBRIFY_PLAYER_DECODER generation=1 phase=stable status=hardware '
              'platform=${Platform.operatingSystem} backend=libmpv '
              'codec=unknown decoder=videotoolbox output=libmpv '
              'pixelformat=unknown hw_pixelformat=none '
              'detected_hw_pixelformat=none verified_hw_pixelformat=none '
              'gamma=unknown primaries=unknown remedy=none remedy_outcome=none '
              'audio_codec=none decoded_channels=none audio_channels=none '
              'audio_format=none ao=none requested_renderer=platform_default '
              'resolution=1280x720',
        ]);
        expect(
          d.logs.where((l) => l.startsWith('DEBRIFY_PLAYER_DECODER')),
          isEmpty,
          reason: 'tvOS never prints the diagnostic',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 tvOS pins the remedy surface on each created player', (
    t,
  ) async {
    final d = await _mount(t, mode: ContentDisplayMatchMode.off);
    try {
      expect(d.propertyWrites(), contains(('hwdec-image-format', 'nv12')));
    } finally {
      await d.close();
    }
  });
}
