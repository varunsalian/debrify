import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/utils/player_audio_config.dart';

List<(String, String)> _props({
  bool isAndroid = false,
  bool isApple = false,
  bool isTvOS = false,
  int routeChannels = 0,
  bool forceStereo = false,
  bool legacyAo = false,
  bool passthrough = false,
  bool effects = false,
  bool multichannel = false,
}) =>
    PlayerAudioConfig.audioProperties(
      isAndroid: isAndroid,
      isApple: isApple,
      isTvOS: isTvOS,
      routeOutputChannels: routeChannels,
      tvosForceStereo: forceStereo,
      tvosLegacyAudioOutput: legacyAo,
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

  test('tvOS selects avfoundation with an audiounit fallback', () {
    // ao_audiounit goes silent on a Dolby Atmos HDMI route; avfoundation
    // renders through AVSampleBufferAudioRenderer instead. The comma list is
    // the point: mpv falls back if the new AO cannot initialise.
    expect(_props(isApple: true, isTvOS: true), [
      ('ao', 'avfoundation,audiounit'),
    ]);
  });

  test('iOS is untouched by the tvOS audio output change', () {
    expect(_props(isApple: true, isTvOS: false), isEmpty);
  });

  test('tvOS keeps the multichannel opt-in after the ao selection', () {
    // Order matters: ao is applied before audio-channels.
    expect(_props(isApple: true, isTvOS: true, multichannel: true), [
      ('ao', 'avfoundation,audiounit'),
      ('audio-channels', 'auto'),
    ]);
  });

  test('Android never gets the tvOS audio output', () {
    expect(
      _props(isAndroid: true, isTvOS: true, passthrough: true),
      isNot(contains(('ao', 'avfoundation,audiounit'))),
    );
  });

  test('a two-channel route is capped to stereo', () {
    // ao_avfoundation passes the native layout through, so 5.1 on AirPods or
    // a stereo TV folds badly (LFE-heavy). Cap it.
    expect(_props(isApple: true, isTvOS: true, routeChannels: 2), [
      ('ao', 'avfoundation,audiounit'),
      ('audio-channels', 'stereo'),
    ]);
  });

  test('a multichannel route is left native', () {
    // The AVR/Atmos case the AO switch exists to fix.
    expect(_props(isApple: true, isTvOS: true, routeChannels: 6), [
      ('ao', 'avfoundation,audiounit'),
    ]);
  });

  test('an unknown route count changes nothing', () {
    // 0 means the query failed; capping a real multichannel route would undo
    // the fix, so leave mpv's default.
    expect(_props(isApple: true, isTvOS: true, routeChannels: 0), [
      ('ao', 'avfoundation,audiounit'),
    ]);
  });

  test('the explicit multichannel opt-in beats the stereo cap', () {
    expect(
      _props(
        isApple: true,
        isTvOS: true,
        routeChannels: 2,
        multichannel: true,
      ),
      [('ao', 'avfoundation,audiounit'), ('audio-channels', 'auto')],
    );
  });

  test('route capping never applies off tvOS', () {
    expect(_props(isApple: true, isTvOS: false, routeChannels: 2), isEmpty);
  });

  test('force-stereo caps even a multichannel route', () {
    // The diagnostic counterpart to the multichannel opt-in: it caps
    // regardless of what the route claims to support.
    expect(
      _props(isApple: true, isTvOS: true, routeChannels: 6, forceStereo: true),
      [('ao', 'avfoundation,audiounit'), ('audio-channels', 'stereo')],
    );
  });

  test('the legacy audio engine drops back to audiounit alone', () {
    // No fallback list here — the point is to isolate the old AO.
    expect(
      _props(isApple: true, isTvOS: true, routeChannels: 6, legacyAo: true),
      [('ao', 'audiounit')],
    );
  });

  test('legacy engine still respects the route cap', () {
    expect(
      _props(isApple: true, isTvOS: true, routeChannels: 2, legacyAo: true),
      [('ao', 'audiounit'), ('audio-channels', 'stereo')],
    );
  });

  test('the multichannel opt-in still beats force-stereo', () {
    expect(
      _props(
        isApple: true,
        isTvOS: true,
        routeChannels: 2,
        forceStereo: true,
        multichannel: true,
      ),
      [('ao', 'avfoundation,audiounit'), ('audio-channels', 'auto')],
    );
  });

  test('the tvOS diagnostics never leak to iOS', () {
    expect(
      _props(
        isApple: true,
        isTvOS: false,
        forceStereo: true,
        legacyAo: true,
      ),
      isEmpty,
    );
  });
}
