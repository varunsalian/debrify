import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/utils/player_audio_config.dart';

List<(String, String)> _props({
  bool isAndroid = false,
  bool isApple = false,
  bool passthrough = false,
  bool effects = false,
  bool multichannel = false,
}) =>
    PlayerAudioConfig.audioProperties(
      isAndroid: isAndroid,
      isApple: isApple,
      passthroughEnabled: passthrough,
      systemAudioEffects: effects,
      multichannelEnabled: multichannel,
    );

void main() {
  test('everything off is empty on every platform', () {
    expect(_props(isAndroid: true), isEmpty);
    expect(_props(isApple: true), isEmpty);
    expect(_props(), isEmpty, reason: 'desktop/web get nothing, ever');
  });

  test('Android passthrough: ao strictly before audio-spdif', () {
    expect(_props(isAndroid: true, passthrough: true), [
      ('ao', 'audiotrack,opensles'),
      ('audio-spdif', 'ac3,eac3,dts'),
    ]);
  });

  test('Android effects alone: ao only, no spdif', () {
    expect(_props(isAndroid: true, effects: true), [
      ('ao', 'audiotrack,opensles'),
    ]);
  });

  test('passthrough + effects emit ao exactly once', () {
    final props = _props(isAndroid: true, passthrough: true, effects: true);
    expect(props.where((p) => p.$1 == 'ao'), hasLength(1),
        reason: 'two ao writers is how the settings would fight');
    expect(props.first.$1, 'ao');
  });

  test('Apple multichannel toggle gates audio-channels=auto', () {
    expect(_props(isApple: true, multichannel: true), [
      ('audio-channels', 'auto'),
    ]);
    expect(_props(isApple: true, multichannel: false), isEmpty);
  });

  test('Apple ignores Android settings and vice versa', () {
    expect(_props(isApple: true, passthrough: true, effects: true), isEmpty,
        reason: 'spdif/audiotrack are Android concepts');
    expect(_props(isAndroid: true, multichannel: true), isEmpty,
        reason: 'audio-channels=auto is validated only for audiounit');
  });

  test('desktop stays empty even with every flag set', () {
    expect(
      _props(passthrough: true, effects: true, multichannel: true),
      isEmpty,
    );
  });

  test('live toggle ON: audiotrack + spdif list', () {
    expect(
      PlayerAudioConfig.androidLiveToggleProperties(
        passthroughEnabled: true,
        systemAudioEffects: false,
      ),
      [('ao', 'audiotrack,opensles'), ('audio-spdif', 'ac3,eac3,dts')],
    );
  });

  test('live toggle OFF restores opensles and CLEARS spdif', () {
    expect(
      PlayerAudioConfig.androidLiveToggleProperties(
        passthroughEnabled: false,
        systemAudioEffects: false,
      ),
      [('ao', 'opensles'), ('audio-spdif', '')],
    );
  });

  test('live toggle OFF keeps audiotrack while the effects session needs it',
      () {
    expect(
      PlayerAudioConfig.androidLiveToggleProperties(
        passthroughEnabled: false,
        systemAudioEffects: true,
      ),
      [('ao', 'audiotrack,opensles'), ('audio-spdif', '')],
    );
  });
}
