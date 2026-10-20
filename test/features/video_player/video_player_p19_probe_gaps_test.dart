import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

const _stable = {
  'hwdec-current': 'videotoolbox',
  'current-vo': 'libmpv',
  'current-ao': 'coreaudio',
  'audio-out-params/channel-count': '2',
};

const _readiness = {
  'hwdec-current',
  'current-vo',
  'current-ao',
  'audio-out-params/channel-count',
};

Future<EngineDriver> _mount(
  WidgetTester t, [
  Map<String, String> properties = _stable,
]) async {
  final d = EngineDriver(
    t,
    configurePlayer: (p) =>
        (p.platform! as FakeNativePlayer).properties.addAll(properties),
  );
  await d.initialize();
  await d.mount();
  await d.f.advance(t, const Duration(seconds: 5));
  return d;
}

List<String> _resolutions(EngineDriver d) => [
  for (final line in d.decoderLines) line.split(' resolution=').last,
];

void main() {
  for (final (label, params) in [
    ('zero width', const mk.VideoParams(w: 0, h: 720)),
    ('zero height', const mk.VideoParams(w: 1280, h: 0)),
    ('missing width', const mk.VideoParams(h: 720)),
    ('missing height', const mk.VideoParams(w: 1280)),
  ]) {
    testWidgets('P19 params with $label are a media boundary', (t) async {
      final d = await _mount(t);
      try {
        final reads = d.propertyReads().length;
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 50));
        d.player.emit('videoParams', params);
        await d.f.advance(t, const Duration(seconds: 5));
        expect(d.decoderLines, hasLength(1));
        expect(
          d.propertyReads().skip(reads).where(_readiness.contains),
          isEmpty,
        );
      } finally {
        await d.close();
      }
    });
  }

  testWidgets('P19 one-pixel params are real media, not a boundary', (t) async {
    final d = await _mount(t);
    try {
      d.player.emit('videoParams', const mk.VideoParams(w: 1, h: 1));
      await d.f.advance(t, const Duration(seconds: 5));
      expect(_resolutions(d), ['1280x720', '1x1']);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 an empty decoder reports unavailable with an unknown decoder',
    (t) async {
      final d = await _mount(t, {..._stable, 'hwdec-current': ''});
      try {
        expect(d.decoderLines, hasLength(1));
        expect(
          d.decoderLines.single,
          contains(' phase=partial status=unavailable '),
        );
        expect(d.decoderLines.single, contains(' decoder=unknown '));
        expect(
          d.decoderLines.single
              .split(' ')
              .skip(1)
              .where((w) => !w.contains('=')),
          isEmpty,
          reason: 'every field is a single key=value token',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a probe superseded by newer params stops at its next read round',
    (t) async {
      final d = await _mount(t);
      try {
        d.native.properties['current-vo'] = 'null';
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 700));
        d.native.properties['current-vo'] = 'libmpv';
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(_resolutions(d), ['1280x720', '3840x2160']);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a boundary and new params at once never revive the running probe',
    (t) async {
      final d = await _mount(t);
      try {
        d.native.properties['current-vo'] = 'null';
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 700));
        d.native.properties['current-vo'] = 'libmpv';
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        await d.f.advance(t, const Duration(seconds: 5));
        expect(_resolutions(d), ['1280x720', '3840x2160']);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a probe superseded during its final stable read reports nothing',
    (t) async {
      final d = await _mount(t);
      final gate = Completer<void>();
      try {
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        await d.f.advance(t, const Duration(milliseconds: 200));
        var armed = true;
        d.native.beforeOperation = (name, value) {
          if (armed &&
              name == 'getProperty' &&
              value == 'audio-out-params/channel-count') {
            armed = false;
            return gate.future;
          }
          return null;
        };
        await d.f.advance(t, const Duration(milliseconds: 250));
        expect(armed, isFalse, reason: 'the second round is parked');
        d.player.emit('videoParams', const mk.VideoParams(w: 3840, h: 2160));
        gate.complete();
        await d.f.advance(t, const Duration(seconds: 5));
        expect(_resolutions(d), ['1280x720', '3840x2160']);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
}
