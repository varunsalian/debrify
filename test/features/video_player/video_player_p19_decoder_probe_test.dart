import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

const _stable = {
  'hwdec-current': 'videotoolbox',
  'current-vo': 'libmpv',
  'current-ao': 'coreaudio',
  'audio-out-params/channel-count': '2',
  'video-codec': 'h264',
  'audio-codec-name': 'aac',
  'audio-params/channel-count': '6',
  'audio-out-params/format': 'floatp',
};

void Function(FakePlayer) _properties(Map<String, String> values) =>
    (p) => (p.platform! as FakeNativePlayer).properties.addAll(values);

const _readiness = [
  'hwdec-current',
  'current-vo',
  'current-ao',
  'audio-out-params/channel-count',
];

int _readinessRounds(EngineDriver d) {
  final reads = d.propertyReads();
  final end = reads.indexOf('video-codec');
  expect(end, isNonNegative, reason: 'the probe reaches its final reads');
  final rounds = reads.sublist(0, end).where((r) => r != 'sid').toList();
  expect(rounds.length % 4, 0);
  for (var i = 0; i < rounds.length; i++) {
    expect(rounds[i], _readiness[i % 4]);
  }
  return rounds.length ~/ 4;
}

String _line(String fields) =>
    'DEBRIFY_PLAYER_DECODER generation=1 $fields '
    'requested_renderer=platform_default resolution=1280x720';

void main() {
  final os = Platform.operatingSystem;

  testWidgets(
    'P19 probe reports one stable hardware line after two matching reads',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _properties(_stable));
      await d.initialize();
      try {
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, [
          _line(
            'phase=stable status=hardware platform=$os backend=libmpv '
            'codec=h264 decoder=videotoolbox output=libmpv '
            'audio_codec=aac decoded_channels=6 audio_channels=2 '
            'audio_format=floatp ao=coreaudio',
          ),
        ]);
        expect(_readinessRounds(d), 2);
        final reads = d.propertyReads();
        final at = reads.indexOf('video-codec');
        expect(reads.sublist(at, at + 4), [
          'video-codec',
          'audio-codec-name',
          'audio-params/channel-count',
          'audio-out-params/format',
        ]);
        expect(
          d.timers.where((x) => x.stack.contains('scheduleDecoderProbe')),
          isNotEmpty,
        );
        expect(
          d.timers
              .where((x) => x.stack.contains('scheduleDecoderProbe'))
              .first
              .duration,
          const Duration(milliseconds: 150),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 probe classifies hwdec=no as software decode', (t) async {
    final d = EngineDriver(
      t,
      configurePlayer: _properties({..._stable, 'hwdec-current': 'no'}),
    );
    await d.initialize();
    try {
      await d.mount();
      await d.f.advance(t, const Duration(seconds: 5));
      expect(d.decoderLines, hasLength(1));
      expect(
        d.decoderLines.single,
        contains('phase=stable status=software platform=$os'),
      );
      expect(d.decoderLines.single, contains(' decoder=no '));
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 probe without a ready output reports partial after twelve reads',
    (t) async {
      final d = EngineDriver(
        t,
        configurePlayer: _properties({
          'hwdec-current': 'videotoolbox',
          'current-vo': 'null',
        }),
      );
      await d.initialize();
      try {
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, [
          _line(
            'phase=partial status=hardware platform=$os backend=libmpv '
            'codec=unknown decoder=videotoolbox output=unknown '
            'audio_codec=none decoded_channels=none audio_channels=none '
            'audio_format=none ao=none',
          ),
        ]);
        expect(_readinessRounds(d), 12);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 probe dedupes a repeated signature and reports a changed one',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _properties(_stable));
      await d.initialize();
      try {
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(1));
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(1), reason: 'same signature');
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(2));
        expect(d.decoderLines.last, endsWith('resolution=1920x1080'));
        expect(d.decoderLines.last, contains('generation=1 phase=stable'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 zero-sized params inside the debounce cancel the pending probe',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _properties(_stable));
      await d.initialize();
      try {
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 5));
        final reads = d.propertyReads().length;
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 50));
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(1));
        expect(
          d.propertyReads().skip(reads).where(_readiness.contains),
          isEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 zero-sized params mid-probe stop the running probe without a line',
    (t) async {
      final d = EngineDriver(t, configurePlayer: _properties(_stable));
      await d.initialize();
      try {
        await d.mount();
        await d.f.advance(t, const Duration(seconds: 5));
        (d.player.platform! as FakeNativePlayer).properties['current-vo'] =
            'null';
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 700));
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 probe property failure reports the error line', (t) async {
    final d = EngineDriver(
      t,
      configurePlayer: (p) {
        _properties(_stable)(p);
        (p.platform! as FakeNativePlayer).failures['getProperty'] = StateError(
          'probe read failed',
        );
      },
    );
    await d.initialize();
    try {
      await d.mount();
      await d.f.advance(t, const Duration(seconds: 5));
      expect(d.decoderLines, [
        'DEBRIFY_PLAYER_DECODER generation=1 phase=error status=unavailable '
            'platform=$os reason=property_query_failed',
      ]);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets('P19 a non-native player reports the web line', (t) async {
    final d = EngineDriver(t, native: false);
    await d.initialize();
    try {
      await d.mount();
      await d.f.advance(t, const Duration(seconds: 5));
      expect(d.decoderLines, [
        'DEBRIFY_PLAYER_DECODER generation=1 phase=stable status=unavailable '
            'platform=web backend=web reason=no_native_decoder',
      ]);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
}
