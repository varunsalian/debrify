/// The single owner of the Dart player's audio-output properties — see
/// AUDIO_FIDELITY_PLAN.md.
///
/// Pure: platform and settings in, an ORDERED mpv property list out. The
/// ordering is a contract (`ao` strictly before `audio-spdif` — the spdif
/// wrapper only helps on an output that can bitstream), and `ao` is emitted
/// at most once however many settings want it, which is what keeps the
/// passthrough and system-audio-effects switches from fighting over it.
class PlayerAudioConfig {
  PlayerAudioConfig._();

  /// mpv properties to apply after player creation, before the first open.
  ///
  /// - Android: `ao=audiotrack,opensles` when passthrough OR the effects
  ///   session needs it (media_kit pins `opensles`, which can neither
  ///   bitstream nor accept an effects session; the trailing `opensles`
  ///   keeps audio alive on any device where AudioTrack fails), then
  ///   `audio-spdif=ac3,eac3,dts` for passthrough. DTS-HD MA sends its DTS
  ///   core over this path — the setting's caption says so.
  /// - Apple (tvOS + iOS): `audio-channels=auto` when the multichannel
  ///   toggle is on. mpv's audiounit output self-caps at the route's real
  ///   channel maximum (MIN(deviceMax, requested)), so an AVR route gets
  ///   full multichannel LPCM while TV speakers stay stereo. Opt-in
  ///   because AirPlay/spatial routes are unproven — the probe's
  ///   decoded_channels/audio_channels fields are the evidence trail.
  /// - Everything else (desktop, web): empty — desktop coreaudio/wasapi
  ///   already negotiate multichannel PCM by default.
  static List<(String, String)> audioProperties({
    required bool isAndroid,
    required bool isApple,
    required bool passthroughEnabled,
    required bool systemAudioEffects,
    required bool multichannelEnabled,
  }) {
    final props = <(String, String)>[];
    if (isAndroid) {
      if (passthroughEnabled || systemAudioEffects) {
        props.add(('ao', 'audiotrack,opensles'));
      }
      if (passthroughEnabled) {
        props.add(('audio-spdif', 'ac3,eac3,dts'));
      }
      return props;
    }
    if (isApple && multichannelEnabled) {
      props.add(('audio-channels', 'auto'));
    }
    return props;
  }

  /// The LIVE Android passthrough flip (in-player toggle): unlike
  /// [audioProperties] — which only ever adds — this emits explicit values
  /// for BOTH properties so turning passthrough off actually restores the
  /// non-passthrough state ('' clears audio-spdif; `ao` falls back to
  /// media_kit's opensles default unless the effects session still needs
  /// audiotrack). The caller must re-init the audio chain afterwards —
  /// `audio-spdif` is read at decoder init, not live.
  static List<(String, String)> androidLiveToggleProperties({
    required bool passthroughEnabled,
    required bool systemAudioEffects,
  }) {
    return [
      (
        'ao',
        passthroughEnabled || systemAudioEffects
            ? 'audiotrack,opensles'
            : 'opensles',
      ),
      ('audio-spdif', passthroughEnabled ? 'ac3,eac3,dts' : ''),
    ];
  }
}
