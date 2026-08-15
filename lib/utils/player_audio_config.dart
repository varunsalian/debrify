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
  /// - tvOS: `ao=avfoundation,audiounit`. `ao_audiounit` goes silent on a
  ///   Dolby Atmos HDMI route (confirmed on a user's receiver, restart-
  ///   controlled: Atmos on = silence, Atmos off = sound). `ao_avfoundation`
  ///   renders through `AVSampleBufferAudioRenderer`, the same Apple stack the
  ///   external players that *do* work on that route use.
  ///
  ///   Written as a LIST, not a single value: mpv falls back to `audiounit`
  ///   if the new AO fails to initialise. That matters because upstream mpv
  ///   only ever builds `ao_avfoundation` for macOS — running it on tvOS
  ///   needs `patch/mpv/avfoundation-tvos.patch` from the rebuilt libmpv
  ///   (TVOS_LIBMPV_UPGRADE_PLAN.md), and nobody has run it on this platform
  ///   before. The fallback does NOT cover a successful init that then
  ///   produces silence, which is the failure mode being fixed.
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
    bool isTvOS = false,
    int routeOutputChannels = 0,
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
    if (isTvOS) {
      props.add(('ao', 'avfoundation,audiounit'));
      // ao_avfoundation hands the route the file's NATIVE layout rather than
      // downmixing like ao_audiounit did. On a route that can only take two
      // channels -- AirPods, Bluetooth, a stereo TV -- letting a 5.1 track
      // through produces an audibly wrong fold, LFE-heavy and diffuse. Cap it
      // ourselves; a multichannel route (AVR, soundbar, Atmos) is left alone,
      // which is the case the AO switch exists to fix.
      //
      // routeOutputChannels <= 0 means the query failed or has not answered
      // yet; leave mpv's default rather than guessing, since capping a real
      // multichannel route would undo the fix.
      // The multichannel opt-in is an explicit "give me the native layout",
      // so it wins. Spelled out here rather than relying on the later
      // audio-channels=auto overwriting this one by list order.
      if (!multichannelEnabled &&
          routeOutputChannels > 0 &&
          routeOutputChannels <= 2) {
        props.add(('audio-channels', 'stereo'));
      }
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
