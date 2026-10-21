import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/utils/language_mapping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

/// One ordered record of player commands and native property writes.
void Function(FakePlayer) _record(
  List<String> seq, {
  Set<String> rejected = const {},
}) => (p) {
  p.beforeOperation = (name, value) => seq.add('player:$name');
  (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
    if (name != 'setProperty') return;
    final (property, v) = value as (String, String);
    seq.add('set:$property=$v');
    if (rejected.contains(property)) throw StateError('$property rejected');
  };
};

const _audio = {'ao', 'audio-channels', 'audio-spdif', 'alang'};

/// Audio-owned writes made before the first open, in order.
List<String> _beforeOpen(List<String> seq) {
  final open = seq.indexOf('player:open');
  expect(open, isNonNegative, reason: 'the original opens the media');
  return [
    for (final entry in seq.take(open))
      if (entry.startsWith('set:') &&
          _audio.contains(entry.substring(4).split('=').first))
        entry,
  ];
}

Future<List<String>> _tvos(
  WidgetTester t, {
  int route = 0,
  bool legacy = false,
  bool stereo = false,
  bool multichannel = false,
  String? language,
}) async {
  final seq = <String>[];
  final d = EngineDriver(
    t,
    tvos: true,
    routeChannels: route,
    configurePlayer: _record(seq),
  );
  await d.initialize();
  try {
    await d.f.finish<void>(
      t,
      PlayerSettingsStorage.setTvosLegacyAudioOutput(legacy),
    );
    await d.f.finish<void>(
      t,
      PlayerSettingsStorage.setTvosForceStereoAudio(stereo),
    );
    await d.f.finish<void>(
      t,
      PlayerSettingsStorage.setAppleMultichannelAudio(multichannel),
    );
    if (language != null) {
      await d.f.finish<void>(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage(language),
      );
    }
    await d.mount();
    expect(d.errors, isEmpty);
    return _beforeOpen(seq);
  } finally {
    await d.close();
  }
}

void main() {
  testWidgets(
    'P19 tvOS two-channel route gets the AVFoundation output capped to stereo before open',
    (t) async {
      expect(await _tvos(t, route: 2), [
        'set:ao=avfoundation,audiounit',
        'set:audio-channels=stereo',
      ]);
    },
  );

  testWidgets(
    'P19 tvOS multichannel route keeps the native layout before open',
    (t) async {
      expect(await _tvos(t, route: 6), ['set:ao=avfoundation,audiounit']);
    },
  );

  testWidgets('P19 tvOS legacy output selects AudioUnit alone', (t) async {
    expect(await _tvos(t, route: 6, legacy: true), ['set:ao=audiounit']);
  });

  testWidgets('P19 tvOS force-stereo caps a multichannel route', (t) async {
    expect(await _tvos(t, route: 6, stereo: true), [
      'set:ao=avfoundation,audiounit',
      'set:audio-channels=stereo',
    ]);
  });

  testWidgets('P19 tvOS multichannel opt-in wins over a two-channel route', (
    t,
  ) async {
    expect(await _tvos(t, route: 2, multichannel: true), [
      'set:ao=avfoundation,audiounit',
      'set:audio-channels=auto',
    ]);
  });

  testWidgets(
    'P19 the preferred audio language reaches mpv as alang after the output list',
    (t) async {
      expect(await _tvos(t, route: 2, language: 'spa'), [
        'set:ao=avfoundation,audiounit',
        'set:audio-channels=stereo',
        'set:alang=${LanguageMapper.alangForCode('spa')}',
      ]);
    },
  );

  testWidgets(
    'P19 desktop sends only the preferred audio language, and nothing without one',
    (t) async {
      for (final language in ['jpn', null]) {
        final seq = <String>[];
        final d = EngineDriver(t, configurePlayer: _record(seq));
        await d.initialize();
        try {
          if (language != null) {
            await d.f.finish<void>(
              t,
              SubtitleSettingsStorage.setDefaultAudioLanguage(language),
            );
          }
          await d.mount();
          expect(_beforeOpen(seq), [
            if (language != null)
              'set:alang=${LanguageMapper.alangForCode(language)}',
          ]);
        } finally {
          await d.close();
        }
      }
    },
  );

  testWidgets(
    'P19 one rejected audio property does not stop the rest or the open',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        tvos: true,
        routeChannels: 2,
        configurePlayer: _record(seq, rejected: {'ao'}),
      );
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('spa'),
        );
        await d.mount();
        expect(_beforeOpen(seq), [
          'set:ao=avfoundation,audiounit',
          'set:audio-channels=stereo',
          'set:alang=${LanguageMapper.alangForCode('spa')}',
        ]);
        expect(
          d.logs,
          contains(
            'VideoPlayer: audio config ao=avfoundation,audiounit failed: '
            'Bad state: ao rejected',
          ),
        );
        expect(d.native.properties.containsKey('ao'), isFalse);
        expect(d.native.properties['audio-channels'], 'stereo');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 a rejected alang write is logged and playback still opens', (
    t,
  ) async {
    final seq = <String>[];
    final d = EngineDriver(
      t,
      configurePlayer: _record(seq, rejected: {'alang'}),
    );
    await d.initialize();
    try {
      await d.f.finish<void>(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('jpn'),
      );
      await d.mount();
      expect(
        d.logs,
        contains('VideoPlayer: alang config failed: Bad state: alang rejected'),
      );
      expect(seq, contains('player:open'));
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  const external = 'https://audio.test/dub.m4a';
  const screen = VideoPlayerScreen(
    videoUrl: 'https://audio.test/video.mkv',
    title: 'External audio',
    audioUrl: external,
  );

  testWidgets(
    'P19 the external audio track is set after the main media loads',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(t, configurePlayer: _record(seq));
      await d.initialize();
      try {
        await d.mount(screen: screen);
        await d.f.advance(t, const Duration(seconds: 2));
        final audio = [
          for (final c in d.player.calls)
            if (c.$1 == 'audio') c.$2 as mk.AudioTrack,
        ];
        expect(audio, hasLength(1));
        expect(audio.single.id, external);
        expect(audio.single.uri, isTrue);
        expect(
          seq.indexOf('player:audio'),
          greaterThan(seq.indexOf('player:open')),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 an external audio failure is swallowed with a log line', (
    t,
  ) async {
    final d = EngineDriver(
      t,
      configurePlayer: (p) =>
          p.failures['audio'] = StateError('external audio refused'),
    );
    await d.initialize();
    try {
      await d.mount(screen: screen);
      await d.f.advance(t, const Duration(seconds: 2));
      expect(
        d.logs,
        contains(
          'VideoPlayer: failed to set external audio track: '
          'Bad state: external audio refused',
        ),
      );
      expect(d.player.calls.where((c) => c.$1 == 'audio'), hasLength(1));
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
}
