import 'dart:async';
import 'package:debrify/features/home/data/home_trailer_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

HomeTrailerPreferencesRepository trailerRepository({
  Future<bool> Function()? enabled,
  bool audio = true,
  int volume = 37,
}) => HomeTrailerPreferencesRepository(
  readEnabled: enabled ?? () async => true,
  readAudioEnabled: (_) async => audio,
  readVolume: (_) async => volume,
);

void main() {
  test(
    'parallel read barrier publishes one complete effective preference pair',
    () async {
      final enabled = Completer<bool>();
      final audio = Completer<bool>();
      final volume = Completer<int>();
      final calls = <String>[];
      final repo = HomeTrailerPreferencesRepository(
        readEnabled: () {
          calls.add('enabled');
          return enabled.future;
        },
        readAudioEnabled: (home) {
          calls.add('audio:$home');
          return audio.future;
        },
        readVolume: (home) {
          calls.add('volume:$home');
          return volume.future;
        },
      );
      var finished = false;
      final pending = repo.read(useHomeAudio: false).then((value) {
        finished = true;
        return value;
      });
      expect(calls, ['enabled', 'audio:false', 'volume:false']);
      volume.complete(83);
      enabled.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      audio.complete(true);
      expect(await pending, (enabled: false, volume: 83.0));
    },
  );

  test(
    'mute sets effective volume to zero without changing enabled state',
    () async {
      expect(
        await trailerRepository(
          audio: false,
          volume: 83,
        ).read(useHomeAudio: true),
        (enabled: true, volume: 0.0),
      );
      expect(await trailerRepository(volume: 130).read(useHomeAudio: true), (
        enabled: true,
        volume: 130.0,
      ));
    },
  );

  test('failed preference read propagates without a partial result', () async {
    await expectLater(
      trailerRepository(
        enabled: () async => throw StateError('storage'),
      ).read(useHomeAudio: true),
      throwsStateError,
    );
  });
}
